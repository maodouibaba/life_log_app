import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'database/app_database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化数据库（创建或打开）
  final db = AppDatabase();
  try {
    await db.database;
    debugPrint('数据库初始化成功');
  } catch (e) {
    debugPrint('数据库初始化失败：$e');
  }

  runApp(const LifeLogApp());
}

class LifeLogApp extends StatelessWidget {
  const LifeLogApp({super.key});

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
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
