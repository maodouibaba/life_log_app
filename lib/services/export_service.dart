import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../database/app_database.dart';

/// 导出服务
class ExportService {
  final AppDatabase _db = AppDatabase();

  /// 导出所有记录到 Excel 文件
  /// 返回导出文件的路径
  Future<String> exportToExcel({int? spaceId}) async {
    final data = await _db.getAllEntriesWithTagPaths(spaceId: spaceId);

    // 第一遍扫描：找出标签路径最大层级数
    int maxDepth = 0;
    for (final row in data) {
      for (final tagPath in row['tags'] as List<String>) {
        final parts = tagPath.split(' > ');
        if (parts.length > maxDepth) maxDepth = parts.length;
      }
    }
    if (maxDepth == 0) maxDepth = 1; // 至少有层级1列

    final excel = Excel.createExcel();
    final sheet = excel['生活记录'];

    // 表头
    final header = <String>['时间', '内容'];
    for (int i = 1; i <= maxDepth; i++) {
      header.add('层级$i');
    }
    header.add('项目');
    header.add('属性标签');
    sheet.appendRow(header);

    // 数据行：一个标签一行
    for (final row in data) {
      final tags = row['tags'] as List<String>;
      final dateTimeStr = _formatDateTime(row['created_at'] as DateTime);
      final content = row['content'] as String;
      final project = row['project'] as String? ?? '';
      final attributeTags = (row['attribute_tags'] as List<dynamic>?)?.cast<String>() ?? [];

      if (tags.isEmpty) {
        sheet.appendRow([
          dateTimeStr,
          content,
          ...List.filled(maxDepth, ''),
          project,
          attributeTags.join('、'),
        ]);
      } else {
        for (final tagPath in tags) {
          final parts = tagPath.split(' > ');
          final padded = List<String>.from(parts)
            ..addAll(List.filled(maxDepth - parts.length, ''));
          sheet.appendRow([
            dateTimeStr,
            content,
            ...padded,
            project,
            attributeTags.join('、'),
          ]);
        }
      }
    }

    // 设置列宽
    sheet.setColumnWidth(0, 25); // 时间列
    sheet.setColumnWidth(1, 60); // 内容列
    for (int i = 0; i < maxDepth; i++) {
      sheet.setColumnWidth(i + 2, 18); // 层级列
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

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

