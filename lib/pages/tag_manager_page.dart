import 'package:flutter/material.dart';
import '../models/tag.dart';
import '../database/app_database.dart';

/// 标签管理页面
/// 树状展示所有标签，支持新增、编辑、删除
class TagManagerPage extends StatefulWidget {
  const TagManagerPage({super.key});

  @override
  State<TagManagerPage> createState() => _TagManagerPageState();
}

class _TagManagerPageState extends State<TagManagerPage> {
  final AppDatabase _db = AppDatabase();
  List<Tag> _rootTags = [];

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _db.getRootTags();
    setState(() => _rootTags = tags);
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _db.createTag(result, parentId: parentId);
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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

  Future<void> _deleteTag(Tag tag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定要删除「${tag.name}」及其所有子标签吗？'),
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
      await _db.deleteTag(tag.id!);
      _loadTags();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建根标签',
            onPressed: () => _addTag(),
          ),
        ],
      ),
      body: _rootTags.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.label_outline, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('还没有标签', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('点击右上角 + 创建根标签', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _rootTags.length,
              itemBuilder: (context, index) {
                return _TagTreeNode(
                  tag: _rootTags[index],
                  database: _db,
                  onChanged: _loadTags,
                  onEdit: _editTag,
                  onDelete: _deleteTag,
                  onAddChild: (int parentId) => _addTag(parentId: parentId),
                  level: 0,
                );
              },
            ),
    );
  }
}

class _TagTreeNode extends StatefulWidget {
  final Tag tag;
  final AppDatabase database;
  final VoidCallback onChanged;
  final Function(Tag) onEdit;
  final Function(Tag) onDelete;
  final void Function(int parentId) onAddChild;
  final int level;

  const _TagTreeNode({
    required this.tag,
    required this.database,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onAddChild,
    required this.level,
  });

  @override
  State<_TagTreeNode> createState() => _TagTreeNodeState();
}

class _TagTreeNodeState extends State<_TagTreeNode> {
  List<Tag>? _children;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    final children = await widget.database.getChildTags(widget.tag.id!);
    setState(() => _children = children);
  }

  @override
  Widget build(BuildContext context) {
        final hasChildren = _children != null && _children!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: widget.level * 24.0),
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 2),
            child: ListTile(
              dense: true,
              leading: hasChildren
                  ? IconButton(
                      icon: Icon(_expanded ? Icons.expand_more : Icons.chevron_right),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24),
                    )
                  : const SizedBox(width: 24),
              title: Text(
                widget.tag.name,
                style: const TextStyle(fontSize: 15),
              ),
              trailing: PopupMenuButton<String>(
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'add', child: Text('添加子标签')),
                  const PopupMenuItem(value: 'edit', child: Text('重命名')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'add':
                      widget.onAddChild(widget.tag.id!);
                      break;
                    case 'edit':
                      widget.onEdit(widget.tag);
                      break;
                    case 'delete':
                      widget.onDelete(widget.tag);
                      break;
                  }
                },
              ),
            ),
          ),
        ),
        if (_expanded && hasChildren)
          ..._children!.map((child) => _TagTreeNode(
                tag: child,
                database: widget.database,
                onChanged: widget.onChanged,
                onEdit: widget.onEdit,
                onDelete: widget.onDelete,
                onAddChild: widget.onAddChild,
                level: widget.level + 1,
              )),
      ],
    );
  }
}



