import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/memory_database.dart';
import 'pipeline_service.dart';

/// 监听并消费 pending_inbox/ 缓冲队列与 iOS AppIntent
class PendingInboxService {
  static final PendingInboxService instance = PendingInboxService._();
  PendingInboxService._();

  static const _channel = MethodChannel('com.aimemory.app/inbox');
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    // 初始化本地通知
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    try {
      await _notifications.initialize(initSettings);
    } catch (_) {}

    // 注册 MethodChannel 接收 iOS AppIntent 后台/前台调用
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'processInboxItem') {
        final uuid = call.arguments as String?;
        if (uuid != null) {
          await processSingleItem(uuid);
        }
      }
    });

    _initialized = true;

    // 每次启动自动消费积压的沙盒队列
    await processAllPendingItems();
  }

  /// 扫描沙盒 Documents/pending_inbox/ 目录并处理全部积压记录
  Future<void> processAllPendingItems() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final inboxDir = Directory(p.join(docs.path, 'pending_inbox'));
      if (!inboxDir.existsSync()) return;

      final files = inboxDir.listSync();
      for (final entity in files) {
        if (entity is File && entity.path.endsWith('.json')) {
          final uuid = p.basenameWithoutExtension(entity.path);
          await processSingleItem(uuid);
        }
      }
    } catch (_) {}
  }

  /// 消费单条待处理项
  Future<void> processSingleItem(String uuid) async {
    final docs = await getApplicationDocumentsDirectory();
    final inboxDir = Directory(p.join(docs.path, 'pending_inbox'));
    final jsonFile = File(p.join(inboxDir.path, '$uuid.json'));
    final imgFile = File(p.join(inboxDir.path, '$uuid.img'));

    if (!jsonFile.existsSync()) return;

    try {
      final jsonStr = await jsonFile.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final rawOcr = data['ocr_text'] as String? ?? '';
      final note = data['user_note'] as String? ?? '';
      final source = data['source'] as String? ?? 'ios_shortcut';
      final imgPath = imgFile.existsSync() ? imgFile.path : null;

      // 执行 4 段式 AI 处理管线
      final item = await PipelineService.instance.processNewMemory(
        id: uuid,
        rawImagePath: imgPath,
        rawOcrText: rawOcr,
        userNote: note,
        sourcePlatform: source,
      );

      // 写入本地 SQLite 主库与 FTS5 索引
      MemoryDatabase.instance.save(item);

      // 发送系统本地通知反馈
      await _showNotification(item.title, item.summaryPoints.join(' · '));

      // 清理 pending_inbox 临时文件
      if (jsonFile.existsSync()) await jsonFile.delete();
      if (imgFile.existsSync()) await imgFile.delete();
    } catch (_) {
      // 若因网络报错，保留文件待下次启动重试
    }
  }

  Future<void> _showNotification(String title, String body) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'ai_memory_channel',
        'AI 记忆提醒',
        importance: Importance.high,
        priority: Priority.high,
      );
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
      );
    } catch (_) {}
  }
}
