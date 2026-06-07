import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../database/app_database.dart';
import '../services/seed_data.dart';

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
  final _pathController = TextEditingController();
  String _scanPath = '';
  int _scanKey = 0; // 用于强制刷新 FutureBuilder

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final json = await _db.exportToJson();

      // 检查返回的 JSON 是否包含错误信息
      String? warningMsg;
      try {
        final parsed = jsonDecode(json) as Map<String, dynamic>;
        if (parsed.containsKey('_export_fatal_error')) {
          warningMsg = '导出过程遇到严重错误，生成的文件可能不完整：\n'
              '${parsed['_export_fatal_error']}';
        } else if (parsed.containsKey('_export_errors')) {
          final errList = parsed['_export_errors'] as List;
          if (errList.isNotEmpty) {
            warningMsg = '导出过程中有以下问题（文件可能部分缺失）：\n'
                '${errList.join('\n')}';
          }
        }
      } catch (_) {}

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${dir.path}/生活记录备份_$timestamp.json';
      await File(filePath).writeAsString(json, flush: true);

      setState(() => _exporting = false);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(warningMsg != null ? '备份完成（有警告）' : '备份成功'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (warningMsg != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: SelectableText(warningMsg,
                        style: const TextStyle(fontSize: 13, color: Colors.deepOrange)),
                  ),
                SelectableText('已保存到：$filePath',
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
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
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出失败'),
          content: SingleChildScrollView(
            child: SelectableText('$e',
                style: const TextStyle(fontSize: 13)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定')),
          ],
        ),
      );
    }
  }

  /// 从 iPhone「文件」App 选择备份文件导入
  Future<void> _importFromFilePicker() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      await _importFromFile(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败：$e'), backgroundColor: Colors.red),
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

  /// 删除单个备份文件（带确认）
  Future<void> _deleteBackupFile(File file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除备份文件'),
        content: Text('确定要删除 "${file.path.split(Platform.pathSeparator).last}" 吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除',
                style:
                    TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await file.delete();
      setState(() => _scanKey++);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('备份文件已删除')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }

  Future<List<FileSystemEntity>> _scanBackupFiles() async {
    final dir = _scanPath.isNotEmpty
        ? Directory(_scanPath)
        : await getApplicationDocumentsDirectory();
    if (!dir.existsSync()) return [];
    final files = dir.listSync();
    return files
        .where((f) => f is File && f.path.endsWith('.json'))
        .toList()
      ..sort(
          (a, b) => -a.statSync().modified.compareTo(b.statSync().modified));
  }

  Future<void> _initDefaultPath() async {
    if (_scanPath.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      _scanPath = dir.path;
      _pathController.text = _scanPath;
    }
  }

  Future<void> _rescan() {
    final path = _pathController.text.trim();
    setState(() {
      _scanPath = path;
      _scanKey++;
    });
    return Future.value();
  }

  @override
  void initState() {
    super.initState();
    _initDefaultPath();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
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
                    '将备份的 .json 文件放入 App 的文档目录，然后点击刷新扫描。',
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 14,
                            color: theme.colorScheme.secondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'iPhone 用爱思助手 → 文件共享 → 生活记录 → Documents → 放入 .json 文件',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSecondaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- 从 iPhone 文件 App 选择 ----
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _importFromFilePicker,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('从 iPhone「文件」App 选择'),
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('或扫描文档目录', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ---- 自定义扫描路径 ----
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pathController,
                          decoration: InputDecoration(
                            hintText: '备份文件目录路径',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            isDense: true,
                            labelStyle: const TextStyle(fontSize: 13),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: '扫描此路径下的 .json 备份文件',
                        child: IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: _rescan,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_importing)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ))
                  else
                    FutureBuilder<List<FileSystemEntity>>(
                      key: ValueKey('scan_$_scanKey'),
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
                                  .withValues(alpha: 0.3),
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
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton(
                                        onPressed: () =>
                                            _importFromFile(file.path),
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              theme.colorScheme.error,
                                        ),
                                        child: const Text('恢复'),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline,
                                            size: 18,
                                            color: theme
                                                .colorScheme.onSurfaceVariant),
                                        tooltip: '删除此备份文件',
                                        onPressed: () =>
                                            _deleteBackupFile(file),
                                      ),
                                    ],
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

          const SizedBox(height: 20),

          // 加载演示数据
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('演示数据',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '一键填充示例数据，方便体验 App 功能。\n'
                    '包含树状标签、属性标签、项目、以及多种格式的演示记录。',
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('加载演示数据'),
                            content: const Text(
                                '将向当前数据库中添加演示数据（标签、项目、记录等）。'
                                '已有数据不会丢失。\n\n确定继续吗？'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消')),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('确定加载'),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        await SeedData.load(_db);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('演示数据加载成功！')),
                        );
                      },
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('加载演示数据'),
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
