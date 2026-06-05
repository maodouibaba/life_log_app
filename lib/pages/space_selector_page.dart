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
        title: const Text('新建入口'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择入口'),
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
                            size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text('还没有入口',
                            style: TextStyle(fontSize: 18, color: Colors.grey)),
                        const SizedBox(height: 8),
                        const Text('创建一个入口开始记录',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _createSpace,
                          icon: const Icon(Icons.add),
                          label: const Text('创建第一个入口'),
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
                          label: const Text('新建入口'),
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
                        trailing:
                            const Icon(Icons.chevron_right),
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
