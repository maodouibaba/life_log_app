import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/entry.dart';
import 'entry_editor_page.dart';
import 'tag_manager_page.dart';
import 'list_view_page.dart';
import '../services/export_service.dart';



class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AppDatabase _db = AppDatabase();
  List<Entry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _loading = true);
    try {
      final entries = await _db.getAllEntries().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('加载记录超时');
          return [];
        },
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      debugPrint('加载记录失败：$e');
      if (!mounted) return;
      setState(() {
        _entries = [];
        _loading = false;
      });
    }
  }

  // 按天分组
  Map<String, List<Entry>> _groupByDate(List<Entry> entries) {
    final map = <String, List<Entry>>{};
    for (final entry in entries) {
      final dateKey = '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}-${entry.createdAt.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(dateKey, () => []);
      map[dateKey]!.add(entry);
    }
    return map;
  }

  String _formatDateKey(String key) {
    final parts = key.split('-');
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final weekday = weekdays[date.weekday - 1];
    return '${parts[0]}年${parts[1].replaceFirst(RegExp(r'^0'), '')}月${parts[2].replaceFirst(RegExp(r'^0'), '')}日 周$weekday';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _exportToExcel() async {
    try {
      final exportService = ExportService();
      final filePath = await exportService.exportToExcel();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出成功：$filePath'),
          action: SnackBarAction(
            label: '分享',
            onPressed: () {
                // Share.shareXFiles([XFile(filePath)], text: '生活记录导出');
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(_entries);

    return Scaffold(
      appBar: AppBar(
        title: const Text('生活记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: '列表视图',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ListViewPage()),
              );
              _loadEntries();
            },
          ),
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: '标签管理',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TagManagerPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导出 Excel',
            onPressed: _exportToExcel,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_note, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('还没有记录', style: TextStyle(fontSize: 18, color: Colors.grey)),
                      SizedBox(height: 8),
                      Text('点击右下角 + 开始记录', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadEntries,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: grouped.keys.length,
                    itemBuilder: (context, index) {
                      final dateKey = grouped.keys.elementAt(index);
                      final dayEntries = grouped[dateKey]!;
                      return _DayGroup(
                        dateLabel: _formatDateKey(dateKey),
                        entries: dayEntries,
                        formatTime: _formatTime,
                        onDelete: (entry) async {
                          await _db.deleteEntry(entry.id!);
                          _loadEntries();
                        },
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EntryEditorPage()),
          );
          if (result == true) {
            _loadEntries();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _DayGroup extends StatefulWidget {
  final String dateLabel;
  final List<Entry> entries;
  final String Function(DateTime) formatTime;
  final Function(Entry) onDelete;

  const _DayGroup({
    required this.dateLabel,
    required this.entries,
    required this.formatTime,
    required this.onDelete,
  });

  @override
  State<_DayGroup> createState() => _DayGroupState();
}

class _DayGroupState extends State<_DayGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.dateLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.entries.length} 条',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ...widget.entries.map((entry) => _EntryCard(
                  entry: entry,
                  formatTime: widget.formatTime,
                  onDelete: () => widget.onDelete(entry),
                )),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final Entry entry;
  final String Function(DateTime) formatTime;
  final VoidCallback onDelete;

  const _EntryCard({
    required this.entry,
    required this.formatTime,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatTime(entry.createdAt),
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.content,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
                if (entry.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: entry.tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tag.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('删除记录'),
                  content: const Text('确定要删除这条记录吗？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onDelete();
                      },
                      child: Text('删除', style: TextStyle(color: theme.colorScheme.error)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}






