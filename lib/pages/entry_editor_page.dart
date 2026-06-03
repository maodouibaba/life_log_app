import 'package:flutter/material.dart';
import '../models/tag.dart';
import '../database/app_database.dart';

/// 新增/编辑记录页面
class EntryEditorPage extends StatefulWidget {
  const EntryEditorPage({super.key});

  @override
  State<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends State<EntryEditorPage> {
  final AppDatabase _db = AppDatabase();
  final _contentController = TextEditingController();

  // 已选标签 ID
  final Set<int> _selectedTagIds = {};

  // 标签树展开状态
  final Set<int> _expandedTagIds = {};

  // 标签数据
  List<Tag> _allTags = [];
  List<Tag> _rootTags = [];

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    _allTags = await _db.getAllTags();
    _rootTags = await _db.getRootTags();
    setState(() {});
  }





  /// 获取标签的完整路径文本


  Future<void> _createAndSelectTag({int? parentId}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入标签名称',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
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
      final newTag = await _db.createTag(result, parentId: parentId);
      setState(() {
        _selectedTagIds.add(newTag.id!);
        _expandedTagIds.addAll([if (parentId != null) parentId]);
      });
      await _loadTags();
    }
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入内容')),
      );
      return;
    }

    await _db.createEntry(content, tagIds: _selectedTagIds.toList());
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('新记录'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Column(
        children: [
          // 内容输入区
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _contentController,
              autofocus: true,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                hintText: '记录今天的生活...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
            ),
          ),

          // 已选标签展示
          if (_selectedTagIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _selectedTagIds.map((id) {
                  final tag = _allTags.firstWhere((t) => t.id == id);
                  return Chip(
                    label: Text(tag.name, style: const TextStyle(fontSize: 13)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() => _selectedTagIds.remove(id)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ),

          const SizedBox(height: 8),

          // 标签选择区
          Expanded(
            child: _rootTags.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('还没有标签', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: () => _createAndSelectTag(),
                          child: const Text('创建第一个标签'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _rootTags.length,
                    itemBuilder: (context, index) {
                      return _TagSelectorNode(
                        tag: _rootTags[index],
                        allTags: _allTags,
                        selectedIds: _selectedTagIds,
                        expandedIds: _expandedTagIds,
                        onToggle: (tagId) {
                          setState(() {
                            if (_selectedTagIds.contains(tagId)) {
                              _selectedTagIds.remove(tagId);
                            } else {
                              _selectedTagIds.add(tagId);
                            }
                          });
                        },
                        onToggleExpand: (tagId) {
                          setState(() {
                            if (_expandedTagIds.contains(tagId)) {
                              _expandedTagIds.remove(tagId);
                            } else {
                              _expandedTagIds.add(tagId);
                            }
                          });
                        },
                        onCreateChild: (parentId) => _createAndSelectTag(parentId: parentId),
                        level: 0,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }
}

/// 标签选择树节点
class _TagSelectorNode extends StatelessWidget {
  final Tag tag;
  final List<Tag> allTags;
  final Set<int> selectedIds;
  final Set<int> expandedIds;
  final Function(int) onToggle;
  final Function(int) onToggleExpand;
  final Function(int) onCreateChild;
  final int level;

  const _TagSelectorNode({
    required this.tag,
    required this.allTags,
    required this.selectedIds,
    required this.expandedIds,
    required this.onToggle,
    required this.onToggleExpand,
    required this.onCreateChild,
    required this.level,
  });

  List<Tag> _getChildren() =>
      allTags.where((t) => t.parentId == tag.id).toList();

  bool _hasChildren() => allTags.any((t) => t.parentId == tag.id);
  bool _isExpanded() => expandedIds.contains(tag.id);
  bool _isSelected() => selectedIds.contains(tag.id);

  @override
  Widget build(BuildContext context) {
    final hasChildren = _hasChildren();
    final isExpanded = _isExpanded();
    final children = _getChildren();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: level * 20.0),
          child: Row(
            children: [
              if (hasChildren)
                IconButton(
                  icon: Icon(isExpanded ? Icons.expand_more : Icons.chevron_right, size: 18),
                  onPressed: () => onToggleExpand(tag.id!),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                )
              else
                const SizedBox(width: 28),
              InkWell(
                onTap: () => onToggle(tag.id!),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isSelected()
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isSelected() ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 18,
                        color: _isSelected()
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tag.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: _isSelected() ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 16),
                onPressed: () => onCreateChild(tag.id!),
                tooltip: '添加子标签',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
        if (isExpanded && hasChildren)
          ...children.map((child) => _TagSelectorNode(
                tag: child,
                allTags: allTags,
                selectedIds: selectedIds,
                expandedIds: expandedIds,
                onToggle: onToggle,
                onToggleExpand: onToggleExpand,
                onCreateChild: onCreateChild,
                level: level + 1,
              )),
      ],
    );
  }
}

