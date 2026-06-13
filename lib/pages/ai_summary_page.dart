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

  DateTime? _startDate;
  DateTime? _endDate;
  List<Entry> _entries = [];
  bool _loading = false;
  bool _summarizing = false;
  String? _summary;
  int _entryCount = 0;

  int get _spaceId => widget.spaceId;

  @override
  void dispose() {
    _customPromptController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
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
      ),
    );
  }
}
