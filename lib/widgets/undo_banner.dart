import 'package:flutter/material.dart';
import '../services/undo_manager.dart';

/// 常驻顶部撤回栏
/// 监听 UndoManager 状态，有可撤回操作时显示在页面顶部
class UndoBanner extends StatelessWidget {
  final VoidCallback? onRefresh;

  const UndoBanner({super.key, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UndoManager(),
      builder: (context, _) {
        final um = UndoManager();
        final canUndo = um.canUndoDelete || um.canUndoEdit;

        if (!canUndo) return const SizedBox.shrink();

        final type = um.canUndoDelete ? 'delete' : 'edit';
        final label = type == 'delete' ? '已删除' : '已编辑';

        return MaterialBanner(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          content: Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
          leading: const Icon(Icons.undo, size: 20),
          actions: [
            TextButton(
              onPressed: () async {
                final ok = type == 'delete'
                    ? await um.undoDelete()
                    : await um.undoEdit();
                if (context.mounted) {
                  if (ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已撤销'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    onRefresh?.call();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('撤销失败'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('撤销'),
            ),
            TextButton(
              onPressed: () => um.clear(),
              child: const Text('忽略'),
            ),
          ],
        );
      },
    );
  }
}
