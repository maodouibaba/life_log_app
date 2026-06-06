import 'package:flutter/material.dart';
import '../models/tag.dart';
import '../models/entry.dart';
import '../models/project.dart';
import '../models/attribute_tag.dart';
import '../models/attribute_tag_group.dart';
import '../models/project_group.dart';
import '../database/app_database.dart';
import '../services/undo_manager.dart';

/// 新增/编辑记录页面
/// 标题 + 内容双字段，通过独立弹窗选择树状标签、属性标签、项目
class EntryEditorPage extends StatefulWidget {
  final Entry? entry; // null = 新建, 非 null = 编辑
  final int spaceId;
  final bool useSheetMode; // true = 弹出窗口形式, false = 全页形式

  const EntryEditorPage({
    super.key,
    this.entry,
    required this.spaceId,
    this.useSheetMode = false,
  });

  /// 以弹出窗口形式（底部弹窗）打开新建/编辑记录页面
  /// 返回 true=新建, 'edit'=编辑已保存, null=取消
  static Future<Object?> showAsSheet(BuildContext context,
      {Entry? entry, required int spaceId}) {
    return showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => EntryEditorPage(
        entry: entry,
        spaceId: spaceId,
        useSheetMode: true,
      ),
    );
  }

  @override
  State<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends State<EntryEditorPage> {
  final AppDatabase _db = AppDatabase();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  int get _spaceId => widget.spaceId;
  bool get _isEditMode => widget.entry != null;

  // 树状标签单分支
  int? _selectedLeafTagId;
  List<Tag> _allTags = [];

  // 属性标签（可多选）
  Set<int> _selectedAttributeTagIds = {};

  // 项目
  int? _selectedProjectId;
  String? _selectedProjectName;

  // 保存状态
  bool _saving = false;

  // 标记初始标签是否已加载（编辑模式专用）
  bool _initialTagsLoaded = false;

  /// 获取叶标签 + 所有祖先的 ID
  Set<int> get _effectiveTagIds {
    if (_selectedLeafTagId == null) return {};
    return _getAncestorsInclusive(_selectedLeafTagId!);
  }

  /// 获取从根到叶的标签路径（按层级排序）
  List<Tag> get _selectedTagPath {
    if (_selectedLeafTagId == null) return [];
    final result = <Tag>[];
    int? currentId = _selectedLeafTagId;
    while (currentId != null) {
      final matches = _allTags.where((t) => t.id == currentId);
      if (matches.isEmpty) break;
      result.insert(0, matches.first);
      currentId = matches.first.parentId;
    }
    return result;
  }

  // 所有的属性标签（用于显示已选标签名）
  List<AttributeTag> _allAttributeTags = [];

  @override
  void initState() {
    super.initState();
    _loadTags();
    _loadAttributeTags();
    if (_isEditMode) {
      _titleController.text = widget.entry!.title ?? '';
      _contentController.text = widget.entry!.content;
      _selectedProjectId = widget.entry!.projectId;
      _selectedProjectName = widget.entry!.projectName;
      // 从已有树状标签中找出最深的那个作为叶标签
      _selectedLeafTagId =
          _findDeepestTag(widget.entry!.tags.map((t) => t.id!).toSet());
      // 属性标签
      _selectedAttributeTagIds =
          widget.entry!.attributeTags.map((t) => t.id!).toSet();
      _initialTagsLoaded = true;
    }
  }

  Future<void> _loadTags() async {
    _allTags = await _db.getAllTags(spaceId: _spaceId);
    // 编辑模式：仅在首次加载时确定最深标签
    // 后续调用（如标签选择器返回后）不覆盖用户已选的标签
    if (_isEditMode && !_initialTagsLoaded && _allTags.isNotEmpty) {
      _selectedLeafTagId =
          _findDeepestTag(widget.entry!.tags.map((t) => t.id!).toSet());
      _initialTagsLoaded = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadAttributeTags() async {
    _allAttributeTags = await _db.getAllAttributeTags(_spaceId);
    if (mounted) setState(() {});
  }

  /// 从一组标签 ID 中找出最深的那个
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

  /// 弹出树状标签选择器（独立窗口）
  Future<void> _openTreeTagPicker() async {
    final result = await showDialog<Tag>(
      context: context,
      builder: (ctx) => _TreeTagPickerDialog(
        spaceId: _spaceId,
        allTags: _allTags,
        selectedLeafId: _selectedLeafTagId,
      ),
    );
    if (result != null) {
      setState(() => _selectedLeafTagId = result.id);
      // 刷新标签列表（可能新建了标签）
      _loadTags();
    }
  }

  /// 弹出属性标签选择器（独立窗口）
  Future<void> _openAttributeTagPicker() async {
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) => _AttributeTagPickerDialog(
        spaceId: _spaceId,
        selectedIds: _selectedAttributeTagIds,
      ),
    );
    if (result != null) {
      setState(() => _selectedAttributeTagIds = result);
    }
  }

  /// 弹出项目选择器（独立窗口）
  Future<void> _openProjectPicker() async {
    final result = await showDialog<MapEntry<int, String>?>(
      context: context,
      builder: (ctx) => _ProjectPickerDialog(
        spaceId: _spaceId,
        selectedProjectId: _selectedProjectId,
      ),
    );
    if (result != null) {
      setState(() {
        _selectedProjectId = result.key;
        _selectedProjectName = result.value;
      });
    }
  }

  /// 弹出事项简介输入框
  Future<void> _openTitleDialog() async {
    final controller = TextEditingController(text: _titleController.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('事项简介'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(
              hintText: '如：今天的工作总结',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _titleController.text = result);
    }
  }

  /// 在 TextEditingController 的光标位置插入文本
  void _insertFormatting(TextEditingController c, String prefix, String suffix,
      {String hint = ''}) {
    final sel = c.selection;
    final text = c.text;
    final selected = sel.isValid && sel.start != sel.end
        ? text.substring(sel.start, sel.end)
        : hint;
    final newText = text.replaceRange(sel.start, sel.end, '$prefix$selected$suffix');
    c.text = newText;
    c.selection = TextSelection.collapsed(
        offset: sel.start + prefix.length + selected.length + suffix.length);
  }

  /// 弹出详细情况输入框
  Future<void> _openContentDialog() async {
    final controller = TextEditingController(text: _contentController.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('详细情况'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              // 格式化工具栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _FormatBtn(
                      icon: Icons.format_bold,
                      tooltip: '粗体 (**text**)',
                      onTap: () => _insertFormatting(controller, '**', '**', hint: '粗体文字'),
                    ),
                    const SizedBox(width: 2),
                    _FormatBtn(
                      icon: Icons.format_italic,
                      tooltip: '斜体 (*text*)',
                      onTap: () => _insertFormatting(controller, '*', '*', hint: '斜体文字'),
                    ),
                    const SizedBox(width: 2),
                    _FormatBtn(
                      icon: Icons.format_list_bulleted,
                      tooltip: '无序列表',
                      onTap: () => _insertFormatting(controller, '- ', ''),
                    ),
                    const SizedBox(width: 2),
                    _FormatBtn(
                      icon: Icons.format_list_numbered,
                      tooltip: '有序列表',
                      onTap: () => _insertFormatting(controller, '1. ', ''),
                    ),
                    const SizedBox(width: 2),
                    _FormatBtn(
                      icon: Icons.title,
                      tooltip: '标题 (#)',
                      onTap: () => _insertFormatting(controller, '# ', ''),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 文本框
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '在此输入详细情况...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _contentController.text = result);
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入事项简介或详细情况')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final tagIds = _selectedLeafTagId != null
          ? _effectiveTagIds.toList()
          : null;
      final attrTagIds = _selectedAttributeTagIds.isNotEmpty
          ? _selectedAttributeTagIds.toList()
          : null;

      if (_isEditMode) {
        // 记录编辑前状态用于撤销
        if (widget.entry != null) {
          UndoManager().recordEdit(widget.entry!);
        }
        await _db.updateEntryWithTags(
          widget.entry!.id!,
          content,
          title: title.isNotEmpty ? title : null,
          tagIds: tagIds,
          attributeTagIds: attrTagIds,
          projectId: _selectedProjectId,
        );
      } else {
        await _db.createEntry(
          content,
          title: title.isNotEmpty ? title : null,
          tagIds: tagIds,
          attributeTagIds: attrTagIds,
          projectId: _selectedProjectId,
          spaceId: _spaceId,
        );
      }
      if (mounted) {
        Navigator.pop(context, _isEditMode ? 'edit' : true);
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
    if (widget.useSheetMode) {
      return _buildSheet(theme);
    }
    return _buildPage(theme);
  }

  Widget _buildPage(ThemeData theme) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? '编辑记录' : '新记录'),
        actions: [
          _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _buildFormSections(theme),
      ),
    );
  }

  Widget _buildSheet(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(
                  _isEditMode ? '编辑记录' : '新记录',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2))
                    : TextButton(
                        onPressed: _save,
                        child: const Text('保存')),
              ],
            ),
          ),
          const Divider(height: 1),
          // 表单内容
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: _buildFormSections(theme),
            ),
          ),
        ],
      ),
    );
  }

  /// 共享表单字段（页面模式与弹出窗口模式共用）
  List<Widget> _buildFormSections(ThemeData theme) {
    final path = _selectedTagPath;
    return [
      // ---- 事项简介（点按弹出输入框） ----
      InkWell(
        onTap: _openTitleDialog,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.short_text,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: _titleController.text.isNotEmpty
                    ? Text(_titleController.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15))
                    : Text('点击输入事项简介',
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 15)),
              ),
              Icon(Icons.edit_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),

      const SizedBox(height: 12),

      // ---- 详细情况（点按弹出输入框） ----
      InkWell(
        onTap: _openContentDialog,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.subject,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: _contentController.text.isNotEmpty
                    ? Text(_contentController.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15))
                    : Text('点击输入详细情况',
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 15)),
              ),
              Icon(Icons.edit_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),

      const SizedBox(height: 20),
      const Divider(),
      const SizedBox(height: 12),

      // ---- 树状标签选择 ----
      _SectionHeader(
        icon: Icons.label_outline,
        label: '树状标签',
        onAdd: _openTreeTagPicker,
      ),
      const SizedBox(height: 4),
      InkWell(
        onTap: _openTreeTagPicker,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: path.isEmpty
              ? Text('点击选择树状标签',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 14))
              : Row(
                  children: [
                    Icon(Icons.label,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        path.map((t) => t.name).join(' > '),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_selectedLeafTagId != null)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _selectedLeafTagId = null),
                        child: Icon(Icons.close,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
        ),
      ),

      const SizedBox(height: 16),

      // ---- 属性标签选择 ----
      _SectionHeader(
        icon: Icons.turned_in_not_outlined,
        label: '属性标签',
        onAdd: _openAttributeTagPicker,
      ),
      const SizedBox(height: 4),
      InkWell(
        onTap: _openAttributeTagPicker,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: _selectedAttributeTagIds.isEmpty
              ? Text('点击选择属性标签',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 14))
              : Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _selectedAttributeTagIds.map((id) {
                    final at = _allAttributeTags
                        .firstWhere((t) => t.id == id,
                            orElse: () => AttributeTag(
                                name: '?', spaceId: _spaceId));
                    return Chip(
                      label: Text(at.name, style: const TextStyle(fontSize: 12)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () {
                        setState(() => _selectedAttributeTagIds.remove(id));
                      },
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    );
                  }).toList(),
                ),
        ),
      ),

      const SizedBox(height: 16),

      // ---- 项目选择 ----
      _SectionHeader(
        icon: Icons.folder_outlined,
        label: '项目',
        onAdd: _openProjectPicker,
      ),
      const SizedBox(height: 4),
      InkWell(
        onTap: _openProjectPicker,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: _selectedProjectId == null
              ? Text('点击选择项目',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 14))
              : Row(
                  children: [
                    Icon(Icons.folder,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      _selectedProjectName ?? '项目$_selectedProjectId',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() {
                        _selectedProjectId = null;
                        _selectedProjectName = null;
                      }),
                      child: Icon(Icons.close,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
        ),
      ),

      const SizedBox(height: 40),
    ];
  }


  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
}

// ==================== 专用弹窗组件 ====================

/// 树状标签选择器弹窗（单分支选择 + 可新建）
class _TreeTagPickerDialog extends StatefulWidget {
  final int spaceId;
  final List<Tag> allTags;
  final int? selectedLeafId;

  const _TreeTagPickerDialog({
    required this.spaceId,
    required this.allTags,
    this.selectedLeafId,
  });

  @override
  State<_TreeTagPickerDialog> createState() => _TreeTagPickerDialogState();
}

class _TreeTagPickerDialogState extends State<_TreeTagPickerDialog> {
  final AppDatabase _db = AppDatabase();
  late List<Tag> _allTags;
  late int? _selectedLeafTagId;
  final Set<int> _expandedIds = {};

  List<Tag> get _rootTags =>
      _allTags.where((t) => t.parentId == null).toList();

  @override
  void initState() {
    super.initState();
    _allTags = List.from(widget.allTags);
    _selectedLeafTagId = widget.selectedLeafId;
    // 展开已选标签的父路径
    if (_selectedLeafTagId != null) {
      int? current = _selectedLeafTagId;
      while (current != null) {
        final matches = _allTags.where((t) => t.id == current);
        if (matches.isEmpty) break;
        final parentId = matches.first.parentId;
        if (parentId != null) _expandedIds.add(parentId);
        current = parentId;
      }
    }
  }

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

  Future<void> _createTag({int? parentId}) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final newTag = await _db.createTag(name,
          parentId: parentId, spaceId: widget.spaceId);
      setState(() {
        _selectedLeafTagId = newTag.id;
        _allTags.add(newTag);
        if (parentId != null) _expandedIds.add(parentId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择树状标签'),
      content: SizedBox(
        width: double.maxFinite,
        child: _rootTags.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('还没有标签', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => _createTag(),
                      child: const Text('创建第一个标签'),
                    ),
                  ],
                ),
              )
            : ListView(
                children: [
                  // 新建根标签
                  InkWell(
                    onTap: () => _createTag(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.add_circle,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('新建根标签',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              )),
                        ],
                      ),
                    ),
                  ),
                  ..._rootTags.map((tag) => _buildNode(tag, 0)),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            if (_selectedLeafTagId != null) {
              final tag = _allTags.firstWhere(
                  (t) => t.id == _selectedLeafTagId);
              Navigator.pop(context, tag);
            } else {
              Navigator.pop(context);
            }
          },
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildNode(Tag tag, int level) {
    final children = _allTags.where((t) => t.parentId == tag.id).toList();
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedIds.contains(tag.id);
    final isSelected = _selectedLeafTagId == tag.id;
    final isInPath = _selectedLeafTagId != null &&
        _getAncestorsInclusive(_selectedLeafTagId!).contains(tag.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: level * 20.0),
          child: Row(
            children: [
              if (hasChildren)
                IconButton(
                  icon: Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18),
                  onPressed: () => setState(() {
                    if (isExpanded) {
                      _expandedIds.remove(tag.id!);
                    } else {
                      _expandedIds.add(tag.id!);
                    }
                  }),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                )
              else
                const SizedBox(width: 28),
              InkWell(
                onTap: () => setState(() => _selectedLeafTagId = tag.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : isInPath
                            ? Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.35)
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
                        color: isSelected || isInPath
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tag.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : null,
                          color: isInPath
                              ? Theme.of(context).colorScheme.primary
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
                onPressed: () => _createTag(parentId: tag.id),
                tooltip: '添加子标签',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
        if (isExpanded && hasChildren)
          ...children.map((c) => _buildNode(c, level + 1)),
      ],
    );
  }
}

/// 属性标签选择器弹窗（多选 + 分组展示 + 可新建）
class _AttributeTagPickerDialog extends StatefulWidget {
  final int spaceId;
  final Set<int> selectedIds;

  const _AttributeTagPickerDialog({
    required this.spaceId,
    required this.selectedIds,
  });

  @override
  State<_AttributeTagPickerDialog> createState() =>
      _AttributeTagPickerDialogState();
}

class _AttributeTagPickerDialogState
    extends State<_AttributeTagPickerDialog> {
  final AppDatabase _db = AppDatabase();
  late Set<int> _selectedIds;
  List<AttributeTag> _allTags = [];
  List<AttributeTagGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.selectedIds);
    _loadData();
  }

  Future<void> _loadData() async {
    _allTags = await _db.getAllAttributeTags(widget.spaceId);
    _groups = await _db.getAllAttributeTagGroups(widget.spaceId);
    if (mounted) setState(() {});
  }

  Future<void> _createTag({int? groupId}) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建属性标签'),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final newTag = await _db.createAttributeTag(name,
          groupId: groupId, spaceId: widget.spaceId);
      setState(() => _allTags.add(newTag));
    }
  }

  List<AttributeTag> _getTagsByGroup(int? groupId) =>
      _allTags.where((t) => t.groupId == groupId).toList();

  @override
  Widget build(BuildContext context) {
    final ungrouped = _getTagsByGroup(null);

    return AlertDialog(
      title: Text('选择属性标签（已选 ${_selectedIds.length}）'),
      content: SizedBox(
        width: double.maxFinite,
        child: _allTags.isEmpty && _groups.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('还没有属性标签',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => _createTag(),
                      child: const Text('创建第一个属性标签'),
                    ),
                  ],
                ),
              )
            : ListView(
                children: [
                  // 新建
                  InkWell(
                    onTap: () => _createTag(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.add_circle,
                              size: 18,
                              color:
                                  Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('新建属性标签',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.primary,
                              )),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),

                  // 分组
                  ..._groups.map((g) {
                    final tags = _getTagsByGroup(g.id);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(g.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ),
                        ...tags.map((t) => _buildTagTile(t)),
                        const SizedBox(height: 4),
                      ],
                    );
                  }),

                  // 未分组
                  if (ungrouped.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('未分组',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    ...ungrouped.map((t) => _buildTagTile(t)),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _selectedIds),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildTagTile(AttributeTag tag) {
    final isSelected = _selectedIds.contains(tag.id);
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: isSelected,
        onChanged: (_) => setState(() {
          if (isSelected) {
            _selectedIds.remove(tag.id!);
          } else {
            _selectedIds.add(tag.id!);
          }
        }),
      ),
      title: Text(tag.name),
      onTap: () => setState(() {
        if (isSelected) {
          _selectedIds.remove(tag.id!);
        } else {
          _selectedIds.add(tag.id!);
        }
      }),
    );
  }
}

/// 项目选择器弹窗（单选 + 分组展示 + 可新建）
class _ProjectPickerDialog extends StatefulWidget {
  final int spaceId;
  final int? selectedProjectId;

  const _ProjectPickerDialog({
    required this.spaceId,
    this.selectedProjectId,
  });

  @override
  State<_ProjectPickerDialog> createState() => _ProjectPickerDialogState();
}

class _ProjectPickerDialogState extends State<_ProjectPickerDialog> {
  final AppDatabase _db = AppDatabase();
  int? _selectedId;
  List<Project> _allProjects = [];
  List<ProjectGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedProjectId;
    _loadData();
  }

  Future<void> _loadData() async {
    _allProjects = await _db.getAllProjects(spaceId: widget.spaceId);
    _groups = await _db.getAllProjectGroups(widget.spaceId);
    if (mounted) setState(() {});
  }

  Future<void> _createProject({int? groupId}) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
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
      final newProject = await _db.createProject(name,
          groupId: groupId, spaceId: widget.spaceId);
      setState(() {
        _allProjects.add(newProject);
        _selectedId = newProject.id;
      });
    }
  }

  List<Project> _getProjectsByGroup(int? groupId) =>
      _allProjects.where((p) => p.groupId == groupId).toList();

  @override
  Widget build(BuildContext context) {
    final ungrouped = _getProjectsByGroup(null);

    return AlertDialog(
      title: const Text('选择项目'),
      content: SizedBox(
        width: double.maxFinite,
        child: _allProjects.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('还没有项目',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => _createProject(),
                      child: const Text('创建第一个项目'),
                    ),
                  ],
                ),
              )
            : ListView(
                children: [
                  InkWell(
                    onTap: () => _createProject(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.add_circle,
                              size: 18,
                              color:
                                  Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('新建项目',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.primary,
                              )),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),

                  // 无项目（清除选择）
                  RadioListTile<int?>(
                    title: const Text('（不选项目）'),
                    value: null,
                    groupValue: _selectedId,
                    onChanged: (v) => setState(() => _selectedId = v),
                    dense: true,
                  ),

                  // 分组
                  ..._groups.map((g) {
                    final projects = _getProjectsByGroup(g.id);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(g.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ),
                        ...projects.map((p) => RadioListTile<int>(
                              title: Text(p.name),
                              value: p.id!,
                              groupValue: _selectedId,
                              onChanged: (v) =>
                                  setState(() => _selectedId = v),
                              dense: true,
                            )),
                      ],
                    );
                  }),

                  // 未分组
                  if (ungrouped.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text('未分组',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    ...ungrouped.map((p) => RadioListTile<int>(
                          title: Text(p.name),
                          value: p.id!,
                          groupValue: _selectedId,
                          onChanged: (v) =>
                              setState(() => _selectedId = v),
                          dense: true,
                        )),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            if (_selectedId == null) {
              Navigator.pop(context);
            } else {
              final p = _allProjects.firstWhere(
                  (p) => p.id == _selectedId);
              Navigator.pop(context,
                  MapEntry<int, String>(p.id!, p.name));
            }
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 格式化工具栏按钮
class _FormatBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _FormatBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

/// 分区标题组件
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onAdd;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
        const Spacer(),
        GestureDetector(
          onTap: onAdd,
          child: Icon(Icons.add_circle_outline,
              size: 18, color: theme.colorScheme.primary),
        ),
      ],
    );
  }
}
