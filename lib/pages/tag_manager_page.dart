import 'package:flutter/material.dart';
import '../models/tag.dart';
import '../database/app_database.dart';

/// 标签管理页面
/// 树状展示所有标签，支持新增、编辑、删除、调整层级（移动父节点）、拖动排序
class TagManagerPage extends StatefulWidget {
  final int spaceId;

  const TagManagerPage({super.key, required this.spaceId});

  @override
  State<TagManagerPage> createState() => _TagManagerPageState();
}

class _TagManagerPageState extends State<TagManagerPage> {
  final AppDatabase _db = AppDatabase();
  List<Tag> _allTags = [];
  final Set<int> _expandedIds = {}; // 展开状态，从父级控制以便一键展开/收起

  int get _spaceId => widget.spaceId;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _db.getAllTags(spaceId: _spaceId);
    if (mounted) setState(() => _allTags = tags);
  }

  List<Tag> _getRootTags() =>
      _allTags.where((t) => t.parentId == null).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<Tag> _getChildren(int parentId) =>
      _allTags.where((t) => t.parentId == parentId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  void _expandAll() {
    setState(() {
      for (final t in _allTags) {
        if (t.id != null && _getChildren(t.id!).isNotEmpty) {
          _expandedIds.add(t.id!);
        }
      }
    });
  }

  void _collapseAll() {
    setState(() => _expandedIds.clear());
  }

  Future<void> _addTag({int? parentId}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(parentId == null ? '新建标签' : '新建子标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '请输入标签名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
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
    if (result != null && result.isNotEmpty) {
      await _db.createTag(result, parentId: parentId, spaceId: _spaceId);
      _loadTags();
    }
  }

  Future<void> _editTag(Tag tag) async {
    final controller = TextEditingController(text: tag.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '标签名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
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
    if (result != null && result.isNotEmpty && result != tag.name) {
      await _db.updateTagName(tag.id!, result);
      _loadTags();
    }
  }

  Future<void> _moveTag(Tag tag) async {
    final excludeIds = _getDescendantIds(tag.id!)..add(tag.id!);
    final candidates =
        _allTags.where((t) => !excludeIds.contains(t.id)).toList();

    final selectedId = await showDialog<int?>(
      context: context,
      builder: (ctx) => _MoveTagDialog(
        tag: tag,
        candidates: candidates,
        currentParentId: tag.parentId,
      ),
    );
    int? newParentId;
    if (selectedId == -1) {
      newParentId = null;
    } else if (selectedId != null && selectedId != tag.parentId) {
      newParentId = selectedId;
    } else {
      return;
    }
    await _db.moveTag(tag.id!, newParentId);
    _loadTags();
  }

  Set<int> _getDescendantIds(int tagId) {
    final ids = <int>{};
    for (final child in _getChildren(tagId)) {
      ids.add(child.id!);
      ids.addAll(_getDescendantIds(child.id!));
    }
    return ids;
  }

  Future<void> _deleteTag(Tag tag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定要删除「${tag.name}」及其所有子标签吗？'),
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
      await _db.deleteTag(tag.id!);
      _loadTags();
    }
  }

  /// 拖拽排序：重新编号同级标签
  Future<void> _reorderChildrenOf(int parentId,
      int oldIndex, int newIndex) async {
    final siblings = _getChildren(parentId);
    if (oldIndex < newIndex) newIndex--;
    final updated = List<Tag>.from(siblings);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    for (int i = 0; i < updated.length; i++) {
      if (updated[i].sortOrder != i) {
        await _db.updateTagSortOrder(updated[i].id!, i);
      }
    }
    if (item.sortOrder != newIndex) {
      await _db.updateTagSortOrder(item.id!, newIndex);
    }
    _loadTags();
  }

  @override
  Widget build(BuildContext context) {
    final rootTags = _getRootTags();

    return Scaffold(
      appBar: AppBar(
        title: const Text('树状标签管理'),
        actions: [
          if (rootTags.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.unfold_more),
              tooltip: '全部展开',
              onPressed: _expandAll,
            ),
            IconButton(
              icon: const Icon(Icons.unfold_less),
              tooltip: '全部收起',
              onPressed: _collapseAll,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建根标签',
            onPressed: () => _addTag(),
          ),
        ],
      ),
      body: rootTags.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.label_outline, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('还没有标签',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('点击右上角 + 创建根标签',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : SingleChildScrollView(
              child: _ReorderableTagList(
              tags: rootTags,
              parentId: null,
              allTags: _allTags,
              getChildren: _getChildren,
              level: 0,
              expandedIds: _expandedIds,
              onToggleExpand: (tagId) {
                setState(() {
                  if (_expandedIds.contains(tagId)) {
                    _expandedIds.remove(tagId);
                  } else {
                    _expandedIds.add(tagId);
                  }
                });
              },
              onAddChild: (parentId) => _addTag(parentId: parentId),
              onEdit: _editTag,
              onMove: _moveTag,
              onDelete: _deleteTag,
              onReorder: _reorderChildrenOf,
              onChanged: _loadTags,
            ),
          ),
    );
  }
}

/// 可拖拽排序的标签列表（会递归显示子标签）
class _ReorderableTagList extends StatefulWidget {
  final List<Tag> tags;
  final int? parentId;
  final List<Tag> allTags;
  final List<Tag> Function(int parentId) getChildren;
  final int level;
  final Set<int> expandedIds;
  final void Function(int tagId) onToggleExpand;
  final void Function(int parentId) onAddChild;
  final Function(Tag) onEdit;
  final Function(Tag) onMove;
  final Function(Tag) onDelete;
  final void Function(int parentId, int oldIndex, int newIndex) onReorder;
  final VoidCallback onChanged;

  const _ReorderableTagList({
    required this.tags,
    required this.parentId,
    required this.allTags,
    required this.getChildren,
    required this.level,
    required this.expandedIds,
    required this.onToggleExpand,
    required this.onAddChild,
    required this.onEdit,
    required this.onMove,
    required this.onDelete,
    required this.onReorder,
    required this.onChanged,
  });

  @override
  State<_ReorderableTagList> createState() => _ReorderableTagListState();
}

class _ReorderableTagListState extends State<_ReorderableTagList> {
  bool _isExpanded(Tag tag) => widget.expandedIds.contains(tag.id);
  bool _hasChildren(Tag tag) => widget.getChildren(tag.id!).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: widget.tags.length,
      onReorder: (oldIndex, newIndex) =>
          widget.onReorder(widget.parentId ?? 0, oldIndex, newIndex),
      proxyDecorator: (child, index, animation) => Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
      itemBuilder: (context, index) {
        final tag = widget.tags[index];
        final hasChildren = _hasChildren(tag);
        final isExpanded = _isExpanded(tag);
        final children = widget.getChildren(tag.id!);

        return Column(
          key: ValueKey(tag.id),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(left: widget.level * 36.0),
              child: Card(
                margin: const EdgeInsets.symmetric(vertical: 1),
                child: ListTile(
                  dense: true,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle, size: 20),
                      ),
                      if (hasChildren)
                        IconButton(
                          icon: Icon(
                            isExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 18,
                          ),
                          onPressed: () =>
                              widget.onToggleExpand(tag.id!),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 24, minHeight: 24),
                        )
                      else
                        const SizedBox(width: 24),
                    ],
                  ),
                  title: Text(tag.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            hasChildren ? FontWeight.w600 : FontWeight.normal,
                      )),
                  trailing: PopupMenuButton<String>(
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                          value: 'add', child: Text('添加子标签')),
                      const PopupMenuItem(
                          value: 'edit', child: Text('重命名')),
                      const PopupMenuItem(
                          value: 'move', child: Text('移动层级')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('删除',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                    onSelected: (v) {
                      switch (v) {
                        case 'add':
                          widget.onAddChild(tag.id!);
                          break;
                        case 'edit':
                          widget.onEdit(tag);
                          break;
                        case 'move':
                          widget.onMove(tag);
                          break;
                        case 'delete':
                          widget.onDelete(tag);
                          break;
                      }
                    },
                  ),
                ),
              ),
            ),
            // 展开显示子标签（递归）
            if (isExpanded && hasChildren)
              _ReorderableTagList(
                tags: children,
                parentId: tag.id,
                allTags: widget.allTags,
                getChildren: widget.getChildren,
                level: widget.level + 1,
                expandedIds: widget.expandedIds,
                onToggleExpand: widget.onToggleExpand,
                onAddChild: widget.onAddChild,
                onEdit: widget.onEdit,
                onMove: widget.onMove,
                onDelete: widget.onDelete,
                onReorder: widget.onReorder,
                onChanged: widget.onChanged,
              ),
          ],
        );
      },
    );
  }
}

/// 移动标签弹窗（选择新父节点）
class _MoveTagDialog extends StatefulWidget {
  final Tag tag;
  final List<Tag> candidates;
  final int? currentParentId;

  const _MoveTagDialog({
    required this.tag,
    required this.candidates,
    required this.currentParentId,
  });

  @override
  State<_MoveTagDialog> createState() => _MoveTagDialogState();
}

class _MoveTagDialogState extends State<_MoveTagDialog> {
  int? _selectedId;

  List<Tag> get _rootCandidates =>
      widget.candidates.where((t) => t.parentId == null).toList();

  List<Tag> _getCandidateChildren(int parentId) =>
      widget.candidates.where((t) => t.parentId == parentId).toList();

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentParentId ?? -1;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('移动「${widget.tag.name}」到：'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            RadioListTile<int>(
              title: const Text('（根层级）'),
              value: -1,
              groupValue: _selectedId ?? -1,
              onChanged: (v) => setState(() => _selectedId = v),
              dense: true,
            ),
            ..._rootCandidates.map((c) => _buildCandidateNode(c, 0)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _selectedId),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildCandidateNode(Tag tag, int level) {
    final children = _getCandidateChildren(tag.id!);
    final hasChildren = children.isNotEmpty;

    return Column(
      children: [
        RadioListTile<int>(
          title: Padding(
            padding: EdgeInsets.only(left: level * 36.0),
            child: Text(tag.name),
          ),
          value: tag.id!,
          groupValue: _selectedId,
          onChanged: (v) => setState(() => _selectedId = v),
          dense: true,
        ),
        if (hasChildren)
          ...children.map((c) => _buildCandidateNode(c, level + 1)),
      ],
    );
  }
}
