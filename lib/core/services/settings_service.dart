import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/pipeline_settings.dart';

/// 系统设置与 API Key 加密存储管理
class SettingsService {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  static const _storage = FlutterSecureStorage();
  PipelineSettings _settings = PipelineSettings();
  bool _loaded = false;

  PipelineSettings get settings => _settings;

  Future<void> init() async {
    if (_loaded) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(p.join(docs.path, 'settings.json'));
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _settings = PipelineSettings.fromJson(json);
      }

      // 从硬件安全区读取 API Keys
      final vlmKey = await _storage.read(key: 'vlm_api_key');
      if (vlmKey != null && vlmKey.isNotEmpty) _settings.vlmApiKey = vlmKey;

      final s2Key = await _storage.read(key: 'stage2_api_key');
      if (s2Key != null && s2Key.isNotEmpty) _settings.stage2ApiKey = s2Key;

      final s3Key = await _storage.read(key: 'stage3_api_key');
      if (s3Key != null && s3Key.isNotEmpty) _settings.stage3ApiKey = s3Key;

      final s4Key = await _storage.read(key: 'stage4_api_key');
      if (s4Key != null && s4Key.isNotEmpty) _settings.stage4ApiKey = s4Key;

      final webdavPwd = await _storage.read(key: 'webdav_password');
      if (webdavPwd != null && webdavPwd.isNotEmpty) _settings.webdavPassword = webdavPwd;
    } catch (_) {
      // 容错使用默认配置
    }
    _loaded = true;
  }

  Future<void> saveSettings(PipelineSettings newSettings) async {
    _settings = newSettings;
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, 'settings.json'));

    // 保存不含明文 Key 的 settings.json 文件（供 WebDAV 同步）
    final safeJson = _settings.toJson(includeKeys: false);
    await file.writeAsString(jsonEncode(safeJson));

    // 将明文 Keys 存储到硬件安全区
    await _storage.write(key: 'vlm_api_key', value: _settings.vlmApiKey);
    await _storage.write(key: 'stage2_api_key', value: _settings.stage2ApiKey);
    await _storage.write(key: 'stage3_api_key', value: _settings.stage3ApiKey);
    await _storage.write(key: 'stage4_api_key', value: _settings.stage4ApiKey);
    await _storage.write(key: 'webdav_password', value: _settings.webdavPassword);
  }

  /// 使用同步主密码（Master Password）通过 AES-256-GCM 加密全部 API Keys 密文
  Future<String> exportEncryptedKeys(String masterPassword) async {
    final keysPayload = jsonEncode({
      'vlm_key': _settings.vlmApiKey,
      'stage2_key': _settings.stage2ApiKey,
      'stage3_key': _settings.stage3ApiKey,
      'stage4_key': _settings.stage4ApiKey,
      'webdav_pwd': _settings.webdavPassword,
    });

    final algorithm = AesGcm.with256bits();
    final secretKey = await _deriveKeyFromPassword(masterPassword);
    final secretBox = await algorithm.encrypt(
      utf8.encode(keysPayload),
      secretKey: secretKey,
    );

    return base64Encode(secretBox.concatenation());
  }

  /// 使用同步主密码解密还原 API Keys
  Future<bool> importEncryptedKeys(String masterPassword, String cipherB64) async {
    try {
      final cipherBytes = base64Decode(cipherB64);
      final algorithm = AesGcm.with256bits();
      final secretBox = SecretBox.fromConcatenation(
        cipherBytes,
        nonceLength: 12,
        macLength: 16,
      );
      final secretKey = await _deriveKeyFromPassword(masterPassword);
      final clearBytes = await algorithm.decrypt(secretBox, secretKey: secretKey);
      final payload = jsonDecode(utf8.decode(clearBytes)) as Map<String, dynamic>;

      _settings.vlmApiKey = payload['vlm_key'] as String? ?? '';
      _settings.stage2ApiKey = payload['stage2_key'] as String? ?? '';
      _settings.stage3ApiKey = payload['stage3_key'] as String? ?? '';
      _settings.stage4ApiKey = payload['stage4_key'] as String? ?? '';
      _settings.webdavPassword = payload['webdav_pwd'] as String? ?? '';

      await saveSettings(_settings);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<SecretKey> _deriveKeyFromPassword(String password) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 10000,
      bits: 256,
    );
    final salt = utf8.encode("ai_memory_master_salt");
    return await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
  }
}
