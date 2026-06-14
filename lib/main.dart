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

/// 根据平台返回适合的中文字体
/// - Windows: 微软雅黑（系统字体，中英文都清晰）
/// - macOS: 使用系统默认（苹方）
/// - 其他平台：不指定（使用系统默认）
String? _getPlatformFont() {
  if (!kIsWeb && Platform.isWindows) {
    return 'Microsoft YaHei';
  }
  return null;
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
    final style = ThemeSettings().style;
    return MaterialApp(
      title: '生活记录',
      debugShowCheckedModeBanner: false,
      theme: style == 'warm'
          ? _buildWarmLightTheme(_getPlatformFont())
          : _buildClassicLightTheme(_getPlatformFont()),
      darkTheme: style == 'warm'
          ? _buildWarmDarkTheme(_getPlatformFont())
          : _buildClassicDarkTheme(_getPlatformFont()),
      themeMode: ThemeSettings().mode,
      home: LockScreen(child: const _AppEntry()),
    );
  }
}

// ===================== 暖棕/金色主题 =====================

ThemeData _buildWarmLightTheme(String? fontFamily) {
  const seedColor = Color(0xFF8B6F47);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.light,
  );
  return _buildWarmThemeData(colorScheme, fontFamily);
}

ThemeData _buildWarmDarkTheme(String? fontFamily) {
  const seedColor = Color(0xFFD4A857);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.dark,
  );
  return _buildWarmThemeData(colorScheme, fontFamily);
}

ThemeData _buildWarmThemeData(ColorScheme colorScheme, String? fontFamily) {
  final isDark = colorScheme.brightness == Brightness.dark;
  // 磨砂半透明背景色
  final scrimColor = isDark
      ? const Color(0xB30F0B09)
      : const Color(0x66000000);
  final surfaceLowOpacity = isDark ? 0.92 : 0.95;
  final surfaceMidOpacity = isDark ? 0.88 : 0.92;
  final surfaceHighOpacity = isDark ? 0.85 : 0.90;
  final borderOpacity = isDark ? 0.25 : 0.15;

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: fontFamily,

    // 背景层：深暖棕黑（暗色）/ 暖纸白（亮色）
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF0F0B09)
        : const Color(0xFFFDF8F3),

    // === AppBar：扁平半透明磨砂 ===
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: colorScheme.surface.withOpacity(surfaceLowOpacity),
      foregroundColor: colorScheme.onSurface,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: colorScheme.primary),
    ),

    // === Card：半透明磨砂卡片 ===
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surfaceContainer.withOpacity(surfaceMidOpacity),
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(borderOpacity),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),

    // === Dialog：大圆角半透明 ===
    dialogTheme: DialogThemeData(
      backgroundColor: isDark
          ? const Color(0xF2221B15)
          : colorScheme.surfaceContainerHigh.withOpacity(surfaceLowOpacity),
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
    ),

    // === BottomSheet：大圆角磨砂弹层 ===
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark
          ? const Color(0xF21A1410)
          : colorScheme.surface.withOpacity(surfaceLowOpacity),
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: isDark
          ? const Color(0xF21A1410)
          : colorScheme.surface.withOpacity(surfaceLowOpacity),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: false,
      modalBarrierColor: scrimColor,
    ),

    // === 输入框：圆角磨砂 ===
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withOpacity(0.6),
        fontSize: 14,
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
    ),

    // === 按钮：金色圆角 ===
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.12),
        disabledForegroundColor: colorScheme.onSurface.withOpacity(0.38),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        disabledForegroundColor: colorScheme.onSurface.withOpacity(0.38),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        side: BorderSide(color: colorScheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        disabledForegroundColor: colorScheme.onSurface.withOpacity(0.38),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      elevation: 0,
      focusElevation: 0,
      highlightElevation: 0,
      hoverElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ),

    // === ListTile：扁平圆角 ===
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.onSurfaceVariant,
      textColor: colorScheme.onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      dense: true,
    ),

    // === Chip：柔和圆角标签 ===
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest.withOpacity(0.6),
      labelStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),

    // === SnackBar：浮动磨砂 ===
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark
          ? const Color(0xF22B221B)
          : colorScheme.surfaceContainerHigh,
      contentTextStyle: TextStyle(color: colorScheme.onSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      actionTextColor: colorScheme.primary,
    ),

    // === 分割线 ===
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withOpacity(borderOpacity),
      thickness: 0.5,
      space: 1,
    ),

    // === 弹出菜单 ===
    popupMenuTheme: PopupMenuThemeData(
      color: isDark
          ? const Color(0xF22B221B)
          : colorScheme.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),

    // === Switch / Checkbox / Radio：金色强调 ===
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colorScheme.primary;
        return colorScheme.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary.withOpacity(0.4);
        }
        return colorScheme.surfaceContainerHighest;
      }),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colorScheme.primary;
        return null;
      }),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colorScheme.primary;
        return null;
      }),
    ),

    // 画布色（半透明磨砂质感）
    canvasColor: colorScheme.surface.withOpacity(surfaceLowOpacity),
  );
}

// ===================== 经典青绿主题 =====================

ThemeData _buildClassicLightTheme(String? fontFamily) {
  const seedColor = Colors.teal;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.light,
  );
  return _buildClassicThemeData(colorScheme, fontFamily);
}

ThemeData _buildClassicDarkTheme(String? fontFamily) {
  const seedColor = Colors.teal;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.dark,
  );
  return _buildClassicThemeData(colorScheme, fontFamily);
}

ThemeData _buildClassicThemeData(ColorScheme colorScheme, String? fontFamily) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: fontFamily,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colorScheme.brightness == Brightness.dark
          ? const Color(0xFF2C2C2C)
          : Colors.grey[800],
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
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
