import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../database/app_database.dart';

/// 隐私设置（单例）
class PrivacySettings {
  static final PrivacySettings _instance = PrivacySettings._internal();
  factory PrivacySettings() => _instance;
  PrivacySettings._internal();

  bool _enabled = false;
  bool _useBiometric = true;
  String _password = '';
  bool _authenticated = false;

  bool get enabled => _enabled;
  bool get useBiometric => _useBiometric;
  String get password => _password;
  bool get authenticated => _authenticated;

  set enabled(bool v) { _enabled = v; _save('privacy_enabled', v ? '1' : '0'); }
  set useBiometric(bool v) { _useBiometric = v; _save('privacy_biometric', v ? '1' : '0'); }
  set password(String v) { _password = v; _save('privacy_password', v); }
  set authenticated(bool v) => _authenticated = v;

  /// 从数据库加载设置
  Future<void> load() async {
    final db = _PrivacyDbProvider();
    _enabled = (await db.get('privacy_enabled')) == '1';
    _useBiometric = (await db.get('privacy_biometric')) != '0';
    _password = await db.get('privacy_password') ?? '';
  }

  void _save(String key, String value) => _PrivacyDbProvider().set(key, value);

  bool get hasPassword => _password.isNotEmpty;

  bool verifyPassword(String input) => _password == input;

  /// 检查设备是否支持生物识别
  static Future<bool> canUseBiometric() async {
    final auth = LocalAuthentication();
    try {
      return await auth.canCheckBiometrics || await auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// 执行生物识别验证
  static Future<bool> authenticateBiometric() async {
    final auth = LocalAuthentication();
    try {
      return await auth.authenticate(
        localizedReason: '验证身份以解锁应用',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// 执行密码验证
  static Future<bool> authenticatePassword(String input) async {
    final settings = PrivacySettings();
    return settings.verifyPassword(input);
  }

  /// 重置当前会话验证状态（后台切换时调用）
  void lock() => _authenticated = false;
}

class _PrivacyDbProvider {
  final AppDatabase _db = AppDatabase();
  Future<String?> get(String key) async { try { return await _db.getSetting(key); } catch (_) { return null; } }
  Future<void> set(String key, String value) async { try { await _db.setSetting(key, value); } catch (_) {} }
}
