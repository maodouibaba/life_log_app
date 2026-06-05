/// 项目模型
/// 不分层级的自定义维度，一条记录通常对应一个项目
/// 可通过 groupId 归入不同项目分组进行分层管理
class Project {
  final int? id;
  final String name;
  final DateTime createdAt;
  final int spaceId;
  final int? groupId; // 所属项目分组，null = 未分组

  Project({
    this.id,
    required this.name,
    DateTime? createdAt,
    this.spaceId = 1,
    this.groupId,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Project.fromMap(Map<String, dynamic> map) {
    return Project(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      spaceId: (map['space_id'] as int?) ?? 1,
      groupId: map['group_id'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'space_id': spaceId,
      'group_id': groupId,
    };
  }

  Project copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    int? spaceId,
    int? groupId,
    bool clearGroupId = false,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      spaceId: spaceId ?? this.spaceId,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
    );
  }

  @override
  String toString() => 'Project(id: $id, name: $name, groupId: $groupId)';
}
