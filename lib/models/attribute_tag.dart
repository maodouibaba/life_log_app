/// 属性标签模型
/// 无层级结构，平坦的属性标签，可归入分组管理
class AttributeTag {
  final int? id;
  final String name;
  final int? groupId; // 所属属性标签分组，null = 未分组
  final int spaceId;
  final int sortOrder; // 同级排序
  final DateTime createdAt;

  AttributeTag({
    this.id,
    required this.name,
    this.groupId,
    required this.spaceId,
    this.sortOrder = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory AttributeTag.fromMap(Map<String, dynamic> map) {
    return AttributeTag(
      id: map['id'] as int?,
      name: map['name'] as String,
      groupId: map['group_id'] as int?,
      spaceId: map['space_id'] as int,
      sortOrder: map['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'group_id': groupId,
      'space_id': spaceId,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
    };
  }

  AttributeTag copyWith({
    int? id,
    String? name,
    int? groupId,
    bool clearGroupId = false,
    int? sortOrder,
    int? spaceId,
    DateTime? createdAt,
  }) {
    return AttributeTag(
      id: id ?? this.id,
      name: name ?? this.name,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      sortOrder: sortOrder ?? this.sortOrder,
      spaceId: spaceId ?? this.spaceId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'AttributeTag(id: $id, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttributeTag &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
