/// 记录-属性标签关联模型
class EntryAttributeTag {
  final int entryId;
  final int attributeTagId;

  EntryAttributeTag({
    required this.entryId,
    required this.attributeTagId,
  });

  factory EntryAttributeTag.fromMap(Map<String, dynamic> map) {
    return EntryAttributeTag(
      entryId: map['entry_id'] as int,
      attributeTagId: map['attribute_tag_id'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'entry_id': entryId,
      'attribute_tag_id': attributeTagId,
    };
  }
}
