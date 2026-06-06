import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../models/tag.dart';
import '../models/entry.dart';
import '../models/entry_tag.dart';
import '../models/entry_attribute_tag.dart';
import '../models/project.dart';
import '../models/project_group.dart';
import '../models/attribute_tag.dart';
import '../models/attribute_tag_group.dart';
import '../models/space.dart';

/// 本地数据库管理类 v3
/// 支持多入口、标题字段、属性标签、项目分组
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
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // ==================== Schema ====================

  Future<void> _onCreate(Database db, int version) async {
    // 入口表
    await db.execute('''
      CREATE TABLE spaces (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 树状标签表
    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        created_at TEXT NOT NULL,
        space_id INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (parent_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');

    // 项目分组表
    await db.execute('''
      CREATE TABLE project_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        space_id INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 项目表
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        space_id INTEGER NOT NULL DEFAULT 1,
        group_id INTEGER,
        FOREIGN KEY (group_id) REFERENCES project_groups(id) ON DELETE SET NULL
      )
    ''');

    // 记录表（含 title、space_id）
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        project_id INTEGER,
        space_id INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
      )
    ''');

    // 记录-树状标签关联表
    await db.execute('''
      CREATE TABLE entry_tags (
        entry_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (entry_id, tag_id),
        FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');

    // 属性标签分组表
    await db.execute('''
      CREATE TABLE attribute_tag_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        space_id INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 属性标签表
    await db.execute('''
      CREATE TABLE attribute_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        group_id INTEGER,
        space_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (group_id) REFERENCES attribute_tag_groups(id) ON DELETE SET NULL
      )
    ''');

    // 记录-属性标签关联表
    await db.execute('''
      CREATE TABLE entry_attribute_tags (
        entry_id INTEGER NOT NULL,
        attribute_tag_id INTEGER NOT NULL,
        PRIMARY KEY (entry_id, attribute_tag_id),
        FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE,
        FOREIGN KEY (attribute_tag_id) REFERENCES attribute_tags(id) ON DELETE CASCADE
      )
    ''');

    // 索引
    await db.execute('CREATE INDEX idx_tags_parent_id ON tags(parent_id)');
    await db.execute('CREATE INDEX idx_tags_space_id ON tags(space_id)');
    await db.execute('CREATE INDEX idx_entries_created_at ON entries(created_at)');
    await db.execute('CREATE INDEX idx_entries_space_id ON entries(space_id)');
    await db.execute('CREATE INDEX idx_entries_project_id ON entries(project_id)');
    await db.execute('CREATE INDEX idx_entry_tags_entry_id ON entry_tags(entry_id)');
    await db.execute('CREATE INDEX idx_entry_tags_tag_id ON entry_tags(tag_id)');
    await db.execute('CREATE INDEX idx_attribute_tags_space_id ON attribute_tags(space_id)');
    await db.execute('CREATE INDEX idx_projects_space_id ON projects(space_id)');
    await db.execute('CREATE INDEX idx_project_groups_space_id ON project_groups(space_id)');
    await db.execute('CREATE INDEX idx_attribute_tag_groups_space_id ON attribute_tag_groups(space_id)');

    // 创建默认入口
    await db.insert('spaces', {
      'name': '默认',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2：添加 projects 表
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
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_entries_project_id ON entries(project_id)');
      } catch (_) {}
    }

    // v2 → v3：多入口 + 属性标签 + 项目分组 + 标题字段 + 排序
    if (oldVersion < 3) {
      // 新增字段：entries
      try { await db.execute('ALTER TABLE entries ADD COLUMN title TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE entries ADD COLUMN space_id INTEGER DEFAULT 1'); } catch (_) {}
      await db.execute('UPDATE entries SET space_id = 1 WHERE space_id IS NULL');

      // 新增字段：tags
      try { await db.execute('ALTER TABLE tags ADD COLUMN space_id INTEGER DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE tags ADD COLUMN sort_order INTEGER DEFAULT 0'); } catch (_) {}
      await db.execute('UPDATE tags SET space_id = 1 WHERE space_id IS NULL');

      // 新增字段：projects
      try { await db.execute('ALTER TABLE projects ADD COLUMN space_id INTEGER DEFAULT 1'); } catch (_) {}
      try { await db.execute('ALTER TABLE projects ADD COLUMN group_id INTEGER'); } catch (_) {}
      await db.execute('UPDATE projects SET space_id = 1 WHERE space_id IS NULL');

      // 新建表：spaces
      await db.execute('''
        CREATE TABLE IF NOT EXISTS spaces (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS project_groups (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          space_id INTEGER NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS attribute_tag_groups (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          space_id INTEGER NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS attribute_tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          group_id INTEGER,
          space_id INTEGER NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS entry_attribute_tags (
          entry_id INTEGER NOT NULL,
          attribute_tag_id INTEGER NOT NULL,
          PRIMARY KEY (entry_id, attribute_tag_id),
          FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE,
          FOREIGN KEY (attribute_tag_id) REFERENCES attribute_tags(id) ON DELETE CASCADE
        )
      ''');

      // 新增索引
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_tags_space_id ON tags(space_id)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_entries_space_id ON entries(space_id)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_attribute_tags_space_id ON attribute_tags(space_id)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_projects_space_id ON projects(space_id)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_project_groups_space_id ON project_groups(space_id)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_attribute_tag_groups_space_id ON attribute_tag_groups(space_id)'); } catch (_) {}

      // 创建默认入口（如果不存在）
      final existing = await db.query('spaces', where: 'id = 1');
      if (existing.isEmpty) {
        await db.insert('spaces', {
          'name': '默认',
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    }
  }

  // ==================== 入口/空间操作 ====================

  Future<List<Space>> getAllSpaces() async {
    final db = await database;
    final maps = await db.query('spaces', orderBy: 'id ASC');
    return maps.map((map) => Space.fromMap(map)).toList();
  }

  Future<Space> createSpace(String name) async {
    final db = await database;
    final space = Space(name: name);
    final id = await db.insert('spaces', space.toMap());
    return space.copyWith(id: id);
  }

  Future<void> updateSpaceName(int spaceId, String newName) async {
    final db = await database;
    await db.update('spaces', {'name': newName}, where: 'id = ?', whereArgs: [spaceId]);
  }

  /// 删除入口及其全部关联数据
  Future<void> deleteSpace(int spaceId) async {
    final db = await database;
    // 获取该空间下所有 entry id
    final entryMaps = await db.query('entries',
        columns: ['id'], where: 'space_id = ?', whereArgs: [spaceId]);
    final entryIds = entryMaps.map((m) => m['id'] as int).toList();

    if (entryIds.isNotEmpty) {
      final ph = entryIds.map((_) => '?').join(',');
      await db.delete('entry_attribute_tags', where: 'entry_id IN ($ph)', whereArgs: entryIds);
      await db.delete('entry_tags', where: 'entry_id IN ($ph)', whereArgs: entryIds);
      await db.delete('entries', where: 'id IN ($ph)', whereArgs: entryIds);
    }

    // 删除该空间下标签关联（tags 有 CASCADE，但手动清理更安全）
    final tagIds = (await db.query('tags',
        columns: ['id'], where: 'space_id = ?', whereArgs: [spaceId]))
        .map((m) => m['id'] as int).toList();
    if (tagIds.isNotEmpty) {
      final ph = tagIds.map((_) => '?').join(',');
      await db.delete('entry_tags', where: 'tag_id IN ($ph)', whereArgs: tagIds);
    }
    await db.delete('tags', where: 'space_id = ?', whereArgs: [spaceId]);

    await db.delete('entry_attribute_tags',
        where: 'attribute_tag_id IN (SELECT id FROM attribute_tags WHERE space_id = ?)',
        whereArgs: [spaceId]);
    await db.delete('attribute_tags', where: 'space_id = ?', whereArgs: [spaceId]);
    await db.delete('attribute_tag_groups', where: 'space_id = ?', whereArgs: [spaceId]);

    await db.delete('projects', where: 'space_id = ?', whereArgs: [spaceId]);
    await db.delete('project_groups', where: 'space_id = ?', whereArgs: [spaceId]);

    await db.delete('spaces', where: 'id = ?', whereArgs: [spaceId]);
  }

  // ==================== 树状标签操作 ====================

  Future<List<Tag>> getAllTags({int? spaceId}) async {
    final db = await database;
    final where = spaceId != null ? 'space_id = ?' : null;
    final args = spaceId != null ? [spaceId] : null;
    final maps = await db.query('tags',
        where: where, whereArgs: args, orderBy: 'sort_order ASC, id ASC');
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  Future<List<Tag>> getRootTags(int spaceId) async {
    final db = await database;
    final maps = await db.query('tags',
        where: 'parent_id IS NULL AND space_id = ?',
        whereArgs: [spaceId],
        orderBy: 'sort_order ASC, id ASC');
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  Future<List<Tag>> getChildTags(int parentId) async {
    final db = await database;
    final maps = await db.query('tags',
        where: 'parent_id = ?',
        whereArgs: [parentId],
        orderBy: 'sort_order ASC, id ASC');
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  Future<Tag> createTag(String name,
      {int? parentId, int? spaceId, int? sortOrder}) async {
    final db = await database;
    if (sortOrder == null && parentId != null) {
      // 自动分配排序号
      final siblings = await getChildTags(parentId);
      sortOrder = siblings.isEmpty ? 0 : siblings.last.sortOrder + 1;
    } else {
      sortOrder ??= 0;
    }
    final tag = Tag(
      name: name,
      parentId: parentId,
      spaceId: spaceId ?? 1,
      sortOrder: sortOrder,
    );
    final id = await db.insert('tags', tag.toMap());
    return tag.copyWith(id: id);
  }

  Future<void> updateTagName(int tagId, String newName) async {
    final db = await database;
    await db.update('tags', {'name': newName}, where: 'id = ?', whereArgs: [tagId]);
  }

  /// 更新标签排序
  Future<void> updateTagSortOrder(int tagId, int sortOrder) async {
    final db = await database;
    await db.update('tags', {'sort_order': sortOrder},
        where: 'id = ?', whereArgs: [tagId]);
  }

  /// 移动标签到新父节点（parentId = null 表示移到根）
  Future<void> moveTag(int tagId, int? newParentId) async {
    final db = await database;
    await db.update('tags', {'parent_id': newParentId},
        where: 'id = ?', whereArgs: [tagId]);
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

  // ==================== 属性标签分组操作 ====================

  Future<List<AttributeTagGroup>> getAllAttributeTagGroups(int spaceId) async {
    final db = await database;
    final maps = await db.query('attribute_tag_groups',
        where: 'space_id = ?', whereArgs: [spaceId], orderBy: 'id ASC');
    return maps.map((map) => AttributeTagGroup.fromMap(map)).toList();
  }

  Future<AttributeTagGroup> createAttributeTagGroup(String name, int spaceId) async {
    final db = await database;
    final group = AttributeTagGroup(name: name, spaceId: spaceId);
    final id = await db.insert('attribute_tag_groups', group.toMap());
    return group.copyWith(id: id);
  }

  Future<void> updateAttributeTagGroupName(int groupId, String newName) async {
    final db = await database;
    await db.update('attribute_tag_groups', {'name': newName},
        where: 'id = ?', whereArgs: [groupId]);
  }

  Future<void> deleteAttributeTagGroup(int groupId) async {
    final db = await database;
    // 组内标签的 group_id 置空
    await db.update('attribute_tags', {'group_id': null},
        where: 'group_id = ?', whereArgs: [groupId]);
    await db.delete('attribute_tag_groups', where: 'id = ?', whereArgs: [groupId]);
  }

  // ==================== 属性标签操作 ====================

  Future<List<AttributeTag>> getAllAttributeTags(int spaceId) async {
    final db = await database;
    final maps = await db.query('attribute_tags',
        where: 'space_id = ?', whereArgs: [spaceId], orderBy: 'id ASC');
    return maps.map((map) => AttributeTag.fromMap(map)).toList();
  }

  Future<List<AttributeTag>> getAttributeTagsByGroup(int groupId) async {
    final db = await database;
    final maps = await db.query('attribute_tags',
        where: 'group_id = ?', whereArgs: [groupId], orderBy: 'id ASC');
    return maps.map((map) => AttributeTag.fromMap(map)).toList();
  }

  Future<AttributeTag> createAttributeTag(String name,
      {int? groupId, required int spaceId}) async {
    final db = await database;
    final tag = AttributeTag(name: name, groupId: groupId, spaceId: spaceId);
    final id = await db.insert('attribute_tags', tag.toMap());
    return tag.copyWith(id: id);
  }

  Future<void> updateAttributeTagName(int tagId, String newName) async {
    final db = await database;
    await db.update('attribute_tags', {'name': newName},
        where: 'id = ?', whereArgs: [tagId]);
  }

  /// 移动属性标签到新分组（groupId = null 表示移到"未分组"）
  Future<void> moveAttributeTagToGroup(int tagId, int? groupId) async {
    final db = await database;
    await db.update('attribute_tags', {'group_id': groupId},
        where: 'id = ?', whereArgs: [tagId]);
  }

  Future<void> deleteAttributeTag(int tagId) async {
    final db = await database;
    await db.delete('entry_attribute_tags',
        where: 'attribute_tag_id = ?', whereArgs: [tagId]);
    await db.delete('attribute_tags', where: 'id = ?', whereArgs: [tagId]);
  }

  // ==================== 项目分组操作 ====================

  Future<List<ProjectGroup>> getAllProjectGroups(int spaceId) async {
    final db = await database;
    final maps = await db.query('project_groups',
        where: 'space_id = ?', whereArgs: [spaceId], orderBy: 'id ASC');
    return maps.map((map) => ProjectGroup.fromMap(map)).toList();
  }

  Future<ProjectGroup> createProjectGroup(String name, int spaceId) async {
    final db = await database;
    final group = ProjectGroup(name: name, spaceId: spaceId);
    final id = await db.insert('project_groups', group.toMap());
    return group.copyWith(id: id);
  }

  Future<void> updateProjectGroupName(int groupId, String newName) async {
    final db = await database;
    await db.update('project_groups', {'name': newName},
        where: 'id = ?', whereArgs: [groupId]);
  }

  Future<void> deleteProjectGroup(int groupId) async {
    final db = await database;
    await db.update('projects', {'group_id': null},
        where: 'group_id = ?', whereArgs: [groupId]);
    await db.delete('project_groups', where: 'id = ?', whereArgs: [groupId]);
  }

  // ==================== 项目操作 ====================

  Future<List<Project>> getAllProjects({int? spaceId}) async {
    final db = await database;
    final where = spaceId != null ? 'space_id = ?' : null;
    final args = spaceId != null ? [spaceId] : null;
    final maps = await db.query('projects',
        where: where, whereArgs: args, orderBy: 'id ASC');
    return maps.map((map) => Project.fromMap(map)).toList();
  }

  Future<List<Project>> getProjectsByGroup(int groupId) async {
    final db = await database;
    final maps = await db.query('projects',
        where: 'group_id = ?', whereArgs: [groupId], orderBy: 'id ASC');
    return maps.map((map) => Project.fromMap(map)).toList();
  }

  Future<Project> createProject(String name,
      {int? groupId, int? spaceId}) async {
    final db = await database;
    final project = Project(name: name, groupId: groupId, spaceId: spaceId ?? 1);
    final id = await db.insert('projects', project.toMap());
    return project.copyWith(id: id);
  }

  Future<void> updateProjectName(int projectId, String newName) async {
    final db = await database;
    await db.update('projects', {'name': newName},
        where: 'id = ?', whereArgs: [projectId]);
  }

  /// 移动项目到新分组（groupId = null 表示移到"未分组"）
  Future<void> moveProjectToGroup(int projectId, int? groupId) async {
    final db = await database;
    await db.update('projects', {'group_id': groupId},
        where: 'id = ?', whereArgs: [projectId]);
  }

  Future<void> deleteProject(int projectId) async {
    final db = await database;
    await db.update('entries', {'project_id': null},
        where: 'project_id = ?', whereArgs: [projectId]);
    await db.delete('projects', where: 'id = ?', whereArgs: [projectId]);
  }

  Future<void> setEntryProject(int entryId, int? projectId) async {
    final db = await database;
    await db.update('entries', {'project_id': projectId},
        where: 'id = ?', whereArgs: [entryId]);
  }

  // ==================== 记录操作 ====================

  /// 新增记录（含标签、属性标签、项目关联）
  Future<Entry> createEntry(String content,
      {String? title,
      List<int>? tagIds,
      List<int>? attributeTagIds,
      int? projectId,
      int? spaceId}) async {
    final db = await database;
    final now = DateTime.now();
    final entry = Entry(
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
      projectId: projectId,
      spaceId: spaceId ?? 1,
    );

    final id = await db.insert('entries', entry.toMap());

    // 树状标签关联
    if (tagIds != null && tagIds.isNotEmpty) {
      final batch = db.batch();
      for (final tagId in tagIds) {
        batch.insert('entry_tags', EntryTag(entryId: id, tagId: tagId).toMap());
      }
      await batch.commit(noResult: true);
    }

    // 属性标签关联
    if (attributeTagIds != null && attributeTagIds.isNotEmpty) {
      final batch = db.batch();
      for (final atId in attributeTagIds) {
        batch.insert('entry_attribute_tags',
            EntryAttributeTag(entryId: id, attributeTagId: atId).toMap());
      }
      await batch.commit(noResult: true);
    }

    return entry.copyWith(id: id);
  }

  /// 从 raw map 加载标签和项目名
  Future<void> _enrichEntries(List<Entry> entries) async {
    for (final entry in entries) {
      try {
        entry.tags
          ..clear()
          ..addAll(await _getTagsForEntry(entry.id!));
      } catch (e) {
        debugPrint('加载记录 #${entry.id} 树状标签失败：$e');
      }
      try {
        entry.attributeTags
          ..clear()
          ..addAll(await _getAttributeTagsForEntry(entry.id!));
      } catch (e) {
        debugPrint('加载记录 #${entry.id} 属性标签失败：$e');
      }
    }
  }

  /// 获取某条记录的树状标签
  Future<List<Tag>> _getTagsForEntry(int entryId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.* FROM tags t
      INNER JOIN entry_tags et ON t.id = et.tag_id
      WHERE et.entry_id = ?
      ORDER BY t.sort_order ASC, t.id ASC
    ''', [entryId]);
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  /// 获取某条记录的属性标签
  Future<List<AttributeTag>> _getAttributeTagsForEntry(int entryId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT at.* FROM attribute_tags at
      INNER JOIN entry_attribute_tags eat ON at.id = eat.attribute_tag_id
      WHERE eat.entry_id = ?
      ORDER BY at.id ASC
    ''', [entryId]);
    return maps.map((map) => AttributeTag.fromMap(map)).toList();
  }

  /// 获取所有记录（按时间倒序）
  Future<List<Entry>> getAllEntries({int? spaceId, int? limit, int? offset}) async {
    final db = await database;
    final where = spaceId != null ? 'WHERE e.space_id = ?' : '';
    final args = spaceId != null ? [spaceId] : null;

    final maps = await db.rawQuery('''
      SELECT e.*, p.name as project_name
      FROM entries e
      LEFT JOIN projects p ON e.project_id = p.id
      $where
      ORDER BY e.created_at DESC
      ${limit != null ? 'LIMIT $limit' : ''}
      ${offset != null ? 'OFFSET $offset' : ''}
    ''', args);
    final entries = maps.map((map) => Entry.fromMap(map)).toList();
    await _enrichEntries(entries);
    return entries;
  }

  /// 按日期范围获取记录
  Future<List<Entry>> getEntriesByDateRange(DateTime start, DateTime end,
      {int? spaceId}) async {
    final db = await database;
    final spaceFilter = spaceId != null ? 'AND e.space_id = ?' : '';
    final args = <Object?>[start.toIso8601String(), end.toIso8601String()];
    if (spaceId != null) args.add(spaceId);

    final maps = await db.rawQuery('''
      SELECT e.*, p.name as project_name
      FROM entries e
      LEFT JOIN projects p ON e.project_id = p.id
      WHERE e.created_at >= ? AND e.created_at <= ? $spaceFilter
      ORDER BY e.created_at DESC
    ''', args);
    final entries = maps.map((map) => Entry.fromMap(map)).toList();
    await _enrichEntries(entries);
    return entries;
  }

  /// 按树状标签筛选记录
  Future<List<Entry>> getEntriesByTag(int tagId, {int? spaceId}) async {
    final db = await database;
    final spaceFilter = spaceId != null ? 'AND e.space_id = ?' : '';
    final args = [tagId];
    if (spaceId != null) args.add(spaceId);

    final maps = await db.rawQuery('''
      SELECT e.*, p.name as project_name
      FROM entries e
      INNER JOIN entry_tags et ON e.id = et.entry_id
      LEFT JOIN projects p ON e.project_id = p.id
      WHERE et.tag_id = ? $spaceFilter
      ORDER BY e.created_at DESC
    ''', args);
    final entries = maps.map((map) => Entry.fromMap(map)).toList();
    await _enrichEntries(entries);
    return entries;
  }

  /// 按属性标签筛选记录
  Future<List<Entry>> getEntriesByAttributeTag(int attributeTagId, {int? spaceId}) async {
    final db = await database;
    final spaceFilter = spaceId != null ? 'AND e.space_id = ?' : '';
    final args = [attributeTagId];
    if (spaceId != null) args.add(spaceId);

    final maps = await db.rawQuery('''
      SELECT e.*, p.name as project_name
      FROM entries e
      INNER JOIN entry_attribute_tags eat ON e.id = eat.entry_id
      LEFT JOIN projects p ON e.project_id = p.id
      WHERE eat.attribute_tag_id = ? $spaceFilter
      ORDER BY e.created_at DESC
    ''', args);
    final entries = maps.map((map) => Entry.fromMap(map)).toList();
    await _enrichEntries(entries);
    return entries;
  }

  /// 按关键词搜索（搜索 title + content，可搜索树状标签名和属性标签名）
  Future<List<Entry>> searchEntries(String keyword, {int? spaceId}) async {
    final db = await database;
    final like = '%$keyword%';
    final spaceFilter = spaceId != null ? 'AND e.space_id = ?' : '';
    final args = <Object?>[like, like, like, like];
    if (spaceId != null) args.add(spaceId);

    final maps = await db.rawQuery('''
      SELECT DISTINCT e.*, p.name as project_name
      FROM entries e
      LEFT JOIN projects p ON e.project_id = p.id
      LEFT JOIN entry_tags et ON e.id = et.entry_id
      LEFT JOIN tags t ON et.tag_id = t.id
      LEFT JOIN entry_attribute_tags eat ON e.id = eat.entry_id
      LEFT JOIN attribute_tags at ON eat.attribute_tag_id = at.id
      WHERE (e.title LIKE ? OR e.content LIKE ? OR t.name LIKE ? OR at.name LIKE ?)
      $spaceFilter
      ORDER BY e.created_at DESC
    ''', args);
    final entries = maps.map((map) => Entry.fromMap(map)).toList();
    await _enrichEntries(entries);
    return entries;
  }

  /// 组合筛选查询（支持多选标签/项目/属性标签 + 日期范围 + 关键词，AND 组合）
  Future<List<Entry>> getEntriesByFilters({
    int? spaceId,
    Set<int>? tagIds,
    Set<int>? attributeTagIds,
    Set<int>? projectIds,
    DateTime? startDate,
    DateTime? endDate,
    String? keyword,
  }) async {
    final db = await database;
    final conditions = <String>[];
    final args = <Object?>[];

    if (spaceId != null) {
      conditions.add('e.space_id = ?');
      args.add(spaceId);
    }

    if (startDate != null && endDate != null) {
      conditions.add('e.created_at >= ? AND e.created_at <= ?');
      args.addAll([startDate.toIso8601String(), endDate.toIso8601String()]);
    }

    if (keyword != null && keyword.isNotEmpty) {
      final like = '%$keyword%';
      conditions.add(
          '(e.title LIKE ? OR e.content LIKE ? OR t.name LIKE ? OR at.name LIKE ?)');
      args.addAll([like, like, like, like]);
    }

    // 树状标签：OR 逻辑（满足任一即可）
    if (tagIds != null && tagIds.isNotEmpty) {
      final ph = tagIds.map((_) => '?').join(',');
      conditions.add(
          'EXISTS (SELECT 1 FROM entry_tags et2 WHERE et2.entry_id = e.id AND et2.tag_id IN ($ph))');
      args.addAll(tagIds.map((id) => id).toList());
    }

    // 属性标签：OR 逻辑（满足任一即可）
    if (attributeTagIds != null && attributeTagIds.isNotEmpty) {
      final ph = attributeTagIds.map((_) => '?').join(',');
      conditions.add(
          'EXISTS (SELECT 1 FROM entry_attribute_tags eat2 WHERE eat2.entry_id = e.id AND eat2.attribute_tag_id IN ($ph))');
      args.addAll(attributeTagIds.map((id) => id).toList());
    }

    // 项目：OR 逻辑（满足任一即可）
    if (projectIds != null && projectIds.isNotEmpty) {
      final ph = projectIds.map((_) => '?').join(',');
      conditions.add('e.project_id IN ($ph)');
      args.addAll(projectIds.map((id) => id).toList());
    }

    final whereClause =
        conditions.isNotEmpty ? conditions.join(' AND ') : '1=1';

    final maps = await db.rawQuery('''
      SELECT DISTINCT e.*, p.name as project_name
      FROM entries e
      LEFT JOIN projects p ON e.project_id = p.id
      LEFT JOIN entry_tags et ON e.id = et.entry_id
      LEFT JOIN tags t ON et.tag_id = t.id
      LEFT JOIN entry_attribute_tags eat ON e.id = eat.entry_id
      LEFT JOIN attribute_tags at ON eat.attribute_tag_id = at.id
      WHERE $whereClause
      ORDER BY e.created_at DESC
    ''', args);

    final entries = maps.map((map) => Entry.fromMap(map)).toList();
    await _enrichEntries(entries);
    return entries;
  }

  /// 获取单条记录详情
  Future<Entry?> getEntry(int entryId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT e.*, p.name as project_name
      FROM entries e
      LEFT JOIN projects p ON e.project_id = p.id
      WHERE e.id = ?
    ''', [entryId]);
    if (maps.isEmpty) return null;
    final entry = Entry.fromMap(maps.first);
    try {
      entry.tags.addAll(await _getTagsForEntry(entry.id!));
      entry.attributeTags.addAll(await _getAttributeTagsForEntry(entry.id!));
    } catch (e) {
      debugPrint('加载记录 #${entry.id} 标签失败：$e');
    }
    return entry;
  }

  /// 删除记录
  Future<void> deleteEntry(int entryId) async {
    final db = await database;
    await db.delete('entry_tags', where: 'entry_id = ?', whereArgs: [entryId]);
    await db.delete('entry_attribute_tags', where: 'entry_id = ?', whereArgs: [entryId]);
    await db.delete('entries', where: 'id = ?', whereArgs: [entryId]);
  }

  /// 批量删除记录
  Future<void> deleteEntries(List<int> entryIds) async {
    if (entryIds.isEmpty) return;
    final db = await database;
    final placeholders = entryIds.map((_) => '?').join(',');
    await db.delete('entry_tags',
        where: 'entry_id IN ($placeholders)', whereArgs: entryIds);
    await db.delete('entry_attribute_tags',
        where: 'entry_id IN ($placeholders)', whereArgs: entryIds);
    await db.delete('entries',
        where: 'id IN ($placeholders)', whereArgs: entryIds);
  }

  /// 更新记录内容、标签、项目、属性标签
  Future<void> updateEntryWithTags(int entryId, String content,
      {String? title,
      List<int>? tagIds,
      List<int>? attributeTagIds,
      int? projectId}) async {
    final db = await database;

    await db.update(
      'entries',
      {
        'title': title,
        'content': content,
        'updated_at': DateTime.now().toIso8601String(),
        'project_id': projectId,
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );

    // 删除旧树状标签关联
    await db.delete('entry_tags', where: 'entry_id = ?', whereArgs: [entryId]);
    // 插入新树状标签关联
    if (tagIds != null && tagIds.isNotEmpty) {
      final batch = db.batch();
      for (final tagId in tagIds) {
        batch.insert('entry_tags', EntryTag(entryId: entryId, tagId: tagId).toMap());
      }
      await batch.commit(noResult: true);
    }

    // 删除旧属性标签关联
    await db.delete('entry_attribute_tags',
        where: 'entry_id = ?', whereArgs: [entryId]);
    // 插入新属性标签关联
    if (attributeTagIds != null && attributeTagIds.isNotEmpty) {
      final batch = db.batch();
      for (final atId in attributeTagIds) {
        batch.insert('entry_attribute_tags',
            EntryAttributeTag(entryId: entryId, attributeTagId: atId).toMap());
      }
      await batch.commit(noResult: true);
    }
  }

  /// 批量替换选中记录的树状标签
  Future<void> batchReplaceTags(List<int> entryIds, List<int> newTagIds) async {
    if (entryIds.isEmpty) return;
    final db = await database;
    final placeholders = entryIds.map((_) => '?').join(',');

    await db.delete('entry_tags',
        where: 'entry_id IN ($placeholders)', whereArgs: entryIds);

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

  /// 批量替换选中记录的属性标签
  Future<void> batchReplaceAttributeTags(
      List<int> entryIds, List<int> newAttributeTagIds) async {
    if (entryIds.isEmpty) return;
    final db = await database;
    final placeholders = entryIds.map((_) => '?').join(',');

    await db.delete('entry_attribute_tags',
        where: 'entry_id IN ($placeholders)', whereArgs: entryIds);

    if (newAttributeTagIds.isNotEmpty) {
      final batch = db.batch();
      for (final entryId in entryIds) {
        for (final atId in newAttributeTagIds) {
          batch.insert('entry_attribute_tags',
              EntryAttributeTag(entryId: entryId, attributeTagId: atId).toMap());
        }
      }
      await batch.commit(noResult: true);
    }
  }

  /// 批量设置选中记录的项目
  Future<void> batchSetProjects(
      List<int> entryIds, int? projectId) async {
    if (entryIds.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final entryId in entryIds) {
      batch.update('entries', {'project_id': projectId},
          where: 'id = ?', whereArgs: [entryId]);
    }
    await batch.commit(noResult: true);
  }

  // ==================== 导入 / 导出 ====================

  /// 导出为 JSON（指定空间或全部）
  Future<String> exportToJson({int? spaceId}) async {
    final errors = <String>[];

    // 辅助：查询表，失败时返回空列表并记录错误
    Future<List<Map<String, dynamic>>> safeQuery(
        String table, {
          String? where,
          List<Object?>? whereArgs,
          String? orderBy,
        }) async {
      try {
        final db = await database;
        return await db.query(table,
            where: where, whereArgs: whereArgs, orderBy: orderBy);
      } catch (e) {
        final msg = '查询表 $table 出错: $e';
        debugPrint('导出 — $msg');
        errors.add(msg);
        return [];
      }
    }

    // 辅助：执行 rawQuery，失败时返回空列表
    Future<List<Map<String, dynamic>>> safeRawQuery(
        String sql, List<Object?> args) async {
      try {
        final db = await database;
        return await db.rawQuery(sql, args);
      } catch (e) {
        final msg = 'rawQuery 出错: $e';
        debugPrint('导出 — $msg');
        errors.add(msg);
        return [];
      }
    }

    try {
      final tags = await (spaceId != null
          ? getAllTags(spaceId: spaceId)
          : getAllTags()).catchError((e) {
        final msg = '获取 tags 列表出错: $e';
        debugPrint('导出 — $msg');
        errors.add(msg);
        return <Tag>[];
      });

      final projects = await (spaceId != null
          ? getAllProjects(spaceId: spaceId)
          : getAllProjects()).catchError((e) {
        final msg = '获取 projects 列表出错: $e';
        debugPrint('导出 — $msg');
        errors.add(msg);
        return <Project>[];
      });

      // 查询记录
      final entryMaps = await safeQuery('entries',
          where: spaceId != null ? 'space_id = ?' : null,
          whereArgs: spaceId != null ? [spaceId] : null,
          orderBy: 'id ASC');

      final entryIds = entryMaps.map((m) => m['id'] as int).toList();

      // 查询关联表
      List<Map<String, dynamic>> entryTagMaps = [];
      List<Map<String, dynamic>> entryAttributeTagMaps = [];

      if (entryIds.isNotEmpty) {
        final ph = entryIds.map((_) => '?').join(',');
        entryTagMaps = await safeRawQuery(
            'SELECT * FROM entry_tags WHERE entry_id IN ($ph) ORDER BY entry_id ASC',
            entryIds);
        entryAttributeTagMaps = await safeRawQuery(
            'SELECT * FROM entry_attribute_tags WHERE entry_id IN ($ph) ORDER BY entry_id ASC',
            entryIds);
      }

      // 查询属性标签
      final attributeTagMaps = await safeQuery('attribute_tags',
          where: spaceId != null ? 'space_id = ?' : null,
          whereArgs: spaceId != null ? [spaceId] : null);

      // 查询属性标签分组
      final attributeTagGroupMaps = await safeQuery('attribute_tag_groups',
          where: spaceId != null ? 'space_id = ?' : null,
          whereArgs: spaceId != null ? [spaceId] : null);

      // 查询入口
      final spaceMaps = await safeQuery('spaces',
          where: spaceId != null ? 'id = ?' : null,
          whereArgs: spaceId != null ? [spaceId] : null);

      // 查询项目分组
      final projectGroupMaps = await safeQuery('project_groups',
          where: spaceId != null ? 'space_id = ?' : null,
          whereArgs: spaceId != null ? [spaceId] : null);

      // 序列化标签（逐条容错）
      final tagMaps = tags.map((t) {
        try {
          return t.toMap();
        } catch (e) {
          final msg = '序列化标签 #${t.id} 出错: $e';
          debugPrint('导出 — $msg');
          errors.add(msg);
          return <String, dynamic>{'id': t.id, 'name': '(序列化错误)'};
        }
      }).toList();

      // 序列化项目（逐条容错）
      final projectMaps = projects.map((p) {
        try {
          return p.toMap();
        } catch (e) {
          final msg = '序列化项目 #${p.id} 出错: $e';
          debugPrint('导出 — $msg');
          errors.add(msg);
          return <String, dynamic>{'id': p.id, 'name': '(序列化错误)'};
        }
      }).toList();

      final data = {
        'version': 3,
        'spaces': spaceMaps,
        'tags': tagMaps,
        'projects': projectMaps,
        'entries': entryMaps,
        'entry_tags': entryTagMaps,
        'attribute_tags': attributeTagMaps,
        'entry_attribute_tags': entryAttributeTagMaps,
        'attribute_tag_groups': attributeTagGroupMaps,
        'project_groups': projectGroupMaps,
        if (errors.isNotEmpty) '_export_errors': errors,
      };

      // JSON 编码——先用普通编码试，不行就简化
      String jsonStr;
      try {
        jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      } catch (e) {
        debugPrint('导出 — 缩进编码失败，尝试无缩进编码: $e');
        errors.add('缩进编码失败: $e');
        try {
          jsonStr = jsonEncode(data); // 无缩进，更轻量
        } catch (e2) {
          debugPrint('导出 — 无缩进编码也失败: $e2');
          errors.add('无缩进编码也失败: $e2');
          // 最后手段：只导出 entries 表
          final minimalData = {
            'version': 3,
            'entries': entryMaps,
            '_export_errors': errors,
            '_note': '完整导出失败，仅导出 entries 表',
          };
          jsonStr = jsonEncode(minimalData);
        }
      }

      return jsonStr;
    } catch (e) {
      final msg = '导出整体异常: $e';
      debugPrint('导出 — $msg');
      // 返回错误信息而非抛出，让调用方能显示有用信息
      return jsonEncode({
        'version': 3,
        '_export_fatal_error': '$e',
        '_export_errors': errors,
      });
    }
  }

  /// 从 JSON 导入数据（先清空所有表，再写入）
  Future<void> importFromJson(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final db = await database;

    await db.transaction((txn) async {
      // 清空所有表
      await txn.delete('entry_attribute_tags');
      await txn.delete('entry_tags');
      await txn.delete('entries');
      await txn.delete('tags');
      await txn.delete('attribute_tags');
      await txn.delete('attribute_tag_groups');
      await txn.delete('projects');
      await txn.delete('project_groups');
      await txn.delete('spaces');

      // 导入入口
      final spacesList = data['spaces'] as List<dynamic>? ?? [];
      for (final item in spacesList) {
        await txn.insert('spaces', item as Map<String, dynamic>);
      }

      // 导入树状标签
      final tagList = data['tags'] as List<dynamic>? ?? [];
      for (final item in tagList) {
        await txn.insert('tags', item as Map<String, dynamic>);
      }

      // 导入项目分组
      final pgList = data['project_groups'] as List<dynamic>? ?? [];
      for (final item in pgList) {
        await txn.insert('project_groups', item as Map<String, dynamic>);
      }

      // 导入项目
      final projectList = data['projects'] as List<dynamic>? ?? [];
      for (final item in projectList) {
        await txn.insert('projects', item as Map<String, dynamic>);
      }

      // 导入属性标签分组
      final atgList = data['attribute_tag_groups'] as List<dynamic>? ?? [];
      for (final item in atgList) {
        await txn.insert('attribute_tag_groups', item as Map<String, dynamic>);
      }

      // 导入属性标签
      final atList = data['attribute_tags'] as List<dynamic>? ?? [];
      for (final item in atList) {
        await txn.insert('attribute_tags', item as Map<String, dynamic>);
      }

      // 导入记录
      final entryList = data['entries'] as List<dynamic>? ?? [];
      for (final item in entryList) {
        await txn.insert('entries', item as Map<String, dynamic>);
      }

      // 导入树状标签关联
      final etList = data['entry_tags'] as List<dynamic>? ?? [];
      for (final item in etList) {
        await txn.insert('entry_tags', item as Map<String, dynamic>);
      }

      // 导入属性标签关联
      final eatList = data['entry_attribute_tags'] as List<dynamic>? ?? [];
      for (final item in eatList) {
        await txn.insert('entry_attribute_tags', item as Map<String, dynamic>);
      }
    });
  }

  // ==================== Excel 导出 ====================

  /// 获取记录及标签路径（用于 Excel 导出）
  Future<List<Map<String, dynamic>>> getAllEntriesWithTagPaths({int? spaceId}) async {
    final entries = await getAllEntries(spaceId: spaceId);
    final result = <Map<String, dynamic>>[];

    for (final entry in entries) {
      final tagPaths = <String>[];
      for (final tag in entry.tags) {
        final path = await _getTagPath(tag.id!);
        tagPaths.add(path);
      }

      result.add({
        'title': entry.title,
        'content': entry.content,
        'created_at': entry.createdAt,
        'updated_at': entry.updatedAt,
        'tags': tagPaths,
        'project': entry.projectName,
        'attribute_tags': entry.attributeTags.map((at) => at.name).toList(),
      });
    }

    return result;
  }

  /// 获取树状标签的完整路径
  Future<String> _getTagPath(int tagId) async {
    final db = await database;
    final parts = <String>[];
    int? currentId = tagId;

    while (currentId != null) {
      final maps = await db.query('tags',
          where: 'id = ?', whereArgs: [currentId]);
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
