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
      _allTags.where((t) => t.parentId == null).toList();

  List<Tag> _getChildren(int parentId) =>
      _allTags.where((t) => t.parentId == parentId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

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

  /// 移动标签到新父节点（层级调整）
  Future<void> _moveTag(Tag tag) async {
    // 获取可能的父节点列表（排除自身及其子节点）
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
    if (selectedId is int) {
      // selectedId == -1 means "move to root"
      // ignore: prefer_null_aware_operators
    }
    int? newParentId;
    if (selectedId == -1) {
      newParentId = null; // 移到根
    } else if (selectedId != null && selectedId != tag.parentId) {
      newParentId = selectedId;
    } else {
      return; // 未变更
    }

    await _db.moveTag(tag.id!, newParentId);
    _loadTags();
  }

  Set<int> _getDescendantIds(int tagId) {
    final ids = <int>{};
    final children = _getChildren(tagId);
    for (final child in children) {
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

  /// 拖拽排序完成后重新编号
  Future<void> _reorderSiblings(List<Tag> siblings, int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex--;
    final updated = List<Tag>.from(siblings);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    for (int i = 0; i < updated.length; i++) {
      if (updated[i].sortOrder != i) {
        await _db.updateTagSortOrder(updated[i].id!, i);
      }
    }
    // Also update the moved item if its sortOrder differs
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
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rootTags.length,
              itemBuilder: (context, index) {
                return _TagTreeNode(
                  tag: rootTags[index],
                  allTags: _allTags,
                  getChildren: _getChildren,
                  onChanged: _loadTags,
                  onEdit: _editTag,
                  onDelete: _deleteTag,
                  onMove: _moveTag,
                  onAddChild: (int parentId) => _addTag(parentId: parentId),
                  onReorder: _reorderSiblings,
                  level: 0,
                );
              },
            ),
    );
  }
}

/// 树状标签节点（支持拖拽排序、移动父节点）
class _TagTreeNode extends StatelessWidget {
  final Tag tag;
  final List<Tag> allTags;
  final List<Tag> Function(int parentId) getChildren;
  final VoidCallback onChanged;
  final Function(Tag) onEdit;
  final Function(Tag) onDelete;
  final Function(Tag) onMove;
  final void Function(int parentId) onAddChild;
  final void Function(List<Tag> children, int oldIndex, int newIndex) onReorder;
  final int level;

  const _TagTreeNode({
    required this.tag,
    required this.allTags,
    required this.getChildren,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onMove,
    required this.onAddChild,
    required this.onReorder,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final children = getChildren(tag.id!);
    final hasChildren = children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: level * 24.0),
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 2),
            child: ListTile(
              dense: true,
              leading: hasChildren
                  ? const Icon(Icons.folder, size: 20)
                  : const Icon(Icons.label_outline, size: 20),
              title: Text(tag.name, style: const TextStyle(fontSize: 15)),
              trailing: PopupMenuButton<String>(
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'add', child: Text('添加子标签')),
                  const PopupMenuItem(value: 'edit', child: Text('重命名')),
                  const PopupMenuItem(value: 'move', child: Text('移动层级')),
                  const PopupMenuItem(
                    value: 'delete',
                    child:
                        Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'add':
                      onAddChild(tag.id!);
                      break;
                    case 'edit':
                      onEdit(tag);
                      break;
                    case 'move':
                      onMove(tag);
                      break;
                    case 'delete':
                      onDelete(tag);
                      break;
                  }
                },
              ),
            ),
          ),
        ),
        if (hasChildren)
          _ReorderableTagList(
            tags: children,
            getChildren: getChildren,
            onChanged: onChanged,
            onEdit: onEdit,
            onDelete: onDelete,
            onMove: onMove,
            onAddChild: onAddChild,
            onReorder: onReorder,
            level: level + 1,
          ),
      ],
    );
  }
}

/// 可拖拽排序的标签列表
class _ReorderableTagList extends StatelessWidget {
  final List<Tag> tags;
  final List<Tag> Function(int parentId) getChildren;
  final VoidCallback onChanged;
  final Function(Tag) onEdit;
  final Function(Tag) onDelete;
  final Function(Tag) onMove;
  final void Function(int parentId) onAddChild;
  final void Function(List<Tag> children, int oldIndex, int newIndex) onReorder;
  final int level;

  const _ReorderableTagList({
    required this.tags,
    required this.getChildren,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onMove,
    required this.onAddChild,
    required this.onReorder,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: tags.length,
      onReorder: (oldIndex, newIndex) =>
          onReorder(tags, oldIndex, newIndex),
      proxyDecorator: (child, index, animation) {
        return Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final child = tags[index];
        return Padding(
          key: ValueKey(child.id),
          padding: EdgeInsets.only(left: level * 24.0),
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 1),
            child: ListTile(
              dense: true,
              leading: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle, size: 20),
              ),
              title: Text(child.name, style: const TextStyle(fontSize: 14)),
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
                      onAddChild(child.id!);
                      break;
                    case 'edit':
                      onEdit(child);
                      break;
                    case 'move':
                      onMove(child);
                      break;
                    case 'delete':
                      onDelete(child);
                      break;
                  }
                },
              ),
            ),
          ),
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
            ..._rootCandidates.map((c) =>
                _buildCandidateNode(c, 0)),
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
            padding: EdgeInsets.only(left: level * 16.0),
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
