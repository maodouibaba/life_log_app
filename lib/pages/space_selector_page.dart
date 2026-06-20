import 'package:flutter/material.dart';
import '../models/space.dart';
import '../database/app_database.dart';

/// 入口选择页面
/// 启动时展示，用户选择或新建入口后进入主页
class SpaceSelectorPage extends StatefulWidget {
  final void Function(int spaceId) onSpaceSelected;

  const SpaceSelectorPage({super.key, required this.onSpaceSelected});

  @override
  State<SpaceSelectorPage> createState() => _SpaceSelectorPageState();
}

class _SpaceSelectorPageState extends State<SpaceSelectorPage> {
  final AppDatabase _db = AppDatabase();
  List<Space> _spaces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSpaces();
  }

  Future<void> _loadSpaces() async {
    final spaces = await _db.getAllSpaces();
    if (!mounted) return;
    setState(() {
      _spaces = spaces;
      _loading = false;
    });
  }

  Future<void> _createSpace() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分区'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如：工作、生活、学习...',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final newSpace = await _db.createSpace(result);
      if (mounted) {
        widget.onSpaceSelected(newSpace.id!);
      }
    }
  }

  Future<void> _renameSpace(Space space) async {
    final controller = TextEditingController(text: space.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名分区'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '分区名称',
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
    if (result != null && result.isNotEmpty && result != space.name) {
      await _db.updateSpaceName(space.id!, result);
      _loadSpaces();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择分区'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _spaces.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.door_front_door_outlined,
                            size: 80,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text('还没有分区',
                            style: TextStyle(fontSize: 18,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        Text('创建一个分区开始记录',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _createSpace,
                          icon: const Icon(Icons.add),
                          label: const Text('创建第一个分区'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _spaces.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _spaces.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: OutlinedButton.icon(
                          onPressed: _createSpace,
                          icon: const Icon(Icons.add),
                          label: const Text('新建分区'),
                        ),
                      );
                    }
                    final space = _spaces[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(Icons.door_front_door,
                              color: theme.colorScheme.onPrimaryContainer),
                        ),
                        title: Text(space.name,
                            style: const TextStyle(fontSize: 17)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                    value: 'rename',
                                    child: Text('重命名')),
                              ],
                              onSelected: (v) async {
                                if (v == 'rename') {
                                  await _renameSpace(space);
                                }
                              },
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => widget.onSpaceSelected(space.id!),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                      ),
                    );
                  },
                ),
    );
  }
}
