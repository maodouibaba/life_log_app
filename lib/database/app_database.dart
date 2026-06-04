import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../models/tag.dart';
import '../models/entry.dart';
import '../models/entry_tag.dart';
import '../models/project.dart';

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
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = appDir.path;
    debugPrint('数据库路径：$dbPath');
    final path = join(dbPath, 'life_log.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
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

    // 项目表
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 记录表（含 project_id）
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        project_id INTEGER,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
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
    await db.execute('CREATE INDEX idx_entries_project_id ON entries(project_id)');
    await db.execute('CREATE INDEX idx_entry_tags_entry_id ON entry_tags(entry_id)');
    await db.execute('CREATE INDEX idx_entry_tags_tag_id ON entry_tags(tag_id)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS projects (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      try {
        await db.execute('ALTER TABLE entries ADD COLUMN project_id INTEGER');
      } catch (_) {
        // 列已存在则忽略
      }
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_entries_project_id ON entries(project_id)');
      } catch (_) {}
    }
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
    final childTags = await getChildTags(tagId);
    for (final child in childTags) {
      await deleteTag(child.id!);
    }
    await db.delete('entry_tags', where: 'tag_id = ?', whereArgs: [tagId]);
    await db.delete('tags', where: 'id = ?', whereArgs: [tagId]);
  }

  // ==================== 项目操作 ====================

  /// 获取所有项目
  Future<List<Project>> getAllProjects() async {
    final db = await database;
    final maps = await db.query('projects', orderBy: 'id ASC');
    return maps.map((map) => Project.fromMap(map)).toList();
  }

  /// 新增项目
  Future<Project> createProject(String name) async {
    final db = await database;
    final project = Project(name: name);
    final id = await db.insert('projects', project.toMap());
    return project.copyWith(id: id);
  }

  /// 更新项目名称
  Future<void> updateProjectName(int projectId, String newName) async {
    final db = await database;
    await db.update('projects', {'name': newName}, where: 'id = ?', whereArgs: [projectId]);
  }

  /// 删除项目（关联记录的 project_id 置空）
  Future<void> deleteProject(int projectId) async {
    final db = await database;
    await db.update('entries', {'project_id': null}, where: 'project_id = ?', whereArgs: [projectId]);
    await db.delete('projects', where: 'id = ?', whereArgs: [projectId]);
  }

  /// 为记录设置项目
  Future<void> setEntryProject(int entryId, int? projectId) async {
    final db = await database;
    await db.update('entries', {'project_id': projectId}, where: 'id = ?', whereArgs: [entryId]);
  }

  // ==================== 记录操作 ====================

  /// 新增记录（含标签关联、项目）
  Future<Entry> createEntry(String content, {List<int>? tagIds, int? projectId}) async {
    final db = await database;
    final now = DateTime.now();
    final entry = Entry(
      content: content,
      createdAt: now,
      updatedAt: now,
      projectId: projectId,
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

  /// 从 raw map 加载标签和项目名
  Future<void> _enrichEntries(List<Entry> entries) async {
    for (final entry in entries) {
      // 加载标签
      try {
        entry.tags
          ..clear()
          ..addAll(await _getTagsForEntry(entry.id!));
      } catch (e) {
        debugPrint('加载记录 #${entry.id} 标签失败：$e');
      }
    }
  }

  /// 获取所有记录（按时间倒序），已关联标签和项目
  Future<List<Entry>> getAllEntries({int? limit, int? offset}) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT e.*, p.name as project_name
      FROM entries e
      LEFT JOIN projects p ON e.project_id = p.id
      ORDER BY e.created_at DESC
      ${limit != null ? 'LIMIT $limit' : ''}
      ${offset != null ? 'OFFSET $offset' : ''}
    ''');
    final entries = maps.map((map) => Entry.fromMap(map)).toList();
    await _enrichEntries(entries);
    return entries;
  }

  /// 按日期范围获取记录
  Future<List<Entry>> getEntriesByDateRange(DateTime start, DateTime end) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT e.*, p.name as project_name
      FROM entries e
      LEFT JOIN projects p ON e.project_id = p.id
      WHERE e.created_at >= ? AND e.created_at <= ?
      ORDER BY e.created_at DESC
    ''', [start.toIso8601String(), end.toIso8601String()]);
    final entries = maps.map((map) => Entry.fromMap(map)).toList();
    await _enrichEntries(entries);
    return entries;
  }

  /// 按标签筛选记录
  Future<List<Entry>> getEntriesByTag(int tagId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT e.*, p.name as project_name
      FROM entries e
      INNER JOIN entry_tags et ON e.id = et.entry_id
      LEFT JOIN projects p ON e.project_id = p.id
      WHERE et.tag_id = ?
      ORDER BY e.created_at DESC
    ''', [tagId]);
    final entries = maps.map((map) => Entry.fromMap(map)).toList();
    await _enrichEntries(entries);
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

  /// 批量删除记录
  Future<void> deleteEntries(List<int> entryIds) async {
    if (entryIds.isEmpty) return;
    final db = await database;
    final placeholders = entryIds.map((_) => '?').join(',');
    await db.delete('entry_tags', where: 'entry_id IN ($placeholders)', whereArgs: entryIds);
    await db.delete('entries', where: 'id IN ($placeholders)', whereArgs: entryIds);
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

  /// 更新记录内容、标签、项目
  Future<void> updateEntryWithTags(int entryId, String content,
      {List<int>? tagIds, int? projectId}) async {
    final db = await database;

    await db.update(
      'entries',
      {
        'content': content,
        'updated_at': DateTime.now().toIso8601String(),
        'project_id': projectId,
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );

    // 删除旧标签关联
    await db.delete('entry_tags', where: 'entry_id = ?', whereArgs: [entryId]);

    // 插入新标签关联
    if (tagIds != null && tagIds.isNotEmpty) {
      final batch = db.batch();
      for (final tagId in tagIds) {
        batch.insert('entry_tags', EntryTag(entryId: entryId, tagId: tagId).toMap());
      }
      await batch.commit(noResult: true);
    }
  }

  /// 批量替换选中记录的标签（全部替换为新标签集）
  Future<void> batchReplaceTags(List<int> entryIds, List<int> newTagIds) async {
    if (entryIds.isEmpty) return;
    final db = await database;
    final placeholders = entryIds.map((_) => '?').join(',');

    // 删除所有选中记录的旧标签
    await db.delete('entry_tags', where: 'entry_id IN ($placeholders)', whereArgs: entryIds);

    // 插入新标签
    if (newTagIds.isNotEmpty) {
      final batch = db.batch();
      for (final entryId in entryIds) {
        for (final tagId in newTagIds) {
          batch.insert('entry_tags', EntryTag(entryId: entryId, tagId: tagId).toMap());
        }
      }
      await batch.commit(noResult: true);
    }
  }

  // ==================== 导入 / 导出 ====================

  /// 导出全部数据为 JSON（用于数据迁移）
  Future<String> exportToJson() async {
    final tags = await getAllTags();
    final projects = await getAllProjects();
    final db = await database;

    final entryMaps = await db.query('entries', orderBy: 'id ASC');
    final entryTagMaps = await db.query('entry_tags', orderBy: 'entry_id ASC');

    final data = {
      'version': 2,
      'tags': tags.map((t) => t.toMap()).toList(),
      'projects': projects.map((p) => p.toMap()).toList(),
      'entries': entryMaps,
      'entry_tags': entryTagMaps,
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 从 JSON 导入数据（先清空所有表，再写入）
  Future<void> importFromJson(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final db = await database;

    await db.transaction((txn) async {
      // 清空所有表（先删子表再删父表）
      await txn.delete('entry_tags');
      await txn.delete('entries');
      await txn.delete('tags');
      await txn.delete('projects');

      // 导入标签
      final tagList = data['tags'] as List<dynamic>;
      for (final item in tagList) {
        await txn.insert('tags', item as Map<String, dynamic>);
      }

      // 导入项目
      final projectList = data['projects'] as List<dynamic>;
      for (final item in projectList) {
        await txn.insert('projects', item as Map<String, dynamic>);
      }

      // 导入记录
      final entryList = data['entries'] as List<dynamic>;
      for (final item in entryList) {
        await txn.insert('entries', item as Map<String, dynamic>);
      }

      // 导入关联
      final etList = data['entry_tags'] as List<dynamic>;
      for (final item in etList) {
        await txn.insert('entry_tags', item as Map<String, dynamic>);
      }
    });
  }

  // ==================== 导出 Excel ====================

  /// 获取所有记录及标签（用于 Excel 导出）
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
        'project': entry.projectName,
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
