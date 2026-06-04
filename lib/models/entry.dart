import 'tag.dart';

/// 记录模型
/// 一条生活记录，包含文字内容，可关联多个标签和一个项目
class Entry {
  final int? id;
  final String content;     // 文字内容
  final DateTime createdAt; // 创建时间
  final DateTime updatedAt; // 更新时间
  final List<Tag> tags;     // 关联的标签（仅用于展示，不入库）
  final int? projectId;     // 关联项目 ID
  final String? projectName; // 项目名称（仅展示）

  Entry({
    this.id,
    required this.content,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Tag>? tags,
    this.projectId,
    this.projectName,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        tags = tags ?? [];

  /// 从数据库 Map 创建
  factory Entry.fromMap(Map<String, dynamic> map) {
    return Entry(
      id: map['id'] as int?,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      projectId: map['project_id'] as int?,
      projectName: map['project_name'] as String?,
    );
  }

  /// 转为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (projectId != null) 'project_id': projectId,
    };
  }

  Entry copyWith({
    int? id,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Tag>? tags,
    int? projectId,
    bool clearProjectId = false,
    String? projectName,
  }) {
    return Entry(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      projectName: projectName ?? this.projectName,
    );
  }

  @override
  String toString() => 'Entry(id: $id, content: $content, createdAt: $createdAt)';
}
