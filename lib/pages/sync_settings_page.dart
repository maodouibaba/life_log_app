import 'package:flutter/material.dart';
import '../services/sync_service.dart';
import '../services/icloud_service.dart';
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
    setState(() => _uploading = true);
    _setStatus('正在上传...');
    try {
      await SyncService.uploadBackup(_config!);
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
      final json = await SyncService.downloadBackup(_config!, file.name);
      if (json == null) {
        _setStatus('❌ 下载失败', isError: true);
        return;
      }
      final db = AppDatabase();
      if (restoreType == 'replace') {
        await db.importFromJson(json);
        _setStatus('✅ 已全量替换');
      } else {
        final result = await db.mergeFromJson(json);
        _setStatus('✅ 合并完成：新增 ${result['added_entries']} 条，更新 ${result['updated_entries']} 条');
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
  final ICloudService _service = ICloudService();
  final AppDatabase _db = AppDatabase();
  String? _selectedDir;
  List<Map<String, dynamic>> _files = [];
  bool _loadingFiles = false;
  bool _uploading = false;
  String? _statusMsg;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _selectedDir = _service.lastSelectedDir;
  }

  void _setStatus(String msg, {bool isError = false}) {
    setState(() {
      _statusMsg = msg;
      _statusIsError = isError;
    });
  }

  Future<void> _pickDir() async {
    final dir = await _service.pickDirectory();
    if (dir != null) {
      setState(() => _selectedDir = dir);
      _refreshFiles();
    }
  }

  Future<void> _refreshFiles() async {
    if (_selectedDir == null) return;
    setState(() => _loadingFiles = true);
    try {
      _files = await _service.listBackupFiles(_selectedDir!);
    } catch (e) {
      _setStatus('❌ 刷新失败：$e', isError: true);
    }
    setState(() => _loadingFiles = false);
  }

  Future<void> _uploadToICloud() async {
    if (_selectedDir == null) return;
    setState(() => _uploading = true);
    _setStatus('正在上传...');
    try {
      final json = await _db.exportToJson();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '生活记录备份_$timestamp.json';
      final ok = await _service.saveBackupFile(_selectedDir!, fileName, json);
      if (ok) {
        _setStatus('✅ 上传成功');
        _refreshFiles();
      } else {
        _setStatus('❌ 上传失败', isError: true);
      }
    } catch (e) {
      _setStatus('❌ 上传异常：$e', isError: true);
    }
    setState(() => _uploading = false);
  }

  Future<void> _restoreFromFile(String filePath, String fileName) async {
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

    try {
      final content = await _service.readBackupFile(filePath);
      if (content == null) {
        _setStatus('❌ 读取文件失败', isError: true);
        return;
      }
      if (restoreType == 'replace') {
        await _db.importFromJson(content);
        _setStatus('✅ 已全量替换');
      } else {
        final result = await _db.mergeFromJson(content);
        _setStatus('✅ 合并完成：新增 ${result['added_entries']} 条，更新 ${result['updated_entries']} 条');
      }
    } catch (e) {
      _setStatus('❌ 恢复异常：$e', isError: true);
    }
  }

  Future<void> _deleteFile(String filePath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除备份'),
        content: Text('确定要删除此备份吗？'),
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
      await _service.deleteBackupFile(filePath);
      _refreshFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // iCloud 说明
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
                    const Text('iCloud Drive 同步',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '通过 iCloud Drive 文件共享实现多设备同步。\n'
                  '选择一个 iCloud Drive 目录，备份文件将保存到该目录，'
                  '其他设备可从同一目录读取恢复。',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickDir,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: Text(
                      _selectedDir != null
                          ? '已选择目录'
                          : '选择 iCloud Drive 目录',
                    ),
                  ),
                ),
                if (_selectedDir != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _selectedDir!,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (_selectedDir != null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _uploading ? null : _uploadToICloud,
              icon: _uploading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(_uploading ? '上传中...' : '上传备份到 iCloud'),
            ),
          ),
        if (_selectedDir != null)
          const SizedBox(height: 8),

        // 文件列表
        if (_selectedDir != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('iCloud 备份文件',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _refreshFiles,
                        icon: Icon(Icons.refresh, size: 16,
                            color: theme.colorScheme.primary),
                        label: Text('刷新',
                            style: TextStyle(
                                color: theme.colorScheme.primary, fontSize: 12)),
                      ),
                    ],
                  ),
                  if (_loadingFiles)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_files.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: Text('暂无备份文件\n请先上传或手动放入 iCloud Drive')),
                    )
                  else
                    ..._files.map((f) => ListTile(
                          dense: true,
                          leading: Icon(Icons.description_outlined, size: 18,
                              color: theme.colorScheme.primary),
                          title: Text(f['name'] as String,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            '${_service.formatSize(f['size'] as int)} · ${f['modified']}',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                          trailing: PopupMenuButton<String>(
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                  value: 'restore', child: Text('恢复'),
                                  ),
                              const PopupMenuItem(
                                  value: 'delete', child: Text('删除'),
                                  ),
                            ],
                            onSelected: (v) {
                              if (v == 'restore') {
                                _restoreFromFile(
                                    f['path'] as String, f['name'] as String);
                              } else if (v == 'delete') {
                                _deleteFile(f['path'] as String);
                              }
                            },
                          ),
                        )),
                ],
              ),
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
    );
  }
}
