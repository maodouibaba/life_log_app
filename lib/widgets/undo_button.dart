import 'package:flutter/material.dart';
import '../services/undo_manager.dart';

/// 撤销按钮组件（小型图标按钮）
/// 无可撤销操作时禁用，有可撤销操作时点击执行撤销
class UndoButton extends StatelessWidget {
  final VoidCallback? onRefresh;

  const UndoButton({super.key, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UndoManager(),
      builder: (context, _) {
        final um = UndoManager();
        final canUndo = um.canUndoDelete || um.canUndoEdit;

        return IconButton(
          icon: Icon(
            Icons.undo,
            size: 16,
            color: canUndo
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          tooltip: canUndo ? '撤销' : '没有可撤销的操作',
          onPressed: () async {
            if (!canUndo) return;
            final ok = um.canUndoDelete
                ? await um.undoDelete()
                : await um.undoEdit();
            if (ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('已撤销'), duration: Duration(seconds: 2)),
              );
              onRefresh?.call();
            } else if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: const Text('撤销失败'),
                    backgroundColor: Theme.of(context).colorScheme.error),
              );
            }
          },
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 24),
        );
      },
    );
  }
}
