/// 入口/空间模型
/// 每个 space 是一个独立的记录空间，数据完全隔离
class Space {
  final int? id;
  final String name;
  final DateTime createdAt;

  Space({
    this.id,
    required this.name,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Space.fromMap(Map<String, dynamic> map) {
    return Space(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Space copyWith({int? id, String? name, DateTime? createdAt}) {
    return Space(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'Space(id: $id, name: $name)';
}
