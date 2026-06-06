import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../database/app_database.dart';
import '../models/entry.dart';
import '../models/space.dart';
import 'entry_detail_page.dart';
import 'entry_editor_page.dart';
import 'tag_manager_page.dart';
import 'attribute_tag_manager_page.dart';
import 'project_manager_page.dart';
import 'list_view_page.dart';
import 'data_migration_page.dart';
import '../services/export_service.dart';
import '../services/undo_manager.dart';
import '../services/ai_service.dart';
import '../services/theme_settings.dart';
import '../utils/text_formatter.dart';

/// 首页时间线
/// 展示当前入口下的所有记录，按天分组
class HomePage extends StatefulWidget {
  final int spaceId;
  final VoidCallback onSwitchSpace;

  const HomePage({
    super.key,
    required this.spaceId,
    required this.onSwitchSpace,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AppDatabase _db = AppDatabase();
  List<Entry> _entries = [];
  bool _loading = true;
  String? _loadError;
  Space? _currentSpace;

  int get _spaceId => widget.spaceId;

  @override
  void initState() {
    super.initState();
    _loadSpace();
    _loadEntries();
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spaceId != widget.spaceId) {
      _loadSpace();
      _loadEntries();
    }
  }

  Future<void> _loadSpace() async {
    final spaces = await _db.getAllSpaces();
    if (!mounted) return;
    setState(() {
      _currentSpace = spaces.cast<Space?>().firstWhere(
            (s) => s!.id == _spaceId,
            orElse: () => null,
          );
    });
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final entries = await _db.getAllEntries(spaceId: _spaceId).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('加载记录超时');
          return [];
        },
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      debugPrint('加载记录失败：$e');
      if (!mounted) return;
      setState(() {
        _entries = [];
        _loading = false;
        _loadError = '数据库读取错误：$e';
      });
    }
  }

  // 按天分组
  Map<String, List<Entry>> _groupByDate(List<Entry> entries) {
    final map = <String, List<Entry>>{};
    for (final entry in entries) {
      final dateKey =
          '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}-${entry.createdAt.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(dateKey, () => []);
      map[dateKey]!.add(entry);
    }
    return map;
  }

  String _formatDateKey(String key) {
    final parts = key.split('-');
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final date =
        DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final weekday = weekdays[date.weekday - 1];
    return '${parts[0]}年${parts[1].replaceFirst(RegExp(r'^0'), '')}月${parts[2].replaceFirst(RegExp(r'^0'), '')}日 周$weekday';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 显示 AI 助写设置弹窗
  Future<void> _showAISettings() async {
    final settings = AISettings();
    final keyController = TextEditingController(text: settings.apiKey);
    final urlController = TextEditingController(text: settings.customApiUrl);
    final modelController = TextEditingController(text: settings.customModel);
    final promptController = TextEditingController(text: settings.customPrompt);
    bool enabled = settings.enabled;
    int providerIndex = settings.providerIndex;
    int styleIndex = settings.styleIndex;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.auto_awesome,
                  color: Theme.of(ctx).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('AI 助写设置'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '开启后，在输入事项简介和详细情况时，'
                  '可使用 AI 对文本进行润色整理。',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                // 开关
                SwitchListTile(
                  title: const Text('启用 AI 助写'),
                  subtitle: Text(
                    enabled ? '输入框将显示 AI 润色按钮' : 'AI 功能已关闭',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                if (enabled) ...[
                  const SizedBox(height: 12),
                  // 供应商选择
                  const Text('AI 供应商',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    value: providerIndex,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: List.generate(AIProvider.all.length, (i) {
                      final p = AIProvider.all[i];
                      return DropdownMenuItem(
                        value: i,
                        child: Text(p.name, style: const TextStyle(fontSize: 14)),
                      );
                    }),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => providerIndex = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  // 默认风格
                  const Text('默认写作风格',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    value: styleIndex,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: List.generate(AIWritingStyle.all.length, (i) {
                      return DropdownMenuItem(
                        value: i,
                        child: Text(AIWritingStyle.all[i].name, style: const TextStyle(fontSize: 14)),
                      );
                    }),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => styleIndex = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  // API Key
                  const Text('API Key',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: keyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: AIProvider.all[providerIndex].name.contains('DeepSeek')
                          ? 'sk-...'
                          : AIProvider.all[providerIndex].name.contains('Claude')
                              ? 'sk-ant-...'
                              : '输入你的 API Key',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  // 自定义选项
                  if (AIProvider.all[providerIndex].name == '自定义') ...[
                    const SizedBox(height: 12),
                    const Text('API 地址',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        hintText: 'https://api.example.com/v1/chat/completions',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    const Text('模型名称',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: modelController,
                      decoration: const InputDecoration(
                        hintText: 'gpt-4o-mini',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _apiKeyHint(providerIndex),
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  // 自定义提示词（仅在选择"自定义"风格时显示）
                  if (AIWritingStyle.all[styleIndex].name == '自定义') ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.edit_note, size: 16,
                            color: Theme.of(ctx).colorScheme.primary),
                        const SizedBox(width: 6),
                        const Text('自定义提示词',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '输入你自己的润色提示词',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: promptController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: '输入你的润色提示词...',
                        border: OutlineInputBorder(),
                        isDense: true,
                        alignLabelWithHint: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                settings.apiKey = keyController.text.trim();
                settings.enabled = enabled;
                settings.providerIndex = providerIndex;
                settings.customApiUrl = urlController.text.trim();
                settings.customModel = modelController.text.trim();
                settings.customPrompt = promptController.text.trim();
                settings.styleIndex = styleIndex;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(
                      enabled && settings.hasKey
                          ? 'AI 助写已启用（${AIProvider.all[providerIndex].name}）'
                          : enabled
                              ? '请填写 API Key'
                              : 'AI 助写已关闭')),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    keyController.dispose();
    urlController.dispose();
    modelController.dispose();
    promptController.dispose();
  }

  String _apiKeyHint(int providerIndex) {
    switch (providerIndex) {
      case 1: return '通义千问 API Key 从 dashscope.aliyun.com 获取';
      case 2: return 'Anthropic API Key 从 console.anthropic.com 获取';
      case 3: return 'OpenAI API Key 从 platform.openai.com 获取';
      case 4: return '填写自定义 API 地址和模型名称（兼容 OpenAI 格式）';
      default: return 'DeepSeek API Key 从 platform.deepseek.com 获取';
    }
  }

  Future<void> _exportToExcel() async {
    try {
      final exportService = ExportService();
      final filePath = await exportService.exportToExcel(spaceId: _spaceId);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出成功：$filePath'),
          action: SnackBarAction(
            label: '打开',
            onPressed: () => OpenFilex.open(filePath),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(_entries);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: widget.onSwitchSpace,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_currentSpace?.name ?? '记录'),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 20,
                  color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: '列表视图',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ListViewPage(spaceId: _spaceId),
                ),
              );
              _loadEntries();
            },
          ),
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: '树状标签',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TagManagerPage(spaceId: _spaceId),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.turned_in_not_outlined),
            tooltip: '属性标签',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AttributeTagManagerPage(spaceId: _spaceId),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: '项目管理',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProjectManagerPage(spaceId: _spaceId),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onSelected: (value) async {
              switch (value) {
                case 'export_excel':
                  await _exportToExcel();
                  break;
                case 'data_migration':
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DataMigrationPage()),
                  );
                  _loadEntries();
                  break;
                case 'switch_space':
                  widget.onSwitchSpace();
                  break;
                case 'ai_settings':
                  if (!context.mounted) return;
                  await _showAISettings();
                  break;
                case 'theme':
                  ThemeSettings().nextMode();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已切换为${ThemeSettings().label}')),
                    );
                  }
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export_excel',
                child: ListTile(
                  leading: Icon(Icons.file_download_outlined),
                  title: Text('导出 Excel'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'data_migration',
                child: ListTile(
                  leading: Icon(Icons.sync_alt),
                  title: Text('数据备份'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'switch_space',
                child: ListTile(
                  leading: Icon(Icons.swap_horiz),
                  title: Text('切换入口'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'ai_settings',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome),
                  title: Text('AI 助写设置'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'theme',
                child: ListTile(
                  leading: Icon(ThemeSettings().icon),
                  title: Text('主题：${ThemeSettings().label}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text('读取数据失败',
                            style: TextStyle(fontSize: 18)),
                        const SizedBox(height: 8),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _loadEntries,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : _entries.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit_note,
                              size: 80, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('还没有记录',
                              style:
                                  TextStyle(fontSize: 18, color: Colors.grey)),
                          SizedBox(height: 8),
                          Text('点击右下角 + 开始记录',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadEntries,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: grouped.keys.length,
                        itemBuilder: (context, index) {
                          final dateKey = grouped.keys.elementAt(index);
                          final dayEntries = grouped[dateKey]!;
                          return _DayGroup(
                            dateLabel: _formatDateKey(dateKey),
                            entries: dayEntries,
                            formatTime: _formatTime,
                            onTap: (entry) async {
                              final result = await Navigator.push<Object>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EntryDetailPage(entry: entry),
                                ),
                              );
                              _loadEntries();
                              if (result == 'edit' && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('已保存'),
                                    action: SnackBarAction(
                                      label: '撤销',
                                      onPressed: () async {
                                        final ok =
                                            await UndoManager().undoEdit();
                                        if (mounted) {
                                          _loadEntries();
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    ok ? '已撤销编辑' : '撤销失败')),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                );
                              }
                            },
                            onDelete: (entry) async {
                              // 记录到撤销管理器
                              UndoManager().recordDeletion(entry);
                              await _db.deleteEntry(entry.id!);
                              _loadEntries();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('已删除'),
                                  action: SnackBarAction(
                                    label: '撤销',
                                    onPressed: () async {
                                      final ok = await UndoManager().undoDelete();
                                      if (mounted) {
                                        if (ok) {
                                          _loadEntries();
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text('已撤销删除')),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text('撤销失败'),
                                                backgroundColor: Colors.red),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result =
              await EntryEditorPage.showAsSheet(context, spaceId: _spaceId);
          _loadEntries();
          if (result == 'edit' && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('已保存'),
                action: SnackBarAction(
                  label: '撤销',
                  onPressed: () async {
                    final ok = await UndoManager().undoEdit();
                    if (mounted) {
                      if (ok) {
                        _loadEntries();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已撤销编辑')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('撤销失败'),
                              backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                ),
              ),
            );
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _DayGroup extends StatefulWidget {
  final String dateLabel;
  final List<Entry> entries;
  final String Function(DateTime) formatTime;
  final Function(Entry) onTap;
  final Function(Entry) onDelete;

  const _DayGroup({
    required this.dateLabel,
    required this.entries,
    required this.formatTime,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_DayGroup> createState() => _DayGroupState();
}

class _DayGroupState extends State<_DayGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.dateLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.entries.length} 条',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ...widget.entries.map((entry) => _EntryCard(
                  entry: entry,
                  formatTime: widget.formatTime,
                  onTap: () => widget.onTap(entry),
                  onDelete: () => widget.onDelete(entry),
                )),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final Entry entry;
  final String Function(DateTime) formatTime;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _EntryCard({
    required this.entry,
    required this.formatTime,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatTime(entry.createdAt),
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 事项简介（如果有）
                    if (entry.title != null && entry.title!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          entry.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    // 内容截断（最多2行，去除格式符号）
                    Text(
                      TextFormatter.stripMarkdown(entry.content),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: entry.title != null && entry.title!.isNotEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 项目名 + 标签
                    Row(
                      children: [
                        if (entry.projectName != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                entry.projectName!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                        if (entry.tags.isNotEmpty)
                          Flexible(
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: entry.tags.map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        theme.colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    tag.name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme
                                          .colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    ),
                    // 属性标签
                    if (entry.attributeTags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: entry.attributeTags.map((at) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                at.name,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: theme.colorScheme.error),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('删除记录'),
                  content: const Text('确定要删除这条记录吗？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消')),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onDelete();
                      },
                      child: Text('删除',
                          style:
                              TextStyle(color: theme.colorScheme.error)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
