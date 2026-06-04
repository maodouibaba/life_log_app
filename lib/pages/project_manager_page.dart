import 'package:flutter/material.dart';
import '../models/project.dart';
import '../database/app_database.dart';

/// 项目管理页面（无层级，简单列表）
class ProjectManagerPage extends StatefulWidget {
  const ProjectManagerPage({super.key});

  @override
  State<ProjectManagerPage> createState() => _ProjectManagerPageState();
}

class _ProjectManagerPageState extends State<ProjectManagerPage> {
  final AppDatabase _db = AppDatabase();
  List<Project> _projects = [];

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    _projects = await _db.getAllProjects();
    setState(() {});
  }

  Future<void> _addProject() async {
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
      await _db.createProject(result);
      _loadProjects();
    }
  }

  Future<void> _renameProject(Project p) async {
    final controller = TextEditingController(text: p.name);
    final result = await showDialog<String>(
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != p.name) {
      await _db.updateProjectName(p.id!, result);
      _loadProjects();
    }
  }

  Future<void> _deleteProject(Project p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除项目'),
        content: Text('确定要删除「${p.name}」吗？\n（相关记录的"项目"字段会被清空，记录本身不受影响）'),
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
      await _db.deleteProject(p.id!);
      _loadProjects();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('项目管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建项目',
            onPressed: _addProject,
          ),
        ],
      ),
      body: _projects.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_outlined, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('还没有项目', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('点击右上角 + 创建项目', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _projects.length,
              itemBuilder: (context, index) {
                final p = _projects[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    leading: Icon(Icons.folder_outlined, color: theme.colorScheme.primary),
                    title: Text(p.name, style: const TextStyle(fontSize: 15)),
                    trailing: PopupMenuButton<String>(
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('重命名')),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _renameProject(p);
                            break;
                          case 'delete':
                            _deleteProject(p);
                            break;
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
