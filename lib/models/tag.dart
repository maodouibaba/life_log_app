/// 标签模型
/// 支持树状层级结构，parentId 为 null 表示根节点
class Tag {
  final int? id;
  final String name;
  final int? parentId; // null = 根节点
  final DateTime createdAt;

  Tag({
    this.id,
    required this.name,
    this.parentId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 从数据库 Map 创建
  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as int?,
      name: map['name'] as String,
      parentId: map['parent_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// 转为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'parent_id': parentId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// 复制并可选修改字段
  Tag copyWith({
    int? id,
    String? name,
    int? parentId,
    bool clearParentId = false,
    DateTime? createdAt,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      createdAt: createdAt ?? this.createdAt,
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
