import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/entry.dart';
import '../models/tag.dart';
import 'entry_detail_page.dart';

/// 列表视图页面
/// 支持按日期范围、标签筛选，批量删除，批量替换标签
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

  // 多选模式
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

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
    try {
      _allTags = await _db.getAllTags().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('加载标签超时');
          return [];
        },
      );

      List<Entry> entries;
      if (_filterTagId != null) {
        entries = await _db.getEntriesByTag(_filterTagId!).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('按标签查询超时');
            return [];
          },
        );
      } else if (_startDate != null && _endDate != null) {
        entries = await _db.getEntriesByDateRange(_startDate!, _endDate!).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('按日期查询超时');
            return [];
          },
        );
      } else {
        entries = await _db.getAllEntries().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('加载所有记录超时');
            return [];
          },
        );
      }

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      debugPrint('加载数据失败：$e');
      if (!mounted) return;
      setState(() {
        _entries = [];
        _loading = false;
      });
    }
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

  // ==================== 批量操作 ====================

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleItem(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 条记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteEntries(_selectedIds.toList());
      _selectedIds.clear();
      _loadData();
    }
  }

  Future<void> _batchReplaceTags() async {
    if (_selectedIds.isEmpty) return;
    // 刷新最新标签列表
    _allTags = await _db.getAllTags();
    if (!mounted) return;

    final tagIds = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => _MultiTagPickerDialog(allTags: _allTags),
    );
    if (tagIds == null || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量替换标签'),
        content: Text('将 ${_selectedIds.length} 条记录的标签替换为所选标签吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.batchReplaceTags(_selectedIds.toList(), tagIds);
      if (!mounted) return;
      _selectedIds.clear();
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFilter = _filterTagId != null || (_startDate != null && _endDate != null);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selectedIds.length} 条' : '列表视图'),
        actions: [
          if (_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
              onPressed: () {
                setState(() {
                  if (_selectedIds.length == _entries.length) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds.addAll(_entries.map((e) => e.id!));
                  }
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.label, color: theme.colorScheme.primary),
              tooltip: '替换标签',
              onPressed: _batchReplaceTags,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              tooltip: '批量删除',
              onPressed: _batchDelete,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消选择',
              onPressed: _toggleSelectMode,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: '选择',
              onPressed: _toggleSelectMode,
            ),
          ],
        ],
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
                  onTap: _selectMode ? null : _pickDateRange,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  icon: Icons.label,
                  label: _filterTagId != null ? '标签' : '标签',
                  active: _filterTagId != null,
                  onTap: _selectMode ? null : _pickTag,
                ),
                if (hasFilter) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _selectMode ? null : _clearFilter,
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
                onDeleted: _selectMode ? null : _clearFilter,
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
                          final isSelected = _selectedIds.contains(entry.id);

                          if (_selectMode) {
                            return ListTile(
                              leading: Checkbox(
                                value: isSelected,
                                onChanged: (_) => _toggleItem(entry.id!),
                              ),
                              title: Text(
                                entry.content,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                _formatDateTime(entry.createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                              onTap: () => _toggleItem(entry.id!),
                            );
                          }

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
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(
                                      spacing: 4,
                                      children: entry.tags.map((t) => Text(
                                        t.name,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.colorScheme.primary,
                                        ),
                                      )).toList(),
                                    ),
                                  ),
                              ],
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EntryDetailPage(entry: entry),
                                ),
                              );
                              _loadData();
                            },
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
  final VoidCallback? onTap;

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

/// 标签选择弹窗（单选，用于筛选）
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

/// 多标签选择弹窗（用于批量替换）
class _MultiTagPickerDialog extends StatefulWidget {
  final List<Tag> allTags;
  const _MultiTagPickerDialog({required this.allTags});

  @override
  State<_MultiTagPickerDialog> createState() => _MultiTagPickerDialogState();
}

class _MultiTagPickerDialogState extends State<_MultiTagPickerDialog> {
  final Set<int> _selectedIds = {};
  final Set<int> _expandedIds = {};
  List<Tag> get _rootTags => widget.allTags.where((t) => t.parentId == null).toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('选择新标签（已选 ${_selectedIds.length}）'),
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
        TextButton(
          onPressed: _selectedIds.isEmpty ? null : () => Navigator.pop(context, _selectedIds.toList()),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildTagNode(Tag tag, int level) {
    final children = widget.allTags.where((t) => t.parentId == tag.id).toList();
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedIds.contains(tag.id);
    final isSelected = _selectedIds.contains(tag.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: level * 20.0),
          child: ListTile(
            dense: true,
            leading: Checkbox(
              value: isSelected,
              onChanged: (_) {
                setState(() {
                  if (isSelected) {
                    _selectedIds.remove(tag.id!);
                  } else {
                    _selectedIds.add(tag.id!);
                  }
                });
              },
            ),
            title: Text(tag.name, style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : null)),
            onTap: hasChildren
                ? () => setState(() {
                      if (isExpanded) { _expandedIds.remove(tag.id!);
                      } else { _expandedIds.add(tag.id!);
                      }
                    })
                : () {
                    setState(() {
                      if (isSelected) {
                        _selectedIds.remove(tag.id!);
                      } else {
                        _selectedIds.add(tag.id!);
                      }
                    });
                  },
            trailing: hasChildren
                ? Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 16)
                : null,
          ),
        ),
        if (isExpanded && hasChildren)
          ...children.map((c) => _buildTagNode(c, level + 1)),
      ],
    );
  }
}
