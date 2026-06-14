/// 打卡事项模型
class CheckinItem {
  final int? id;
  final String name; // 事项名称
  final int spaceId; // 所属入口
  final int? tagId; // 关联树状标签
  final int? attributeTagId; // 关联属性标签
  final int? projectId; // 关联项目
  final int sortOrder;
  final DateTime createdAt;

  CheckinItem({
    this.id,
    required this.name,
    this.spaceId = 1,
    this.tagId,
    this.attributeTagId,
    this.projectId,
    this.sortOrder = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory CheckinItem.fromMap(Map<String, dynamic> map) {
    return CheckinItem(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      spaceId: (map['space_id'] as int?) ?? 1,
      tagId: map['tag_id'] as int?,
      attributeTagId: map['attribute_tag_id'] as int?,
      projectId: map['project_id'] as int?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'space_id': spaceId,
      if (tagId != null) 'tag_id': tagId,
      if (attributeTagId != null) 'attribute_tag_id': attributeTagId,
      if (projectId != null) 'project_id': projectId,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
    };
  }

  CheckinItem copyWith({
    int? id,
    String? name,
    int? spaceId,
    int? tagId,
    bool clearTagId = false,
    int? attributeTagId,
    bool clearAttributeTagId = false,
    int? projectId,
    bool clearProjectId = false,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return CheckinItem(
      id: id ?? this.id,
      name: name ?? this.name,
      spaceId: spaceId ?? this.spaceId,
      tagId: clearTagId ? null : (tagId ?? this.tagId),
      attributeTagId: clearAttributeTagId ? null : (attributeTagId ?? this.attributeTagId),
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'CheckinItem(id: $id, name: $name)';
}
