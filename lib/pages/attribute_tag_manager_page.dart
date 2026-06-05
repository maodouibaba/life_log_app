import 'package:flutter/material.dart';
import '../models/attribute_tag.dart';
import '../models/attribute_tag_group.dart';
import '../database/app_database.dart';

/// 属性标签管理页面
/// 属性标签无层级，按分组管理
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

  int get _spaceId => widget.spaceId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _allTags = await _db.getAllAttributeTags(_spaceId);
    _groups = await _db.getAllAttributeTagGroups(_spaceId);
    if (mounted) setState(() {});
  }

  List<AttributeTag> _getTagsByGroup(int? groupId) =>
      _allTags.where((t) => t.groupId == groupId).toList();

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
        content: Text('确定要删除分组「${g.name}」吗？\n（组内的属性标签不会删除，会变为"未分组"状态）'),
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
      await _db.createAttributeTag(name,
          groupId: groupId, spaceId: _spaceId);
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
        content: Text('确定要删除属性标签「${tag.name}」吗？\n（相关记录的此标签会被移除）'),
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
    final hasGroups = _groups.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('属性标签'),
        actions: [
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
                  Text('点击右上角 + 创建', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // 各分组
                ..._groups.map((g) {
                  final tags = _getTagsByGroup(g.id);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 分组标题
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                          child: Row(
                            children: [
                              Icon(Icons.folder_outlined,
                                  size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(g.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                              const Spacer(),
                              PopupMenuButton<String>(
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                      value: 'add',
                                      child: Text('在此分组新建标签')),
                                  const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('重命名分组')),
                                  const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除分组',
                                          style: TextStyle(color: Colors.red))),
                                ],
                                onSelected: (v) {
                                  switch (v) {
                                    case 'add':
                                      _addTag(groupId: g.id);
                                      break;
                                    case 'rename':
                                      _renameGroup(g);
                                      break;
                                    case 'delete':
                                      _deleteGroup(g);
                                      break;
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        if (tags.isEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                            child: Text('（空）',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey)),
                          )
                        else
                          ...tags.map(
                              (t) => _buildTagTile(t, theme, inGroup: true)),
                      ],
                    ),
                  );
                }),

                // 未分组
                if (ungrouped.isNotEmpty) ...[
                  if (hasGroups)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text('未分组',
                          style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500)),
                    ),
                  ...ungrouped.map((t) => _buildTagTile(t, theme, inGroup: false)),
                  const SizedBox(height: 40),
                ],
              ],
            ),
    );
  }

  Widget _buildTagTile(AttributeTag tag, ThemeData theme,
      {required bool inGroup}) {
    return ListTile(
      dense: true,
      leading: Icon(Icons.turned_in,
          size: 18, color: theme.colorScheme.secondary),
      title: Text(tag.name, style: const TextStyle(fontSize: 14)),
      trailing: PopupMenuButton<String>(
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
                builder: (ctx) => _PickGroupDialog(
                  groups: _groups,
                  currentGroupId: tag.groupId,
                ),
              );
              if (result != tag.groupId) {
                await _db.moveAttributeTagToGroup(tag.id!, result);
                _loadData();
              }
              break;
            case 'delete':
              _deleteTag(tag);
              break;
          }
        },
      ),
    );
  }
}

/// 选择分组弹窗
class _PickGroupDialog extends StatelessWidget {
  final List<AttributeTagGroup> groups;
  final int? currentGroupId;

  const _PickGroupDialog({
    required this.groups,
    required this.currentGroupId,
  });

  @override
  Widget build(BuildContext context) {
    int? selected = currentGroupId;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('移动到分组'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int?>(
              title: const Text('（不分组）'),
              value: null,
              groupValue: selected,
              onChanged: (v) => setState(() => selected = v),
              dense: true,
            ),
            ...groups.map((g) => RadioListTile<int?>(
                  title: Text(g.name),
                  value: g.id,
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v),
                  dense: true,
                )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
