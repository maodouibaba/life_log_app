/// 记录-标签关联模型
/// 用于多对多关系的中间表
class EntryTag {
  final int entryId;
  final int tagId;

  EntryTag({
    required this.entryId,
    required this.tagId,
  });

  factory EntryTag.fromMap(Map<String, dynamic> map) {
    return EntryTag(
      entryId: map['entry_id'] as int,
      tagId: map['tag_id'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'entry_id': entryId,
      'tag_id': tagId,
    };
  }
}
