import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/entry_template.dart';
import '../models/tag.dart';
import '../models/attribute_tag.dart';
import '../models/project.dart';
import '../models/project_group.dart';
import '../models/attribute_tag_group.dart';

/// 模板编辑页面
class TemplateEditorPage extends StatefulWidget {
  final EntryTemplate? template;
  final int spaceId;

  const TemplateEditorPage({super.key, this.template, required this.spaceId});

  @override
  State<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends State<TemplateEditorPage> {
  final AppDatabase _db = AppDatabase();
  final _nameController = TextEditingController();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _followUpController = TextEditingController();

  bool _isEditMode = false;
  bool _saving = false;

  // 标签选择
  List<Tag> _allTags = [];
  List<AttributeTag> _allAttributeTags = [];
  List<Project> _allProjects = [];
  List<ProjectGroup> _allProjectGroups = [];
  List<AttributeTagGroup> _allAttrTagGroups = [];

  // 选中状态
  int? _selectedLeafTagId;
  final Set<int> _selectedTagIds = {};
  final Set<int> _selectedAttributeTagIds = {};
  int? _selectedProjectId;
  String? _selectedProjectName;

  // 对接人 & 后续待办
  String _contactPerson = '';
  String _followUp = '';

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.template != null;
    _loadData();
  }

  Future<void> _loadData() async {
    _allTags = await _db.getAllTags(spaceId: widget.spaceId);
    _allAttributeTags = await _db.getAllAttributeTags(widget.spaceId);
    _allProjects = await _db.getAllProjects(spaceId: widget.spaceId);
    _allProjectGroups = await _db.getAllProjectGroups(widget.spaceId);
    _allAttrTagGroups = await _db.getAllAttributeTagGroups(widget.spaceId);

    if (_isEditMode && widget.template != null) {
      final t = widget.template!;
      _nameController.text = t.name;
      _titleController.text = t.title ?? '';
      _contentController.text = t.content;
      _contactPerson = t.contactPerson ?? '';
      _contactPersonController.text = _contactPerson;
      _followUp = t.followUp ?? '';
      _followUpController.text = _followUp;
      _selectedProjectId = t.projectId;
      _selectedProjectName = t.projectName;

      if (t.tagIds.isNotEmpty) {
        _selectedTagIds.addAll(t.tagIds);
        // 找最深的标签作为 leaf tag
        final allTags = _allTags;
        int? deepestId;
        int maxDepth = -1;
        for (final tagId in t.tagIds) {
          final tag = allTags.where((t) => t.id == tagId).firstOrNull;
          if (tag == null) continue;
          int depth = 0;
          int? parentId = tag.parentId;
          while (parentId != null) {
            depth++;
            final parent = allTags.where((t) => t.id == parentId).firstOrNull;
            parentId = parent?.parentId;
          }
          if (depth > maxDepth) {
            maxDepth = depth;
            deepestId = tagId;
          }
        }
        if (deepestId != null) _selectedLeafTagId = deepestId;
      }
      _selectedAttributeTagIds.addAll(t.attributeTagIds);
    }

    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入模板名称')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final template = EntryTemplate(
        name: name,
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : null,
        content: _contentController.text.trim(),
        tagIds: _selectedTagIds.toList(),
        attributeTagIds: _selectedAttributeTagIds.toList(),
        projectId: _selectedProjectId,
        projectName: _selectedProjectName,
        contactPerson: _contactPerson.isNotEmpty ? _contactPerson : null,
        followUp: _followUp.isNotEmpty ? _followUp : null,
      );

      if (_isEditMode) {
        await _db.updateTemplate(widget.template!.id!, template);
      } else {
        await _db.createTemplate(template);
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(true);
      }
    } catch (e) {
      debugPrint('保存模板失败：$e');
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
                  child: const Text('确定')),
            ],
          ),
        );
      }
    }
  }

  // ==================== 选择器弹窗 ====================

  Future<void> _pickTag() async {
    // 展开已选路径
    final initExpanded = <int>{};
    if (_selectedLeafTagId != null) {
      int? cid = _selectedLeafTagId;
      while (cid != null) {
        initExpanded.add(cid);
        cid = _allTags.where((t) => t.id == cid).firstOrNull?.parentId;
      }
    }

    int? selectedId = _selectedLeafTagId;
    final expanded = initExpanded;

    List<Tag> childrenOf(int? pid) => _allTags
        .where((t) => t.parentId == pid).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInnerState) {
          Widget buildTree(int? parentId) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: childrenOf(parentId).expand((tag) {
                final hasChildren = childrenOf(tag.id).isNotEmpty;
                final isExpanded = expanded.contains(tag.id);
                final isSelected = selectedId == tag.id;
                final tile = ListTile(
                  dense: true,
                  leading: hasChildren
                      ? SizedBox(
                          width: 24,
                          child: IconButton(
                            icon: Icon(isExpanded ? Icons.expand_more : Icons.chevron_right, size: 18),
                            onPressed: () => setInnerState(() {
                              if (isExpanded) expanded.remove(tag.id);
                              else expanded.add(tag.id!);
                            }),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          ),
                        )
                      : const SizedBox(width: 24),
                  title: Text(tag.name, style: const TextStyle(fontSize: 14)),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, size: 18, color: Theme.of(ctx2).colorScheme.primary)
                      : null,
                  selected: isSelected,
                  onTap: () => setInnerState(() => selectedId = tag.id),
                );
                if (isExpanded) {
                  return [
                    tile,
                    Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: buildTree(tag.id),
                    ),
                  ];
                }
                return [tile];
              }).toList(),
            );
          }

          return AlertDialog(
            title: const Text('选择树状标签'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: SingleChildScrollView(
                child: buildTree(null),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              TextButton(
                onPressed: selectedId != null ? () => Navigator.pop(ctx, selectedId) : null,
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && mounted) {
      final allTags = _allTags;
      final newIds = <int>{};
      void addAnc(int tagId) {
        newIds.add(tagId);
        final tag = allTags.where((t) => t.id == tagId).firstOrNull;
        if (tag?.parentId != null) addAnc(tag!.parentId!);
      }
      addAnc(result);
      setState(() {
        _selectedLeafTagId = result;
        _selectedTagIds..clear()..addAll(newIds);
      });
    }
  }

  Future<void> _pickAttributeTags() async {
    final selected = Set<int>.from(_selectedAttributeTagIds);

    final result = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInnerState) {
          Widget buildTile(AttributeTag t) {
            final sel = selected.contains(t.id);
            return ListTile(
              dense: true,
              leading: Icon(
                sel ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: sel ? Theme.of(ctx).colorScheme.primary : null,
              ),
              title: Text(t.name, style: const TextStyle(fontSize: 14)),
              onTap: () {
                setInnerState(() {
                  if (sel) selected.remove(t.id);
                  else selected.add(t.id!);
                });
              },
            );
          }

          List<Widget> buildList() {
            final widgets = <Widget>[];
            final ungrouped = _allAttributeTags.where((t) => t.groupId == null).toList();
            for (final t in ungrouped) widgets.add(buildTile(t));
            for (final g in _allAttrTagGroups) {
              final gtags = _allAttributeTags.where((t) => t.groupId == g.id).toList();
              if (gtags.isEmpty) continue;
              widgets.add(Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(g.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    )),
              ));
              for (final t in gtags) widgets.add(buildTile(t));
            }
            return widgets;
          }

          return AlertDialog(
            title: Text('属性标签（已选 ${selected.length}）'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView(children: buildList()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, Set.of(selected)),
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && mounted) {
      setState(() => _selectedAttributeTagIds
        ..clear()
        ..addAll(result));
    }
  }

  Future<void> _pickProject() async {
    int? selectedId = _selectedProjectId;
    String? selectedName;

    final result = await showDialog<MapEntry<int, String>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInnerState) {
          Widget buildTile(Project p) {
            final sel = selectedId == p.id;
            return ListTile(
              dense: true,
              leading: Icon(
                sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18,
                color: sel ? Theme.of(ctx).colorScheme.primary : null,
              ),
              title: Text(p.name, style: const TextStyle(fontSize: 14)),
              selected: sel,
              onTap: () => setInnerState(() { selectedId = p.id; selectedName = p.name; }),
            );
          }

          List<Widget> buildList() {
            final widgets = <Widget>[];
            final ungrouped = _allProjects.where((p) => p.groupId == null).toList();
            for (final p in ungrouped) widgets.add(buildTile(p));
            for (final g in _allProjectGroups) {
              final gprojects = _allProjects.where((p) => p.groupId == g.id).toList();
              if (gprojects.isEmpty) continue;
              widgets.add(Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(g.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    )),
              ));
              for (final p in gprojects) widgets.add(buildTile(p));
            }
            return widgets;
          }

          return AlertDialog(
            title: const Text('选择项目'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView(children: buildList()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              TextButton(
                onPressed: selectedId != null
                    ? () => Navigator.pop(ctx, MapEntry(selectedId!, selectedName ?? ''))
                    : null,
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedProjectId = result.key;
        _selectedProjectName = result.value;
      });
    }
  }

  Future<void> _editTextField({
    required String title,
    required String initialValue,
    required String hint,
    required ValueChanged<String> onChanged,
    int maxLines = 3,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
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
    controller.dispose();
    if (result != null) {
      onChanged(result);
    }
  }

  // ==================== 构建 UI ====================

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _contactPersonController.dispose();
    _followUpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? '编辑模板' : '新建模板'),
        actions: [
          _saving
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- 模板名称 ----
            _buildSectionHeader(theme, Icons.bookmark, '模板名称'),
            const SizedBox(height: 8),
            _buildClickableField(
              theme: theme,
              value: _nameController.text,
              hint: '如：周报模板',
              icon: Icons.edit_outlined,
              onTap: () => _editTextField(
                title: '模板名称',
                initialValue: _nameController.text,
                hint: '输入模板名称',
                onChanged: (v) => setState(() => _nameController.text = v),
                maxLines: 1,
              ),
            ),

            const SizedBox(height: 20),

            // ---- 事项简介 ----
            Row(
              children: [
                Icon(Icons.short_text,
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('事项简介',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            _buildClickableField(
              theme: theme,
              value: _titleController.text,
              hint: '默认标题（可选）',
              icon: Icons.edit_outlined,
              onTap: () => _editTextField(
                title: '事项简介',
                initialValue: _titleController.text,
                hint: '默认标题',
                onChanged: (v) => setState(() => _titleController.text = v),
                maxLines: 2,
              ),
            ),

            const SizedBox(height: 16),

            // ---- 详细情况 ----
            Row(
              children: [
                Icon(Icons.subject,
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('详细情况',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            _buildClickableField(
              theme: theme,
              value: _contentController.text,
              hint: '默认内容（可选）',
              icon: Icons.edit_outlined,
              onTap: () => _editTextField(
                title: '详细情况',
                initialValue: _contentController.text,
                hint: '默认详细内容',
                onChanged: (v) => setState(() => _contentController.text = v),
                maxLines: 5,
              ),
            ),

            const SizedBox(height: 20),

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
            const SizedBox(height: 8),
            _buildClickableField(
              theme: theme,
              value: _contactPerson,
              hint: '默认对接人（可选）',
              icon: Icons.edit_outlined,
              onTap: () => _editTextField(
                title: '对接人',
                initialValue: _contactPerson,
                hint: '如：张三',
                onChanged: (v) => setState(() => _contactPerson = v),
                maxLines: 1,
              ),
            ),

            const SizedBox(height: 12),

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
            const SizedBox(height: 8),
            _buildClickableField(
              theme: theme,
              value: _followUp,
              hint: '默认后续待办（可选）',
              icon: Icons.edit_outlined,
              onTap: () => _editTextField(
                title: '后续待办',
                initialValue: _followUp,
                hint: '如：下周五前回复邮件',
                onChanged: (v) => setState(() => _followUp = v),
                maxLines: 2,
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // ---- 树状标签 ----
            _buildSectionHeader(theme, Icons.label, '树状标签'),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickTag,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.label,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _selectedLeafTagId != null
                          ? Text(
                              _getTagPath(_selectedLeafTagId!),
                              style: const TextStyle(fontSize: 14),
                            )
                          : Text('选择标签（可选）',
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              )),
                    ),
                    if (_selectedLeafTagId != null)
                      GestureDetector(
                        onTap: () => setState(() {
                          _selectedLeafTagId = null;
                          _selectedTagIds.clear();
                        }),
                        child: Icon(Icons.close,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ---- 属性标签 ----
            _buildSectionHeader(theme, Icons.turned_in_not, '属性标签'),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickAttributeTags,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Icon(Icons.turned_in_not,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    if (_selectedAttributeTagIds.isEmpty)
                      Text('选择属性标签（可选）',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          )),
                    ..._selectedAttributeTagIds.map((id) {
                      final tag =
                          _allAttributeTags.where((t) => t.id == id).firstOrNull;
                      if (tag == null) return const SizedBox.shrink();
                      return Chip(
                        label: Text(tag.name, style: const TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () => setState(
                            () => _selectedAttributeTagIds.remove(id)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      );
                    }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ---- 项目 ----
            _buildSectionHeader(theme, Icons.folder_outlined, '项目'),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickProject,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_outlined,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _selectedProjectId != null
                          ? Text(_selectedProjectName ?? '',
                              style: const TextStyle(fontSize: 14))
                          : Text('选择项目（可选）',
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              )),
                    ),
                    if (_selectedProjectId != null)
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

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }

  Widget _buildClickableField({
    required ThemeData theme,
    required String value,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
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
            Expanded(
              child: value.isNotEmpty
                  ? Text(value, style: const TextStyle(fontSize: 14))
                  : Text(hint,
                      style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant)),
            ),
            Icon(icon,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  String _getTagPath(int tagId) {
    final parts = <String>[];
    int? currentId = tagId;
    while (currentId != null) {
      final tag = _allTags.where((t) => t.id == currentId).firstOrNull;
      if (tag == null) break;
      parts.insert(0, tag.name);
      currentId = tag.parentId;
    }
    return parts.join(' > ');
  }
}

// ==================== 选择器弹窗（简化版，供模板编辑使用） ====================

class _TagPickerDialog extends StatefulWidget {
  final List<Tag> allTags;
  final int? initialSelectedTagId;
  final Set<int> selectedTagIds;

  const _TagPickerDialog({
    required this.allTags,
    this.initialSelectedTagId,
    required this.selectedTagIds,
  });

  @override
  State<_TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<_TagPickerDialog> {
  int? _selectedId;
  final Set<int> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedTagId;
    // 展开选中路径
    if (_selectedId != null) {
      int? currentId = _selectedId;
      while (currentId != null) {
        _expandedIds.add(currentId);
        final tag = widget.allTags.where((t) => t.id == currentId).firstOrNull;
        currentId = tag?.parentId;
      }
    }
  }

  List<Tag> _getChildren(int? parentId) {
    return widget.allTags
        .where((t) => t.parentId == parentId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择树状标签'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView(
          children: _buildTagTree(null),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('取消')),
        TextButton(
          onPressed: _selectedId != null
              ? () => Navigator.of(context, rootNavigator: true).pop(_selectedId)
              : null,
          child: const Text('确定'),
        ),
      ],
    );
  }

  List<Widget> _buildTagTree(int? parentId) {
    final children = _getChildren(parentId);
    final widgets = <Widget>[];
    for (final tag in children) {
      final hasChildren = _getChildren(tag.id).isNotEmpty;
      final isExpanded = _expandedIds.contains(tag.id);
      final isSelected = _selectedId == tag.id;
      widgets.add(
        Padding(
          padding: EdgeInsets.only(left: parentId != null ? 24.0 : 0),
          child: ListTile(
            dense: true,
            leading: hasChildren
                ? IconButton(
                    icon: Icon(
                      isExpanded
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedIds.remove(tag.id);
                        } else {
                          _expandedIds.add(tag.id!);
                        }
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 24, minHeight: 24),
                  )
                : const SizedBox(width: 24),
            title: Text(tag.name, style: const TextStyle(fontSize: 14)),
            trailing: isSelected
                ? Icon(Icons.check_circle,
                    size: 18, color: Theme.of(context).colorScheme.primary)
                : null,
            selected: isSelected,
            onTap: () {
              setState(() => _selectedId = tag.id);
            },
          ),
        ),
      );
      if (isExpanded) {
        widgets.addAll(_buildTagTree(tag.id));
      }
    }
    return widgets;
  }
}

class _AttributeTagPickerDialog extends StatefulWidget {
  final List<AttributeTag> tags;
  final List<AttributeTagGroup> groups;
  final Set<int> initialSelectedIds;

  const _AttributeTagPickerDialog({
    required this.tags,
    required this.groups,
    required this.initialSelectedIds,
  });

  @override
  State<_AttributeTagPickerDialog> createState() =>
      _AttributeTagPickerDialogState();
}

class _AttributeTagPickerDialogState extends State<_AttributeTagPickerDialog> {
  late Set<int> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('属性标签（已选 ${_selectedIds.length}）'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView(
          children: _buildGroupedList(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('取消')),
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(Set.from(_selectedIds)),
          child: const Text('确定'),
        ),
      ],
    );
  }

  List<Widget> _buildGroupedList() {
    final widgets = <Widget>[];
    // 未分组标签
    final ungrouped = widget.tags.where((t) => t.groupId == null).toList();
    if (ungrouped.isNotEmpty) {
      for (final tag in ungrouped) {
        widgets.add(_buildTagTile(tag));
      }
    }
    // 按组分
    for (final group in widget.groups) {
      final groupTags =
          widget.tags.where((t) => t.groupId == group.id).toList();
      if (groupTags.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(group.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
        ),
      );
      for (final tag in groupTags) {
        widgets.add(_buildTagTile(tag));
      }
    }
    return widgets;
  }

  Widget _buildTagTile(AttributeTag tag) {
    final isSelected = _selectedIds.contains(tag.id);
    return ListTile(
      dense: true,
      leading: Icon(
        isSelected ? Icons.check_box : Icons.check_box_outline_blank,
        size: 18,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      title: Text(tag.name, style: const TextStyle(fontSize: 14)),
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedIds.remove(tag.id);
          } else {
            _selectedIds.add(tag.id!);
          }
        });
      },
    );
  }
}

class _ProjectPickerDialog extends StatefulWidget {
  final List<Project> projects;
  final List<ProjectGroup> groups;
  final int? initialProjectId;

  const _ProjectPickerDialog({
    required this.projects,
    required this.groups,
    this.initialProjectId,
  });

  @override
  State<_ProjectPickerDialog> createState() => _ProjectPickerDialogState();
}

class _ProjectPickerDialogState extends State<_ProjectPickerDialog> {
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialProjectId;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择项目'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView(
          children: _buildGroupedList(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('取消')),
        TextButton(
          onPressed: _selectedId != null
              ? () {
                  final project = widget.projects
                      .where((p) => p.id == _selectedId)
                      .firstOrNull;
                  Navigator.of(context, rootNavigator: true).pop(
                    project != null
                        ? MapEntry(project.id!, project.name)
                        : null,
                  );
                }
              : null,
          child: const Text('确定'),
        ),
      ],
    );
  }

  List<Widget> _buildGroupedList() {
    final widgets = <Widget>[];
    // 未分组
    final ungrouped = widget.projects.where((p) => p.groupId == null).toList();
    if (ungrouped.isNotEmpty) {
      for (final p in ungrouped) {
        widgets.add(_buildTile(p));
      }
    }
    for (final group in widget.groups) {
      final groupProjects =
          widget.projects.where((p) => p.groupId == group.id).toList();
      if (groupProjects.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(group.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
        ),
      );
      for (final p in groupProjects) {
        widgets.add(_buildTile(p));
      }
    }
    return widgets;
  }

  Widget _buildTile(Project project) {
    final isSelected = _selectedId == project.id;
    return ListTile(
      dense: true,
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 18,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      title: Text(project.name, style: const TextStyle(fontSize: 14)),
      selected: isSelected,
      onTap: () => setState(() => _selectedId = project.id),
    );
  }
}
