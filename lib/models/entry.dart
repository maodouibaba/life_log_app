import 'tag.dart';
import 'attribute_tag.dart';

/// 记录模型
/// 一条生活记录，包含事项简介 + 详细情况，可关联树状标签、属性标签和一个项目
/// 支持对接人（contact_person）和后续待办（follow_up）
class Entry {
  final int? id;
  final String? title;           // 事项简介
  final String content;           // 详细情况
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Tag> tags;          // 树状标签（仅展示，不入库）
  final List<AttributeTag> attributeTags; // 属性标签（仅展示，不入库）
  final int? projectId;
  final String? projectName;
  final int spaceId;             // 所属入口
  final String? contactPerson;   // 对接人
  final String? followUp;        // 后续待办

  Entry({
    this.id,
    this.title,
    required this.content,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Tag>? tags,
    List<AttributeTag>? attributeTags,
    this.projectId,
    this.projectName,
    this.spaceId = 1,
    this.contactPerson,
    this.followUp,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        tags = tags ?? [],
        attributeTags = attributeTags ?? [];

  factory Entry.fromMap(Map<String, dynamic> map) {
    return Entry(
      id: map['id'] as int?,
      title: map['title'] as String?,
      content: map['content'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      projectId: map['project_id'] as int?,
      projectName: map['project_name'] as String?,
      spaceId: (map['space_id'] as int?) ?? 1,
      contactPerson: map['contact_person'] as String?,
      followUp: map['follow_up'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (projectId != null) 'project_id': projectId,
      'space_id': spaceId,
      if (contactPerson != null) 'contact_person': contactPerson,
      if (followUp != null) 'follow_up': followUp,
    };
  }

  Entry copyWith({
    int? id,
    String? title,
    bool clearTitle = false,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Tag>? tags,
    List<AttributeTag>? attributeTags,
    int? projectId,
    bool clearProjectId = false,
    String? projectName,
    int? spaceId,
    String? contactPerson,
    bool clearContactPerson = false,
    String? followUp,
    bool clearFollowUp = false,
  }) {
    return Entry(
      id: id ?? this.id,
      title: clearTitle ? null : (title ?? this.title),
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      attributeTags: attributeTags ?? this.attributeTags,
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      projectName: projectName ?? this.projectName,
      spaceId: spaceId ?? this.spaceId,
      contactPerson: clearContactPerson ? null : (contactPerson ?? this.contactPerson),
      followUp: clearFollowUp ? null : (followUp ?? this.followUp),
    );
  }

  @override
  String toString() => 'Entry(id: $id, title: $title, createdAt: $createdAt)';
}
