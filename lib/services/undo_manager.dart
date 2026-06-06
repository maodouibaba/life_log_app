import '../models/entry.dart';
import '../database/app_database.dart';
import 'package:flutter/material.dart';

/// 撤销操作管理器（单例）
/// 支持：删除记录撤回、编辑记录撤回
class UndoManager {
  static final UndoManager _instance = UndoManager._internal();
  factory UndoManager() => _instance;
  UndoManager._internal();

  final AppDatabase _db = AppDatabase();

  // 存储最近一次被删除的完整数据
  Entry? _lastDeletedEntry;
  List<int> _lastDeletedTagIds = [];
  List<int> _lastDeletedAttributeTagIds = [];

  // 存储最近一次编辑前的数据
  int? _lastEditedEntryId;
  String? _lastEditedContent;
  String? _lastEditedTitle;
  List<int>? _lastEditedTagIds;
  List<int>? _lastEditedAttributeTagIds;
  int? _lastEditedProjectId;

  bool get canUndoDelete => _lastDeletedEntry != null;
  bool get canUndoEdit => _lastEditedEntryId != null;

  /// 记录被删除的记录
  void recordDeletion(Entry entry) {
    _lastDeletedEntry = entry;
    _lastDeletedTagIds = entry.tags.map((t) => t.id!).toList();
    _lastDeletedAttributeTagIds = entry.attributeTags.map((at) => at.id!).toList();
  }

  /// 撤销删除：将被删除的记录重新写入数据库
  Future<bool> undoDelete() async {
    if (_lastDeletedEntry == null) return false;

    try {
      await _db.createEntry(
        _lastDeletedEntry!.content,
        title: _lastDeletedEntry!.title,
        tagIds: _lastDeletedTagIds.isNotEmpty ? _lastDeletedTagIds : null,
        attributeTagIds: _lastDeletedAttributeTagIds.isNotEmpty
            ? _lastDeletedAttributeTagIds
            : null,
        projectId: _lastDeletedEntry!.projectId,
        spaceId: _lastDeletedEntry!.spaceId,
      );
      _lastDeletedEntry = null;
      _lastDeletedTagIds = [];
      _lastDeletedAttributeTagIds = [];
      return true;
    } catch (e) {
      debugPrint('撤销删除失败：$e');
      return false;
    }
  }

  /// 记录编辑前的状态
  void recordEdit(Entry oldEntry) {
    _lastEditedEntryId = oldEntry.id;
    _lastEditedContent = oldEntry.content;
    _lastEditedTitle = oldEntry.title;
    _lastEditedTagIds = oldEntry.tags.map((t) => t.id!).toList();
    _lastEditedAttributeTagIds = oldEntry.attributeTags.map((at) => at.id!).toList();
    _lastEditedProjectId = oldEntry.projectId;
  }

  /// 撤销编辑：恢复到编辑前的状态
  Future<bool> undoEdit() async {
    if (_lastEditedEntryId == null) return false;

    try {
      await _db.updateEntryWithTags(
        _lastEditedEntryId!,
        _lastEditedContent ?? '',
        title: _lastEditedTitle,
        tagIds: _lastEditedTagIds,
        attributeTagIds: _lastEditedAttributeTagIds,
        projectId: _lastEditedProjectId,
      );
      _lastEditedEntryId = null;
      _lastEditedContent = null;
      _lastEditedTitle = null;
      _lastEditedTagIds = null;
      _lastEditedAttributeTagIds = null;
      _lastEditedProjectId = null;
      return true;
    } catch (e) {
      debugPrint('撤销编辑失败：$e');
      return false;
    }
  }

  /// 清空所有记录
  void clear() {
    _lastDeletedEntry = null;
    _lastDeletedTagIds = [];
    _lastDeletedAttributeTagIds = [];
    _lastEditedEntryId = null;
    _lastEditedContent = null;
    _lastEditedTitle = null;
    _lastEditedTagIds = null;
    _lastEditedAttributeTagIds = null;
    _lastEditedProjectId = null;
  }
}
