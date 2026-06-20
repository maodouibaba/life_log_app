import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/app_database.dart';
import '../models/entry.dart';
import '../services/ai_service.dart';
import '../utils/text_formatter.dart';

/// AI 总结页面
/// 按日期范围筛选记录，调用 AI 生成总结
class AISummaryPage extends StatefulWidget {
  final int spaceId;

  const AISummaryPage({super.key, required this.spaceId});

  @override
  State<AISummaryPage> createState() => _AISummaryPageState();
}

class _AISummaryPageState extends State<AISummaryPage> {
  final AppDatabase _db = AppDatabase();
  final _customPromptController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _customUrlController = TextEditingController();
  final _customModelController = TextEditingController();
  int _providerIndex = 0;

  DateTime? _startDate;
  DateTime? _endDate;
  List<Entry> _entries = [];
  bool _loading = false;
  bool _summarizing = false;
  String? _summary;
  int _entryCount = 0;

  int get _spaceId => widget.spaceId;

  @override
  void initState() {
    super.initState();
    final s = AISettings();
    _apiKeyController.text = s.apiKey;
    _customUrlController.text = s.customApiUrl;
    _customModelController.text = s.customModel;
    _providerIndex = s.providerIndex;
  }

  @override
  void dispose() {
    _customPromptController.dispose();
    _apiKeyController.dispose();
    _customUrlController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  /// 保存 AI 配置
  void _saveAiConfig() {
    final s = AISettings();
    s.apiKey = _apiKeyController.text.trim();
    s.providerIndex = _providerIndex;
    s.customApiUrl = _customUrlController.text.trim();
    s.customModel = _customModelController.text.trim();
    setState(() {});
  }

  Future<void> _pickDateRange() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('选择单日'),
              onTap: () => Navigator.pop(ctx, 'day'),
            ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('选择时段'),
              onTap: () => Navigator.pop(ctx, 'range'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'day') {
      final day = await showDatePicker(
        context: context,
        initialDate: _startDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        helpText: '选择日期',
      );
      if (day == null || !mounted) return;
      setState(() {
        _startDate = DateTime(day.year, day.month, day.day);
        _endDate = DateTime(day.year, day.month, day.day, 23, 59, 59);
        _summary = null;
      });
    } else {
      final from = await showDatePicker(
        context: context,
        initialDate: _startDate ?? DateTime.now().subtract(const Duration(days: 7)),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        helpText: '选择起始日期',
      );
      if (from == null || !mounted) return;

      final to = await showDatePicker(
        context: context,
        initialDate: _endDate ?? DateTime.now(),
        firstDate: from,
        lastDate: DateTime.now(),
        helpText: '选择结束日期',
      );
      if (to == null || !mounted) return;
      setState(() {
        _startDate = from;
        _endDate = to;
        _summary = null;
      });
    }
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    if (_startDate == null || _endDate == null) return;
    setState(() => _loading = true);
    try {
      final entries = await _db.getEntriesByDateRange(
        _startDate!, _endDate!, spaceId: _spaceId,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _entryCount = entries.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载记录失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _doSummary() async {
    if (_entries.isEmpty) return;
    if (!AISettings().hasKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中配置 AI API Key'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _summarizing = true;
      _summary = null;
    });

    try {
      final entryData = _entries.map((e) =>
          MapEntry(e.title ?? '', e.content)).toList();
      final prompt = _customPromptController.text.trim();
      final result = await AIService.summarize(entryData,
          customPrompt: prompt.isNotEmpty ? prompt : null);
      if (!mounted) return;
      setState(() {
        _summary = result;
        _summarizing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _summarizing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 总结'),
        actions: [
          if (_summary != null)
            IconButton(
              icon: const Icon(Icons.content_copy, size: 20),
              tooltip: '复制总结',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _summary!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('总结已复制到剪贴板'), duration: Duration(seconds: 2)),
                );
              },
            ),
            if (_summary != null)
              IconButton(
                icon: const Icon(Icons.select_all, size: 20),
                tooltip: '全选复制（纯文本）',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _summary!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('总结已复制到剪贴板'), duration: Duration(seconds: 2)),
                  );
                },
              ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- 如果没配 AI Key，先显示配置 ----
          if (!AISettings().hasKey)
            Card(
              color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.tertiary),
                        const SizedBox(width: 8),
                        const Text('配置 AI 服务',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('使用 AI 总结前，请先配置 API Key',
                        style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 16),
                    // 供应商选择
                    DropdownButtonFormField<int>(
                      value: _providerIndex >= 0 && _providerIndex < AIProvider.all.length ? _providerIndex : 0,
                      decoration: const InputDecoration(
                        labelText: 'AI 供应商',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: List.generate(AIProvider.all.length, (i) {
                        final p = AIProvider.all[i];
                        return DropdownMenuItem(value: i, child: Text(p.name));
                      }),
                      onChanged: (v) {
                        if (v != null) setState(() => _providerIndex = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    // API Key
                    TextField(
                      controller: _apiKeyController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: '输入你的 API Key',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    // 如果选了自定义，显示自定义 URL 和模型
                    if (_providerIndex >= 0 && _providerIndex < AIProvider.all.length &&
                        AIProvider.all[_providerIndex].name.contains('自定义')) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _customUrlController,
                        decoration: const InputDecoration(
                          labelText: '自定义 API 地址',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _customModelController,
                        decoration: const InputDecoration(
                          labelText: '模型名称',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          _saveAiConfig();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('✅ AI 配置已保存')),
                          );
                        },
                        child: const Text('保存配置并开始使用'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ---- 已配置时显示正常界面 ----
          if (AISettings().hasKey) ...[
          // ---- 日期范围选择 ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.date_range, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('选择日期范围',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _pickDateRange,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            _startDate != null && _endDate != null
                                ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
                                    ' ~ ${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                                : '点击选择日期范围',
                            style: TextStyle(
                              fontSize: 14,
                              color: _startDate != null
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---- 自定义提示词（可选） ----
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit_note, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text('总结要求（可选）',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customPromptController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '例如：帮我总结这周的工作重点、遇到的问题和下周计划',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.all(12),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ---- 记录数量 + 生成按钮 ----
          if (_entryCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '共 $_entryCount 条记录',
                style: TextStyle(
                    fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_loading || _summarizing || _entries.isEmpty)
                  ? null
                  : _doSummary,
              icon: _summarizing
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_summarizing
                  ? '正在生成总结...'
                  : _entries.isEmpty
                      ? '请先选择日期范围'
                      : '生成 AI 总结'),
            ),
          ),

          const SizedBox(height: 20),

          // ---- 总结结果 ----
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_summary != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        const Text('AI 总结',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 渲染 Markdown 格式
                    ...TextFormatter.render(
                      _summary!,
                      baseStyle: const TextStyle(fontSize: 14, height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _summary!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 2)),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('复制纯文本', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_entryCount} 条记录 · ${AISettings().provider.name}',
                          style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
