/// 项目分组模型
/// 用于对项目进行分层管理（项目本身无层级，但可通过分组归类）
class ProjectGroup {
  final int? id;
  final String name;
  final int spaceId;
  final DateTime createdAt;

  ProjectGroup({
    this.id,
    required this.name,
    required this.spaceId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ProjectGroup.fromMap(Map<String, dynamic> map) {
    return ProjectGroup(
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

  ProjectGroup copyWith({int? id, String? name, int? spaceId, DateTime? createdAt}) {
    return ProjectGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      spaceId: spaceId ?? this.spaceId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'ProjectGroup(id: $id, name: $name)';
}
