import 'package:flutter/material.dart';
import '../models/entry.dart';
import '../database/app_database.dart';
import 'entry_editor_page.dart';

/// 记录详情页（只读）
class EntryDetailPage extends StatelessWidget {
  final Entry entry;

  const EntryDetailPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('记录详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () async {
              // 重新加载最新数据再进入编辑
              final db = AppDatabase();
              final allEntries = await db.getAllEntries();
              final fresh = allEntries.where((e) => e.id == entry.id).firstOrNull;
              if (!context.mounted) return;
              await Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => EntryEditorPage(entry: fresh ?? entry),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  _formatFullDateTime(entry.createdAt),
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // 项目
            if (entry.projectName != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.folder_outlined, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      entry.projectName!,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // 标签
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: entry.tags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tag.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // 全文内容
            SelectableText(
              entry.content,
              style: const TextStyle(fontSize: 16, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFullDateTime(DateTime dt) {
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${dt.year}年${dt.month}月${dt.day}日 周${weekdays[dt.weekday - 1]} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
