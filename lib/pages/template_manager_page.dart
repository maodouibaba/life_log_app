import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/entry_template.dart';
import 'template_editor_page.dart';

/// 模板管理页面
class TemplateManagerPage extends StatefulWidget {
  final int spaceId;

  const TemplateManagerPage({super.key, required this.spaceId});

  @override
  State<TemplateManagerPage> createState() => _TemplateManagerPageState();
}

class _TemplateManagerPageState extends State<TemplateManagerPage> {
  final AppDatabase _db = AppDatabase();
  List<EntryTemplate> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _loading = true);
    try {
      _templates = await _db.getAllTemplates();
    } catch (e) {
      debugPrint('加载模板失败：$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deleteTemplate(EntryTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('确定删除模板"${template.name}"吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true && template.id != null) {
      await _db.deleteTemplate(template.id!);
      _loadTemplates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('模板管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建模板',
            onPressed: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => TemplateEditorPage(
                    spaceId: widget.spaceId,
                  ),
                ),
              );
              if (result == true) _loadTemplates();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
              ? _buildEmptyState(theme)
              : _buildTemplateList(theme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border,
              size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('还没有模板',
              style: TextStyle(
                fontSize: 16,
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 8),
          Text('点击右上角 + 创建模板',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              )),
        ],
      ),
    );
  }

  Widget _buildTemplateList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _templates.length,
      itemBuilder: (ctx, i) {
        final template = _templates[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Icon(Icons.bookmark,
                color: theme.colorScheme.primary, size: 24),
            title: Text(template.name,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (template.content.isNotEmpty)
                  Text(
                    template.content.length > 80
                        ? '${template.content.substring(0, 80)}...'
                        : template.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${template.tagIds.isNotEmpty ? "🏷${template.tagIds.length} " : ""}'
                  '${_formatDate(template.updatedAt)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18, color: theme.colorScheme.error),
              onPressed: () => _deleteTemplate(template),
            ),
            onTap: () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => TemplateEditorPage(
                    template: template,
                    spaceId: widget.spaceId,
                  ),
                ),
              );
              if (result == true) _loadTemplates();
            },
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
