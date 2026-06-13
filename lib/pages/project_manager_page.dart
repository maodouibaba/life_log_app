import 'package:flutter/material.dart';
import '../models/project.dart';
import '../models/project_group.dart';
import '../database/app_database.dart';

/// 项目管理页面
/// 支持分组分层管理，分组可收起展开，支持批量操作
/// 同级拖拽排序，长按项目体可拖到其他分组
class ProjectManagerPage extends StatefulWidget {
  final int spaceId;

  const ProjectManagerPage({super.key, required this.spaceId});

  @override
  State<ProjectManagerPage> createState() => _ProjectManagerPageState();
}

class _ProjectManagerPageState extends State<ProjectManagerPage> {
  final AppDatabase _db = AppDatabase();
  List<Project> _projects = [];
  List<ProjectGroup> _groups = [];

  // 分组展开状态
  final Set<int> _expandedGroupIds = {};
  // 选择模式
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  int get _spaceId => widget.spaceId;

  @override
  void initState() {
    super.initState();
    _loadData();
    // 默认展开所有分组
    _db.getAllProjectGroups(_spaceId).then((groups) {
      for (final g in groups) {
        if (g.id != null) _expandedGroupIds.add(g.id!);
      }
    });
  }

  Future<void> _loadData() async {
    _projects = await _db.getAllProjects(spaceId: _spaceId);
    _groups = await _db.getAllProjectGroups(_spaceId);
    if (mounted) setState(() {});
  }

  List<Project> _getProjectsByGroup(int? groupId) =>
      _projects.where((p) => p.groupId == groupId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// 重新排序同级项目
  Future<void> _reorderInGroup(int? groupId, int oldIndex, int newIndex) async {
    final siblings = _getProjectsByGroup(groupId);
    if (oldIndex < newIndex) newIndex--;
    final updated = List<Project>.from(siblings);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    for (int i = 0; i < updated.length; i++) {
      if (updated[i].sortOrder != i) {
        await _db.updateProjectSortOrder(updated[i].id!, i);
      }
    }
    if (item.sortOrder != newIndex) {
      await _db.updateProjectSortOrder(item.id!, newIndex);
    }
    _loadData();
  }

  /// 移动项目到新分组（拖拽）
  Future<void> _moveProjectToGroup(Project p, int? targetGroupId) async {
    if (p.groupId == targetGroupId) return;
    await _db.moveProjectToGroup(p.id!, targetGroupId);
    _loadData();
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个项目吗？'),
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
      for (final id in _selectedIds) {
        await _db.deleteProject(id);
      }
      _selectedIds.clear();
      _loadData();
    }
  }

  Future<void> _batchMoveToGroup() async {
    if (_selectedIds.isEmpty) return;
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => _PickProjectGroupBatchDialog(groups: _groups),
    );
    if (result == null) return;
    final groupId = result == -1 ? null : result;
    for (final id in _selectedIds) {
      await _db.moveProjectToGroup(id, groupId);
    }
    _selectedIds.clear();
    _loadData();
  }

  // ===== 分组操作 =====
  Future<void> _addGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建项目分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '分组名称（如：工作项目、个人项目）',
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
      await _db.createProjectGroup(name, _spaceId);
      _loadData();
    }
  }

  Future<void> _renameGroup(ProjectGroup g) async {
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
      await _db.updateProjectGroupName(g.id!, name);
      _loadData();
    }
  }

  Future<void> _deleteGroup(ProjectGroup g) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分组'),
        content: Text(
            '确定要删除分组「${g.name}」吗？\n（组内的项目不会删除，会变为"未分组"状态）'),
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
      await _db.deleteProjectGroup(g.id!);
      _loadData();
    }
  }

  // ===== 项目操作 =====
  Future<void> _addProject({int? groupId}) async {
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
      await _db.createProject(name, groupId: groupId, spaceId: _spaceId);
      _loadData();
    }
  }

  Future<void> _renameProject(Project p) async {
    final controller = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名项目'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '项目名称',
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
    if (name != null && name.isNotEmpty && name != p.name) {
      await _db.updateProjectName(p.id!, name);
      _loadData();
    }
  }

  Future<void> _deleteProject(Project p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除项目'),
        content: Text(
            '确定要删除「${p.name}」吗？\n（相关记录的"项目"字段会被清空，记录本身不受影响）'),
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
      await _db.deleteProject(p.id!);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ungrouped = _getProjectsByGroup(null);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selectedIds.length}' : '项目管理'),
        actions: [
          if (_selectMode) ...[
            IconButton(
              icon: const Icon(Icons.drive_file_move_outlined),
              tooltip: '移动到分组',
              onPressed:
                  _selectedIds.isNotEmpty ? _batchMoveToGroup : null,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: theme.colorScheme.error),
              tooltip: '批量删除',
              onPressed:
                  _selectedIds.isNotEmpty ? _batchDelete : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消选择',
              onPressed: _toggleSelectMode,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: '选择',
              onPressed: _toggleSelectMode,
            ),
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              tooltip: '新建分组',
              onPressed: _addGroup,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新建项目',
              onPressed: () => _addProject(),
            ),
          ],
        ],
      ),
      body: _projects.isEmpty && _groups.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_outlined, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('还没有项目',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('点击右上角 + 创建项目',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ..._groups.map((g) => _ProjectGroupSection(
                      group: g,
                      projects: _getProjectsByGroup(g.id),
                      allGroups: _groups,
                      isExpanded: _expandedGroupIds.contains(g.id),
                      selectMode: _selectMode,
                      selectedIds: _selectedIds,
                      theme: theme,
                      onToggleExpand: () => setState(() {
                        if (_expandedGroupIds.contains(g.id!)) {
                          _expandedGroupIds.remove(g.id!);
                        } else {
                          _expandedGroupIds.add(g.id!);
                        }
                      }),
                      onToggleSelect: _toggleSelect,
                      onAddProject: () => _addProject(groupId: g.id),
                      onRenameGroup: () => _renameGroup(g),
                      onDeleteGroup: () => _deleteGroup(g),
                      onRenameProject: _renameProject,
                      onDeleteProject: _deleteProject,
                      onReorder: (oldIndex, newIndex) =>
                          _reorderInGroup(g.id, oldIndex, newIndex),
                      onMoveProjectToGroup: (p) =>
                          _moveProjectToGroup(p, g.id),
                    )),

                // 未分组项目（同时是 DragTarget）
                if (ungrouped.isNotEmpty || _groups.isNotEmpty)
                  _buildUngroupedSection(theme, ungrouped),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildUngroupedSection(ThemeData theme, List<Project> ungrouped) {
    return DragTarget<Project>(
      onAcceptWithDetails: (details) =>
          _moveProjectToGroup(details.data, null),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isHovering
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: isHovering
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isHovering)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_downward, size: 14,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('释放到此处设为未分组',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
              if (ungrouped.isNotEmpty || !isHovering)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('未分组（${ungrouped.length}）',
                      style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500)),
                ),
              if (ungrouped.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('（空）',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                )
              else
                ...ungrouped.map((p) => _buildProjectTile(p, theme)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProjectTile(Project p, ThemeData theme) {
    return LongPressDraggable<Project>(
      data: p,
      delay: const Duration(milliseconds: 300),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 200,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.drive_file_rename_outline,
                size: 18, color: theme.colorScheme.primary),
            title: Text(p.name, style: const TextStyle(fontSize: 13)),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: ListTile(
          dense: true,
          leading: _selectMode
              ? Checkbox(
                  value: _selectedIds.contains(p.id),
                  onChanged: (_) => _toggleSelect(p.id!),
                )
              : Icon(Icons.folder_outlined,
                  size: 18, color: theme.colorScheme.primary),
          title: Text(p.name, style: const TextStyle(fontSize: 14)),
          trailing: _selectMode ? null : PopupMenuButton<String>(
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('重命名')),
              if (_groups.isNotEmpty)
                const PopupMenuItem(value: 'move', child: Text('移动到分组')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('删除', style: TextStyle(color: Colors.red)),
              ),
            ],
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  _renameProject(p);
                  break;
                case 'move':
                  _showMoveDialog(p);
                  break;
                case 'delete':
                  _deleteProject(p);
                  break;
              }
            },
          ),
          onTap: _selectMode ? () => _toggleSelect(p.id!) : null,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: _selectMode
            ? Checkbox(
                value: _selectedIds.contains(p.id),
                onChanged: (_) => _toggleSelect(p.id!),
              )
            : Icon(Icons.folder_outlined,
                size: 18, color: theme.colorScheme.primary),
        title: Text(p.name, style: const TextStyle(fontSize: 14)),
        trailing: _selectMode ? null : PopupMenuButton<String>(
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('重命名')),
            if (_groups.isNotEmpty)
              const PopupMenuItem(value: 'move', child: Text('移动到分组')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
          onSelected: (v) {
            switch (v) {
              case 'edit':
                _renameProject(p);
                break;
              case 'move':
                _showMoveDialog(p);
                break;
              case 'delete':
                _deleteProject(p);
                break;
            }
          },
        ),
        onTap: _selectMode ? () => _toggleSelect(p.id!) : null,
      ),
    );
  }

  Future<void> _showMoveDialog(Project p) async {
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => _PickProjectGroupBatchDialog(groups: _groups),
    );
    if (result != null) {
      await _db.moveProjectToGroup(p.id!, result == -1 ? null : result);
      _loadData();
    }
  }
}

/// 项目分组区块（可收起展开，支持拖拽排序+拖入）
class _ProjectGroupSection extends StatelessWidget {
  final ProjectGroup group;
  final List<Project> projects;
  final List<ProjectGroup> allGroups;
  final bool isExpanded;
  final bool selectMode;
  final Set<int> selectedIds;
  final ThemeData theme;
  final VoidCallback onToggleExpand;
  final Function(int) onToggleSelect;
  final VoidCallback onAddProject;
  final VoidCallback onRenameGroup;
  final VoidCallback onDeleteGroup;
  final Function(Project) onRenameProject;
  final Function(Project) onDeleteProject;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Function(Project) onMoveProjectToGroup;

  const _ProjectGroupSection({
    required this.group,
    required this.projects,
    required this.allGroups,
    required this.isExpanded,
    required this.selectMode,
    required this.selectedIds,
    required this.theme,
    required this.onToggleExpand,
    required this.onToggleSelect,
    required this.onAddProject,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onRenameProject,
    required this.onDeleteProject,
    required this.onReorder,
    required this.onMoveProjectToGroup,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Project>(
      onAcceptWithDetails: (details) => onMoveProjectToGroup(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isHovering
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: isHovering
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          child: Card(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onToggleExpand,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 20,
                          color: isHovering ? theme.colorScheme.primary : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.folder,
                            size: 18, color: isHovering ? theme.colorScheme.primary : theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(group.name,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isHovering ? theme.colorScheme.primary : null)),
                        const Spacer(),
                        if (isHovering)
                          Text('释放移到此处',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.primary))
                        else if (!selectMode) ...[
                          Text('${projects.length}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant)),
                          IconButton(
                            icon: const Icon(Icons.add, size: 18),
                            tooltip: '在此分组新建项目',
                            onPressed: onAddProject,
                          ),
                          PopupMenuButton<String>(
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                  value: 'rename', child: Text('重命名分组')),
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除分组',
                                      style: TextStyle(color: Colors.red))),
                            ],
                            onSelected: (v) {
                              switch (v) {
                                case 'rename':
                                  onRenameGroup();
                                  break;
                                case 'delete':
                                  onDeleteGroup();
                                  break;
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (isExpanded)
                  if (projects.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Text('（空）',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: projects.length,
                      onReorder: onReorder,
                      proxyDecorator: (child, index, animation) => Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(8),
                        child: child,
                      ),
                      itemBuilder: (context, index) {
                        final p = projects[index];
                        return LongPressDraggable<Project>(
                          key: ValueKey(p.id),
                          data: p,
                          delay: const Duration(milliseconds: 350),
                          feedback: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 200,
                              child: ListTile(
                                dense: true,
                                leading: Icon(Icons.drive_file_rename_outline,
                                    size: 18, color: theme.colorScheme.primary),
                                title: Text(p.name, style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.4,
                            child: ListTile(
                              dense: true,
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.drag_handle, size: 18),
                                  if (selectMode)
                                    Checkbox(
                                      value: selectedIds.contains(p.id),
                                      onChanged: (_) => onToggleSelect(p.id!),
                                    )
                                  else
                                    const SizedBox(width: 4),
                                ],
                              ),
                              title: Text(p.name, style: const TextStyle(fontSize: 14)),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(Icons.drag_handle, size: 18),
                                ),
                                if (selectMode)
                                  Checkbox(
                                    value: selectedIds.contains(p.id),
                                    onChanged: (_) => onToggleSelect(p.id!),
                                  )
                                else
                                  const SizedBox(width: 4),
                              ],
                            ),
                            title: Text(p.name, style: const TextStyle(fontSize: 14)),
                            trailing: selectMode
                                ? null
                                : PopupMenuButton<String>(
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                          value: 'edit', child: Text('重命名')),
                                      if (allGroups.isNotEmpty)
                                        const PopupMenuItem(
                                            value: 'move', child: Text('移动到分组')),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('删除',
                                            style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                    onSelected: (v) {
                                      switch (v) {
                                        case 'edit':
                                          onRenameProject(p);
                                          break;
                                        case 'move':
                                          final ctx = context;
                                          showDialog<int?>(
                                            context: ctx,
                                            builder: (ctx) =>
                                                _PickProjectGroupBatchDialog(
                                                    groups: allGroups),
                                          ).then((result) {});
                                          break;
                                        case 'delete':
                                          onDeleteProject(p);
                                          break;
                                      }
                                    },
                                  ),
                            onTap: selectMode ? () => onToggleSelect(p.id!) : null,
                          ),
                        );
                      },
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 批量选择分组弹窗
class _PickProjectGroupBatchDialog extends StatelessWidget {
  final List<ProjectGroup> groups;

  const _PickProjectGroupBatchDialog({required this.groups});

  @override
  Widget build(BuildContext context) {
    int? selected;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('移动到分组'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int>(
              title: const Text('（不分组）'),
              value: -1,
              groupValue: selected,
              onChanged: (v) => setState(() => selected = v),
              dense: true,
            ),
            ...groups.map((g) => RadioListTile<int>(
                  title: Text(g.name),
                  value: g.id!,
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v),
                  dense: true,
                )),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          TextButton(
            onPressed: selected != null
                ? () => Navigator.pop(context, selected)
                : null,
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
