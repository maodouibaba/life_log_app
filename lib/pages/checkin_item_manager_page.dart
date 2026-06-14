import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/checkin_item.dart';
import '../models/tag.dart';
import '../models/attribute_tag.dart';
import '../models/project.dart';
import '../models/project_group.dart';
import '../models/attribute_tag_group.dart';

/// 打卡事项管理页面
class CheckinItemManagerPage extends StatefulWidget {
  final int spaceId;

  const CheckinItemManagerPage({super.key, required this.spaceId});

  @override
  State<CheckinItemManagerPage> createState() => _CheckinItemManagerPageState();
}

class _CheckinItemManagerPageState extends State<CheckinItemManagerPage> {
  final AppDatabase _db = AppDatabase();
  List<CheckinItem> _items = [];
  List<Tag> _allTags = [];
  List<AttributeTag> _allAttributeTags = [];
  List<Project> _allProjects = [];
  List<ProjectGroup> _allProjectGroups = [];
  List<AttributeTagGroup> _allAttrTagGroups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      _items = await _db.getCheckinItems(widget.spaceId);
      _allTags = await _db.getAllTags(spaceId: widget.spaceId);
      _allAttributeTags = await _db.getAllAttributeTags(widget.spaceId);
      _allProjects = await _db.getAllProjects(spaceId: widget.spaceId);
      _allProjectGroups = await _db.getAllProjectGroups(widget.spaceId);
      _allAttrTagGroups = await _db.getAllAttributeTagGroups(widget.spaceId);
    } catch (e) {
      debugPrint('加载打卡事项失败：$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  String _tagName(int? tagId) {
    if (tagId == null) return '';
    final tag = _allTags.where((t) => t.id == tagId).firstOrNull;
    return tag?.name ?? '';
  }

  String _attrTagName(int? tagId) {
    if (tagId == null) return '';
    final tag = _allAttributeTags.where((t) => t.id == tagId).firstOrNull;
    return tag?.name ?? '';
  }

  String _projectName(int? projectId) {
    if (projectId == null) return '';
    final p = _allProjects.where((p) => p.id == projectId).firstOrNull;
    return p?.name ?? '';
  }

  Future<void> _addOrEditItem({CheckinItem? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    int? selTagId = existing?.tagId;
    int? selAttrTagId = existing?.attributeTagId;
    int? selProjectId = existing?.projectId;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setInnerState) => AlertDialog(
          title: Text(existing != null ? '编辑事项' : '新建事项'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '事项名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 关联树状标签
                  Row(
                    children: [
                      const Icon(Icons.label, size: 14),
                      const SizedBox(width: 6),
                      const Text('关联树状标签', style: TextStyle(fontSize: 13)),
                      const Spacer(),
                      if (selTagId != null)
                        GestureDetector(
                          onTap: () => setInnerState(() => selTagId = null),
                          child: const Icon(Icons.close, size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final result = await showDialog<int>(
                        context: ctx2,
                        builder: (c) => _SimpleTagPicker(
                          allTags: _allTags,
                          selectedId: selTagId,
                        ),
                      );
                      if (result != null) {
                        setInnerState(() => selTagId = result);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(ctx2).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        selTagId != null ? _tagName(selTagId) : '不关联',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 关联属性标签
                  Row(
                    children: [
                      const Icon(Icons.turned_in_not, size: 14),
                      const SizedBox(width: 6),
                      const Text('关联属性标签', style: TextStyle(fontSize: 13)),
                      const Spacer(),
                      if (selAttrTagId != null)
                        GestureDetector(
                          onTap: () => setInnerState(() => selAttrTagId = null),
                          child: const Icon(Icons.close, size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final result = await showDialog<int>(
                        context: ctx2,
                        builder: (c) => _SimpleAttrTagPicker(
                          tags: _allAttributeTags,
                          groups: _allAttrTagGroups,
                          selectedId: selAttrTagId,
                        ),
                      );
                      if (result != null) {
                        setInnerState(() => selAttrTagId = result);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(ctx2).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        selAttrTagId != null ? _attrTagName(selAttrTagId) : '不关联',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 关联项目
                  Row(
                    children: [
                      const Icon(Icons.folder_outlined, size: 14),
                      const SizedBox(width: 6),
                      const Text('关联项目', style: TextStyle(fontSize: 13)),
                      const Spacer(),
                      if (selProjectId != null)
                        GestureDetector(
                          onTap: () => setInnerState(() => selProjectId = null),
                          child: const Icon(Icons.close, size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final result = await showDialog<int>(
                        context: ctx2,
                        builder: (c) => _SimpleProjectPicker(
                          projects: _allProjects,
                          groups: _allProjectGroups,
                          selectedId: selProjectId,
                        ),
                      );
                      if (result != null) {
                        setInnerState(() => selProjectId = result);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(ctx2).colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        selProjectId != null ? _projectName(selProjectId) : '不关联',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      try {
        final item = CheckinItem(
          name: nameCtrl.text.trim(),
          spaceId: widget.spaceId,
          tagId: selTagId,
          attributeTagId: selAttrTagId,
          projectId: selProjectId,
        );
        if (existing != null) {
          await _db.updateCheckinItem(existing.id!, item);
        } else {
          await _db.createCheckinItem(item);
        }
        _loadData();
      } catch (e) {
        debugPrint('保存打卡事项失败：$e');
      }
    }
    nameCtrl.dispose();
  }

  Future<void> _deleteItem(CheckinItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除事项'),
        content: Text('确定删除"${item.name}"吗？\n相关的打卡记录也会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true && item.id != null) {
      await _db.deleteCheckinItem(item.id!);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('打卡事项'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEditItem(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text('还没有打卡事项',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Text('点击右上角 + 添加',
                          style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final item = _items[i];
                    final tags = [
                      if (item.tagId != null) '🏷${_tagName(item.tagId)}',
                      if (item.attributeTagId != null) '✨${_attrTagName(item.attributeTagId)}',
                      if (item.projectId != null) '📁${_projectName(item.projectId)}',
                    ];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        leading: Icon(Icons.check_box_outlined,
                            color: theme.colorScheme.primary, size: 24),
                        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: tags.isNotEmpty
                            ? Text(tags.join('  '),
                                style: const TextStyle(fontSize: 12), maxLines: 1)
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _addOrEditItem(existing: item),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 18, color: theme.colorScheme.error),
                              onPressed: () => _deleteItem(item),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ==================== 简单选择器 ====================

class _SimpleTagPicker extends StatefulWidget {
  final List<Tag> allTags;
  final int? selectedId;
  const _SimpleTagPicker({required this.allTags, this.selectedId});

  @override
  State<_SimpleTagPicker> createState() => _SimpleTagPickerState();
}

class _SimpleTagPickerState extends State<_SimpleTagPicker> {
  int? _selectedId;
  final Set<int> _expandedIds = {};

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    if (_selectedId != null) {
      int? cid = _selectedId;
      while (cid != null) {
        _expandedIds.add(cid);
        cid = widget.allTags.where((t) => t.id == cid).firstOrNull?.parentId;
      }
    }
  }

  List<Tag> _children(int? pid) => widget.allTags
      .where((t) => t.parentId == pid).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择树状标签'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView(children: _buildTree(null)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: _selectedId != null ? () => Navigator.pop(context, _selectedId) : null,
          child: const Text('确定'),
        ),
      ],
    );
  }

  List<Widget> _buildTree(int? pid) {
    return _children(pid).expand((tag) {
      final hasChildren = _children(tag.id).isNotEmpty;
      final exp = _expandedIds.contains(tag.id);
      final sel = _selectedId == tag.id;
      final tile = ListTile(
        dense: true,
        leading: hasChildren
            ? SizedBox(
                width: 24,
                child: IconButton(
                  icon: Icon(exp ? Icons.expand_more : Icons.chevron_right, size: 18),
                  onPressed: () => setState(() {
                    if (exp) _expandedIds.remove(tag.id);
                    else _expandedIds.add(tag.id!);
                  }),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              )
            : const SizedBox(width: 24),
        title: Text(tag.name, style: const TextStyle(fontSize: 14)),
        trailing: sel
            ? Icon(Icons.check_circle, size: 18, color: Theme.of(context).colorScheme.primary)
            : null,
        selected: sel,
        onTap: () => setState(() => _selectedId = tag.id),
      );
      return exp ? [tile, Padding(padding: const EdgeInsets.only(left: 24), child: Column(children: _buildTree(tag.id)))] : [tile];
    }).toList();
  }
}

class _SimpleAttrTagPicker extends StatefulWidget {
  final List<AttributeTag> tags;
  final List<AttributeTagGroup> groups;
  final int? selectedId;
  const _SimpleAttrTagPicker({required this.tags, required this.groups, this.selectedId});

  @override
  State<_SimpleAttrTagPicker> createState() => _SimpleAttrTagPickerState();
}

class _SimpleAttrTagPickerState extends State<_SimpleAttrTagPicker> {
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择属性标签'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView(children: _buildList()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: _selectedId != null ? () => Navigator.pop(context, _selectedId) : null,
          child: const Text('确定'),
        ),
      ],
    );
  }

  List<Widget> _buildList() {
    final ws = <Widget>[];
    for (final t in widget.tags.where((t) => t.groupId == null)) {
      ws.add(_tile(t));
    }
    for (final g in widget.groups) {
      final gtags = widget.tags.where((t) => t.groupId == g.id).toList();
      if (gtags.isEmpty) continue;
      ws.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(g.name, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        )),
      ));
      for (final t in gtags) ws.add(_tile(t));
    }
    return ws;
  }

  Widget _tile(AttributeTag t) {
    final sel = _selectedId == t.id;
    return ListTile(
      dense: true,
      leading: Icon(
        sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 18,
        color: sel ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(t.name, style: const TextStyle(fontSize: 14)),
      onTap: () => setState(() => _selectedId = t.id),
    );
  }
}

class _SimpleProjectPicker extends StatefulWidget {
  final List<Project> projects;
  final List<ProjectGroup> groups;
  final int? selectedId;
  const _SimpleProjectPicker({required this.projects, required this.groups, this.selectedId});

  @override
  State<_SimpleProjectPicker> createState() => _SimpleProjectPickerState();
}

class _SimpleProjectPickerState extends State<_SimpleProjectPicker> {
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择项目'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView(children: _buildList()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: _selectedId != null ? () => Navigator.pop(context, _selectedId) : null,
          child: const Text('确定'),
        ),
      ],
    );
  }

  List<Widget> _buildList() {
    final ws = <Widget>[];
    for (final p in widget.projects.where((p) => p.groupId == null)) {
      ws.add(_tile(p));
    }
    for (final g in widget.groups) {
      final gps = widget.projects.where((p) => p.groupId == g.id).toList();
      if (gps.isEmpty) continue;
      ws.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(g.name, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        )),
      ));
      for (final p in gps) ws.add(_tile(p));
    }
    return ws;
  }

  Widget _tile(Project p) {
    final sel = _selectedId == p.id;
    return ListTile(
      dense: true,
      leading: Icon(
        sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 18,
        color: sel ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(p.name, style: const TextStyle(fontSize: 14)),
      onTap: () => setState(() => _selectedId = p.id),
    );
  }
}
