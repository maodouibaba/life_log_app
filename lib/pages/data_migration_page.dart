import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import '../database/app_database.dart';
import '../services/seed_data.dart';
import '../services/photo_service.dart';

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

  // 批量选择
  bool _selectMode = false;
  final Set<String> _selectedPaths = {};

  Future<void> _export() async {
    // 先让用户选择是否包含照片
    final includePhotos = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('备份选项'),
        content: const Text('是否在备份中包含照片？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('仅数据（JSON）'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('包含照片（ZIP）'),
          ),
        ],
      ),
    );
    if (includePhotos == null || !mounted) return;

    setState(() => _exporting = true);
    try {
      final json = await _db.exportToJson();
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String filePath;

      if (includePhotos) {
        // 构建 ZIP 包（使用 Archive + ZipEncoder 支持内存文件）
        final zipPath = '${dir.path}/生活记录备份_$timestamp.zip';
        final archive = Archive();

        // 添加 JSON 文件
        final jsonBytes = utf8.encode(json);
        archive.addFile(ArchiveFile('生活记录备份.json', jsonBytes.length, jsonBytes));

        // 添加照片
        final photoFilenames = await _collectAllPhotoFilenames();
        for (final fileName in photoFilenames) {
          try {
            final bytes = await PhotoService().getPhotoBytes(fileName);
            if (bytes != null) {
              archive.addFile(ArchiveFile('photos/$fileName', bytes.length, bytes));
            }
          } catch (_) {}
        }

        // 编码并写入
        final encoded = ZipEncoder().encode(archive);
        if (encoded == null) throw Exception('ZIP 编码失败');
        await File(zipPath).writeAsBytes(encoded);
        filePath = zipPath;
      } else {
        filePath = '${dir.path}/生活记录备份_$timestamp.json';
        await File(filePath).writeAsString(json, flush: true);
      }

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
                      color: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).colorScheme.tertiary.withOpacity(0.4)),
                    ),
                    child: SelectableText(warningMsg,
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onTertiaryContainer)),
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

  /// 收集所有记录中用到的照片文件名
  Future<Set<String>> _collectAllPhotoFilenames() async {
    final allEntries = await _db.getAllEntries();
    final filenames = <String>{};
    for (final entry in allEntries) {
      filenames.addAll(entry.photoFilenames);
    }
    return filenames;
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
        SnackBar(
          content: Text('选择文件失败：$e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _importFromFile(String filePath) async {
    final theme = Theme.of(context);
    final fileName = filePath.split(Platform.pathSeparator).last;
    final restoreType = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择恢复模式'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('备份文件：$fileName', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              const Text('请选择恢复方式：', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Icon(Icons.swap_horiz, color: theme.colorScheme.primary),
                  title: const Text('合并到本地'),
                  subtitle: const Text(
                    '将备份与本地数据合并，冲突时保留较新的版本。本地数据不会丢失。',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () => Navigator.pop(ctx, 'merge'),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Icon(Icons.file_copy, color: theme.colorScheme.error),
                  title: const Text('覆盖恢复'),
                  subtitle: const Text(
                    '清空所有本地数据，替换为备份内容。此操作不可撤销。',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () => Navigator.pop(ctx, 'replace'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (restoreType == null || !mounted) return;

    // 覆盖模式再确认一次
    if (restoreType == 'replace') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认覆盖恢复'),
          content: const Text(
            '此操作将清空所有本地数据并替换为备份内容，\n'
            '不可撤销。建议先导出一份当前数据的备份。\n\n确定继续吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('确定覆盖',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    setState(() => _importing = true);
    try {
      final jsonText = await File(filePath).readAsString();
      if (restoreType == 'replace') {
        await _db.importFromJson(jsonText);
        setState(() => _importing = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复成功：$filePath')),
        );
      } else {
        final result = await _db.mergeFromJson(jsonText);
        setState(() => _importing = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('合并完成：新增 ${result['added_entries']} 条，更新 ${result['updated_entries']} 条'),
          ),
        );
      }
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

  Future<void> _batchDelete() async {
    if (_selectedPaths.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 ${_selectedPaths.length} 个备份文件吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      for (final path in _selectedPaths) {
        try { await File(path).delete(); } catch (_) {}
      }
      _selectedPaths.clear();
      _selectMode = false;
      setState(() => _scanKey++);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已批量删除')),
      );
    }
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
        title: Text(_selectMode ? '已选 ${_selectedPaths.length}' : '数据备份'),
        actions: [
          if (_selectMode) ...[
            IconButton(
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              tooltip: '批量删除',
              onPressed: _selectedPaths.isNotEmpty ? _batchDelete : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消选择',
              onPressed: () => setState(() {
                _selectMode = false;
                _selectedPaths.clear();
              }),
            ),
          ],
        ],
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
                      '导出的文件可分享到微信、AirDrop 等。\n'
                      'iOS/Android 用户可通过爱思助手取出。'),
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
                  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid))
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
                              Platform.isIOS
                                  ? 'iPhone 用爱思助手 → 文件共享 → 生活记录 → Documents → 放入 .json 文件'
                                  : '将 .json 备份文件放入 App 的文档目录',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSecondaryContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // ---- 从文件管理器选择 ----
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _importFromFilePicker,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('选择备份文件'),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('或扫描文档目录',
                            style: TextStyle(fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ),
                      const Expanded(child: Divider()),
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
                                    size: 48,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
                                const SizedBox(height: 8),
                                Text('没有找到备份文件',
                                    style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 4),
                                Text(
                                  '请先将 .json 备份文件放入 App 的文档目录\n然后点击刷新扫描',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('找到 ${files.length} 个备份文件：',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: theme
                                            .colorScheme.onSurfaceVariant)),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _selectMode = !_selectMode;
                                    if (!_selectMode) _selectedPaths.clear();
                                  }),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _selectMode ? Icons.close : Icons.checklist,
                                        size: 16,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        _selectMode ? '取消' : '选择',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
                              final isSelected = _selectedPaths.contains(file.path);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  leading: _selectMode
                                      ? Checkbox(
                                          value: isSelected,
                                          onChanged: (_) => setState(() {
                                            if (isSelected) {
                                              _selectedPaths.remove(file.path);
                                            } else {
                                              _selectedPaths.add(file.path);
                                            }
                                          }),
                                        )
                                      : Icon(Icons.description,
                                          color: theme.colorScheme.primary),
                                  title: Text(name,
                                      style: const TextStyle(fontSize: 14)),
                                  subtitle: Text('$size · $modTime',
                                      style:
                                          const TextStyle(fontSize: 11)),
                                  trailing: _selectMode
                                      ? null
                                      : Row(
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
                                  onTap: _selectMode
                                      ? () => setState(() {
                                            if (isSelected) {
                                              _selectedPaths.remove(file.path);
                                            } else {
                                              _selectedPaths.add(file.path);
                                            }
                                          })
                                      : null,
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
