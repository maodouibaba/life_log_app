import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../database/app_database.dart';

/// 数据导入导出页面（JSON 格式，用于完整数据迁移）
class DataMigrationPage extends StatefulWidget {
  const DataMigrationPage({super.key});

  @override
  State<DataMigrationPage> createState() => _DataMigrationPageState();
}

class _DataMigrationPageState extends State<DataMigrationPage> {
  final AppDatabase _db = AppDatabase();
  final _importController = TextEditingController();
  bool _exporting = false;
  bool _importing = false;
  String? _lastExportPath;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final json = await _db.exportToJson();
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${dir.path}/生活记录备份_$timestamp.json';
      await File(filePath).writeAsString(json);

      setState(() {
        _lastExportPath = filePath;
        _exporting = false;
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出成功'),
          content: Text('已保存到：$filePath'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                OpenFilex.open(filePath);
              },
              child: const Text('分享'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _exporting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _import() async {
    final jsonText = _importController.text.trim();
    if (jsonText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先粘贴要导入的 JSON 数据')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入数据'),
        content: const Text('导入将清空所有现有数据并替换为导入内容，此操作不可撤销。\n\n确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('确定导入', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _importing = true);
    try {
      await _db.importFromJson(jsonText);
      setState(() => _importing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导入成功')),
      );
      _importController.clear();
    } catch (e) {
      setState(() => _importing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据迁移'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 导出
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.file_upload_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('导出数据', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('将所有记录、标签、项目导出为 JSON 文件，用于备份或迁移到其他设备。'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _exporting ? null : _export,
                      icon: _exporting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.file_upload_outlined),
                      label: Text(_exporting ? '导出中...' : '导出 JSON'),
                    ),
                  ),
                  if (_lastExportPath != null) ...[
                    const SizedBox(height: 8),
                    Text('上次导出：$_lastExportPath',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 导入
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.file_download_outlined, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Text('导入数据', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('将之前导出的 JSON 内容粘贴到下方文本框，然后点击导入。导入后会替换全部现有数据。'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _importController,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: '在此粘贴 JSON 数据...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _importing ? null : _import,
                      style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                      icon: _importing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.file_download_outlined),
                      label: Text(_importing ? '导入中...' : '导入'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
