import 'package:flutter/material.dart';

/// 主题设置（单例）
class ThemeSettings {
  static final ThemeSettings _instance = ThemeSettings._internal();
  factory ThemeSettings() => _instance;
  ThemeSettings._internal();

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  void setMode(ThemeMode mode) {
    _mode = mode;
    _notifyListeners();
  }

  void nextMode() {
    switch (_mode) {
      case ThemeMode.system: setMode(ThemeMode.light); break;
      case ThemeMode.light: setMode(ThemeMode.dark); break;
      case ThemeMode.dark: setMode(ThemeMode.system); break;
    }
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

  // 简单监听机制
  final List<VoidCallback> _listeners = [];
  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);
  void _notifyListeners() {
    for (final cb in _listeners) { cb(); }
  }
}
