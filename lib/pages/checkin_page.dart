import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/checkin_item.dart';
import '../models/checkin_record.dart';
import '../models/entry.dart';
import 'checkin_item_manager_page.dart';

/// 打卡主页面
class CheckinPage extends StatefulWidget {
  final int spaceId;

  const CheckinPage({super.key, required this.spaceId});

  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  final AppDatabase _db = AppDatabase();
  List<CheckinItem> _items = [];
  Set<int> _todayItemIds = {};
  Map<int, int> _streaks = {};
  Map<int, Set<String>> _monthlyStats = {};
  bool _loading = true;
  int _currentMonth = DateTime.now().month;
  int _currentYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      _items = await _db.getCheckinItems(widget.spaceId);
      _todayItemIds = await _db.getTodayCheckinItemIds(widget.spaceId);
      _monthlyStats =
          await _db.getMonthlyCheckinStats(widget.spaceId, _currentYear, _currentMonth);

      // 计算每个事项的连续天数
      final streaks = <int, int>{};
      for (final item in _items) {
        if (item.id != null) {
          streaks[item.id!] = await _db.getStreakDays(item.id!);
        }
      }
      _streaks = streaks;
    } catch (e) {
      debugPrint('加载打卡数据失败：$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _doCheckin(CheckinItem item) async {
    if (item.id == null) return;
    if (_todayItemIds.contains(item.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${item.name}" 今日已打卡')),
      );
      return;
    }

    try {
      final now = DateTime.now();
      // 自动生成一条记录
      final entry = await _db.createEntry(
        '✅ 打卡：${item.name}',
        title: item.name,
        tagIds: item.tagId != null ? [item.tagId!] : null,
        attributeTagIds: item.attributeTagId != null ? [item.attributeTagId!] : null,
        projectId: item.projectId,
        spaceId: widget.spaceId,
        createdAt: now,
      );

      // 记录打卡
      await _db.recordCheckin(CheckinRecord(
        itemId: item.id!,
        entryId: entry.id!,
        checkinDate: now,
        checkinTime: now,
      ));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ "${item.name}" 打卡成功')),
      );

      _loadData();
    } catch (e) {
      debugPrint('打卡失败：$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打卡失败：$e')),
        );
      }
    }
  }

  // ==================== 统计计算 ====================

  int get _todayCount => _items.where((i) => i.id != null && _todayItemIds.contains(i.id)).length;

  int get _totalCount => _items.length;

  int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  int _monthCheckinCount(int itemId) {
    final dates = _monthlyStats[itemId];
    return dates?.length ?? 0;
  }

  int _maxStreak() {
    int max = 0;
    for (final s in _streaks.values) {
      if (s > max) max = s;
    }
    return max;
  }

  /// 本周每日打卡数
  List<int> _weekData() {
    final result = <int>[0, 0, 0, 0, 0, 0, 0];
    final now = DateTime.now();
    // 周一为第0天
    final weekDay = now.weekday - 1;
    for (final item in _items) {
      if (item.id == null) continue;
      final dates = _monthlyStats[item.id!];
      if (dates == null) continue;
      for (final d in dates) {
        final parts = d.split('-');
        final date = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        final diff = now.difference(date).inDays;
        if (diff >= 0 && diff < 7) {
          result[6 - diff] = result[6 - diff] + 1;
        }
      }
    }
    return result;
  }

  /// 月度热力图数据 (天 → 打卡数)
  Map<int, int> _heatmapData() {
    final result = <int, int>{};
    final days = _daysInMonth(_currentYear, _currentMonth);
    for (var d = 1; d <= days; d++) {
      final dateStr =
          '$_currentYear-${_currentMonth.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      int count = 0;
      for (final item in _items) {
        if (item.id == null) continue;
        final dates = _monthlyStats[item.id!];
        if (dates != null && dates.contains(dateStr)) {
          count++;
        }
      }
      result[d] = count;
    }
    return result;
  }

  // ==================== 导航 ====================

  Future<void> _openManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckinItemManagerPage(spaceId: widget.spaceId),
      ),
    );
    _loadData();
  }

  void _prevMonth() {
    setState(() {
      if (_currentMonth == 1) {
        _currentMonth = 12;
        _currentYear--;
      } else {
        _currentMonth--;
      }
    });
    _loadData();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_currentYear == now.year && _currentMonth == now.month) return;
    setState(() {
      if (_currentMonth == 12) {
        _currentMonth = 1;
        _currentYear++;
      } else {
        _currentMonth++;
      }
    });
    _loadData();
  }

  // ==================== 构建 UI ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('打卡'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '管理事项',
            onPressed: _openManager,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatsBar(theme),
                        const SizedBox(height: 20),
                        _buildCheckinGrid(theme),
                        const SizedBox(height: 24),
                        _buildWeekChart(theme),
                        const SizedBox(height: 24),
                        _buildHeatmap(theme),
                        const SizedBox(height: 24),
                        _buildCompletionList(theme),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ---- 顶部统计 ----
  Widget _buildStatsBar(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _statItem(theme, Icons.today, '今日', '$_todayCount/$_totalCount'),
            Container(width: 1, height: 40, color: theme.colorScheme.outlineVariant),
            _statItem(theme, Icons.trending_up, '本周趋势', '${_weekData().reduce((a, b) => a + b)}次'),
            Container(width: 1, height: 40, color: theme.colorScheme.outlineVariant),
            _statItem(theme, Icons.local_fire_department, '最长连续', '${_maxStreak()}天'),
          ],
        ),
      ),
    );
  }

  Widget _statItem(ThemeData theme, IconData icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ---- 打卡按钮网格 ----
  Widget _buildCheckinGrid(ThemeData theme) {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Icon(Icons.check_circle_outline,
                size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('还没有打卡事项',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _openManager,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加事项'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('今日打卡',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
            ],
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.1,
              ),
              itemCount: _items.length,
              itemBuilder: (ctx, i) => _buildCheckinButton(theme, _items[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckinButton(ThemeData theme, CheckinItem item) {
    final checked = item.id != null && _todayItemIds.contains(item.id);
    final streak = item.id != null ? (_streaks[item.id!] ?? 0) : 0;

    return InkWell(
      onTap: () => _doCheckin(item),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: checked
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: checked
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              checked ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 28,
              color: checked ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                item.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: checked ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (streak > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '🔥$streak',
                  style: TextStyle(
                    fontSize: 11,
                    color: checked
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 本周趋势柱状图 ----
  Widget _buildWeekChart(ThemeData theme) {
    final weekData = _weekData();
    final maxVal = weekData.reduce((a, b) => a > b ? a : b);
    final weekNames = ['一', '二', '三', '四', '五', '六', '日'];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('本周趋势',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (i) {
                final val = weekData[i];
                final height = maxVal > 0 ? (val / maxVal) * 60.0 : 0.0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$val',
                        style: TextStyle(
                            fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Container(
                      width: 20,
                      height: height.clamp(4.0, 60.0),
                      decoration: BoxDecoration(
                        color: val > 0
                            ? theme.colorScheme.primary.withValues(alpha: 0.4 + (val / (maxVal > 0 ? maxVal : 1)) * 0.6)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(weekNames[i],
                        style: TextStyle(
                            fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 月度热力图 ----
  Widget _buildHeatmap(ThemeData theme) {
    final now = DateTime.now();
    final days = _daysInMonth(_currentYear, _currentMonth);
    final heatmap = _heatmapData();
    final isCurrentMonth = _currentYear == now.year && _currentMonth == now.month;
    final maxVal = heatmap.values.reduce((a, b) => a > b ? a : b);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: _prevMonth,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                Text('${_currentYear}年${_currentMonth}月',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: isCurrentMonth ? null : _nextMonth,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const Spacer(),
                Icon(Icons.grid_on, size: 14, color: theme.colorScheme.primary),
              ],
            ),
            const SizedBox(height: 12),
            // 热力图网格
            Wrap(
              spacing: 3,
              runSpacing: 3,
              children: List.generate(days, (d) {
                final day = d + 1;
                final count = heatmap[day] ?? 0;
                final isToday = isCurrentMonth && day == now.day;
                final opacity = maxVal > 0 ? (count / maxVal).clamp(0.1, 1.0) : 0.1;
                return Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: count > 0
                        ? theme.colorScheme.primary.withValues(alpha: opacity)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    border: isToday
                        ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 9,
                        color: count > 0
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 事项完成率排名 ----
  Widget _buildCompletionList(ThemeData theme) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final daysInMonth = _daysInMonth(_currentYear, _currentMonth);
    final sorted = List<CheckinItem>.from(_items)
      ..sort((a, b) {
        final ac = a.id != null ? _monthCheckinCount(a.id!) : 0;
        final bc = b.id != null ? _monthCheckinCount(b.id!) : 0;
        return bc.compareTo(ac);
      });

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('本月完成率',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            ...sorted.map((item) {
              final count = item.id != null ? _monthCheckinCount(item.id!) : 0;
              final rate = daysInMonth > 0 ? count / daysInMonth : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(item.name,
                            style: const TextStyle(fontSize: 13)),
                        const Spacer(),
                        Text('$count/$daysInMonth',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: rate,
                        minHeight: 6,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
