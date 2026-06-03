import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/entry.dart';
import '../models/tag.dart';

/// 列表视图页面
/// 支持按日期范围、标签筛选
class ListViewPage extends StatefulWidget {
  const ListViewPage({super.key});

  @override
  State<ListViewPage> createState() => _ListViewPageState();
}

class _ListViewPageState extends State<ListViewPage> {
  final AppDatabase _db = AppDatabase();
  List<Entry> _entries = [];
  List<Tag> _allTags = [];
  bool _loading = true;

  // 筛选条件
  DateTime? _startDate;
  DateTime? _endDate;
  int? _filterTagId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    _allTags = await _db.getAllTags();

    List<Entry> entries;
    if (_filterTagId != null) {
      entries = await _db.getEntriesByTag(_filterTagId!);
    } else if (_startDate != null && _endDate != null) {
      entries = await _db.getEntriesByDateRange(_startDate!, _endDate!);
    } else {
      entries = await _db.getAllEntries();
    }

    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (range != null) {
      setState(() {
        _startDate = range.start;
        _endDate = range.end;
        _filterTagId = null;
      });
      _loadData();
    }
  }

  Future<void> _pickTag() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => _TagPickerDialog(allTags: _allTags),
    );

    if (selected != null) {
      setState(() {
        _filterTagId = selected;
        _startDate = null;
        _endDate = null;
      });
      _loadData();
    }
  }

  void _clearFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _filterTagId = null;
    });
    _loadData();
  }

  String _getFilterLabel() {
    if (_filterTagId != null) {
      final tag = _allTags.firstWhere((t) => t.id == _filterTagId);
      return '标签：${tag.name}';
    }
    if (_startDate != null && _endDate != null) {
      return '${_startDate!.month}/${_startDate!.day} - ${_endDate!.month}/${_endDate!.day}';
    }
    return '全部记录';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFilter = _filterTagId != null || (_startDate != null && _endDate != null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('列表视图'),
      ),
      body: Column(
        children: [
          // 筛选栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _FilterChip(
                  icon: Icons.date_range,
                  label: _startDate != null ? '日期范围' : '日期',
                  active: _startDate != null,
                  onTap: _pickDateRange,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  icon: Icons.label,
                  label: _filterTagId != null ? '标签' : '标签',
                  active: _filterTagId != null,
                  onTap: _pickTag,
                ),
                if (hasFilter) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _clearFilter,
                    child: const Text('清除'),
                  ),
                ],
                const Spacer(),
                Text(
                  '${_entries.length} 条',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // 当前筛选标签
          if (hasFilter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Chip(
                label: Text(_getFilterLabel()),
                onDeleted: _clearFilter,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),

          const Divider(height: 1),

          // 列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? const Center(child: Text('没有匹配的记录'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          return ListTile(
                            title: Text(
                              entry.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatDateTime(entry.createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (entry.tags.isNotEmpty)
                                  Wrap(
                                    spacing: 4,
                                    children: entry.tags.map((t) => Text(
                                      t.name,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )).toList(),
                                  ),
                              ],
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
      color: active ? WidgetStateProperty.all(Theme.of(context).colorScheme.primaryContainer) : null,
    );
  }
}

/// 标签选择弹窗
class _TagPickerDialog extends StatefulWidget {
  final List<Tag> allTags;
  const _TagPickerDialog({required this.allTags});

  @override
  State<_TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<_TagPickerDialog> {
  final Set<int> _expandedIds = {};
  List<Tag> get _rootTags => widget.allTags.where((t) => t.parentId == null).toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择标签'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _rootTags.length,
          itemBuilder: (context, index) {
            return _buildTagNode(_rootTags[index], 0);
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      ],
    );
  }

  Widget _buildTagNode(Tag tag, int level) {
    final children = widget.allTags.where((t) => t.parentId == tag.id).toList();
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedIds.contains(tag.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: level * 20.0),
          child: ListTile(
            dense: true,
            leading: hasChildren
                ? Icon(isExpanded ? Icons.expand_more : Icons.chevron_right, size: 18)
                : const Icon(Icons.label_outline, size: 18),
            title: Text(tag.name),
            onTap: () { if (tag.id != null) Navigator.pop(context, tag.id); },
            trailing: hasChildren
                ? IconButton(
                    icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() {
                      if (isExpanded) { _expandedIds.remove(tag.id!);
                      } else { _expandedIds.add(tag.id!);
                      }
                    }),
                  )
                : null,
          ),
        ),
        if (isExpanded && hasChildren)
          ...children.map((c) => _buildTagNode(c, level + 1)),
      ],
    );
  }
}



