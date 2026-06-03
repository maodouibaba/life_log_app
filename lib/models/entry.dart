import 'tag.dart';

/// 记录模型
/// 一条生活记录，包含文字内容，可关联多个标签
class Entry {
  final int? id;
  final String content;     // 文字内容
  final DateTime createdAt; // 创建时间
  final DateTime updatedAt; // 更新时间
  final List<Tag> tags;     // 关联的标签（仅用于展示，不入库）

  Entry({
    this.id,
    required this.content,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.tags = const [],
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? updatedAt ?? DateTime.now();

  /// 从数据库 Map 创建（不含 tags）
  factory Entry.fromMap(Map<String, dynamic> map) {
    return Entry(
      id: map['id'] as int?,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// 转为数据库 Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Entry copyWith({
    int? id,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Tag>? tags,
  }) {
    return Entry(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
    );
  }

  @override
  String toString() => 'Entry(id: $id, content: $content, createdAt: $createdAt)';
}
