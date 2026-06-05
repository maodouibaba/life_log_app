import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../database/app_database.dart';

/// 数据备份页面
/// 导出全部数据为 JSON，支持分享和导入恢复
class DataMigrationPage extends StatefulWidget {
  const DataMigrationPage({super.key});

  @override
  State<DataMigrationPage> createState() => _DataMigrationPageState();
}

class _DataMigrationPageState extends State<DataMigrationPage> {
  final AppDatabase _db = AppDatabase();
  bool _exporting = false;
  bool _importing = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final json = await _db.exportToJson();
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${dir.path}/生活记录备份_$timestamp.json';
      await File(filePath).writeAsString(json, flush: true);

      setState(() => _exporting = false);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('备份成功'),
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

  Future<void> _importFromFile(String filePath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复备份'),
        content: const Text(
            '恢复备份将清空所有现有数据并替换为备份内容，此操作不可撤销。\n\n确定继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('确定恢复',
                style:
                    TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _importing = true);
    try {
      final jsonText = await File(filePath).readAsString();
      await _db.importFromJson(jsonText);
      setState(() => _importing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复成功：$filePath')),
      );
    } catch (e) {
      setState(() => _importing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败：$e')),
      );
    }
  }

  Future<List<FileSystemEntity>> _scanBackupFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir.listSync();
    return files
        .where((f) => f is File && f.path.endsWith('.json'))
        .toList()
      ..sort(
          (a, b) => -a.statSync().modified.compareTo(b.statSync().modified));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据备份'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 导出备份
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.file_upload_outlined,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('导出备份',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      '将所有记录、标签、项目等数据导出为 JSON 备份文件。\n'
                      '导出的文件可分享到微信、AirDrop 等，也可通过爱思助手取出。'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _exporting ? null : _export,
                      icon: _exporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.file_upload_outlined),
                      label: Text(_exporting ? '导出中...' : '导出备份'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 导入恢复
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.file_download_outlined,
                          color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      const Text('恢复备份',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '将备份的 .json 文件放入 App 的文档目录（可通过爱思助手"文件共享"操作），'
                    '然后在下方选择要恢复的备份文件。恢复后会替换全部现有数据。',
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  if (_importing)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ))
                  else
                    FutureBuilder<List<FileSystemEntity>>(
                      future: _scanBackupFiles(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final files = snapshot.data ?? [];
                        if (files.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.folder_open,
                                    size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 8),
                                const Text('没有找到备份文件',
                                    style:
                                        TextStyle(color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(
                                  '请先将 .json 备份文件通过爱思助手放入 App 的文档目录',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('找到 ${files.length} 个备份文件：',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: theme
                                        .colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 8),
                            ...files.map((f) {
                              final file = f as File;
                              final name = file.path
                                  .split(Platform.pathSeparator)
                                  .last;
                              final size =
                                  _formatFileSize(file.statSync().size);
                              final modTime = _formatModTime(
                                  file.statSync().modified);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  leading: Icon(Icons.description,
                                      color: theme.colorScheme.primary),
                                  title: Text(name,
                                      style: const TextStyle(fontSize: 14)),
                                  subtitle: Text('$size · $modTime',
                                      style:
                                          const TextStyle(fontSize: 11)),
                                  trailing: TextButton(
                                    onPressed: () =>
                                        _importFromFile(file.path),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          theme.colorScheme.error,
                                    ),
                                    child: const Text('恢复'),
                                  ),
                                  dense: true,
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatModTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
