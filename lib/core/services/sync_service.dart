import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../database/memory_database.dart';
import '../models/memory_item.dart';
import 'settings_service.dart';

/// WebDAV 增量同步状态机（一卡一 JSON + WebP 增量同步）
class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  Future<bool> syncNow() async {
    if (_isSyncing) return false;
    final settings = SettingsService.instance.settings;
    if (!settings.webdavEnabled || settings.webdavUrl.isEmpty) return false;

    _isSyncing = true;
    try {
      final client = webdav.newClient(
        settings.webdavUrl,
        user: settings.webdavUser,
        password: settings.webdavPassword,
        debug: false,
      );

      // 确保远端基础目录存在
      try {
        await client.mkdir('/memories');
        await client.mkdir('/assets');
      } catch (_) {}

      final docs = await getApplicationDocumentsDirectory();

      // 1. 读取本地所有记录构建本地 Manifest
      final localItems = MemoryDatabase.instance.getAll();
      final localManifest = <String, Map<String, dynamic>>{};
      for (final item in localItems) {
        localManifest[item.id] = {
          'updated_at': item.updatedAt,
          'is_deleted': item.isDeleted,
        };
      }

      // 2. 读取远端 sync_manifest.json
      Map<String, dynamic> remoteManifest = {};
      try {
        final remoteManifestData = await client.read('/sync_manifest.json');
        final str = utf8.decode(remoteManifestData);
        final parsed = jsonDecode(str) as Map<String, dynamic>;
        remoteManifest = parsed['items'] as Map<String, dynamic>? ?? {};
      } catch (_) {
        // 远端尚未建立 manifest
      }

      // 3. 计算 Pull（拉取远端更新）
      for (final entry in remoteManifest.entries) {
        final uuid = entry.key;
        final remoteInfo = entry.value as Map<String, dynamic>;
        final remoteUpdated = remoteInfo['updated_at'] as int? ?? 0;
        final remoteDeleted = remoteInfo['is_deleted'] as bool? ?? false;

        final localInfo = localManifest[uuid];
        final localUpdated = localInfo?['updated_at'] as int? ?? 0;

        if (localInfo == null || remoteUpdated > localUpdated) {
          if (remoteDeleted) {
            MemoryDatabase.instance.delete(uuid, soft: true);
          } else {
            // 下载 JSON
            try {
              final jsonBytes = await client.read('/memories/$uuid.json');
              final itemJson = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
              final item = MemoryItem.fromJson(itemJson);
              MemoryDatabase.instance.save(item);

              // 按策略下载图片
              if (settings.webdavSyncPolicy == 'full' && item.assetRelPath.isNotEmpty) {
                try {
                  final imgBytes = await client.read('/assets/$uuid.webp');
                  final targetFile = File(p.join(docs.path, item.assetRelPath));
                  if (!targetFile.parent.existsSync()) targetFile.parent.createSync(recursive: true);
                  await targetFile.writeAsBytes(imgBytes);
                } catch (_) {}
              }
            } catch (_) {}
          }
        }
      }

      // 4. 计算 Push（上传本地更新）
      for (final entry in localManifest.entries) {
        final uuid = entry.key;
        final localInfo = entry.value;
        final localUpdated = localInfo['updated_at'] as int;
        final localDeleted = localInfo['is_deleted'] as bool;

        final remoteInfo = remoteManifest[uuid] as Map<String, dynamic>?;
        final remoteUpdated = remoteInfo?['updated_at'] as int? ?? 0;

        if (remoteInfo == null || localUpdated > remoteUpdated) {
          final item = MemoryDatabase.instance.getById(uuid);
          if (item != null) {
            // 上传 JSON
            final jsonStr = jsonEncode(item.toJson());
            await client.write('/memories/$uuid.json', utf8.encode(jsonStr));

            // 上传 WebP 图片
            if (settings.webdavSyncPolicy != 'text_only' && item.assetRelPath.isNotEmpty) {
              final localImgFile = File(p.join(docs.path, item.assetRelPath));
              if (localImgFile.existsSync()) {
                final bytes = await localImgFile.readAsBytes();
                await client.write('/assets/$uuid.webp', bytes);
              }
            }
          }

          // 更新 manifest 缓存
          remoteManifest[uuid] = {
            'updated_at': localUpdated,
            'is_deleted': localDeleted,
          };
        }
      }

      // 5. 写回最新的 sync_manifest.json 到网盘
      final finalManifestPayload = jsonEncode({'items': remoteManifest});
      await client.write('/sync_manifest.json', utf8.encode(finalManifestPayload));

      return true;
    } catch (_) {
      return false;
    } finally {
      _isSyncing = false;
    }
  }
}
