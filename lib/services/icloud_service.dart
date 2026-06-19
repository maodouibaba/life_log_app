import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

/// iCloud Drive 同步服务
/// 通过文件读写方式操作 iCloud Drive 中的备份文件
/// 不需要付费开发者账号，用户手动选择 iCloud Drive 目录
class ICloudService {
  static final ICloudService _instance = ICloudService._internal();
  factory ICloudService() => _instance;
  ICloudService._internal();

  String? _lastSelectedDir;

  /// 让用户选择 iCloud Drive 中的一个目录，返回目录路径
  Future<String?> pickDirectory() async {
    if (kIsWeb) return null;
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择 iCloud Drive 目录',
      );
      if (result != null) {
        _lastSelectedDir = result;
      }
      return result;
    } catch (e) {
      debugPrint('选择 iCloud Drive 目录失败：$e');
      return null;
    }
  }

  /// 获取上次选择的目录路径
  String? get lastSelectedDir => _lastSelectedDir;

  /// 列出 iCloud Drive 目录下的备份文件（.json / .zip）
  Future<List<Map<String, dynamic>>> listBackupFiles(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final files = <Map<String, dynamic>>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.endsWith('.json') || name.endsWith('.zip')) {
          final stat = await entity.stat();
          files.add({
            'name': name,
            'path': entity.path,
            'size': stat.size,
            'modified': stat.modified,
          });
        }
      }
    }
    // 按修改时间倒序
    files.sort((a, b) => (b['modified'] as DateTime)
        .compareTo(a['modified'] as DateTime));
    return files;
  }

  /// 读取备份文件内容（JSON 字符串）
  Future<String?> readBackupFile(String filePath) async {
    try {
      return await File(filePath).readAsString();
    } catch (e) {
      debugPrint('读取备份文件失败：$e');
      return null;
    }
  }

  /// 保存备份文件到 iCloud Drive
  Future<bool> saveBackupFile(String dirPath, String fileName, String content) async {
    try {
      final file = File('${dirPath}${Platform.pathSeparator}$fileName');
      await file.writeAsString(content, flush: true);
      return true;
    } catch (e) {
      debugPrint('保存备份文件失败：$e');
      return false;
    }
  }

  /// 删除 iCloud Drive 中的备份文件
  Future<bool> deleteBackupFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      debugPrint('删除备份文件失败：$e');
      return false;
    }
  }

  /// 格式化文件大小
  String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
