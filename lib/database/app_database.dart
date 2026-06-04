import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../models/tag.dart';
import '../models/entry.dart';
import '../models/entry_tag.dart';

/// 本地数据库管理类
/// 使用 sqflite，数据存储在手机本地
class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // 使用 path_provider 确保在 iOS 上获取正确的可写目录
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = appDir.path;
    debugPrint('数据库路径：$dbPath');
    final path = join(dbPath, 'life_log.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 标签表
    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (parent_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');

    // 记录表
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 记录-标签关联表
    await db.execute('''
      CREATE TABLE entry_tags (
        entry_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (entry_id, tag_id),
        FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');

    // 索引
    await db.execute('CREATE INDEX idx_tags_parent_id ON tags(parent_id)');
    await db.execute('CREATE INDEX idx_entries_created_at ON entries(created_at)');
    await db.execute('CREATE INDEX idx_entry_tags_entry_id ON entry_tags(entry_id)');
    await db.execute('CREATE INDEX idx_entry_tags_tag_id ON entry_tags(tag_id)');
  }

  // ==================== 标签操作 ====================

  /// 获取所有标签
  Future<List<Tag>> getAllTags() async {
    final db = await database;
    final maps = await db.query('tags', orderBy: 'id ASC');
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  /// 获取根标签（parent_id 为 null）
  Future<List<Tag>> getRootTags() async {
    final db = await database;
    final maps = await db.query('tags', where: 'parent_id IS NULL', orderBy: 'id ASC');
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  /// 获取某个标签的直接子标签
  Future<List<Tag>> getChildTags(int parentId) async {
    final db = await database;
    final maps = await db.query('tags', where: 'parent_id = ?', whereArgs: [parentId], orderBy: 'id ASC');
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  /// 新增标签
  Future<Tag> createTag(String name, {int? parentId}) async {
    final db = await database;
    final tag = Tag(name: name, parentId: parentId);
    final id = await db.insert('tags', tag.toMap());
    return tag.copyWith(id: id);
  }

  /// 更新标签名称
  Future<void> updateTagName(int tagId, String newName) async {
    final db = await database;
    await db.update('tags', {'name': newName}, where: 'id = ?', whereArgs: [tagId]);
  }

  /// 删除标签（级联删除子标签和关联）
  Future<void> deleteTag(int tagId) async {
    final db = await database;
    // 先删所有子标签
    final childTags = await getChildTags(tagId);
    for (final child in childTags) {
      await deleteTag(child.id!);
    }
    // 删关联
    await db.delete('entry_tags', where: 'tag_id = ?', whereArgs: [tagId]);
    // 删标签本身
    await db.delete('tags', where: 'id = ?', whereArgs: [tagId]);
  }

  // ==================== 记录操作 ====================

  /// 新增记录（含标签关联）
  Future<Entry> createEntry(String content, {List<int>? tagIds}) async {
    final db = await database;
    final now = DateTime.now();
    final entry = Entry(
      content: content,
      createdAt: now,
      updatedAt: now,
    );

    final id = await db.insert('entries', entry.toMap());

    // 建立标签关联
    if (tagIds != null && tagIds.isNotEmpty) {
      final batch = db.batch();
      for (final tagId in tagIds) {
        batch.insert('entry_tags', EntryTag(entryId: id, tagId: tagId).toMap());
      }
      await batch.commit(noResult: true);
    }

    return entry.copyWith(id: id);
  }

  /// 获取所有记录（按时间倒序）
  Future<List<Entry>> getAllEntries({int? limit, int? offset}) async {
    final db = await database;
    final maps = await db.query(
      'entries',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    final entries = maps.map((map) => Entry.fromMap(map)).toList();

    // 为每条记录加载标签（单条失败不影响其他记录）
    for (final entry in entries) {
      try {
        entry.tags
          ..clear()
          ..addAll(await _getTagsForEntry(entry.id!));
      } catch (e) {
        debugPrint('加载记录 #${entry.id} 标签失败：$e');
      }
    }

    return entries;
  }

  /// 按日期范围获取记录
  Future<List<Entry>> getEntriesByDateRange(DateTime start, DateTime end) async {
    final db = await database;
    final maps = await db.query(
      'entries',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'created_at DESC',
    );
    final entries = maps.map((map) => Entry.fromMap(map)).toList();

    for (final entry in entries) {
      try {
        entry.tags
          ..clear()
          ..addAll(await _getTagsForEntry(entry.id!));
      } catch (e) {
        debugPrint('加载记录 #${entry.id} 标签失败：$e');
      }
    }

    return entries;
  }

  /// 按标签筛选记录
  Future<List<Entry>> getEntriesByTag(int tagId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT e.* FROM entries e
      INNER JOIN entry_tags et ON e.id = et.entry_id
      WHERE et.tag_id = ?
      ORDER BY e.created_at DESC
    ''', [tagId]);
    final entries = maps.map((map) => Entry.fromMap(map)).toList();

    for (final entry in entries) {
      try {
        entry.tags
          ..clear()
          ..addAll(await _getTagsForEntry(entry.id!));
      } catch (e) {
        debugPrint('加载记录 #${entry.id} 标签失败：$e');
      }
    }

    return entries;
  }

  /// 获取某条记录的标签
  Future<List<Tag>> _getTagsForEntry(int entryId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.* FROM tags t
      INNER JOIN entry_tags et ON t.id = et.tag_id
      WHERE et.entry_id = ?
      ORDER BY t.id ASC
    ''', [entryId]);
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  /// 删除记录
  Future<void> deleteEntry(int entryId) async {
    final db = await database;
    await db.delete('entry_tags', where: 'entry_id = ?', whereArgs: [entryId]);
    await db.delete('entries', where: 'id = ?', whereArgs: [entryId]);
  }

  /// 更新记录内容
  Future<void> updateEntry(int entryId, String content) async {
    final db = await database;
    await db.update(
      'entries',
      {'content': content, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [entryId],
    );
  }

  // ==================== 导出 ====================

  /// 获取所有记录及标签（用于导出）
  Future<List<Map<String, dynamic>>> getAllEntriesWithTagPaths() async {
    final entries = await getAllEntries();
    final result = <Map<String, dynamic>>[];

    for (final entry in entries) {
      final tagPaths = <String>[];
      for (final tag in entry.tags) {
        final path = await _getTagPath(tag.id!);
        tagPaths.add(path);
      }

      result.add({
        'content': entry.content,
        'created_at': entry.createdAt,
        'updated_at': entry.updatedAt,
        'tags': tagPaths,
      });
    }

    return result;
  }

  /// 获取标签的完整路径（如 "生活 > 饮食 > 午餐"）
  Future<String> _getTagPath(int tagId) async {
    final db = await database;
    final parts = <String>[];
    int? currentId = tagId;

    while (currentId != null) {
      final maps = await db.query('tags', where: 'id = ?', whereArgs: [currentId]);
      if (maps.isEmpty) break;
      parts.insert(0, maps[0]['name'] as String);
      currentId = maps[0]['parent_id'] as int?;
    }

    return parts.join(' > ');
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

