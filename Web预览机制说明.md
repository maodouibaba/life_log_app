---
title: Flutter Web 预览机制说明
date: 2026-06-07
tags: [flutter, web, preview, 开发环境]
---

# Flutter Web 预览机制说明

## 用途

在 Windows 上开发 Flutter 项目时，通过 Web 浏览器实时预览 App 界面，
实现热重载开发（改代码 → 保存 → 浏览器自动刷新），无需 iOS 模拟器或 Android 模拟器。

## 前置条件

- Flutter SDK 已安装
- 项目已添加 Web 平台支持

## 启动预览

```bash
# 进入项目目录
cd 项目路径

# 启动 Web 预览（指定端口避免冲突）
flutter run -d web-server --web-port 8100
```

启动后在浏览器打开 `http://localhost:8100` 即可看到 App 界面。

### 热重载

- 改代码后按 `r` 键（在运行 flutter run 的终端中按）
- 或直接在浏览器刷新页面

## 新项目快速搭建

### 第一步：创建项目并添加 Web 支持

```bash
flutter create my_app
cd my_app
# 如果创建时没加 --platforms=web，可以手动补：
flutter create --platforms=web .
```

### 第二步：如果项目使用 sqflite

sqflite 在 Web 上无法直接运行，需要添加一个内存数据库适配层。

将本项目中的 `lib/database/web_database.dart` 复制到新项目同路径下。

然后在 `lib/database/app_database.dart` 的 `database` getter 中加判断：

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'web_database.dart';  // Web 内存数据库

// 在获取数据库实例时：
Future<Database> get database async {
  if (kIsWeb) {
    if (_webDb != null) return _webDb!;
    _webDb = WebDatabase();
    await _initWebDatabase(_webDb!);  // 初始化表结构
    return _webDb!;
  }
  // 原有的 sqflite 逻辑...
}
```

### 第三步：启动预览

```bash
flutter pub get
flutter run -d web-server --web-port 8100
```

## 注意事项

### Web 限制
- sqflite 不兼容 Web → 需要用 `web_database.dart` 替代（内存存储）
- `dart:io` 部分 API 不可用 → 用 `kIsWeb` 判断做平台分支
- 数据只存在于浏览器会话中，刷新页面后数据丢失（预览用途，不影响真机）

### 端口冲突
如果端口被占用，换一个端口：
```bash
flutter run -d web-server --web-port 8090
```

### 后台保持运行
Windows 上可以用 nohup 让预览进程在后台持续运行：
```bash
nohup flutter run -d web-server --web-port 8100 > flutter_web.log 2>&1 &
```
