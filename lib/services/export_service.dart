import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import '../database/app_database.dart';
import '../services/photo_service.dart';

/// 导出服务
class ExportService {
  final AppDatabase _db = AppDatabase();
  final PhotoService _photoService = PhotoService();

  /// 导出记录到 Excel（可选日期范围、可选含照片 ZIP）
  /// [spaceId] - 入口 ID
  /// [startDate] / [endDate] - 可选日期范围
  /// [includePhotos] - 是否在 ZIP 中包含照片
  /// 返回文件路径（.xlsx 或 .zip）
  Future<String> exportToExcel({
    int? spaceId,
    DateTime? startDate,
    DateTime? endDate,
    bool includePhotos = false,
  }) async {
    // 获取数据
    final data = await _getExportData(spaceId: spaceId, startDate: startDate, endDate: endDate);

    // 生成 Excel
    final excelPath = await _buildExcel(data, includePhotos: includePhotos);

    // 如果需要照片，打包 ZIP
    if (includePhotos) {
      final zipPath = await _buildZip(excelPath, data);
      // 删除临时的 Excel 文件
      await File(excelPath).delete();
      return zipPath;
    }

    return excelPath;
  }

  /// 获取导出数据（支持日期筛选）
  Future<List<Map<String, dynamic>>> _getExportData({
    int? spaceId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (startDate != null && endDate != null) {
      return await _db.getEntriesWithTagPathsByDateRange(
          startDate, endDate, spaceId: spaceId);
    }
    return await _db.getAllEntriesWithTagPaths(spaceId: spaceId);
  }

  /// 构建 Excel 文件，返回文件路径
  Future<String> _buildExcel(List<Map<String, dynamic>> data, {bool includePhotos = false}) async {
    // 第一遍扫描：找出标签路径的最大层级数
    int maxDepth = 0;
    for (final row in data) {
      final tags = row['tags'] as List<String>;
      for (final tagPath in tags) {
        final parts = tagPath.split(' > ');
        if (parts.length > maxDepth) maxDepth = parts.length;
      }
    }
    if (maxDepth == 0) maxDepth = 1;

    final excel = Excel.createExcel();
    final sheet = excel['生活记录'];

    // 表头
    final header = <String>['时间', '事项简介', '内容'];
    for (int i = 1; i <= maxDepth; i++) {
      header.add('层级$i');
    }
    header.add('项目');
    header.add('属性标签');
    header.add('对接人');
    header.add('后续待办');
    if (includePhotos) {
      header.add('照片');
    }
    sheet.appendRow(header);

    // 数据行
    for (final row in data) {
      final tags = row['tags'] as List<String>;
      final dateTimeStr = _formatDateTime(row['created_at'] as DateTime);
      final content = row['content'] as String;
      final project = row['project'] as String? ?? '';
      final attributeTags = (row['attribute_tags'] as List<dynamic>?)
              ?.cast<String>() ?? [];

      // 找出最长的标签路径
      List<String> deepestParts = [];
      for (final tagPath in tags) {
        final parts = tagPath.split(' > ');
        if (parts.length > deepestParts.length) {
          deepestParts = parts;
        }
      }

      // 补齐到 maxDepth
      final padded = List<String>.from(deepestParts)
        ..addAll(List.filled(maxDepth - deepestParts.length, ''));

      final title = row['title'] as String? ?? '';
      final contactPerson = row['contact_person'] as String? ?? '';
      final followUp = row['follow_up'] as String? ?? '';

      final rowData = <dynamic>[
        dateTimeStr,
        title,
        content,
        ...padded,
        project,
        attributeTags.join('、'),
        contactPerson,
        followUp,
      ];

      // 照片列：存相对路径（后面会转为超链接）
      if (includePhotos) {
        final photoFilenames = (row['photo_filenames'] as List<dynamic>?)
                ?.cast<String>() ?? [];
        rowData.add(photoFilenames.map((f) => 'photos/$f').join('; '));
      }

      sheet.appendRow(rowData);

      // 照片列显示相对路径（解压 ZIP 后 photos/ 与 Excel 在同一目录）
      // 因 excel 包不支持超链接，路径文本已足够用户定位
    }

    // 设置列宽
    sheet.setColumnWidth(0, 25); // 时间列
    sheet.setColumnWidth(1, 20); // 事项简介列
    sheet.setColumnWidth(2, 60); // 内容列
    for (int i = 0; i < maxDepth; i++) {
      sheet.setColumnWidth(i + 3, 18); // 层级列
    }

    // 保存文件
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${dir.path}/生活记录_$timestamp.xlsx';
    final fileBytes = excel.encode();
    if (fileBytes == null) throw Exception('导出失败：文件编码错误');
    await File(filePath).writeAsBytes(fileBytes);

    return filePath;
  }

  /// 构建 ZIP 包（Excel + photos 文件夹）
  Future<String> _buildZip(String excelPath, List<Map<String, dynamic>> data) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final zipPath = '${(await getApplicationDocumentsDirectory()).path}/生活记录_$timestamp.zip';
    final archive = Archive();

    // 添加 Excel 文件到 ZIP 根目录
    final excelBytes = await File(excelPath).readAsBytes();
    archive.addFile(ArchiveFile('生活记录.xlsx', excelBytes.length, excelBytes));

    // 收集所有不重复的照片文件名
    final photoFiles = <String>{};
    for (final row in data) {
      final filenames = (row['photo_filenames'] as List<dynamic>?)
              ?.cast<String>() ?? [];
      photoFiles.addAll(filenames);
    }

    // 添加照片到 ZIP 的 photos/ 目录
    for (final fileName in photoFiles) {
      try {
        final bytes = await _photoService.getPhotoBytes(fileName);
        if (bytes != null) {
          archive.addFile(ArchiveFile('photos/$fileName', bytes.length, bytes));
        }
      } catch (e) {
        debugPrint('添加照片到 ZIP 失败：$fileName - $e');
      }
    }

    // 编码并写入
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) throw Exception('ZIP 编码失败');
    await File(zipPath).writeAsBytes(encoded);
    return zipPath;
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
