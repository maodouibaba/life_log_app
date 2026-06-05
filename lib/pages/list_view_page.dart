import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/entry.dart';
import '../models/tag.dart';
import '../models/project.dart';
import '../models/attribute_tag.dart';
import 'entry_detail_page.dart';

/// 列表视图页面
/// 支持按日期范围/单日、标签（树状&属性）、项目筛选，关键词搜索，批量操作
class ListViewPage extends StatefulWidget {
  final int spaceId;

  const ListViewPage({super.key, required this.spaceId});

  @override
  State<ListViewPage> createState() => _ListViewPageState();
}

class _ListViewPageState extends State<ListViewPage> {
  final AppDatabase _db = AppDatabase();
  List<Entry> _entries = [];
  List<Tag> _allTags = [];
  List<Project> _allProjects = [];
  List<AttributeTag> _allAttributeTags = [];
  bool _loading = true;

  // 多选模式
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  // 筛选条件（多选 + 组合）
  DateTime? _startDate;
  DateTime? _endDate;
  final Set<int> _filterTagIds = {};
  final Set<int> _filterProjectIds = {};
  final Set<int> _filterAttributeTagIds = {};

  // 关键词搜索
  final _searchController = TextEditingController();
  String _searchKeyword = '';

  // 自定义分组
  String _groupBy = 'date'; // 'date' | 'project' | 'none'

  int get _spaceId => widget.spaceId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      _allTags = await _db.getAllTags(spaceId: _spaceId).timeout(
        const Duration(seconds: 10),
        onTimeout: () => [],
      );
      _allProjects = await _db.getAllProjects(spaceId: _spaceId).timeout(
        const Duration(seconds: 10),
        onTimeout: () => [],
      );
      _allAttributeTags =
          await _db.getAllAttributeTags(_spaceId).timeout(
        const Duration(seconds: 10),
        onTimeout: () => [],
      );

      // 组合筛选：所有活跃条件 AND 组合
      final entries = await _db.getEntriesByFilters(
        spaceId: _spaceId,
        tagIds: _filterTagIds.isNotEmpty ? _filterTagIds : null,
        attributeTagIds:
            _filterAttributeTagIds.isNotEmpty ? _filterAttributeTagIds : null,
        projectIds: _filterProjectIds.isNotEmpty ? _filterProjectIds : null,
        startDate: _startDate,
        endDate: _endDate,
        keyword: _searchKeyword.isNotEmpty ? _searchKeyword : null,
      ).timeout(const Duration(seconds: 10), onTimeout: () => []);

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

  // ==================== 筛选条件 ====================

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
      });
      _loadData();
    }
  }

  /// 单日筛选
  Future<void> _pickSingleDay() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _startDate ?? DateTime.now(),
    );
    if (date != null) {
      final dayStart = DateTime(date.year, date.month, date.day);
      final dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59);
      setState(() {
        _startDate = dayStart;
        _endDate = dayEnd;
      });
      _loadData();
    }
  }

  Future<void> _pickTag() async {
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) => _MultiTagFilterDialog(
        allTags: _allTags,
        initialSelectedIds: _filterTagIds,
      ),
    );

    if (result != null) {
      setState(() => _filterTagIds
        ..clear()
        ..addAll(result));
      _loadData();
    }
  }

  Future<void> _pickAttributeTag() async {
    _allAttributeTags = await _db.getAllAttributeTags(_spaceId);
    if (!mounted) return;
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) => _MultiAttributeTagFilterDialog(
        tags: _allAttributeTags,
        initialSelectedIds: _filterAttributeTagIds,
      ),
    );

    if (result != null) {
      setState(() => _filterAttributeTagIds
        ..clear()
        ..addAll(result));
      _loadData();
    }
  }

  Future<void> _pickProject() async {
    _allProjects = await _db.getAllProjects(spaceId: _spaceId);
    if (!mounted) return;

    final result = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) => _MultiProjectFilterDialog(
        projects: _allProjects,
        initialSelectedIds: _filterProjectIds,
      ),
    );

    if (result != null) {
      setState(() => _filterProjectIds
        ..clear()
        ..addAll(result));
      _loadData();
    }
  }

  void _clearFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _filterTagIds.clear();
      _filterProjectIds.clear();
      _filterAttributeTagIds.clear();
      _searchKeyword = '';
      _searchController.clear();
    });
    _loadData();
  }

  void _doSearch(String keyword) {
    setState(() => _searchKeyword = keyword.trim());
    _loadData();
  }

  bool get _hasFilter =>
      _filterTagIds.isNotEmpty ||
      _filterProjectIds.isNotEmpty ||
      _filterAttributeTagIds.isNotEmpty ||
      (_startDate != null && _endDate != null) ||
      _searchKeyword.isNotEmpty;

  /// 获取所有活跃筛选条件的标签列表
  List<Widget> _buildFilterChips(ThemeData theme) {
    final chips = <Widget>[];
    void addChip(IconData icon, String label, VoidCallback onRemove) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 2),
        child: Chip(
          avatar: Icon(icon, size: 14),
          label: Text(label, style: const TextStyle(fontSize: 11)),
          onDeleted: _selectMode ? null : onRemove,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ));
    }

    if (_searchKeyword.isNotEmpty) {
      addChip(Icons.search, '搜索：$_searchKeyword', () {
        _searchController.clear();
        _doSearch('');
      });
    }
    if (_filterTagIds.isNotEmpty) {
      final names = _allTags
          .where((t) => _filterTagIds.contains(t.id))
          .map((t) => t.name)
          .join(', ');
      addChip(Icons.label, '标签：$names', () {
        setState(() => _filterTagIds.clear());
        _loadData();
      });
    }
    if (_filterAttributeTagIds.isNotEmpty) {
      final names = _allAttributeTags
          .where((t) => _filterAttributeTagIds.contains(t.id))
          .map((t) => t.name)
          .join(', ');
      addChip(Icons.turned_in_not, '属性：$names', () {
        setState(() => _filterAttributeTagIds.clear());
        _loadData();
      });
    }
    if (_filterProjectIds.isNotEmpty) {
      final names = _allProjects
          .where((p) => _filterProjectIds.contains(p.id))
          .map((p) => p.name)
          .join(', ');
      addChip(Icons.folder_outlined, '项目：$names', () {
        setState(() => _filterProjectIds.clear());
        _loadData();
      });
    }
    if (_startDate != null && _endDate != null) {
      final isSingle = _startDate!.day == _endDate!.day &&
          _startDate!.month == _endDate!.month &&
          _startDate!.year == _endDate!.year;
      final label = isSingle
          ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
          : '${_startDate!.month}/${_startDate!.day} - ${_endDate!.month}/${_endDate!.day}';
      addChip(Icons.date_range, label, () {
        setState(() {
          _startDate = null;
          _endDate = null;
        });
        _loadData();
      });
    }
    return chips;
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ==================== 分组 ====================

  Map<String, List<Entry>> _groupEntries(List<Entry> entries) {
    switch (_groupBy) {
      case 'project':
        final map = <String, List<Entry>>{};
        for (final entry in entries) {
          final key = entry.projectName ?? '未分组';
          map.putIfAbsent(key, () => []);
          map[key]!.add(entry);
        }
        return map;
      case 'tag':
        final map = <String, List<Entry>>{};
        for (final entry in entries) {
          final key = entry.tags.isNotEmpty
              ? entry.tags.first.name
              : '未标签';
          map.putIfAbsent(key, () => []);
          map[key]!.add(entry);
        }
        return map;
      case 'attribute_tag':
        final map = <String, List<Entry>>{};
        for (final entry in entries) {
          final key = entry.attributeTags.isNotEmpty
              ? entry.attributeTags.first.name
              : '未标签';
          map.putIfAbsent(key, () => []);
          map[key]!.add(entry);
        }
        return map;
      case 'none':
        return {'': entries};
      default: // date
        final map = <String, List<Entry>>{};
        for (final entry in entries) {
          final key =
              '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}-${entry.createdAt.day.toString().padLeft(2, '0')}';
          map.putIfAbsent(key, () => []);
          map[key]!.add(entry);
        }
        return map;
    }
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
        content:
            Text('确定要删除选中的 ${_selectedIds.length} 条记录吗？'),
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
    if (confirm == true) {
      await _db.deleteEntries(_selectedIds.toList());
      _selectedIds.clear();
      _loadData();
    }
  }

  Future<void> _batchReplaceTags() async {
    if (_selectedIds.isEmpty) return;
    _allTags = await _db.getAllTags(spaceId: _spaceId);
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
        content: Text(
            '将 ${_selectedIds.length} 条记录的树状标签替换为所选标签吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
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

    final grouped = _groupEntries(_entries);

    return Scaffold(
      appBar: AppBar(
        title: Text(
            _selectMode ? '已选 ${_selectedIds.length} 条' : '列表视图'),
        actions: [
          if (_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '全选/取消',
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
              icon: Icon(Icons.label,
                  color: theme.colorScheme.primary),
              tooltip: '替换树状标签',
              onPressed: _batchReplaceTags,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: theme.colorScheme.error),
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
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索内容、标签...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchKeyword.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _doSearch('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withOpacity(0.3),
                isDense: true,
              ),
              onSubmitted: _doSearch,
              textInputAction: TextInputAction.search,
            ),
          ),

          // 筛选栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _FilterChip(
                  icon: Icons.date_range,
                  label: '日期',
                  active: _startDate != null,
                  onTap: _selectMode ? null : _pickSingleDay,
                  onLongPress: _selectMode ? null : _pickDateRange,
                ),
                const SizedBox(width: 4),
                _FilterChip(
                  icon: Icons.label,
                  label: '树状标签',
                  active: _filterTagIds.isNotEmpty,
                  onTap: _selectMode ? null : _pickTag,
                ),
                const SizedBox(width: 4),
                _FilterChip(
                  icon: Icons.turned_in_not,
                  label: '属性标签',
                  active: _filterAttributeTagIds.isNotEmpty,
                  onTap: _selectMode ? null : _pickAttributeTag,
                ),
                const SizedBox(width: 4),
                _FilterChip(
                  icon: Icons.folder_outlined,
                  label: '项目',
                  active: _filterProjectIds.isNotEmpty,
                  onTap: _selectMode ? null : _pickProject,
                ),
                const Spacer(),
                // 分组方式切换
                PopupMenuButton<String>(
                  icon: const Icon(Icons.view_headline, size: 20),
                  tooltip: '分组方式',
                  onSelected: (v) => setState(() => _groupBy = v),
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: 'date',
                      checked: _groupBy == 'date',
                      child: const Text('按日期'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'project',
                      checked: _groupBy == 'project',
                      child: const Text('按项目'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'tag',
                      checked: _groupBy == 'tag',
                      child: const Text('按树状标签'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'attribute_tag',
                      checked: _groupBy == 'attribute_tag',
                      child: const Text('按属性标签'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'none',
                      checked: _groupBy == 'none',
                      child: const Text('不分组'),
                    ),
                  ],
                ),
                Text(
                  ' ${_entries.length}',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13),
                ),
              ],
            ),
          ),

          // 当前活跃筛选条件（多标签展示）
          if (_hasFilter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Wrap(
                children: [
                  ..._buildFilterChips(theme),
                  TextButton.icon(
                    onPressed: _selectMode ? null : _clearFilter,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('清除', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // 列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? const Center(child: Text('没有匹配的记录'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: grouped.keys.length,
                        itemBuilder: (context, index) {
                          final key = grouped.keys.elementAt(index);
                          final entries = grouped[key]!;
                          return _GroupSection(
                            groupLabel: key,
                            entries: entries,
                            selectMode: _selectMode,
                            selectedIds: _selectedIds,
                            theme: theme,
                            onToggle: _toggleItem,
                            onTapEntry: (entry) async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EntryDetailPage(entry: entry),
                                ),
                              );
                              _loadData();
                            },
                            formatDateTime: _formatDateTime,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ==================== 组件 ====================

class _GroupSection extends StatelessWidget {
  final String groupLabel;
  final List<Entry> entries;
  final bool selectMode;
  final Set<int> selectedIds;
  final ThemeData theme;
  final Function(int) onToggle;
  final Function(Entry) onTapEntry;
  final String Function(DateTime) formatDateTime;

  const _GroupSection({
    required this.groupLabel,
    required this.entries,
    required this.selectMode,
    required this.selectedIds,
    required this.theme,
    required this.onToggle,
    required this.onTapEntry,
    required this.formatDateTime,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (groupLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4, left: 4),
            child: Text(groupLabel,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary)),
          ),
        ...entries.map((entry) {
          final isSelected = selectedIds.contains(entry.id);

          if (selectMode) {
            return ListTile(
              leading: Checkbox(
                value: isSelected,
                onChanged: (_) => onToggle(entry.id!),
              ),
              title: Text(
                entry.title ?? entry.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                formatDateTime(entry.createdAt),
                style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              onTap: () => onToggle(entry.id!),
            );
          }

          return ListTile(
            title: Text(
              entry.title ?? entry.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight:
                    entry.title != null ? FontWeight.w600 : null,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDateTime(entry.createdAt),
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (entry.projectName != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color:
                                theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.projectName!,
                            style: TextStyle(
                              fontSize: 10,
                              color: theme
                                  .colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                    if (entry.tags.isNotEmpty)
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: entry.tags
                              .map((t) => Text(
                                    t.name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          theme.colorScheme.primary,
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            onTap: () => onTapEntry(entry),
          );
        }),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _FilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        onPressed: onTap,
        color: active
            ? WidgetStateProperty.all(
                Theme.of(context).colorScheme.primaryContainer)
            : null,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// 树状标签多选弹窗（用于筛选，有初始选中状态）
class _MultiTagFilterDialog extends StatefulWidget {
  final List<Tag> allTags;
  final Set<int> initialSelectedIds;

  const _MultiTagFilterDialog({
    required this.allTags,
    required this.initialSelectedIds,
  });

  @override
  State<_MultiTagFilterDialog> createState() => _MultiTagFilterDialogState();
}

class _MultiTagFilterDialogState extends State<_MultiTagFilterDialog> {
  late final Set<int> _selectedIds;
  final Set<int> _expandedIds = {};
  List<Tag> get _rootTags =>
      widget.allTags.where((t) => t.parentId == null).toList();

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('筛选树状标签（已选 ${_selectedIds.length}）'),
      content: SizedBox(
        width: double.maxFinite,
        child: _rootTags.isEmpty
            ? const Text('暂无标签')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _rootTags.length,
                itemBuilder: (context, index) {
                  return _buildTagNode(_rootTags[index], 0);
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        TextButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.pop(context, Set.from(_selectedIds)),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildTagNode(Tag tag, int level) {
    final children =
        widget.allTags.where((t) => t.parentId == tag.id).toList();
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
            title: Text(tag.name,
                style:
                    TextStyle(fontWeight: isSelected ? FontWeight.w600 : null)),
            onTap: hasChildren
                ? () => setState(() {
                      if (isExpanded) {
                        _expandedIds.remove(tag.id!);
                      } else {
                        _expandedIds.add(tag.id!);
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
                ? Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16)
                : null,
          ),
        ),
        if (isExpanded && hasChildren)
          ...children.map((c) => _buildTagNode(c, level + 1)),
      ],
    );
  }
}

/// 属性标签多选弹窗（用于筛选，有初始选中状态）
class _MultiAttributeTagFilterDialog extends StatefulWidget {
  final List<AttributeTag> tags;
  final Set<int> initialSelectedIds;

  const _MultiAttributeTagFilterDialog({
    required this.tags,
    required this.initialSelectedIds,
  });

  @override
  State<_MultiAttributeTagFilterDialog> createState() =>
      _MultiAttributeTagFilterDialogState();
}

class _MultiAttributeTagFilterDialogState
    extends State<_MultiAttributeTagFilterDialog> {
  late final Set<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('筛选属性标签（已选 ${_selectedIds.length}）'),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.tags.isEmpty
            ? const Text('暂无属性标签')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.tags.length,
                itemBuilder: (context, index) {
                  final t = widget.tags[index];
                  final isSelected = _selectedIds.contains(t.id);
                  return ListTile(
                    leading: Checkbox(
                      value: isSelected,
                      onChanged: (_) => setState(() {
                        if (isSelected) {
                          _selectedIds.remove(t.id!);
                        } else {
                          _selectedIds.add(t.id!);
                        }
                      }),
                    ),
                    title: Text(t.name),
                    onTap: () => setState(() {
                      if (isSelected) {
                        _selectedIds.remove(t.id!);
                      } else {
                        _selectedIds.add(t.id!);
                      }
                    }),
                    dense: true,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        TextButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.pop(context, Set.from(_selectedIds)),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 项目多选弹窗（用于筛选，有初始选中状态）
class _MultiProjectFilterDialog extends StatefulWidget {
  final List<Project> projects;
  final Set<int> initialSelectedIds;

  const _MultiProjectFilterDialog({
    required this.projects,
    required this.initialSelectedIds,
  });

  @override
  State<_MultiProjectFilterDialog> createState() =>
      _MultiProjectFilterDialogState();
}

class _MultiProjectFilterDialogState
    extends State<_MultiProjectFilterDialog> {
  late final Set<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('筛选项目（已选 ${_selectedIds.length}）'),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.projects.isEmpty
            ? const Text('暂无项目')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: widget.projects.length,
                itemBuilder: (context, index) {
                  final p = widget.projects[index];
                  final isSelected = _selectedIds.contains(p.id);
                  return ListTile(
                    leading: Checkbox(
                      value: isSelected,
                      onChanged: (_) => setState(() {
                        if (isSelected) {
                          _selectedIds.remove(p.id!);
                        } else {
                          _selectedIds.add(p.id!);
                        }
                      }),
                    ),
                    title: Text(p.name),
                    onTap: () => setState(() {
                      if (isSelected) {
                        _selectedIds.remove(p.id!);
                      } else {
                        _selectedIds.add(p.id!);
                      }
                    }),
                    dense: true,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        TextButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.pop(context, Set.from(_selectedIds)),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _MultiTagPickerDialog extends StatefulWidget {
  final List<Tag> allTags;
  const _MultiTagPickerDialog({required this.allTags});

  @override
  State<_MultiTagPickerDialog> createState() =>
      _MultiTagPickerDialogState();
}

class _MultiTagPickerDialogState extends State<_MultiTagPickerDialog> {
  final Set<int> _selectedIds = {};
  final Set<int> _expandedIds = {};
  List<Tag> get _rootTags =>
      widget.allTags.where((t) => t.parentId == null).toList();

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
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        TextButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedIds.toList()),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildTagNode(Tag tag, int level) {
    final children =
        widget.allTags.where((t) => t.parentId == tag.id).toList();
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
            title: Text(tag.name,
                style:
                    TextStyle(fontWeight: isSelected ? FontWeight.w600 : null)),
            onTap: hasChildren
                ? () => setState(() {
                      if (isExpanded) {
                        _expandedIds.remove(tag.id!);
                      } else {
                        _expandedIds.add(tag.id!);
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
                ? Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16)
                : null,
          ),
        ),
        if (isExpanded && hasChildren)
          ...children.map((c) => _buildTagNode(c, level + 1)),
      ],
    );
  }
}
