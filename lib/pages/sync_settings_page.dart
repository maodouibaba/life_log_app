import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import '../services/sync_service.dart';
import '../services/photo_service.dart';
import '../services/backup_crypto.dart';
import '../database/app_database.dart';

/// 网络同步页面
/// 包含两个 Tab：坚果云 WebDAV 和 iCloud Drive
class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络同步'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.cloud_outlined), text: '坚果云'),
            Tab(icon: Icon(Icons.cloud_queue), text: 'iCloud'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _WebDavTab(),
          _ICloudTab(),
        ],
      ),
    );
  }
}

// ===================== 坚果云 WebDAV Tab =====================

class _WebDavTab extends StatefulWidget {
  const _WebDavTab();

  @override
  State<_WebDavTab> createState() => _WebDavTabState();
}

class _WebDavTabState extends State<_WebDavTab> {
  final _urlController = TextEditingController(
    text: 'https://dav.jianguoyun.com/dav/',
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  SyncConfig? _config;
  bool _testing = false;
  bool _uploading = false;
  bool _loadingFiles = false;
  String? _statusMsg;
  bool _statusIsError = false;

  List<RemoteFile> _remoteFiles = [];
  bool _loadedOnce = false;
  bool _selectMode = false;
  final Set<String> _selectedFileNames = {};

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  Future<void> _loadSavedConfig() async {
    final config = await SyncService.loadConfig();
    if (config != null && mounted) {
      _urlController.text = config.url;
      _usernameController.text = config.username;
      _passwordController.text = config.password;
      setState(() => _config = config);
      _refreshFileList();
    }
  }

  void _setStatus(String msg, {bool isError = false}) {
    setState(() {
      _statusMsg = msg;
      _statusIsError = isError;
    });
  }

  Future<void> _saveConfig() async {
    final config = SyncConfig(
      url: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
    );
    await SyncService.saveConfig(config);
    setState(() => _config = config);
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    _setStatus('正在测试...');
    try {
      final config = SyncConfig(
        url: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final ok = await SyncService.testConnection(config);
      if (ok) {
        _setStatus('✅ 连接成功');
        await _saveConfig();
        _refreshFileList();
      } else {
        _setStatus('❌ 连接失败', isError: true);
      }
    } catch (e) {
      _setStatus('❌ 连接异常：$e', isError: true);
    }
    setState(() => _testing = false);
  }

  Future<void> _uploadBackup() async {
    // 先让用户选择是否包含照片
    final includePhotos = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上传选项'),
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

    setState(() => _uploading = true);
    _setStatus('正在上传...');
    try {
      if (includePhotos) {
        await SyncService.uploadBackupZip(_config!);
      } else {
        await SyncService.uploadBackup(_config!);
      }
      _setStatus('✅ 上传成功');
      _refreshFileList();
    } catch (e) {
      _setStatus('❌ 上传异常：$e', isError: true);
    }
    setState(() => _uploading = false);
  }

  Future<void> _downloadAndRestore(RemoteFile file) async {
    final theme = Theme.of(context);
    final restoreType = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择恢复模式'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('备份文件：${file.name}', style: const TextStyle(fontSize: 13)),
              Text('备份时间：${file.modified}', style: const TextStyle(fontSize: 13)),
              Text('文件大小：${file.size}', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              const Text('请选择恢复方式：', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Icon(Icons.swap_horiz, color: theme.colorScheme.primary),
                  title: const Text('合并到本地'),
                  subtitle: const Text(
                    '将云端与本地数据合并，冲突时保留较新的版本。本地数据不会丢失。',
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
                    '清空所有本地数据，替换为云端备份。此操作不可撤销。',
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
            '不可撤销。建议先上传一份当前数据的备份。\n\n确定继续吗？',
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

    _setStatus('正在下载...');
    try {
      final isZip = file.name.endsWith('.zip');
      String json;
      int restoredPhotos = 0;

      if (isZip) {
        // 下载 ZIP，提取 JSON + 恢复照片
        final bytes = await SyncService.downloadBackupBytes(_config!, file.name);
        final archive = ZipDecoder().decodeBytes(bytes);
        String? jsonContent;
        for (final af in archive) {
          if (af.name.endsWith('.json')) {
            jsonContent = String.fromCharCodes(af.content);
          } else if (af.name.startsWith('photos/') && !af.name.endsWith('/')) {
            final photoName = af.name.substring('photos/'.length);
            final photoDir = await PhotoService().getPhotoDir();
            await File('${photoDir.path}/$photoName').writeAsBytes(af.content);
            restoredPhotos++;
          }
        }
        if (jsonContent == null) {
          _setStatus('❌ ZIP 中未找到备份数据', isError: true);
          return;
        }
        json = jsonContent;
      } else {
        final result = await SyncService.downloadBackup(_config!, file.name);
        if (result == null) {
          _setStatus('❌ 下载失败', isError: true);
          return;
        }
        json = result;
      }

      // 检测加密并解密
      if (BackupCrypto.isEncrypted(json)) {
        final pwdController = TextEditingController();
        final pwd = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('此备份已加密'),
            content: TextField(
              controller: pwdController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '请输入密码',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, pwdController.text.trim()),
                child: const Text('解密并恢复')),
            ],
          ),
        );
        pwdController.dispose();
        if (pwd == null || pwd.isEmpty) {
          _setStatus('已取消');
          return;
        }
        try {
          json = BackupCrypto.decrypt(json, pwd);
        } catch (e) {
          _setStatus('❌ 解密失败：密码错误或文件损坏', isError: true);
          return;
        }
      }

      final db = AppDatabase();
      if (restoreType == 'replace') {
        await db.importFromJson(json);
        _setStatus('✅ 已全量替换${restoredPhotos > 0 ? '（含 $restoredPhotos 张照片）' : ''}');
      } else {
        final result = await db.mergeFromJson(json);
        _setStatus('✅ 合并完成：新增 ${result['added_entries']} 条，更新 ${result['updated_entries']} 条${restoredPhotos > 0 ? '，恢复 $restoredPhotos 张照片' : ''}');
      }
    } catch (e) {
      _setStatus('❌ 恢复异常：$e', isError: true);
    }
  }

  Future<void> _refreshFileList() async {
    if (_config == null) return;
    setState(() => _loadingFiles = true);
    try {
      _remoteFiles = await SyncService.listBackups(_config!);
      _loadedOnce = true;
    } catch (e) {
      _setStatus('❌ 刷新列表失败：$e', isError: true);
    }
    setState(() => _loadingFiles = false);
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFileNames.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除备份'),
        content: Text('确定要删除选中的 ${_selectedFileNames.length} 个备份吗？'),
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
    if (confirm != true) return;
    for (final name in _selectedFileNames) {
      await SyncService.deleteBackup(_config!, name);
    }
    _selectedFileNames.clear();
    _refreshFileList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 连接信息
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_outlined, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('坚果云 WebDAV 配置',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'WebDAV 地址',
                    hintText: 'https://dav.jianguoyun.com/dav/',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    hintText: '坚果云注册邮箱',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '应用密码',
                    hintText: '登录坚果云→安全选项→添加第三方应用密码',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering, size: 18),
                    label: Text(_testing ? '测试中...' : '测试连接并保存'),
                  ),
                ),
                if (_statusMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_statusMsg!,
                        style: TextStyle(
                          color: _statusIsError
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                          fontSize: 13,
                        )),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 上传/刷新按钮
        if (_config != null)
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _uploading ? null : _uploadBackup,
                  icon: _uploading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: Text(_uploading ? '上传中...' : '上传到坚果云'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _loadingFiles ? null : _refreshFileList,
                icon: Icon(Icons.refresh, size: 18,
                    color: theme.colorScheme.primary),
                label: Text('刷新云端备份列表',
                    style: TextStyle(color: theme.colorScheme.primary)),
              ),
            ],
          ),

        // 云端文件列表
        if (_config != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('云端备份文件',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant)),
                      const Spacer(),
                      Text('${_remoteFiles.length} 个',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_loadingFiles)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (!_loadedOnce)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text('点击「刷新」查看云端备份')),
                    )
                  else if (_remoteFiles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text('暂无云端备份文件')),
                    )
                  else
                    ..._remoteFiles.map((file) => ListTile(
                          dense: true,
                          leading: _selectMode
                              ? Checkbox(
                                  value: _selectedFileNames.contains(file.name),
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedFileNames.add(file.name);
                                      } else {
                                        _selectedFileNames.remove(file.name);
                                      }
                                    });
                                  },
                                )
                              : Icon(Icons.description_outlined, size: 18,
                                  color: theme.colorScheme.primary),
                          title: Text(file.name,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            '${file.modified} · ${file.size}',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                          onTap: () {
                            if (_selectMode) {
                              setState(() {
                                if (_selectedFileNames.contains(file.name)) {
                                  _selectedFileNames.remove(file.name);
                                } else {
                                  _selectedFileNames.add(file.name);
                                }
                              });
                            } else {
                              _downloadAndRestore(file);
                            }
                          },
                        )),
                  if (_selectMode && _selectedFileNames.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _deleteSelectedFiles,
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: theme.colorScheme.error),
                          label: Text('删除选中 (${_selectedFileNames.length})'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  if (_remoteFiles.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        _selectMode = !_selectMode;
                        if (!_selectMode) _selectedFileNames.clear();
                      }),
                      child: Text(_selectMode ? '完成' : '选择'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// ===================== iCloud Drive Tab =====================

class _ICloudTab extends StatefulWidget {
  const _ICloudTab();

  @override
  State<_ICloudTab> createState() => _ICloudTabState();
}

class _ICloudTabState extends State<_ICloudTab> {
  final AppDatabase _db = AppDatabase();
  bool _uploading = false;
  String? _statusMsg;
  bool _statusIsError = false;

  void _setStatus(String msg, {bool isError = false}) {
    setState(() {
      _statusMsg = msg;
      _statusIsError = isError;
    });
  }

  /// 导出备份到 iCloud Drive（通过系统文件选择器）
  Future<void> _uploadToICloud() async {
    setState(() => _uploading = true);
    _setStatus('正在生成备份...');
    try {
      final json = await _db.exportToJson();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '生活记录备份_$timestamp.json';

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '保存备份到 iCloud Drive',
        fileName: fileName,
        bytes: utf8.encode(json),
      );

      if (savePath != null) {
        _setStatus('✅ 备份已保存');
      } else {
        _setStatus('已取消');
      }
    } catch (e) {
      _setStatus('❌ 导出失败：$e', isError: true);
    }
    setState(() => _uploading = false);
  }

  /// 从 iCloud Drive 选择备份文件并恢复
  Future<void> _pickAndRestore() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择备份文件',
        type: FileType.custom,
        allowedExtensions: ['json', 'zip'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final filePath = file.path;
      final fileName = file.name;
      if (filePath == null) {
        _setStatus('❌ 无法读取文件', isError: true);
        return;
      }

      // 读取文件内容，如果是 ZIP 同时恢复照片
      String content;
      int restoredPhotos = 0;
      final isZip = fileName.endsWith('.zip');
      if (isZip) {
        final bytes = await File(filePath).readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        ArchiveFile? jsonFile;
        for (final af in archive) {
          if (af.name.endsWith('.json')) {
            jsonFile = af;
          } else if (af.name.startsWith('photos/') && !af.name.endsWith('/')) {
            // 恢复照片到 app 目录
            final photoName = af.name.substring('photos/'.length);
            final photoDir = await PhotoService().getPhotoDir();
            await File('${photoDir.path}/$photoName').writeAsBytes(af.content);
            restoredPhotos++;
          }
        }
        if (jsonFile == null) {
          _setStatus('❌ ZIP 中未找到 JSON 备份', isError: true);
          return;
        }
        content = String.fromCharCodes(jsonFile.content);
      } else {
        content = await File(filePath).readAsString();
      }

      // 检测加密并解密
      if (BackupCrypto.isEncrypted(content)) {
        final pwdController = TextEditingController();
        final pwd = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('此备份已加密'),
            content: TextField(
              controller: pwdController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '请输入密码',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, pwdController.text.trim()),
                child: const Text('解密并恢复')),
            ],
          ),
        );
        pwdController.dispose();
        if (pwd == null || pwd.isEmpty) {
          _setStatus('已取消');
          return;
        }
        try {
          content = BackupCrypto.decrypt(content, pwd);
        } catch (e) {
          _setStatus('❌ 解密失败：密码错误或文件损坏', isError: true);
          return;
        }
      }

      // 选择恢复模式
      final theme = Theme.of(context);
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
                      '将云端与本地数据合并，冲突时保留较新的版本。本地数据不会丢失。',
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

      _setStatus('正在恢复...');
      if (restoreType == 'replace') {
        await _db.importFromJson(content);
        _setStatus('✅ 已全量替换${restoredPhotos > 0 ? '（含 $restoredPhotos 张照片）' : ''}');
      } else {
        final result = await _db.mergeFromJson(content);
        _setStatus('✅ 合并完成：新增 ${result['added_entries']} 条，更新 ${result['updated_entries']} 条${restoredPhotos > 0 ? '，恢复 $restoredPhotos 张照片' : ''}');
      }
    } catch (e) {
      _setStatus('❌ 恢复失败：$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_queue, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('iCloud Drive',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '通过系统文件选择器读写 iCloud Drive，无需额外配置。\n'
                  '导出：选择 iCloud Drive 中的目录保存备份\n'
                  '恢复：从 iCloud Drive 选择备份文件恢复',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _uploading ? null : _uploadToICloud,
            icon: _uploading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text(_uploading ? '生成中...' : '导出备份到 iCloud Drive'),
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : _pickAndRestore,
            icon: const Icon(Icons.cloud_download_outlined, size: 18),
            label: const Text('从 iCloud Drive 选择备份恢复'),
          ),
        ),

        if (_statusMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_statusMsg!,
                style: TextStyle(
                  color: _statusIsError
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                  fontSize: 13,
                )),
          ),
      ],
    );
  }
}
