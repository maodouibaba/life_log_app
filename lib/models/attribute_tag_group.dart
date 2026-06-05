/// 属性标签分组模型
/// 用于对属性标签进行分组管理（属性标签本身无层级）
class AttributeTagGroup {
  final int? id;
  final String name;
  final int spaceId;
  final DateTime createdAt;

  AttributeTagGroup({
    this.id,
    required this.name,
    required this.spaceId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory AttributeTagGroup.fromMap(Map<String, dynamic> map) {
    return AttributeTagGroup(
      id: map['id'] as int?,
      name: map['name'] as String,
      spaceId: map['space_id'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'space_id': spaceId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  AttributeTagGroup copyWith({int? id, String? name, int? spaceId, DateTime? createdAt}) {
    return AttributeTagGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      spaceId: spaceId ?? this.spaceId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'AttributeTagGroup(id: $id, name: $name)';
}
