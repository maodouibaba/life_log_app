/// 打卡记录模型
class CheckinRecord {
  final int? id;
  final int itemId; // 关联打卡事项
  final int entryId; // 关联自动生成的记录
  final DateTime checkinDate; // 打卡日期（仅日期部分）
  final DateTime checkinTime; // 打卡时间（完整时间戳）
  final DateTime createdAt;

  CheckinRecord({
    this.id,
    required this.itemId,
    required this.entryId,
    required this.checkinDate,
    DateTime? checkinTime,
    DateTime? createdAt,
  })  : checkinTime = checkinTime ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  factory CheckinRecord.fromMap(Map<String, dynamic> map) {
    return CheckinRecord(
      id: map['id'] as int?,
      itemId: map['item_id'] as int? ?? 0,
      entryId: map['entry_id'] as int? ?? 0,
      checkinDate: DateTime.parse(map['checkin_date'] as String),
      checkinTime: DateTime.parse(map['checkin_time'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'item_id': itemId,
      'entry_id': entryId,
      'checkin_date':
          '${checkinDate.year}-${checkinDate.month.toString().padLeft(2, '0')}-${checkinDate.day.toString().padLeft(2, '0')}',
      'checkin_time': checkinTime.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  String toString() => 'CheckinRecord(itemId: $itemId, date: $checkinDate)';
}
