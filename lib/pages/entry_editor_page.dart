import 'package:flutter/material.dart';
import '../models/tag.dart';
import '../models/entry.dart';
import '../models/project.dart';
import '../database/app_database.dart';

/// 新增/编辑记录页面
/// 标签采用单分支选择：一条记录只能选标签树上的一条路径
class EntryEditorPage extends StatefulWidget {
  final Entry? entry; // null = 新建, 非 null = 编辑

  const EntryEditorPage({super.key, this.entry});

  @override
  State<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends State<EntryEditorPage> {
  final AppDatabase _db = AppDatabase();
  final _contentController = TextEditingController();

  bool get _isEditMode => widget.entry != null;

  // 当前选中的"叶标签"（只存一个，祖先自动推导）
  int? _selectedLeafTagId;

  // 展开状态
  final Set<int> _expandedTagIds = {};

  // 标签数据
  List<Tag> _allTags = [];
  List<Tag> _rootTags = [];

  // 项目
  List<Project> _allProjects = [];
  int? _selectedProjectId;

  // 保存状态
  bool _saving = false;

  /// 获取叶标签 + 所有祖先的 ID
  Set<int> get _effectiveTagIds {
    if (_selectedLeafTagId == null) return {};
    return _getAncestorsInclusive(_selectedLeafTagId!);
  }

  /// 获取从根到叶的标签列表（按层级排序）
  List<Tag> get _selectedTagPath {
    if (_selectedLeafTagId == null) return [];
    final result = <Tag>[];
    // 从叶往上收集
    int? currentId = _selectedLeafTagId;
    while (currentId != null) {
      final matches = _allTags.where((t) => t.id == currentId);
      if (matches.isEmpty) break;
      result.insert(0, matches.first);
      currentId = matches.first.parentId;
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    if (_isEditMode) {
      _contentController.text = widget.entry!.content;
      _selectedProjectId = widget.entry!.projectId;
      // 从已有标签中找出最深的那个作为叶标签
      _selectedLeafTagId = _findDeepestTag(widget.entry!.tags.map((t) => t.id!).toSet());
    }
  }

  /// 从一组标签 ID 中找出最深的那个（离根最远）
  int? _findDeepestTag(Set<int> ids) {
    if (ids.isEmpty) return null;
    int? deepest;
    int maxDepth = -1;
    for (final id in ids) {
      int depth = 0;
      int? current = id;
      while (current != null) {
        final matches = _allTags.where((t) => t.id == current);
        if (matches.isEmpty) break;
        current = matches.first.parentId;
        if (current != null) depth++;
      }
      if (depth > maxDepth) {
        maxDepth = depth;
        deepest = id;
      }
    }
    return deepest;
  }

  Future<void> _loadData() async {
    _allTags = await _db.getAllTags();
    _rootTags = await _db.getRootTags();
    _allProjects = await _db.getAllProjects();
    setState(() {});
  }

  /// 获取某个标签及其所有祖先的 ID
  Set<int> _getAncestorsInclusive(int tagId) {
    final result = <int>{tagId};
    int? currentId = tagId;
    while (currentId != null) {
      final matches = _allTags.where((t) => t.id == currentId);
      if (matches.isEmpty) break;
      final parentId = matches.first.parentId;
      if (parentId != null) {
        result.add(parentId);
        currentId = parentId;
      } else {
        break;
      }
    }
    return result;
  }

  /// 切换标签选中（单分支）：点选一个标签作为叶标签
  void _selectTag(Tag tag) {
    setState(() {
      if (_selectedLeafTagId == tag.id) {
        _selectedLeafTagId = null; // 取消选中
      } else {
        _selectedLeafTagId = tag.id;
      }
    });
  }

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
        _selectedLeafTagId = newTag.id;
        if (parentId != null) {
          _expandedTagIds.add(parentId);
        }
      });
      await _loadData();
    }
  }

  Future<void> _createProject() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建项目'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入项目名称',
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
      final newProject = await _db.createProject(result);
      setState(() => _selectedProjectId = newProject.id);
      _allProjects = await _db.getAllProjects();
      setState(() {});
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

    setState(() => _saving = true);

    try {
      if (_isEditMode) {
        await _db.updateEntryWithTags(
          widget.entry!.id!,
          content,
          tagIds: _effectiveTagIds.toList(),
          projectId: _selectedProjectId,
        );
      } else {
        await _db.createEntry(
          content,
          tagIds: _effectiveTagIds.toList(),
          projectId: _selectedProjectId,
        );
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('保存记录失败：$e');
      if (mounted) {
        setState(() => _saving = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('保存失败'),
            content: Text('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = _selectedTagPath;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? '编辑记录' : '新记录'),
        actions: [
          _saving
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
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
                fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              ),
            ),
          ),

          // 项目选择区
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('项目', style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  onPressed: _createProject,
                  tooltip: '新建项目',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (_allProjects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _allProjects.map((p) => ChoiceChip(
                      label: Text(p.name, style: const TextStyle(fontSize: 13)),
                      selected: _selectedProjectId == p.id,
                      onSelected: (selected) {
                        setState(() => _selectedProjectId = selected ? p.id : null);
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    )).toList(),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('暂无项目', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            ),

          const SizedBox(height: 12),

          // 已选标签路径展示（单分支路径）
          if (path.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.label_outline, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        path.map((t) => t.name).join(' > '),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _selectedLeafTagId = null),
                      child: Icon(Icons.close, size: 14, color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 8),

          // 标签选择区（点选即设为叶标签，不允许多分支）
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
                    itemCount: _rootTags.length + 1, // +1 为"新建根标签"
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: InkWell(
                            onTap: () => _createAndSelectTag(),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  const SizedBox(width: 4),
                                  Icon(Icons.add_circle, size: 18, color: theme.colorScheme.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    '新建根标签',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      return _TagSelectorNode(
                        tag: _rootTags[index - 1],
                        allTags: _allTags,
                        selectedLeafId: _selectedLeafTagId,
                        isInSelectedPath: _effectiveTagIds.contains(_rootTags[index - 1].id),
                        expandedIds: _expandedTagIds,
                        onSelect: _selectTag,
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

/// 标签选择树节点（单分支）
class _TagSelectorNode extends StatelessWidget {
  final Tag tag;
  final List<Tag> allTags;
  final int? selectedLeafId;     // 当前选中的叶标签
  final bool isInSelectedPath;   // 当前节点是否在选中路径上
  final Set<int> expandedIds;
  final Function(Tag) onSelect;
  final Function(int) onToggleExpand;
  final Function(int) onCreateChild;
  final int level;

  const _TagSelectorNode({
    required this.tag,
    required this.allTags,
    required this.selectedLeafId,
    required this.isInSelectedPath,
    required this.expandedIds,
    required this.onSelect,
    required this.onToggleExpand,
    required this.onCreateChild,
    required this.level,
  });

  List<Tag> _getChildren() =>
      allTags.where((t) => t.parentId == tag.id).toList();

  bool _hasChildren() => allTags.any((t) => t.parentId == tag.id);
  bool _isExpanded() => expandedIds.contains(tag.id);
  bool _isSelected() => selectedLeafId == tag.id;

  @override
  Widget build(BuildContext context) {
    final hasChildren = _hasChildren();
    final isExpanded = _isExpanded();
    final children = _getChildren();
    final isSelected = _isSelected();
    final theme = Theme.of(context);

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
                onTap: () => onSelect(tag),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primaryContainer
                        : isInSelectedPath
                            ? theme.colorScheme.primaryContainer.withOpacity(0.35)
                            : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: isSelected || isInSelectedPath
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tag.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : null,
                          color: isInSelectedPath
                              ? theme.colorScheme.primary
                              : null,
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
                selectedLeafId: selectedLeafId,
                isInSelectedPath: isInSelectedPath && isExpanded
                    ? _isChildInPath(child.id!)
                    : false,
                expandedIds: expandedIds,
                onSelect: onSelect,
                onToggleExpand: onToggleExpand,
                onCreateChild: onCreateChild,
                level: level + 1,
              )),
      ],
    );
  }

  bool _isChildInPath(int childId) {
    if (selectedLeafId == null) return false;
    // 判断 childId 是否在选中路径上
    int? current = selectedLeafId;
    while (current != null) {
      if (current == childId) return true;
      final matches = allTags.where((t) => t.id == current);
      if (matches.isEmpty) break;
      current = matches.first.parentId;
    }
    return false;
  }
}
