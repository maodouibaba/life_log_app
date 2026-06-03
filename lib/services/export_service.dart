import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../database/app_database.dart';

/// 导出服务
class ExportService {
  final AppDatabase _db = AppDatabase();

  /// 导出所有记录到 Excel 文件
  /// 返回导出文件的路径
  Future<String> exportToExcel() async {
    final data = await _db.getAllEntriesWithTagPaths();

    final excel = Excel.createExcel();
    final sheet = excel['生活记录'];

    // 表头
    sheet.appendRow([
      '时间',
      '内容',
      '标签',
    ]);

    // 数据行
    for (final row in data) {
      sheet.appendRow([
        _formatDateTime(row['created_at'] as DateTime),
        row['content'] as String,
        (row['tags'] as List<String>).join('; '),
      ]);
    }

    // 设置列宽
    sheet.setColumnWidth(0, 25);  // 时间列
    sheet.setColumnWidth(1, 60);  // 内容列
    sheet.setColumnWidth(2, 40);  // 标签列

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

