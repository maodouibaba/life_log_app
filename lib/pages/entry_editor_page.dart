import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/tag.dart';
import '../models/entry.dart';
import '../models/project.dart';
import '../models/attribute_tag.dart';
import '../models/attribute_tag_group.dart';
import '../models/project_group.dart';
import '../models/entry_template.dart';
import '../database/app_database.dart';
import '../services/undo_manager.dart';
import '../services/ai_service.dart';
import '../utils/text_formatter.dart';

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
      // 不覆写 shape，使用全局 bottomSheetTheme（24px 圆角磨砂）
      builder: (ctx) => _FrostedSheet(
        child: EntryEditorPage(
          entry: entry,
          spaceId: spaceId,
          useSheetMode: true,
        ),
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
  final _contactPersonController = TextEditingController();
  final _followUpController = TextEditingController();

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

  // 记录时间（默认当前，可手动修改）
  late DateTime _createdAt;

  // 保存状态
  bool _saving = false;

  // 对接人 & 后续待办
  String _contactPerson = '';
  String _followUp = '';

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
    _createdAt = widget.entry?.createdAt ?? DateTime.now();
    _loadTags();
    _loadAttributeTags();
    if (_isEditMode) {
      _titleController.text = widget.entry!.title ?? '';
      _contentController.text = widget.entry!.content;
      _selectedProjectId = widget.entry!.projectId;
      _selectedProjectName = widget.entry!.projectName;
      _contactPerson = widget.entry!.contactPerson ?? '';
      _contactPersonController.text = _contactPerson;
      _followUp = widget.entry!.followUp ?? '';
      _followUpController.text = _followUp;
      // 从已有树状标签中找出最深的那个作为叶标签
      // 属性标签
      _selectedAttributeTagIds =
          widget.entry!.attributeTags.map((t) => t.id!).toSet();
      // 注意：_selectedLeafTagId 不在此处设置——_loadTags() 是异步的，
      // _allTags 此时尚未加载完成，等到 _loadTags() 完成后会自动设置
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
      // 刷新属性标签列表（确保标签名正确显示）
      _loadAttributeTags();
    }
  }

  /// 弹出日期时间选择器
  Future<void> _openTimePicker() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _createdAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_createdAt),
    );
    if (time == null) return;
    setState(() {
      _createdAt = DateTime(
        date.year, date.month, date.day,
        time.hour, time.minute,
      );
    });
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
        title: Row(
          children: [
            const Expanded(child: Text('事项简介')),
            if (AISettings().enabled && AISettings().hasKey)
              _AIBtn(controller: controller),
          ],
        ),
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
      builder: (ctx) {
        bool previewMode = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('详细情况')),
                // 预览/编辑切换按钮
                TextButton.icon(
                  onPressed: () => setDialogState(() => previewMode = !previewMode),
                  icon: Icon(previewMode ? Icons.edit : Icons.visibility, size: 16),
                  label: Text(previewMode ? '编辑' : '预览', style: const TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Stack(
                children: [
                    // 编辑模式：文本框（用 Offstage 保持挂载，避免销毁重建导致输入异常）
                    Offstage(
                      offstage: previewMode,
                      child: SizedBox(
                        width: double.infinity,
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
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
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
                                    if (AISettings().enabled && AISettings().hasKey) ...[
                                      const SizedBox(width: 4),
                                      Container(width: 1, height: 18, color: Theme.of(ctx).colorScheme.outlineVariant),
                                      const SizedBox(width: 4),
                                      _AIBtn(
                                        controller: controller,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
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
                    ),
                    // 预览模式：渲染效果
                    Offstage(
                      offstage: !previewMode,
                      child: SizedBox(
                        width: double.infinity,
                        height: 400,
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: controller.text.trim().isEmpty
                                ? Text('暂无内容',
                                    style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant))
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: TextFormatter.render(
                                      controller.text,
                                      baseStyle: TextStyle(
                                        fontSize: 15,
                                        color: Theme.of(ctx).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                          ),
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
            );
          },
        );
      },
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

      final cp = _contactPerson.trim();
      final fu = _followUp.trim();

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
          createdAt: _createdAt,
          contactPerson: cp.isNotEmpty ? cp : null,
          followUp: fu.isNotEmpty ? fu : null,
        );
      } else {
        await _db.createEntry(
          content,
          title: title.isNotEmpty ? title : null,
          tagIds: tagIds,
          attributeTagIds: attrTagIds,
          projectId: _selectedProjectId,
          spaceId: _spaceId,
          createdAt: _createdAt,
          contactPerson: cp.isNotEmpty ? cp : null,
          followUp: fu.isNotEmpty ? fu : null,
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

  // ==================== 模板功能 ====================

  /// 从模板导入
  Future<void> _pickTemplate() async {
    final templates = await _db.getAllTemplates();
    if (!mounted) return;
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有模板，请先在模板管理中创建')),
      );
      return;
    }

    final selected = await showDialog<EntryTemplate>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从模板导入'),
        content: SizedBox(
          width: double.maxFinite,
          child: templates.length > 6
              ? ListView.builder(
                  shrinkWrap: true,
                  itemCount: templates.length,
                  itemBuilder: (ctx, i) => _buildTemplateTile(templates[i]),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: templates.map(_buildTemplateTile).toList(),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
        ],
      ),
    );

    if (selected != null) {
      _applyTemplate(selected);
    }
  }

  Widget _buildTemplateTile(EntryTemplate template) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.bookmark_outline, size: 18),
      title: Text(template.name, style: const TextStyle(fontSize: 14)),
      subtitle: template.content.isNotEmpty
          ? Text(
              template.content.length > 60
                  ? '${template.content.substring(0, 60)}...'
                  : template.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            )
          : null,
      onTap: () => Navigator.pop(context, template),
    );
  }

  void _applyTemplate(EntryTemplate template) {
    setState(() {
      if (template.title != null) {
        _titleController.text = template.title!;
      }
      if (template.content.isNotEmpty) {
        _contentController.text = template.content;
      }
      // 树状标签（取最深标签作为叶标签）
      if (template.tagIds.isNotEmpty) {
        // 找最深标签
        int? deepestId;
        int maxDepth = -1;
        for (final tagId in template.tagIds) {
          final tag = _allTags.where((t) => t.id == tagId).firstOrNull;
          if (tag == null) continue;
          int depth = 0;
          int? parentId = tag.parentId;
          while (parentId != null) {
            depth++;
            parentId = _allTags
                .where((t) => t.id == parentId)
                .firstOrNull
                ?.parentId;
          }
          if (depth > maxDepth) {
            maxDepth = depth;
            deepestId = tagId;
          }
        }
        _selectedLeafTagId = deepestId;
      }
      // 属性标签
      if (template.attributeTagIds.isNotEmpty) {
        _selectedAttributeTagIds.clear();
        _selectedAttributeTagIds.addAll(template.attributeTagIds);
      }
      // 项目
      if (template.projectId != null) {
        _selectedProjectId = template.projectId;
        _selectedProjectName = template.projectName;
      }
      // 对接人
      if (template.contactPerson != null) {
        _contactPerson = template.contactPerson!;
        _contactPersonController.text = _contactPerson;
      }
      // 后续待办
      if (template.followUp != null) {
        _followUp = template.followUp!;
        _followUpController.text = _followUp;
      }
    });
  }

  /// 将当前记录保存为模板
  Future<void> _saveAsTemplate() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('另存为模板'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入模板名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty) return;

    try {
      final template = EntryTemplate(
        name: name,
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : null,
        content: _contentController.text.trim(),
        tagIds: _effectiveTagIds.toList(),
        attributeTagIds: _selectedAttributeTagIds.toList(),
        projectId: _selectedProjectId,
        projectName: _selectedProjectName,
        contactPerson: _contactPerson.isNotEmpty ? _contactPerson : null,
        followUp: _followUp.isNotEmpty ? _followUp : null,
      );
      await _db.createTemplate(template);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存为模板')),
        );
      }
    } catch (e) {
      debugPrint('保存模板失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存模板失败：$e')),
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
      // 不设 background color，让 BottomSheet 主题的半透明色透过 BackdropFilter 磨砂效果
      decoration: const BoxDecoration(),
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
      // ---- 从模板导入 ----
      if (!_isEditMode)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: _pickTemplate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.bookmark_outline,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('从模板导入',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      )),
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      size: 18, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
        ),

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
                    ? Text(TextFormatter.stripMarkdown(_contentController.text),
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

      const SizedBox(height: 16),

      // ---- 对接人 ----
      Row(
        children: [
          Icon(Icons.person_outline,
              size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text('对接人',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
      const SizedBox(height: 6),
      _buildTextField(
        label: '对接人',
        icon: Icons.person_outline,
        value: _contactPerson,
        hint: '如：张三',
        onChanged: (v) => setState(() => _contactPerson = v),
      ),
      const SizedBox(height: 16),

      // ---- 后续待办 ----
      Row(
        children: [
          Icon(Icons.checklist_outlined,
              size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text('后续待办',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
      const SizedBox(height: 6),
      _buildTextField(
        label: '后续待办',
        icon: Icons.checklist_outlined,
        value: _followUp,
        hint: '如：下周五前回复邮件',
        onChanged: (v) => setState(() => _followUp = v),
      ),

      const SizedBox(height: 16),

      // ---- 另存为模板 ----
      InkWell(
        onTap: _saveAsTemplate,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.bookmark_add_outlined,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('另存为模板',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              const Spacer(),
              Icon(Icons.chevron_right,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),

      const SizedBox(height: 16),
      const Divider(),
      const SizedBox(height: 12),

      // ---- 记录时间 ----
      InkWell(
        onTap: _openTimePicker,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.access_time,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _formatEditorDateTime(_createdAt),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Icon(Icons.edit_outlined,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),

      const SizedBox(height: 16),

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


  /// 简单的文本输入行（对接人 / 后续待办）
  Widget _buildTextField({
    required String label,
    required IconData icon,
    required String value,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return InkWell(
      onTap: () async {
        final controller = TextEditingController(text: value);
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(label),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('确定'),
              ),
            ],
          ),
        );
        if (result != null) {
          onChanged(result);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: value.isNotEmpty
                  ? Text(value, style: const TextStyle(fontSize: 14))
                  : Text(hint,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14)),
            ),
            Icon(Icons.edit_outlined,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  String _formatEditorDateTime(DateTime dt) {
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${dt.year}年${dt.month}月${dt.day}日 '
        '周${weekdays[dt.weekday - 1]} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contactPersonController.dispose();
    _followUpController.dispose();
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
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<Tag> get _rootTags =>
      _allTags.where((t) => t.parentId == null).toList();

  /// 获取标签的完整路径字符串
  String _getTagPath(Tag tag) {
    final parts = <String>[tag.name];
    int? currentId = tag.parentId;
    while (currentId != null) {
      final matches = _allTags.where((t) => t.id == currentId);
      if (matches.isEmpty) break;
      parts.insert(0, matches.first.name);
      currentId = matches.first.parentId;
    }
    return parts.join(' > ');
  }

  /// 搜索模式下匹配的标签列表（按路径排序）
  List<Tag> get _matchedTags {
    if (_searchQuery.isEmpty) return [];
    final q = _searchQuery.toLowerCase();
    final matches = _allTags.where((t) =>
        t.name.toLowerCase().contains(q)).toList();
    matches.sort((a, b) => _getTagPath(a).compareTo(_getTagPath(b)));
    return matches;
  }

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final theme = Theme.of(context);

    // 搜索模式下构建扁平结果列表
    Widget buildSearchResults() {
      final matched = _matchedTags;
      if (matched.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('没有匹配的标签', style: TextStyle(color: Colors.grey)),
        );
      }
      return ListView(
        children: matched.map((tag) {
          final isSelected = _selectedLeafTagId == tag.id;
          final path = _getTagPath(tag);
          return ListTile(
            dense: true,
            leading: Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: isSelected ? theme.colorScheme.primary : null,
            ),
            title: Text(tag.name, style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : null,
              color: isSelected ? theme.colorScheme.primary : null,
            )),
            subtitle: Text(path, style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            )),
            onTap: () => setState(() => _selectedLeafTagId = tag.id),
          );
        }).toList(),
      );
    }

    return AlertDialog(
      title: const Text('选择树状标签'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 搜索框
            if (_allTags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索标签...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            // 内容区域
            Expanded(
              child: _searchQuery.isNotEmpty
                  ? buildSearchResults()
                  : _rootTags.isEmpty
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
                                        color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text('新建根标签',
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                        )),
                                  ],
                                ),
                              ),
                            ),
                            ..._rootTags.map((tag) => _buildNode(tag, 0)),
                          ],
                        ),
            ),
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
          padding: EdgeInsets.only(left: level * 36.0),
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
              // 添加子标签按钮紧跟在标签名后，避免太远不好对应
              if (tag.id != null && !isSelected)
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
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<int> _collapsedGroupIds = {};

  List<AttributeTag> get _filteredTags {
    if (_searchQuery.isEmpty) return _allTags;
    final q = _searchQuery.toLowerCase();
    return _allTags.where((t) =>
        t.name.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.selectedIds);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final theme = Theme.of(context);
    final ungrouped = _getTagsByGroup(null);
    final filtered = _filteredTags;

    Widget buildTagList() {
      if (_searchQuery.isNotEmpty) {
        if (filtered.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('没有匹配的属性标签', style: TextStyle(color: Colors.grey)),
          );
        }
        return ListView(
          children: filtered.map((t) => _buildTagTile(t)).toList(),
        );
      }

      if (_allTags.isEmpty && _groups.isEmpty) {
        return Center(
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
        );
      }

      return ListView(
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
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('新建属性标签',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                      )),
                ],
              ),
            ),
          ),
          const Divider(),

          // 分组（可折叠）
          ..._groups.map((g) {
            final tags = _getTagsByGroup(g.id);
            final isCollapsed = _collapsedGroupIds.contains(g.id);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() {
                    if (isCollapsed) {
                      _collapsedGroupIds.remove(g.id);
                    } else {
                      _collapsedGroupIds.add(g.id!);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          isCollapsed ? Icons.chevron_right : Icons.expand_more,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(g.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('（${tags.length}）',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                if (!isCollapsed) ...tags.map((t) => _buildTagTile(t)),
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
      );
    }

    return AlertDialog(
      title: Text('选择属性标签（已选 ${_selectedIds.length}）'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 搜索框
            if (_allTags.isNotEmpty || _groups.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索属性标签...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            Expanded(child: buildTagList()),
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
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<int> _collapsedGroupIds = {};

  List<Project> get _filteredProjects {
    if (_searchQuery.isEmpty) return _allProjects;
    final q = _searchQuery.toLowerCase();
    return _allProjects.where((p) =>
        p.name.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedProjectId;
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    _allProjects = await _db.getAllProjects(spaceId: widget.spaceId);
    _groups = await _db.getAllProjectGroups(widget.spaceId);
    if (mounted) setState(() {});
  }

  Future<void> _createProject({int? groupId}) async {
    final nameController = TextEditingController();
    int? selectedGroupId = groupId;

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建项目'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '输入项目名称',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
              if (groupId == null && _groups.isNotEmpty) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  value: selectedGroupId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '所属分组（可选）',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('不分组'),
                    ),
                    ..._groups.map((g) => DropdownMenuItem<int?>(
                      value: g.id,
                      child: Text(g.name),
                    )),
                  ],
                  onChanged: (v) => setDialogState(() => selectedGroupId = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (name != null && name.isNotEmpty) {
      final newProject = await _db.createProject(name,
          groupId: selectedGroupId, spaceId: widget.spaceId);
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
    final theme = Theme.of(context);
    final ungrouped = _getProjectsByGroup(null);
    final filtered = _filteredProjects;

    Widget buildProjectList() {
      if (_searchQuery.isNotEmpty) {
        if (filtered.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('没有匹配的项目', style: TextStyle(color: Colors.grey)),
          );
        }
        return ListView(
          children: filtered.map((p) => RadioListTile<int>(
            title: Text(p.name),
            value: p.id!,
            groupValue: _selectedId,
            onChanged: (v) => setState(() => _selectedId = v),
            dense: true,
          )).toList(),
        );
      }
      if (_allProjects.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('还没有项目', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => _createProject(),
                child: const Text('创建第一个项目'),
              ),
            ],
          ),
        );
      }
      return ListView(
        children: [
          InkWell(
            onTap: () => _createProject(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.add_circle, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('新建项目', style: TextStyle(color: theme.colorScheme.primary)),
                ],
              ),
            ),
          ),
          const Divider(),
          RadioListTile<int?>(
            title: const Text('（不选项目）'),
            value: null,
            groupValue: _selectedId,
            onChanged: (v) => setState(() => _selectedId = v),
            dense: true,
          ),
          ..._groups.map((g) {
            final projects = _getProjectsByGroup(g.id);
            final isCollapsed = _collapsedGroupIds.contains(g.id);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() {
                    if (isCollapsed) {
                      _collapsedGroupIds.remove(g.id);
                    } else {
                      _collapsedGroupIds.add(g.id!);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          isCollapsed ? Icons.chevron_right : Icons.expand_more,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text('${projects.length}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        if (!isCollapsed) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _createProject(groupId: g.id),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_circle_outline, size: 14, color: theme.colorScheme.primary),
                                const SizedBox(width: 2),
                                Text('在该分组下新建', style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (!isCollapsed)
                  ...projects.map((p) => RadioListTile<int>(
                    title: Text(p.name),
                    value: p.id!,
                    groupValue: _selectedId,
                    onChanged: (v) => setState(() => _selectedId = v),
                    dense: true,
                  )),
              ],
            );
          }),
          if (ungrouped.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('未分组', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ...ungrouped.map((p) => RadioListTile<int>(
              title: Text(p.name),
              value: p.id!,
              groupValue: _selectedId,
              onChanged: (v) => setState(() => _selectedId = v),
              dense: true,
            )),
          ],
        ],
      );
    }

    return AlertDialog(
      title: const Text('选择项目'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_allProjects.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索项目...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            Expanded(child: buildProjectList()),
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
              final p = _allProjects.firstWhere((p) => p.id == _selectedId);
              Navigator.pop(context, MapEntry<int, String>(p.id!, p.name));
            }
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// AI 润色按钮（点击弹出风格选择，选中后执行润色）
/// 始终以用户输入的原始语料为基础切换风格
class _AIBtn extends StatefulWidget {
  final TextEditingController controller;

  const _AIBtn({required this.controller});

  @override
  State<_AIBtn> createState() => _AIBtnState();
}

class _AIBtnState extends State<_AIBtn> {
  bool _loading = false;
  String? _originalText; // 用户最初输入的原始文本

  /// 获取原始文本：如果从未 AI 处理过则取当前文本，
  /// 否则取保存的原始文本
  String get _baseText => _originalText ?? widget.controller.text.trim();

  Future<void> _doPolish(int styleIndex) async {
    // 记录原始文本（首次执行时）
    _originalText ??= widget.controller.text.trim();
    if (_originalText!.isEmpty) return;

    setState(() => _loading = true);
    try {
      final result = await AIService.polish(_originalText!, styleIndex: styleIndex);
      if (mounted) {
        widget.controller.text = result;
        widget.controller.selection = TextSelection.collapsed(offset: result.length);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      onSelected: _doPolish,
      offset: const Offset(0, 36),
      enabled: !_loading,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(6),
              child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 16,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down, size: 16,
                      color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          enabled: false,
          child: Text('选择润色风格', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        ...List.generate(AIWritingStyle.all.length, (i) {
          final style = AIWritingStyle.all[i];
          return PopupMenuItem<int>(
            value: i,
            child: Text(style.name, style: const TextStyle(fontSize: 13)),
          );
        }),
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

/// 磨砂玻璃效果 wrapper（用于 BottomSheet）
class _FrostedSheet extends StatelessWidget {
  final Widget child;
  const _FrostedSheet({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor.withOpacity(0.0),
          ),
          child: child,
        ),
      ),
    );
  }
}
