/// 记录模板模型
/// 可复用的记录模板，新建记录时导入模板后修改
class EntryTemplate {
  final int? id;
  final String name; // 模板名称（必填）
  final String? title; // 默认事项简介
  final String content; // 默认详细情况
  final List<int> tagIds; // 默认树状标签 ID 列表
  final List<int> attributeTagIds; // 默认属性标签 ID 列表
  final int? projectId; // 默认项目
  final String? projectName; // 项目名称（展示用）
  final String? contactPerson; // 默认对接人
  final String? followUp; // 默认后续待办
  final DateTime createdAt;
  final DateTime updatedAt;

  EntryTemplate({
    this.id,
    required this.name,
    this.title,
    this.content = '',
    List<int>? tagIds,
    List<int>? attributeTagIds,
    this.projectId,
    this.projectName,
    this.contactPerson,
    this.followUp,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : tagIds = tagIds ?? [],
        attributeTagIds = attributeTagIds ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory EntryTemplate.fromMap(Map<String, dynamic> map) {
    return EntryTemplate(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      title: map['title'] as String?,
      content: map['content'] as String? ?? '',
      projectId: map['project_id'] as int?,
      projectName: map['project_name'] as String?,
      contactPerson: map['contact_person'] as String?,
      followUp: map['follow_up'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      // tagIds 和 attributeTagIds 不在此处解析，由数据库层单独加载
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      if (title != null) 'title': title,
      'content': content,
      if (projectId != null) 'project_id': projectId,
      if (contactPerson != null) 'contact_person': contactPerson,
      if (followUp != null) 'follow_up': followUp,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  EntryTemplate copyWith({
    int? id,
    String? name,
    String? title,
    bool clearTitle = false,
    String? content,
    List<int>? tagIds,
    List<int>? attributeTagIds,
    int? projectId,
    bool clearProjectId = false,
    String? projectName,
    String? contactPerson,
    bool clearContactPerson = false,
    String? followUp,
    bool clearFollowUp = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EntryTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      title: clearTitle ? null : (title ?? this.title),
      content: content ?? this.content,
      tagIds: tagIds ?? this.tagIds,
      attributeTagIds: attributeTagIds ?? this.attributeTagIds,
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      projectName: projectName ?? this.projectName,
      contactPerson:
          clearContactPerson ? null : (contactPerson ?? this.contactPerson),
      followUp: clearFollowUp ? null : (followUp ?? this.followUp),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'EntryTemplate(id: $id, name: $name)';
}
