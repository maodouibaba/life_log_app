import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'pages/home_page.dart';
import 'pages/space_selector_page.dart';
import 'pages/lock_screen.dart';
import 'database/app_database.dart';
import 'services/theme_settings.dart';
import 'services/ai_service.dart';
import 'services/privacy_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows 桌面端需要初始化 sqflite FFI
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 初始化数据库（创建或打开）
  final db = AppDatabase();
  try {
    await db.database;
    debugPrint('数据库初始化成功');
  } catch (e) {
    debugPrint('数据库初始化失败：$e');
  }

  // 加载持久化设置
  try {
    await Future.wait([
      AISettings().load(),
      PrivacySettings().load(),
      ThemeSettings().load(),
    ]);
    debugPrint('设置加载完成');
  } catch (e) {
    debugPrint('设置加载失败：$e');
  }

  runApp(const LifeLogApp());
}

class LifeLogApp extends StatefulWidget {
  const LifeLogApp({super.key});

  @override
  State<LifeLogApp> createState() => _LifeLogAppState();
}

class _LifeLogAppState extends State<LifeLogApp> {
  @override
  void initState() {
    super.initState();
    ThemeSettings().addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeSettings().removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '生活记录',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.grey[800],
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF2C2C2C),
        ),
      ),
      themeMode: ThemeSettings().mode,
      home: LockScreen(child: const _AppEntry()),
    );
  }
}

/// 应用入口控制器
/// 决定显示入口选择页还是主页
class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  final AppDatabase _db = AppDatabase();
  bool _loading = true;
  int? _spaceId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final spaces = await _db.getAllSpaces();
      if (spaces.isNotEmpty && mounted) {
        setState(() {
          _spaceId = spaces.first.id;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('加载入口列表失败：$e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSpaceSelected(int spaceId) {
    setState(() => _spaceId = spaceId);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_spaceId == null) {
      return SpaceSelectorPage(onSpaceSelected: _onSpaceSelected);
    }
    return HomePage(
      spaceId: _spaceId!,
      onSwitchSpace: () => setState(() => _spaceId = null),
    );
  }
}
