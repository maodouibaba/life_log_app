import 'package:flutter/material.dart';
import '../models/attribute_tag.dart';
import '../models/attribute_tag_group.dart';
import '../database/app_database.dart';

/// 属性标签管理页面
/// 属性标签无层级，按分组管理。分组可收起展开，支持批量操作
/// 同级拖拽排序，长按标签体可拖到其他分组
class AttributeTagManagerPage extends StatefulWidget {
  final int spaceId;

  const AttributeTagManagerPage({super.key, required this.spaceId});

  @override
  State<AttributeTagManagerPage> createState() =>
      _AttributeTagManagerPageState();
}

class _AttributeTagManagerPageState extends State<AttributeTagManagerPage> {
  final AppDatabase _db = AppDatabase();
  List<AttributeTag> _allTags = [];
  List<AttributeTagGroup> _groups = [];

  // 分组展开状态
  final Set<int> _expandedGroupIds = {};
  // 选择模式
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  int get _spaceId => widget.spaceId;

  @override
  void initState() {
    super.initState();
    _loadData();
    // 默认展开所有分组
    _db.getAllAttributeTagGroups(_spaceId).then((groups) {
      for (final g in groups) {
        if (g.id != null) _expandedGroupIds.add(g.id!);
      }
    });
  }

  Future<void> _loadData() async {
    _allTags = await _db.getAllAttributeTags(_spaceId);
    _groups = await _db.getAllAttributeTagGroups(_spaceId);
    if (mounted) setState(() {});
  }

  List<AttributeTag> _getTagsByGroup(int? groupId) =>
      _allTags.where((t) => t.groupId == groupId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// 重新排序同级标签
  Future<void> _reorderInGroup(int? groupId, int oldIndex, int newIndex) async {
    final siblings = _getTagsByGroup(groupId);
    if (oldIndex < newIndex) newIndex--;
    final updated = List<AttributeTag>.from(siblings);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    for (int i = 0; i < updated.length; i++) {
      if (updated[i].sortOrder != i) {
        await _db.updateAttributeTagSortOrder(updated[i].id!, i);
      }
    }
    if (item.sortOrder != newIndex) {
      await _db.updateAttributeTagSortOrder(item.id!, newIndex);
    }
    _loadData();
  }

  /// 移动标签到新分组（拖拽）
  Future<void> _moveTagToGroup(AttributeTag tag, int? targetGroupId) async {
    if (tag.groupId == targetGroupId) return;
    await _db.moveAttributeTagToGroup(tag.id!, targetGroupId);
    _loadData();
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleSelect(int id) {
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
        content: Text('确定要删除选中的 ${_selectedIds.length} 个属性标签吗？'),
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
      for (final id in _selectedIds) {
        await _db.deleteAttributeTag(id);
      }
      _selectedIds.clear();
      _loadData();
    }
  }

  Future<void> _batchMoveToGroup() async {
    if (_selectedIds.isEmpty) return;
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => _PickGroupForBatchDialog(groups: _groups),
    );
    if (result == null) return;
    final groupId = result == -1 ? null : result;
    for (final id in _selectedIds) {
      await _db.moveAttributeTagToGroup(id, groupId);
    }
    _selectedIds.clear();
    _loadData();
  }

  // ===== 分组操作 =====

  Future<void> _addGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建属性标签分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '分组名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await _db.createAttributeTagGroup(name, _spaceId);
      _loadData();
    }
  }

  Future<void> _renameGroup(AttributeTagGroup g) async {
    final controller = TextEditingController(text: g.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '分组名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && name != g.name) {
      await _db.updateAttributeTagGroupName(g.id!, name);
      _loadData();
    }
  }

  Future<void> _deleteGroup(AttributeTagGroup g) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分组'),
        content: Text(
            '确定要删除分组「${g.name}」吗？\n（组内的属性标签不会删除，会变为"未分组"状态）'),
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
      await _db.deleteAttributeTagGroup(g.id!);
      _loadData();
    }
  }

  // ===== 属性标签操作 =====
  Future<void> _addTag({int? groupId}) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建属性标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '标签名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await _db.createAttributeTag(name, groupId: groupId, spaceId: _spaceId);
      _loadData();
    }
  }

  Future<void> _renameTag(AttributeTag tag) async {
    final controller = TextEditingController(text: tag.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '标签名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && name != tag.name) {
      await _db.updateAttributeTagName(tag.id!, name);
      _loadData();
    }
  }

  Future<void> _deleteTag(AttributeTag tag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除属性标签'),
        content: Text(
            '确定要删除属性标签「${tag.name}」吗？\n（相关记录的此标签会被移除）'),
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
      await _db.deleteAttributeTag(tag.id!);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ungrouped = _getTagsByGroup(null);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selectedIds.length}' : '属性标签'),
        actions: [
          if (_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.drive_file_move_outlined),
              tooltip: '移动到分组',
              onPressed: _selectedIds.isNotEmpty ? _batchMoveToGroup : null,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: theme.colorScheme.error),
              tooltip: '批量删除',
              onPressed: _selectedIds.isNotEmpty ? _batchDelete : null,
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
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'add_group') _addGroup();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'add_group',
                  child: Text('新建分组'),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新建属性标签',
              onPressed: () => _addTag(),
            ),
          ],
        ],
      ),
      body: _allTags.isEmpty && _groups.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.turned_in_outlined,
                      size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('还没有属性标签',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('点击右上角 + 创建',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ..._groups.map((g) => _GroupSection(
                      group: g,
                      tags: _getTagsByGroup(g.id),
                      allGroups: _groups,
                      isExpanded: _expandedGroupIds.contains(g.id),
                      selectMode: _selectMode,
                      selectedIds: _selectedIds,
                      theme: theme,
                      onToggleExpand: () => setState(() {
                        if (_expandedGroupIds.contains(g.id!)) {
                          _expandedGroupIds.remove(g.id!);
                        } else {
                          _expandedGroupIds.add(g.id!);
                        }
                      }),
                      onToggleSelect: _toggleSelect,
                      onAddTag: () => _addTag(groupId: g.id),
                      onRenameGroup: () => _renameGroup(g),
                      onDeleteGroup: () => _deleteGroup(g),
                      onRenameTag: _renameTag,
                      onDeleteTag: _deleteTag,
                      onReorder: (oldIndex, newIndex) =>
                          _reorderInGroup(g.id, oldIndex, newIndex),
                      onMoveTagToGroup: (tag) =>
                          _moveTagToGroup(tag, g.id),
                    )),

                // 未分组（同时也是 DragTarget 接收拖入的标签）
                if (ungrouped.isNotEmpty || _groups.isNotEmpty)
                  _buildUngroupedSection(theme, ungrouped),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildUngroupedSection(ThemeData theme, List<AttributeTag> ungrouped) {
    return DragTarget<AttributeTag>(
      onAcceptWithDetails: (details) =>
          _moveTagToGroup(details.data, null),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isHovering
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: isHovering
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isHovering)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_downward, size: 14,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('释放到此处设为未分组',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
              if (ungrouped.isNotEmpty || !isHovering)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('未分组（${ungrouped.length}）',
                      style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500)),
                ),
              if (ungrouped.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('（空）',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                )
              else
                ...ungrouped.map((t) => _buildTagTile(t, theme)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTagTile(AttributeTag tag, ThemeData theme) {
    return LongPressDraggable<AttributeTag>(
      data: tag,
      delay: const Duration(milliseconds: 300),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 200,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.drive_file_rename_outline,
                size: 18, color: theme.colorScheme.primary),
            title: Text(tag.name, style: const TextStyle(fontSize: 13)),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: ListTile(
          dense: true,
          leading: _selectMode
              ? Checkbox(
                  value: _selectedIds.contains(tag.id),
                  onChanged: (_) => _toggleSelect(tag.id!),
                )
              : Icon(Icons.turned_in, size: 18, color: theme.colorScheme.secondary),
          title: Text(tag.name, style: const TextStyle(fontSize: 14)),
          trailing: _selectMode ? null : PopupMenuButton<String>(
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('重命名')),
              if (_groups.isNotEmpty)
                const PopupMenuItem(value: 'move', child: Text('移动到分组')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('删除', style: TextStyle(color: Colors.red)),
              ),
            ],
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  _renameTag(tag);
                  break;
                case 'move':
                  final result = await showDialog<int?>(
                    context: context,
                    builder: (ctx) =>
                        _PickGroupForBatchDialog(groups: _groups),
                  );
                  if (result != null) {
                    await _db.moveAttributeTagToGroup(
                        tag.id!, result == -1 ? null : result);
                    _loadData();
                  }
                  break;
                case 'delete':
                  _deleteTag(tag);
                  break;
              }
            },
          ),
          onTap: _selectMode ? () => _toggleSelect(tag.id!) : null,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: _selectMode
            ? Checkbox(
                value: _selectedIds.contains(tag.id),
                onChanged: (_) => _toggleSelect(tag.id!),
              )
            : Icon(Icons.turned_in, size: 18, color: theme.colorScheme.secondary),
        title: Text(tag.name, style: const TextStyle(fontSize: 14)),
        trailing: _selectMode ? null : PopupMenuButton<String>(
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('重命名')),
            if (_groups.isNotEmpty)
              const PopupMenuItem(value: 'move', child: Text('移动到分组')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
          onSelected: (v) async {
            switch (v) {
              case 'edit':
                _renameTag(tag);
                break;
              case 'move':
                final result = await showDialog<int?>(
                  context: context,
                  builder: (ctx) =>
                      _PickGroupForBatchDialog(groups: _groups),
                );
                if (result != null) {
                  await _db.moveAttributeTagToGroup(
                      tag.id!, result == -1 ? null : result);
                  _loadData();
                }
                break;
              case 'delete':
                _deleteTag(tag);
                break;
            }
          },
        ),
        onTap: _selectMode ? () => _toggleSelect(tag.id!) : null,
      ),
    );
  }
}

/// 分组区块（可收起展开，支持拖拽排序+拖入）
class _GroupSection extends StatelessWidget {
  final AttributeTagGroup group;
  final List<AttributeTag> tags;
  final List<AttributeTagGroup> allGroups;
  final bool isExpanded;
  final bool selectMode;
  final Set<int> selectedIds;
  final ThemeData theme;
  final VoidCallback onToggleExpand;
  final Function(int) onToggleSelect;
  final VoidCallback onAddTag;
  final VoidCallback onRenameGroup;
  final VoidCallback onDeleteGroup;
  final Function(AttributeTag) onRenameTag;
  final Function(AttributeTag) onDeleteTag;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Function(AttributeTag) onMoveTagToGroup;

  const _GroupSection({
    required this.group,
    required this.tags,
    required this.allGroups,
    required this.isExpanded,
    required this.selectMode,
    required this.selectedIds,
    required this.theme,
    required this.onToggleExpand,
    required this.onToggleSelect,
    required this.onAddTag,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onRenameTag,
    required this.onDeleteTag,
    required this.onReorder,
    required this.onMoveTagToGroup,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<AttributeTag>(
      onAcceptWithDetails: (details) => onMoveTagToGroup(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isHovering
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: isHovering
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          child: Card(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 分组头部（可点击展开/收起）
                InkWell(
                  onTap: onToggleExpand,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 20,
                          color: isHovering ? theme.colorScheme.primary : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.folder_outlined,
                            size: 18, color: isHovering ? theme.colorScheme.primary : theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(group.name,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isHovering ? theme.colorScheme.primary : null)),
                        const Spacer(),
                        if (isHovering)
                          Text('释放移到此处',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.primary))
                        else if (!selectMode) ...[
                          Text('${tags.length}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant)),
                          IconButton(
                            icon: const Icon(Icons.add, size: 18),
                            tooltip: '在此分组新建标签',
                            onPressed: onAddTag,
                          ),
                          PopupMenuButton<String>(
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                  value: 'rename', child: Text('重命名分组')),
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除分组',
                                      style: TextStyle(color: Colors.red))),
                            ],
                            onSelected: (v) {
                              switch (v) {
                                case 'rename':
                                  onRenameGroup();
                                  break;
                                case 'delete':
                                  onDeleteGroup();
                                  break;
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // 组内标签列表（可拖拽排序）
                if (isExpanded)
                  if (tags.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Text('（空）',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: tags.length,
                      onReorder: onReorder,
                      proxyDecorator: (child, index, animation) => Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(8),
                        child: child,
                      ),
                      itemBuilder: (context, index) {
                        final t = tags[index];
                        return LongPressDraggable<AttributeTag>(
                          key: ValueKey(t.id),
                          data: t,
                          delay: const Duration(milliseconds: 350),
                          feedback: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 200,
                              child: ListTile(
                                dense: true,
                                leading: Icon(Icons.drive_file_rename_outline,
                                    size: 18, color: theme.colorScheme.primary),
                                title: Text(t.name, style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.4,
                            child: ListTile(
                              dense: true,
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.drag_handle, size: 18),
                                  if (selectMode)
                                    Checkbox(
                                      value: selectedIds.contains(t.id),
                                      onChanged: (_) => onToggleSelect(t.id!),
                                    )
                                  else
                                    const SizedBox(width: 4),
                                ],
                              ),
                              title: Text(t.name, style: const TextStyle(fontSize: 14)),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(Icons.drag_handle, size: 18),
                                ),
                                if (selectMode)
                                  Checkbox(
                                    value: selectedIds.contains(t.id),
                                    onChanged: (_) => onToggleSelect(t.id!),
                                  )
                                else
                                  const SizedBox(width: 4),
                              ],
                            ),
                            title: Text(t.name, style: const TextStyle(fontSize: 14)),
                            trailing: selectMode
                                ? null
                                : PopupMenuButton<String>(
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                          value: 'edit', child: Text('重命名')),
                                      if (allGroups.isNotEmpty)
                                        const PopupMenuItem(
                                            value: 'move', child: Text('移动到分组')),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('删除',
                                            style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                    onSelected: (v) {
                                    switch (v) {
                                      case 'edit':
                                        onRenameTag(t);
                                        break;
                                      case 'move':
                                        final ctx = context;
                                        showDialog<int?>(
                                          context: ctx,
                                          builder: (ctx) =>
                                              _PickGroupForBatchDialog(
                                                  groups: allGroups),
                                        ).then((result) {
                                          if (result != null) {
                                            // handled by parent
                                          }
                                        });
                                        break;
                                      case 'delete':
                                        onDeleteTag(t);
                                        break;
                                    }
                                  },
                                ),
                          onTap: selectMode ? () => onToggleSelect(t.id!) : null,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 批量选择分组弹窗
class _PickGroupForBatchDialog extends StatelessWidget {
  final List<AttributeTagGroup> groups;

  const _PickGroupForBatchDialog({required this.groups});

  @override
  Widget build(BuildContext context) {
    int? selected;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('移动到分组'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int>(
              title: const Text('（不分组）'),
              value: -1,
              groupValue: selected,
              onChanged: (v) => setState(() => selected = v),
              dense: true,
            ),
            ...groups.map((g) => RadioListTile<int>(
                  title: Text(g.name),
                  value: g.id!,
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v),
                  dense: true,
                )),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          TextButton(
            onPressed: selected != null
                ? () => Navigator.pop(context, selected)
                : null,
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
