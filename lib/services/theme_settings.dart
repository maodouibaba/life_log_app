import 'package:flutter/material.dart';
import '../database/app_database.dart';

/// 主题设置（单例）
class ThemeSettings {
  static final ThemeSettings _instance = ThemeSettings._internal();
  factory ThemeSettings() => _instance;
  ThemeSettings._internal();

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  String _style = 'warm'; // 'warm' | 'classic'
  String get style => _style;

  void setMode(ThemeMode mode) {
    _mode = mode;
    final v = mode == ThemeMode.system ? 'system'
        : mode == ThemeMode.light ? 'light' : 'dark';
    _ThemeDbProvider().set('theme_mode', v);
    _notifyListeners();
  }

  void setStyle(String style) {
    _style = style;
    _ThemeDbProvider().set('theme_style', style);
    _notifyListeners();
  }

  String get styleLabel => _style == 'classic' ? '经典青绿' : '暖棕/金色';
  IconData get styleIcon => _style == 'classic'
      ? Icons.palette_outlined
      : Icons.palette;

  /// 从数据库加载设置
  Future<void> load() async {
    final v = await _ThemeDbProvider().get('theme_mode');
    if (v == 'light') _mode = ThemeMode.light;
    else if (v == 'dark') _mode = ThemeMode.dark;
    else _mode = ThemeMode.system;

    final s = await _ThemeDbProvider().get('theme_style');
    if (s == 'classic') _style = 'classic';
    else _style = 'warm';
  }

  String get label {
    switch (_mode) {
      case ThemeMode.light: return '日间模式';
      case ThemeMode.dark: return '夜间模式';
      case ThemeMode.system: return '跟随系统';
    }
  }

  IconData get icon {
    switch (_mode) {
      case ThemeMode.light: return Icons.light_mode;
      case ThemeMode.dark: return Icons.dark_mode;
      case ThemeMode.system: return Icons.brightness_auto;
    }
  }

  final List<VoidCallback> _listeners = [];
  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);
  void _notifyListeners() {
    for (final cb in _listeners) { cb(); }
  }
}

class _ThemeDbProvider {
  final AppDatabase _db = AppDatabase();
  Future<String?> get(String key) async { try { return await _db.getSetting(key); } catch (_) { return null; } }
  Future<void> set(String key, String value) async { try { await _db.setSetting(key, value); } catch (_) {} }
}
