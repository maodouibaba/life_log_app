/// 树状标签模型
/// 支持树状层级结构，parentId 为 null 表示根节点
/// spaceId 用于多入口数据隔离
/// sortOrder 用于同级标签排序
class Tag {
  final int? id;
  final String name;
  final int? parentId; // null = 根节点
  final DateTime createdAt;
  final int spaceId;
  final int sortOrder;

  Tag({
    this.id,
    required this.name,
    this.parentId,
    DateTime? createdAt,
    this.spaceId = 1,
    this.sortOrder = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as int?,
      name: map['name'] as String,
      parentId: map['parent_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      spaceId: (map['space_id'] as int?) ?? 1,
      sortOrder: (map['sort_order'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'parent_id': parentId,
      'created_at': createdAt.toIso8601String(),
      'space_id': spaceId,
      'sort_order': sortOrder,
    };
  }

  Tag copyWith({
    int? id,
    String? name,
    int? parentId,
    bool clearParentId = false,
    DateTime? createdAt,
    int? spaceId,
    int? sortOrder,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      createdAt: createdAt ?? this.createdAt,
      spaceId: spaceId ?? this.spaceId,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  String toString() => 'Tag(id: $id, name: $name, parentId: $parentId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tag &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
