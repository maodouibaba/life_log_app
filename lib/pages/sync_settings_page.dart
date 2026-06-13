import 'package:flutter/material.dart';
import '../services/sync_service.dart';
import '../database/app_database.dart';

/// 坚果云 WebDAV 同步设置页面
/// 配置连接信息、上传/下载/删除备份文件
class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  final _urlController = TextEditingController(
    text: 'https://dav.jianguoyun.com/dav/',
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  SyncConfig? _config;
  bool _testing = false;
  bool _uploading = false;
  bool _downloading = false;
  bool _loadingFiles = false;
  String? _statusMsg;
  bool _statusIsError = false;

  List<RemoteFile> _remoteFiles = [];
  bool _loadedOnce = false;
  // 批量选择
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

  SyncConfig? _buildConfig() {
    final url = _urlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (url.isEmpty || username.isEmpty || password.isEmpty) return null;
    return SyncConfig(url: url, username: username, password: password);
  }

  void _setStatus(String msg, {bool isError = false}) {
    setState(() {
      _statusMsg = msg;
      _statusIsError = isError;
    });
  }

  // ==================== 连接测试 ====================

  Future<void> _testConnection() async {
    final config = _buildConfig();
    if (config == null) {
      _setStatus('请填写完整的连接信息（地址、邮箱、应用密码）', isError: true);
      return;
    }
    setState(() => _testing = true);
    _setStatus('正在测试连接...');

    final ok = await SyncService.testConnection(config);
    if (!mounted) return;
    setState(() => _testing = false);

    if (ok) {
      await SyncService.saveConfig(config);
      setState(() => _config = config);
      _setStatus('✅ 连接成功！');
      _refreshFileList();
    } else {
      _setStatus('❌ 连接失败，请检查地址和密码是否正确', isError: true);
    }
  }

  // ==================== 列出云端文件 ====================

  Future<void> _refreshFileList() async {
    final config = _config;
    if (config == null) return;

    setState(() => _loadingFiles = true);
    try {
      final files = await SyncService.listBackups(config);
      if (!mounted) return;
      setState(() {
        _remoteFiles = files;
        _loadingFiles = false;
        _loadedOnce = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFiles = false;
        _loadedOnce = true;
      });
      _setStatus('❌ 获取备份列表失败：$e', isError: true);
    }
  }

  // ==================== 上传 ====================

  Future<void> _uploadBackup() async {
    final config = _config;
    if (config == null) {
      _setStatus('请先测试连接并保存配置', isError: true);
      return;
    }

    // 确认上传
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上传到坚果云'),
        content: const Text('将当前本地所有数据上传到坚果云保存。\n'
            '不会覆盖云端已有文件，而是创建新的时间戳备份。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定上传'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _uploading = true);
    _setStatus('正在上传...');

    try {
      final fileName = await SyncService.uploadBackup(config);
      if (!mounted) return;
      setState(() => _uploading = false);
      _setStatus('✅ 上传成功：$fileName');
      _refreshFileList();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _setStatus('❌ 上传失败：$e', isError: true);
    }
  }

  // ==================== 下载 ====================

  Future<void> _downloadBackup(RemoteFile file) async {
    final config = _config;
    if (config == null) return;

    final sizeStr = _formatSize(file.size);
    final dateStr = _formatDateTime(file.modified);
    // 选择恢复模式：覆盖 or 合并
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择恢复模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('备份文件：${file.name}', style: const TextStyle(fontSize: 13)),
            Text('备份时间：$dateStr', style: const TextStyle(fontSize: 13)),
            Text('文件大小：$sizeStr', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            const Text('请选择恢复方式：', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.teal),
                title: const Text('合并到本地'),
                subtitle: const Text('将云端与本地数据合并，'
                    '冲突时保留较新的版本。本地数据不会丢失。',
                    style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, SyncService.modeMerge),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.file_copy, color: Colors.red),
                title: const Text('覆盖恢复'),
                subtitle: const Text('清空所有本地数据，替换为云端备份。'
                    '此操作不可撤销。',
                    style: TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, SyncService.modeOverwrite),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
        ],
      ),
    );
    if (mode == null) return;

    // 覆盖模式再确认一次
    if (mode == SyncService.modeOverwrite) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认覆盖恢复'),
          content: const Text('此操作将清空所有本地数据并替换为备份内容，\n'
              '不可撤销。建议先上传一份当前数据的备份。\n\n确定继续吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('确定覆盖',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _downloading = true);
    _setStatus('正在下载...');

    try {
      final jsonContent =
          await SyncService.downloadBackup(config, file.name);
      if (!mounted) return;

      final db = AppDatabase();
      if (mode == SyncService.modeMerge) {
        // 合并模式
        final stats = await db.mergeFromJson(jsonContent);
        if (!mounted) return;
        setState(() => _downloading = false);
        final errors = stats['skipped_errors'] as int? ?? 0;
        final errHint = errors > 0 ? '（$errors 条异常已跳过）' : '';
        _setStatus('✅ 合并成功！新增 ${stats['added_entries']} 条记录、'
            '更新 ${stats['updated_entries']} 条、新增 ${stats['added_tags']} 个标签。'
            '$errHint');
      } else {
        // 覆盖模式（原有逻辑）
        await db.importFromJson(jsonContent);
        if (!mounted) return;
        setState(() => _downloading = false);
        _setStatus('✅ 覆盖恢复成功！本地数据已替换为云端备份。');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      _setStatus('❌ 恢复失败：$e', isError: true);
    }
  }

  // ==================== 删除 ====================

  Future<void> _deleteRemoteBackup(RemoteFile file) async {
    final config = _config;
    if (config == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除云端备份'),
        content: Text('确定要删除 "${file.name}" 吗？\n\n'
            '此操作将从坚果云中永久删除该备份文件。'),
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
    if (confirmed != true) return;

    try {
      await SyncService.deleteBackup(config, file.name);
      if (!mounted) return;
      _setStatus('已删除：${file.name}');
      _refreshFileList();
    } catch (e) {
      if (!mounted) return;
      _setStatus('❌ 删除失败：$e', isError: true);
    }
  }

  // ==================== 批量删除 ====================

  Future<void> _batchDeleteRemote() async {
    if (_selectedFileNames.isEmpty) return;
    final config = _config;
    if (config == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 ${_selectedFileNames.length} 个云端备份文件吗？'),
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
      int ok = 0;
      for (final name in _selectedFileNames) {
        try {
          await SyncService.deleteBackup(config, name);
          ok++;
        } catch (_) {}
      }
      _selectedFileNames.clear();
      _selectMode = false;
      setState(() {});
      _setStatus('已批量删除 $ok 个云端备份文件');
      _refreshFileList();
    }
  }

  // ==================== 清除配置 ====================

  Future<void> _clearConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除同步配置'),
        content: const Text('将清除已保存的坚果云账号和密码，确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('确定清除',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await SyncService.clearConfig();
    if (!mounted) return;
    setState(() {
      _config = null;
      _usernameController.clear();
      _passwordController.clear();
      _remoteFiles = [];
      _loadedOnce = false;
      _statusMsg = '已清除配置';
      _statusIsError = false;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('坚果云同步'),
        actions: [
          if (_config != null)
            IconButton(
              icon: const Icon(Icons.logout, size: 20),
              tooltip: '清除配置',
              onPressed: _clearConfig,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- 连接设置 ----
          _buildSectionCard(
            theme: theme,
            icon: Icons.cloud_outlined,
            title: '连接设置',
            children: [
              const Text(
                '配置坚果云 WebDAV 后，可在多设备间手动同步数据。\n'
                '请在坚果云官网 → 安全选项 → 添加「第三方应用密码」获取密码。',
                style: TextStyle(fontSize: 12),
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
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名（坚果云注册邮箱）',
                  hintText: 'example@jianguoyun.com',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 14),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码（第三方应用密码）',
                  hintText: '在坚果云官网生成的应用密码',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_testing ? '测试中...' : '测试连接并保存'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ---- 状态消息 ----
          if (_statusMsg != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusIsError
                    ? Colors.red.withValues(alpha: 0.08)
                    : Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _statusIsError
                      ? Colors.red.shade300
                      : Colors.green.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
                    size: 18,
                    color: _statusIsError ? Colors.red : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      _statusMsg!,
                      style: TextStyle(
                        fontSize: 13,
                        color: _statusIsError ? Colors.red[800] : Colors.green[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ---- 同步操作 ----
          if (_config != null) ...[
            const SizedBox(height: 16),
            _buildSectionCard(
              theme: theme,
              icon: Icons.sync,
              title: '同步操作',
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _uploading ? null : _uploadBackup,
                    icon: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(_uploading ? '上传中...' : '上传到坚果云'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _refreshFileList,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('刷新云端备份列表'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ---- 云端文件列表 ----
            _buildSectionCard(
              theme: theme,
              icon: Icons.folder_outlined,
              title: _selectMode ? '云端备份文件（已选 ${_selectedFileNames.length}）' : '云端备份文件',
              children: [
                // 批量选择操作栏
                if (_remoteFiles.isNotEmpty)
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() {
                          _selectMode = !_selectMode;
                          if (!_selectMode) _selectedFileNames.clear();
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
                      if (_selectMode && _selectedFileNames.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _batchDeleteRemote,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 16,
                                  color: theme.colorScheme.error),
                              const SizedBox(width: 2),
                              Text('删除所选（${_selectedFileNames.length}）',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.error,
                                  )),
                            ],
                          ),
                        ),
                      ],
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
                    padding: EdgeInsets.all(16),
                    child: Text('点击「刷新云端备份列表」查看',
                        style: TextStyle(color: Colors.grey)),
                  )
                else if (_remoteFiles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无云端备份文件，点击上方按钮上传',
                        style: TextStyle(color: Colors.grey)),
                  )
                else
                  ..._remoteFiles.map((file) => _buildFileTile(file, theme)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildFileTile(RemoteFile file, ThemeData theme) {
    final sizeStr = _formatSize(file.size);
    final dateStr = _formatDateTime(file.modified);
    final isSelected = _selectedFileNames.contains(file.name);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: _selectMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => setState(() {
                  if (isSelected) {
                    _selectedFileNames.remove(file.name);
                  } else {
                    _selectedFileNames.add(file.name);
                  }
                }),
              )
            : Icon(Icons.description, color: theme.colorScheme.primary),
        title: Text(file.name, style: const TextStyle(fontSize: 13)),
        subtitle: Text('$sizeStr · $dateStr',
            style: const TextStyle(fontSize: 11)),
        trailing: _selectMode
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _downloading ? null : () => _downloadBackup(file),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: const Text('恢复'),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                    tooltip: '删除云端备份',
                    onPressed: () => _deleteRemoteBackup(file),
                  ),
                ],
              ),
        onTap: _selectMode
            ? () => setState(() {
                  if (isSelected) {
                    _selectedFileNames.remove(file.name);
                  } else {
                    _selectedFileNames.add(file.name);
                  }
                })
            : null,
        dense: true,
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
