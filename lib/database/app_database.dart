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
import '../models/entry_template.dart';
import '../models/checkin_item.dart';
import '../models/checkin_record.dart';
import '../services/photo_service.dart';
import 'web_database.dart';

/// 本地数据库管理类 v3
/// 支持多入口、标题字段、属性标签、项目分组
/// 在 Web 上使用 InMemory 实现
class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  factory AppDatabase() => _instance;
  AppDatabase._internal();

  Database? _database;
  WebDatabase? _webDb;
  bool get _isWeb => kIsWeb;

  /// 获取数据库实例（sqflite 或 Web 内存数据库）
  Future<Database> get database async {
    if (_isWeb) {
      if (_webDb != null) return _webDb!;
      _webDb = WebDatabase();
      await _initWebDatabase(_webDb!);
      return _webDb!;
    }
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化 Web 内存数据库的表和默认数据
  Future<void> _initWebDatabase(WebDatabase db) async {
    await db.execute('''
      CREATE TABLE spaces (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER,
        created_at TEXT NOT NULL,
        space_id INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE project_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        space_id INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        space_id INTEGER NOT NULL DEFAULT 1,
        group_id INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        project_id INTEGER,
        space_id INTEGER NOT NULL DEFAULT 1,
        contact_person TEXT,
        follow_up TEXT,
        photo_filenames TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE entry_tags (
        entry_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (entry_id, tag_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE attribute_tag_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        space_id INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE attribute_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        group_id INTEGER,
        space_id INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE entry_attribute_tags (
        entry_id INTEGER NOT NULL,
        attribute_tag_id INTEGER NOT NULL,
        PRIMARY KEY (entry_id, attribute_tag_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        title TEXT,
        content TEXT NOT NULL DEFAULT '',
        project_id INTEGER,
        contact_person TEXT,
        follow_up TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE template_tags (
        template_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (template_id, tag_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE template_attribute_tags (
        template_id INTEGER NOT NULL,
        attribute_tag_id INTEGER NOT NULL,
        PRIMARY KEY (template_id, attribute_tag_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE checkin_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        space_id INTEGER NOT NULL DEFAULT 1,
        tag_id INTEGER,
        attribute_tag_id INTEGER,
        project_id INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE checkin_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        entry_id INTEGER NOT NULL,
        checkin_date TEXT NOT NULL,
        checkin_time TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    // 创建默认入口
    await db.insert('spaces', {
      'name': '默认',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Database> _initDatabase() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = appDir.path;
    debugPrint('数据库路径：$dbPath');
    final path = join(dbPath, 'life_log.db');

    return await openDatabase(
      path,
      version: 10,
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

    // 记录表（含 title、space_id、contact_person、follow_up、photo_filenames）
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        project_id INTEGER,
        space_id INTEGER NOT NULL DEFAULT 1,
        contact_person TEXT,
        follow_up TEXT,
        photo_filenames TEXT,
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

    // 设置表
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 模板表
    await db.execute('''
      CREATE TABLE templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        title TEXT,
        content TEXT NOT NULL DEFAULT '',
        project_id INTEGER,
        contact_person TEXT,
        follow_up TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE template_tags (
        template_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (template_id, tag_id),
        FOREIGN KEY (template_id) REFERENCES templates(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE template_attribute_tags (
        template_id INTEGER NOT NULL,
        attribute_tag_id INTEGER NOT NULL,
        PRIMARY KEY (template_id, attribute_tag_id),
        FOREIGN KEY (template_id) REFERENCES templates(id) ON DELETE CASCADE,
        FOREIGN KEY (attribute_tag_id) REFERENCES attribute_tags(id) ON DELETE CASCADE
      )
    ''');

    // 打卡事项表
    await db.execute('''
      CREATE TABLE checkin_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        space_id INTEGER NOT NULL DEFAULT 1,
        tag_id INTEGER,
        attribute_tag_id INTEGER,
        project_id INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    // 打卡记录表
    await db.execute('''
      CREATE TABLE checkin_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL,
        entry_id INTEGER NOT NULL,
        checkin_date TEXT NOT NULL,
        checkin_time TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_checkin_records_item ON checkin_records(item_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_checkin_records_date ON checkin_records(checkin_date)');

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

    // v3 → v4：设置表
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }

    // v4 → v5：属性标签和项目增加 sort_order 字段，支持拖拽排序
    if (oldVersion < 5) {
      try { await db.execute('ALTER TABLE attribute_tags ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE projects ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
    }

    // v5 → v6：记录增加 contact_person（对接人）和 follow_up（后续待办）字段
    if (oldVersion < 6) {
      try { await db.execute('ALTER TABLE entries ADD COLUMN contact_person TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE entries ADD COLUMN follow_up TEXT'); } catch (_) {}
    }

    // v6 → v7：确保 contact_person 和 follow_up 列存在（修复全新安装时建表遗漏）
    if (oldVersion < 7) {
      try { await db.execute('ALTER TABLE entries ADD COLUMN contact_person TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE entries ADD COLUMN follow_up TEXT'); } catch (_) {}
    }

    // v7 → v8：增加模板表
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS templates (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          title TEXT,
          content TEXT NOT NULL DEFAULT '',
          project_id INTEGER,
          contact_person TEXT,
          follow_up TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS template_tags (
          template_id INTEGER NOT NULL,
          tag_id INTEGER NOT NULL,
          PRIMARY KEY (template_id, tag_id),
          FOREIGN KEY (template_id) REFERENCES templates(id) ON DELETE CASCADE,
          FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS template_attribute_tags (
          template_id INTEGER NOT NULL,
          attribute_tag_id INTEGER NOT NULL,
          PRIMARY KEY (template_id, attribute_tag_id),
          FOREIGN KEY (template_id) REFERENCES templates(id) ON DELETE CASCADE,
          FOREIGN KEY (attribute_tag_id) REFERENCES attribute_tags(id) ON DELETE CASCADE
        )
      ''');
    }

    // v8 → v9：增加打卡表
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS checkin_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          space_id INTEGER NOT NULL DEFAULT 1,
          tag_id INTEGER,
          attribute_tag_id INTEGER,
          project_id INTEGER,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS checkin_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_id INTEGER NOT NULL,
          entry_id INTEGER NOT NULL,
          checkin_date TEXT NOT NULL,
          checkin_time TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_checkin_records_item ON checkin_records(item_id)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_checkin_records_date ON checkin_records(checkin_date)'); } catch (_) {}
    }

    // v9 → v10：增加 photo_filenames 列
    if (oldVersion < 10) {
      try { await db.execute('ALTER TABLE entries ADD COLUMN photo_filenames TEXT'); } catch (_) {}
    }
  }

  // ==================== 设置持久化 ====================

  /// 读取设置值
  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query('settings',
        where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  /// 写入设置值
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 删除设置
  Future<void> removeSetting(String key) async {
    final db = await database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
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
  /// 同时同步更新已有记录的关联标签
  Future<void> moveTag(int tagId, int? newParentId) async {
    final db = await database;
    final oldParentId = (await db.query('tags',
        columns: ['parent_id'], where: 'id = ?', whereArgs: [tagId]))
        .firstOrNull?['parent_id'] as int?;

    await db.update('tags', {'parent_id': newParentId},
        where: 'id = ?', whereArgs: [tagId]);

    // 同步更新已有记录的标签关联
    await _syncEntryTagsAfterMove(tagId, oldParentId, newParentId);
  }

  /// 重建所有记录的标签关联（修复旧数据中残留的错误祖先标签）
  /// 策略：找出每条记录的叶标签，用当前的祖先链重建
  Future<int> rebuildAllEntryTags() async {
    final db = await database;

    // 获取所有标签的 parent_id 映射
    final allTags = await db.query('tags');
    final parentMap = <int, int?>{};
    for (final t in allTags) {
      parentMap[t['id'] as int] = t['parent_id'] as int?;
    }

    // 获取所有有标签关联的记录
    final entryMaps = await db.rawQuery(
        'SELECT DISTINCT entry_id FROM entry_tags');
    final entryIds = entryMaps.map((m) => m['entry_id'] as int).toList();

    int fixedCount = 0;
    for (final entryId in entryIds) {
      final etMaps = await db.query('entry_tags',
          where: 'entry_id = ?', whereArgs: [entryId]);
      final currentTagIds = etMaps.map((m) => m['tag_id'] as int).toSet();
      if (currentTagIds.isEmpty) continue;

      // 找叶标签（没有任何子标签也在当前集合中的标签）
      final leafTagIds = <int>{};
      for (final tId in currentTagIds) {
        bool hasChild = false;
        for (final otherId in currentTagIds) {
          if (otherId != tId && parentMap[otherId] == tId) {
            hasChild = true;
            break;
          }
        }
        if (!hasChild) leafTagIds.add(tId);
      }

      // 重新计算正确的标签集合
      final correctTagIds = <int>{};
      for (final leafId in leafTagIds) {
        correctTagIds.addAll(_getFullAncestorChain(leafId, parentMap));
      }

      // 检查是否需要更新（有差异才写库）
      if (currentTagIds.length != correctTagIds.length ||
          !currentTagIds.containsAll(correctTagIds)) {
        await db.delete('entry_tags', where: 'entry_id = ?', whereArgs: [entryId]);
        final batch = db.batch();
        for (final newId in correctTagIds) {
          batch.insert('entry_tags',
              {'entry_id': entryId, 'tag_id': newId},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await batch.commit(noResult: true);
        fixedCount++;
      }
    }

    return fixedCount;
  }

  /// 移动标签后，同步更新已有记录的 ancestor 关联
  /// 策略：找出每条记录的叶标签，用新的祖先链重建关联（丢弃旧祖先）
  Future<void> _syncEntryTagsAfterMove(int tagId, int? oldParentId, int? newParentId) async {
    final db = await database;

    // 1. 收集所有受影响的标签（被移动的标签及其所有子标签）
    final affectedTagIds = <int>{};
    await _collectDescendantIds(tagId, affectedTagIds);
    affectedTagIds.add(tagId);

    // 2. 找出所有关联了这些标签的记录
    final ph = affectedTagIds.map((_) => '?').join(',');
    final entryMaps = await db.rawQuery(
      'SELECT DISTINCT entry_id FROM entry_tags WHERE tag_id IN ($ph)',
      affectedTagIds.toList(),
    );
    final entryIds = entryMaps.map((m) => m['entry_id'] as int).toList();
    if (entryIds.isEmpty) return;

    // 3. 获取全部标签的 parent_id 映射（用于重建祖先链）
    final allTags = await db.query('tags');
    final parentMap = <int, int?>{};
    for (final t in allTags) {
      parentMap[t['id'] as int] = t['parent_id'] as int?;
    }

    // 4. 对每条记录重建标签关联
    for (final entryId in entryIds) {
      // 获取该记录当前关联的所有 tag_id
      final etMaps = await db.query('entry_tags',
          where: 'entry_id = ?', whereArgs: [entryId]);
      final currentTagIds = etMaps.map((m) => m['tag_id'] as int).toSet();
      if (currentTagIds.isEmpty) continue;

      // 找出叶标签（在 currentTagIds 中没有任何子标签也在 currentTagIds 中的标签）
      final leafTagIds = <int>{};
      for (final tId in currentTagIds) {
        // 检查 currentTagIds 中是否有标签的 parentId 是 tId
        bool hasChild = false;
        for (final otherId in currentTagIds) {
          if (otherId != tId && parentMap[otherId] == tId) {
            hasChild = true;
            break;
          }
        }
        if (!hasChild) {
          leafTagIds.add(tId);
        }
      }

      // 用每个叶标签重新计算完整祖先链（这样旧的祖先会被自然丢弃）
      final newTagIds = <int>{};
      for (final leafId in leafTagIds) {
        newTagIds.addAll(_getFullAncestorChain(leafId, parentMap));
      }

      // 更新 entry_tags
      await db.delete('entry_tags', where: 'entry_id = ?', whereArgs: [entryId]);
      if (newTagIds.isNotEmpty) {
        final batch = db.batch();
        for (final newId in newTagIds) {
          batch.insert('entry_tags',
              {'entry_id': entryId, 'tag_id': newId},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await batch.commit(noResult: true);
      }
    }
  }

  /// 获取标签及其路径上所有祖先的 ID 集合
  Set<int> _getFullAncestorChain(int tagId, Map<int, int?> parentMap) {
    final result = <int>{tagId};
    int? current = parentMap[tagId];
    while (current != null) {
      result.add(current);
      current = parentMap[current];
    }
    return result;
  }

  /// 递归收集所有子标签 ID
  Future<void> _collectDescendantIds(int parentId, Set<int> result) async {
    final db = await database;
    final children = await db.query('tags',
        columns: ['id'], where: 'parent_id = ?', whereArgs: [parentId]);
    for (final child in children) {
      final id = child['id'] as int;
      result.add(id);
      await _collectDescendantIds(id, result);
    }
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
        where: 'space_id = ?', whereArgs: [spaceId], orderBy: 'sort_order ASC, id ASC');
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

  Future<void> updateAttributeTagSortOrder(int tagId, int sortOrder) async {
    final db = await database;
    await db.update('attribute_tags', {'sort_order': sortOrder},
        where: 'id = ?', whereArgs: [tagId]);
  }

  Future<void> updateProjectSortOrder(int projectId, int sortOrder) async {
    final db = await database;
    await db.update('projects', {'sort_order': sortOrder},
        where: 'id = ?', whereArgs: [projectId]);
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
        where: where, whereArgs: args, orderBy: 'sort_order ASC, id ASC');
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

  // ==================== 模板 CRUD ====================

  /// 获取所有模板
  Future<List<EntryTemplate>> getAllTemplates() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.*, p.name as project_name
      FROM templates t
      LEFT JOIN projects p ON t.project_id = p.id
      ORDER BY t.updated_at DESC
    ''');
    final templates = maps.map((map) => EntryTemplate.fromMap(map)).toList();
    await _enrichTemplates(templates);
    return templates;
  }

  Future<void> _enrichTemplates(List<EntryTemplate> templates) async {
    for (final t in templates) {
      if (t.id == null) continue;
      t.tagIds.addAll(await _getTemplateTagIds(t.id!));
      t.attributeTagIds
          .addAll(await _getTemplateAttributeTagIds(t.id!));
    }
  }

  /// 获取单个模板详情
  Future<EntryTemplate?> getTemplate(int templateId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.*, p.name as project_name
      FROM templates t
      LEFT JOIN projects p ON t.project_id = p.id
      WHERE t.id = ?
    ''', [templateId]);
    if (maps.isEmpty) return null;
    final template = EntryTemplate.fromMap(maps.first);
    template.tagIds.addAll(await _getTemplateTagIds(template.id!));
    template.attributeTagIds
        .addAll(await _getTemplateAttributeTagIds(template.id!));
    return template;
  }

  Future<List<int>> _getTemplateTagIds(int templateId) async {
    final db = await database;
    final maps = await db.query('template_tags',
        where: 'template_id = ?', whereArgs: [templateId]);
    return maps.map((m) => m['tag_id'] as int).toList();
  }

  Future<List<int>> _getTemplateAttributeTagIds(int templateId) async {
    final db = await database;
    final maps = await db.query('template_attribute_tags',
        where: 'template_id = ?', whereArgs: [templateId]);
    return maps.map((m) => m['attribute_tag_id'] as int).toList();
  }

  /// 创建模板
  Future<EntryTemplate> createTemplate(EntryTemplate template) async {
    final db = await database;
    final id = await db.insert('templates', template.toMap());

    // 树状标签关联
    if (template.tagIds.isNotEmpty) {
      final batch = db.batch();
      for (final tagId in template.tagIds) {
        batch.insert('template_tags',
            {'template_id': id, 'tag_id': tagId});
      }
      await batch.commit(noResult: true);
    }

    // 属性标签关联
    if (template.attributeTagIds.isNotEmpty) {
      final batch = db.batch();
      for (final atId in template.attributeTagIds) {
        batch.insert('template_attribute_tags',
            {'template_id': id, 'attribute_tag_id': atId});
      }
      await batch.commit(noResult: true);
    }

    return template.copyWith(id: id);
  }

  /// 更新模板
  Future<void> updateTemplate(int templateId, EntryTemplate template) async {
    final db = await database;
    await db.update('templates', template.toMap(),
        where: 'id = ?', whereArgs: [templateId]);

    // 替换树状标签关联
    await db.delete('template_tags',
        where: 'template_id = ?', whereArgs: [templateId]);
    if (template.tagIds.isNotEmpty) {
      final batch = db.batch();
      for (final tagId in template.tagIds) {
        batch.insert('template_tags',
            {'template_id': templateId, 'tag_id': tagId});
      }
      await batch.commit(noResult: true);
    }

    // 替换属性标签关联
    await db.delete('template_attribute_tags',
        where: 'template_id = ?', whereArgs: [templateId]);
    if (template.attributeTagIds.isNotEmpty) {
      final batch = db.batch();
      for (final atId in template.attributeTagIds) {
        batch.insert('template_attribute_tags',
            {'template_id': templateId, 'attribute_tag_id': atId});
      }
      await batch.commit(noResult: true);
    }
  }

  /// 删除模板
  Future<void> deleteTemplate(int templateId) async {
    final db = await database;
    await db.delete('template_tags',
        where: 'template_id = ?', whereArgs: [templateId]);
    await db.delete('template_attribute_tags',
        where: 'template_id = ?', whereArgs: [templateId]);
    await db.delete('templates', where: 'id = ?', whereArgs: [templateId]);
  }

  // ==================== 打卡 CRUD ====================

  /// 获取入口下所有打卡事项
  Future<List<CheckinItem>> getCheckinItems(int spaceId) async {
    final db = await database;
    final maps = await db.query('checkin_items',
        where: 'space_id = ?',
        whereArgs: [spaceId],
        orderBy: 'sort_order ASC, id ASC');
    return maps.map((map) => CheckinItem.fromMap(map)).toList();
  }

  /// 创建打卡事项
  Future<CheckinItem> createCheckinItem(CheckinItem item) async {
    final db = await database;
    final id = await db.insert('checkin_items', item.toMap());
    return item.copyWith(id: id);
  }

  /// 更新打卡事项
  Future<void> updateCheckinItem(int itemId, CheckinItem item) async {
    final db = await database;
    await db.update('checkin_items', item.toMap(),
        where: 'id = ?', whereArgs: [itemId]);
  }

  /// 删除打卡事项（同时删除关联打卡记录）
  Future<void> deleteCheckinItem(int itemId) async {
    final db = await database;
    await db.delete('checkin_records',
        where: 'item_id = ?', whereArgs: [itemId]);
    await db.delete('checkin_items', where: 'id = ?', whereArgs: [itemId]);
  }

  /// 记录一次打卡
  Future<CheckinRecord> recordCheckin(CheckinRecord record) async {
    final db = await database;
    final id = await db.insert('checkin_records', record.toMap());
    return CheckinRecord(
      id: id,
      itemId: record.itemId,
      entryId: record.entryId,
      checkinDate: record.checkinDate,
      checkinTime: record.checkinTime,
      createdAt: record.createdAt,
    );
  }

  /// 获取某事项在某日期范围内的打卡记录
  Future<List<CheckinRecord>> getCheckinRecords(int itemId,
      {DateTime? start, DateTime? end}) async {
    final db = await database;
    var where = 'item_id = ?';
    final args = <Object?>[itemId];
    if (start != null && end != null) {
      where += ' AND checkin_date >= ? AND checkin_date <= ?';
      args.add(
          '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}');
      args.add(
          '${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}');
    }
    final maps = await db.query('checkin_records',
        where: where, whereArgs: args, orderBy: 'checkin_date DESC');
    return maps.map((map) => CheckinRecord.fromMap(map)).toList();
  }

  /// 获取今日已打卡的事项ID集合
  Future<Set<int>> getTodayCheckinItemIds(int spaceId) async {
    final db = await database;
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final maps = await db.rawQuery('''
      SELECT cr.item_id FROM checkin_records cr
      INNER JOIN checkin_items ci ON cr.item_id = ci.id
      WHERE ci.space_id = ? AND cr.checkin_date = ?
    ''', [spaceId, dateStr]);
    return maps.map((m) => m['item_id'] as int).toSet();
  }

  /// 获取打卡统计
  /// 返回: 每个事项ID → 该月打卡日期集合
  Future<Map<int, Set<String>>> getMonthlyCheckinStats(
      int spaceId, int year, int month) async {
    final db = await database;
    final monthStr =
        '$year-${month.toString().padLeft(2, '0')}';
    final maps = await db.rawQuery('''
      SELECT cr.item_id, cr.checkin_date FROM checkin_records cr
      INNER JOIN checkin_items ci ON cr.item_id = ci.id
      WHERE ci.space_id = ? AND cr.checkin_date LIKE ?
    ''', [spaceId, '$monthStr%']);
    final result = <int, Set<String>>{};
    for (final m in maps) {
      final itemId = m['item_id'] as int;
      final date = m['checkin_date'] as String;
      result.putIfAbsent(itemId, () => {});
      result[itemId]!.add(date);
    }
    return result;
  }

  /// 获取事项的连续打卡天数
  Future<int> getStreakDays(int itemId) async {
    final db = await database;
    final maps = await db.query('checkin_records',
        where: 'item_id = ?',
        whereArgs: [itemId],
        orderBy: 'checkin_date DESC');
    final dates = maps
        .map((m) => m['checkin_date'] as String)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (dates.isEmpty) return 0;
    int streak = 0;
    final today = DateTime.now();
    var checkDate = DateTime(today.year, today.month, today.day);
    for (final d in dates) {
      final dateParts = d.split('-');
      final date =
          DateTime(int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]));
      final diff = checkDate.difference(date).inDays;
      if (diff == 0) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else if (diff == 1) {
        streak++;
        checkDate = date.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// 新增记录（含标签、属性标签、项目关联、照片）
  Future<Entry> createEntry(String content,
      {String? title,
      List<int>? tagIds,
      List<int>? attributeTagIds,
      int? projectId,
      int? spaceId,
      DateTime? createdAt,
      String? contactPerson,
      String? followUp,
      List<String>? photoFilenames}) async {
    final db = await database;
    final now = createdAt ?? DateTime.now();
    final entry = Entry(
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
      projectId: projectId,
      spaceId: spaceId ?? 1,
      contactPerson: contactPerson,
      followUp: followUp,
      photoFilenames: photoFilenames,
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

  /// 获取某条记录的树状标签（两步查询，网络兼容）
  Future<List<Tag>> _getTagsForEntry(int entryId) async {
    final db = await database;
    // 1. 查关联表获取标签 ID
    final etMaps = await db.query('entry_tags',
        where: 'entry_id = ?', whereArgs: [entryId]);
    if (etMaps.isEmpty) return [];
    final tagIds = etMaps.map((m) => m['tag_id'] as int).toList();
    // 2. 根据 ID 查标签
    final ph = tagIds.map((_) => '?').join(',');
    return (await db.query('tags',
        where: 'id IN ($ph)', whereArgs: tagIds,
        orderBy: 'sort_order ASC, id ASC'))
        .map((map) => Tag.fromMap(map)).toList();
  }

  /// 获取某条记录的属性标签（两步查询，网络兼容）
  Future<List<AttributeTag>> _getAttributeTagsForEntry(int entryId) async {
    final db = await database;
    // 1. 查关联表获取属性标签 ID
    final eatMaps = await db.query('entry_attribute_tags',
        where: 'entry_id = ?', whereArgs: [entryId]);
    if (eatMaps.isEmpty) return [];
    final atIds = eatMaps.map((m) => m['attribute_tag_id'] as int).toList();
    // 2. 根据 ID 查属性标签
    final ph = atIds.map((_) => '?').join(',');
    return (await db.query('attribute_tags',
        where: 'id IN ($ph)', whereArgs: atIds,
        orderBy: 'id ASC'))
        .map((map) => AttributeTag.fromMap(map)).toList();
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

  /// 获取所有出现过的不重复对接人姓名
  Future<List<String>> getAllContactPersons({int? spaceId}) async {
    final db = await database;
    final where = spaceId != null ? 'WHERE space_id = ?' : '';
    final args = spaceId != null ? [spaceId] : null;
    final maps = await db.rawQuery('''
      SELECT DISTINCT contact_person FROM entries
      ${spaceId != null ? 'WHERE space_id = ? AND' : 'WHERE'}
      contact_person IS NOT NULL AND contact_person != ''
      ORDER BY contact_person ASC
    ''', args);
    return maps.map((m) => m['contact_person'] as String).toList();
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
    String? contactPerson,
    bool? hasFollowUp,
  }) async {
    // Web 平台：用多步查询替代复杂 SQL，避免 EXISTS 子查询不支持的问题
    if (_isWeb) {
      return _getEntriesByFiltersWeb(
        spaceId: spaceId,
        tagIds: tagIds,
        attributeTagIds: attributeTagIds,
        projectIds: projectIds,
        startDate: startDate,
        endDate: endDate,
        keyword: keyword,
        contactPerson: contactPerson,
        hasFollowUp: hasFollowUp,
      );
    }

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

    // 对接人筛选
    if (contactPerson != null && contactPerson.isNotEmpty) {
      conditions.add('e.contact_person LIKE ?');
      args.add('%$contactPerson%');
    }

    // 有后续待办
    if (hasFollowUp == true) {
      conditions.add('e.follow_up IS NOT NULL AND e.follow_up != \'\'');
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

  /// Web 平台筛选：多步查询 + Dart 内存过滤
  Future<List<Entry>> _getEntriesByFiltersWeb({
    int? spaceId,
    Set<int>? tagIds,
    Set<int>? attributeTagIds,
    Set<int>? projectIds,
    DateTime? startDate,
    DateTime? endDate,
    String? keyword,
    String? contactPerson,
    bool? hasFollowUp,
  }) async {
    // 1. 先获取该空间下所有记录
    var entries = await getAllEntries(spaceId: spaceId);

    // 2. 内存过滤
    if (tagIds != null && tagIds.isNotEmpty) {
      // 获取所有匹配的记录 ID
      final db = await database;
      final ph = tagIds.map((_) => '?').join(',');
      final etMaps = await db.query('entry_tags',
          where: 'tag_id IN ($ph)', whereArgs: tagIds.toList());
      final matchingEntryIds = etMaps.map((m) => m['entry_id'] as int).toSet();
      entries = entries.where((e) => matchingEntryIds.contains(e.id)).toList();
    }

    if (attributeTagIds != null && attributeTagIds.isNotEmpty) {
      final db = await database;
      final ph = attributeTagIds.map((_) => '?').join(',');
      final eatMaps = await db.query('entry_attribute_tags',
          where: 'attribute_tag_id IN ($ph)', whereArgs: attributeTagIds.toList());
      final matchingEntryIds = eatMaps.map((m) => m['entry_id'] as int).toSet();
      entries = entries.where((e) => matchingEntryIds.contains(e.id)).toList();
    }

    if (projectIds != null && projectIds.isNotEmpty) {
      entries = entries.where((e) => projectIds.contains(e.projectId)).toList();
    }

    if (startDate != null && endDate != null) {
      entries = entries.where((e) =>
          e.createdAt.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
          e.createdAt.isBefore(endDate.add(const Duration(days: 1)))).toList();
    }

    if (keyword != null && keyword.isNotEmpty) {
      final kw = keyword.toLowerCase();
      entries = entries.where((e) {
        if (e.title?.toLowerCase().contains(kw) == true) return true;
        if (e.content.toLowerCase().contains(kw)) return true;
        if (e.tags.any((t) => t.name.toLowerCase().contains(kw))) return true;
        if (e.attributeTags.any((at) => at.name.toLowerCase().contains(kw))) return true;
        return false;
      }).toList();
    }

    // 对接人筛选
    if (contactPerson != null && contactPerson.isNotEmpty) {
      final kw = contactPerson.toLowerCase();
      entries = entries
          .where((e) =>
              e.contactPerson?.toLowerCase().contains(kw) == true)
          .toList();
    }

    // 有后续待办
    if (hasFollowUp == true) {
      entries = entries
          .where((e) =>
              e.followUp != null && e.followUp!.isNotEmpty)
          .toList();
    }

    // 按时间倒序
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

  /// 删除记录（同时删除关联照片文件）
  Future<void> deleteEntry(int entryId) async {
    final db = await database;
    // 先获取照片文件名以便删除文件
    final entryMaps = await db.query('entries',
        columns: ['photo_filenames'], where: 'id = ?', whereArgs: [entryId]);
    if (entryMaps.isNotEmpty) {
      final raw = entryMaps.first['photo_filenames'] as String?;
      if (raw != null && raw.isNotEmpty) {
        try {
          final names = (const JsonDecoder().convert(raw) as List<dynamic>)
              .map((e) => e.toString()).toList();
          await PhotoService().deletePhotos(names);
        } catch (_) {}
      }
    }
    await db.delete('entry_tags', where: 'entry_id = ?', whereArgs: [entryId]);
    await db.delete('entry_attribute_tags', where: 'entry_id = ?', whereArgs: [entryId]);
    await db.delete('entries', where: 'id = ?', whereArgs: [entryId]);
  }

  /// 批量删除记录（同时删除关联照片文件）
  Future<void> deleteEntries(List<int> entryIds) async {
    if (entryIds.isEmpty) return;
    final db = await database;
    final placeholders = entryIds.map((_) => '?').join(',');
    // 先获取照片文件名以便删除文件
    final entryMaps = await db.query('entries',
        columns: ['photo_filenames'],
        where: 'id IN ($placeholders)', whereArgs: entryIds);
    for (final m in entryMaps) {
      final raw = m['photo_filenames'] as String?;
      if (raw != null && raw.isNotEmpty) {
        try {
          final names = (const JsonDecoder().convert(raw) as List<dynamic>)
              .map((e) => e.toString()).toList();
          await PhotoService().deletePhotos(names);
        } catch (_) {}
      }
    }
    await db.delete('entry_tags',
        where: 'entry_id IN ($placeholders)', whereArgs: entryIds);
    await db.delete('entry_attribute_tags',
        where: 'entry_id IN ($placeholders)', whereArgs: entryIds);
    await db.delete('entries',
        where: 'id IN ($placeholders)', whereArgs: entryIds);
  }

  /// 更新记录内容、标签、项目、属性标签、对接人、后续待办、照片
  Future<void> updateEntryWithTags(int entryId, String content,
      {String? title,
      List<int>? tagIds,
      List<int>? attributeTagIds,
      int? projectId,
      DateTime? createdAt,
      String? contactPerson,
      String? followUp,
      List<String>? photoFilenames}) async {
    final db = await database;

    final updateData = <String, dynamic>{
      'title': title,
      'content': content,
      'updated_at': DateTime.now().toIso8601String(),
      'project_id': projectId,
      'contact_person': contactPerson,
      'follow_up': followUp,
    };
    if (createdAt != null) {
      updateData['created_at'] = createdAt.toIso8601String();
    }
    if (photoFilenames != null) {
      updateData['photo_filenames'] = photoFilenames.isNotEmpty
          ? const JsonEncoder().convert(photoFilenames)
          : null;
    }

    await db.update(
      'entries',
      updateData,
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

      // 查询模板（每个空间独立）
      final templateMaps = await safeQuery('templates',
          where: spaceId != null ? 'space_id = ?' : null,
          whereArgs: spaceId != null ? [spaceId] : null);

      // 查询打卡事项（每个空间独立）
      final checkinItemMaps = await safeQuery('checkin_items',
          where: spaceId != null ? 'space_id = ?' : null,
          whereArgs: spaceId != null ? [spaceId] : null);

      // 查询打卡记录（无 space_id 关联，全部导出）
      final checkinRecordMaps = await safeQuery('checkin_records');

      // 查询模板关联表
      final templateTagMaps = await safeQuery('template_tags');
      final templateAttributeTagMaps = await safeQuery('template_attribute_tags');

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
        'templates': templateMaps,
        'template_tags': templateTagMaps,
        'template_attribute_tags': templateAttributeTagMaps,
        'checkin_items': checkinItemMaps,
        'checkin_records': checkinRecordMaps,
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

  /// 从 JSON 合并导入数据（保留本地已有数据，合并互补，冲突以更新者为准）
  /// 每条记录逐条容错——单条失败不会导致整体回滚
  Future<Map<String, dynamic>> mergeFromJson(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final db = await database;

    int addedEntries = 0;
    int updatedEntries = 0;
    int addedTags = 0;
    int skippedErrors = 0;
    final errorDetails = <String>[];

    await db.transaction((txn) async {
      // ======== 合并入口 ========
      final incomingSpaces = data['spaces'] as List<dynamic>? ?? [];
      final existingSpaces = await txn.query('spaces');
      final existingSpaceIds = existingSpaces.map((m) => m['id'] as int).toSet();
      for (final item in incomingSpaces) {
        final m = item as Map<String, dynamic>;
        final id = m['id'] as int;
        if (!existingSpaceIds.contains(id)) {
          try {
            await txn.insert('spaces', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('spaces #$id: $e');
          }
        }
      }

      // ======== 合并树状标签 ========
      final incomingTags = data['tags'] as List<dynamic>? ?? [];
      final existingTags = await txn.query('tags');
      final existingTagIds = existingTags.map((m) => m['id'] as int).toSet();
      for (final item in incomingTags) {
        final m = item as Map<String, dynamic>;
        final id = m['id'] as int;
        if (!existingTagIds.contains(id)) {
          try {
            await txn.insert('tags', m, conflictAlgorithm: ConflictAlgorithm.ignore);
            addedTags++;
          } catch (e) {
            skippedErrors++;
            errorDetails.add('tags #$id: $e');
          }
        }
      }

      // ======== 合并项目分组 ========
      final incomingPG = data['project_groups'] as List<dynamic>? ?? [];
      final existingPG = await txn.query('project_groups');
      final existingPGIds = existingPG.map((m) => m['id'] as int).toSet();
      for (final item in incomingPG) {
        final m = item as Map<String, dynamic>;
        if (!existingPGIds.contains(m['id'] as int)) {
          try {
            await txn.insert('project_groups', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('project_groups #${m['id']}: $e');
          }
        }
      }

      // ======== 合并项目 ========
      final incomingProjects = data['projects'] as List<dynamic>? ?? [];
      final existingProjects = await txn.query('projects');
      final existingProjectIds = existingProjects.map((m) => m['id'] as int).toSet();
      for (final item in incomingProjects) {
        final m = item as Map<String, dynamic>;
        if (!existingProjectIds.contains(m['id'] as int)) {
          try {
            await txn.insert('projects', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('projects #${m['id']}: $e');
          }
        }
      }

      // ======== 合并属性标签分组 ========
      final incomingATG = data['attribute_tag_groups'] as List<dynamic>? ?? [];
      final existingATG = await txn.query('attribute_tag_groups');
      final existingATGIds = existingATG.map((m) => m['id'] as int).toSet();
      for (final item in incomingATG) {
        final m = item as Map<String, dynamic>;
        if (!existingATGIds.contains(m['id'] as int)) {
          try {
            await txn.insert('attribute_tag_groups', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('attribute_tag_groups #${m['id']}: $e');
          }
        }
      }

      // ======== 合并属性标签 ========
      final incomingAT = data['attribute_tags'] as List<dynamic>? ?? [];
      final existingAT = await txn.query('attribute_tags');
      final existingATIds = existingAT.map((m) => m['id'] as int).toSet();
      for (final item in incomingAT) {
        final m = item as Map<String, dynamic>;
        if (!existingATIds.contains(m['id'] as int)) {
          try {
            await txn.insert('attribute_tags', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('attribute_tags #${m['id']}: $e');
          }
        }
      }

      // ======== 合并记录（按 updated_at 判断冲突） ========
      final incomingEntries = data['entries'] as List<dynamic>? ?? [];
      final existingEntries = await txn.query('entries');
      final existingEntryMap = <int, Map<String, dynamic>>{};
      for (final e in existingEntries) {
        existingEntryMap[e['id'] as int] = e;
      }

      for (final item in incomingEntries) {
        final m = item as Map<String, dynamic>;
        final id = m['id'] as int;
        try {
          if (existingEntryMap.containsKey(id)) {
            // 冲突：保留 updated_at 更新的那个
            final localStr = existingEntryMap[id]!['updated_at'] as String?;
            final remoteStr = m['updated_at'] as String?;
            if (localStr == null || remoteStr == null) continue;
            final localUpdated = DateTime.parse(localStr);
            final remoteUpdated = DateTime.parse(remoteStr);
            if (remoteUpdated.isAfter(localUpdated)) {
              await txn.update('entries', m, where: 'id = ?', whereArgs: [id]);
              updatedEntries++;
            }
          } else {
            await txn.insert('entries', m, conflictAlgorithm: ConflictAlgorithm.fail);
            addedEntries++;
          }
        } catch (e) {
          skippedErrors++;
          errorDetails.add('entries #$id: $e');
        }
      }

      // ======== 合并记录-树状标签关联 ========
      final incomingET = data['entry_tags'] as List<dynamic>? ?? [];
      final existingET = await txn.query('entry_tags');
      final existingETSet = existingET
          .map((m) => '${m['entry_id']}-${m['tag_id']}')
          .toSet();
      for (final item in incomingET) {
        final m = item as Map<String, dynamic>;
        final key = '${m['entry_id']}-${m['tag_id']}';
        if (!existingETSet.contains(key)) {
          try {
            await txn.insert('entry_tags', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('entry_tags ${m['entry_id']}-${m['tag_id']}: $e');
          }
        }
      }

      // ======== 合并记录-属性标签关联 ========
      final incomingEAT = data['entry_attribute_tags'] as List<dynamic>? ?? [];
      final existingEAT = await txn.query('entry_attribute_tags');
      final existingEATSet = existingEAT
          .map((m) => '${m['entry_id']}-${m['attribute_tag_id']}')
          .toSet();
      for (final item in incomingEAT) {
        final m = item as Map<String, dynamic>;
        final key = '${m['entry_id']}-${m['attribute_tag_id']}';
        if (!existingEATSet.contains(key)) {
          try {
            await txn.insert('entry_attribute_tags', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('entry_attribute_tags ${m['entry_id']}-${m['attribute_tag_id']}: $e');
          }
        }
      }

      // ======== 合并模板 ========
      final incomingTemplates = data['templates'] as List<dynamic>? ?? [];
      final existingTemplates = await txn.query('templates');
      final existingTemplateIds = existingTemplates.map((m) => m['id'] as int).toSet();
      for (final item in incomingTemplates) {
        final m = item as Map<String, dynamic>;
        if (!existingTemplateIds.contains(m['id'] as int)) {
          try {
            await txn.insert('templates', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('templates #${m['id']}: $e');
          }
        }
      }

      // ======== 合并模板-树状标签关联 ========
      final incomingTT = data['template_tags'] as List<dynamic>? ?? [];
      final existingTT = await txn.query('template_tags');
      final existingTTSet = existingTT
          .map((m) => '${m['template_id']}-${m['tag_id']}')
          .toSet();
      for (final item in incomingTT) {
        final m = item as Map<String, dynamic>;
        final key = '${m['template_id']}-${m['tag_id']}';
        if (!existingTTSet.contains(key)) {
          try {
            await txn.insert('template_tags', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('template_tags ${m['template_id']}-${m['tag_id']}: $e');
          }
        }
      }

      // ======== 合并模板-属性标签关联 ========
      final incomingTAT = data['template_attribute_tags'] as List<dynamic>? ?? [];
      final existingTAT = await txn.query('template_attribute_tags');
      final existingTATSet = existingTAT
          .map((m) => '${m['template_id']}-${m['attribute_tag_id']}')
          .toSet();
      for (final item in incomingTAT) {
        final m = item as Map<String, dynamic>;
        final key = '${m['template_id']}-${m['attribute_tag_id']}';
        if (!existingTATSet.contains(key)) {
          try {
            await txn.insert('template_attribute_tags', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('template_attribute_tags ${m['template_id']}-${m['attribute_tag_id']}: $e');
          }
        }
      }

      // ======== 合并打卡事项 ========
      final incomingCI = data['checkin_items'] as List<dynamic>? ?? [];
      final existingCI = await txn.query('checkin_items');
      final existingCIIds = existingCI.map((m) => m['id'] as int).toSet();
      for (final item in incomingCI) {
        final m = item as Map<String, dynamic>;
        if (!existingCIIds.contains(m['id'] as int)) {
          try {
            await txn.insert('checkin_items', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('checkin_items #${m['id']}: $e');
          }
        }
      }

      // ======== 合并打卡记录 ========
      final incomingCR = data['checkin_records'] as List<dynamic>? ?? [];
      final existingCR = await txn.query('checkin_records');
      final existingCRSet = existingCR
          .map((m) => '${m['item_id']}-${m['entry_id']}-${m['checkin_date']}')
          .toSet();
      for (final item in incomingCR) {
        final m = item as Map<String, dynamic>;
        final key = '${m['item_id']}-${m['entry_id']}-${m['checkin_date']}';
        if (!existingCRSet.contains(key)) {
          try {
            await txn.insert('checkin_records', m, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (e) {
            skippedErrors++;
            errorDetails.add('checkin_records ${m['item_id']}-${m['entry_id']}: $e');
          }
        }
      }
    });

    // 如有错误，打印日志辅助排查
    if (errorDetails.isNotEmpty) {
      debugPrint('=== mergeFromJson 合并异常汇总 ===');
      for (final err in errorDetails) {
        debugPrint('  $err');
      }
    }

    return {
      'added_entries': addedEntries,
      'updated_entries': updatedEntries,
      'added_tags': addedTags,
      'skipped_errors': skippedErrors,
      if (errorDetails.isNotEmpty) 'error_details': errorDetails,
    };
  }

  /// 从 JSON 导入数据（先清空所有表，再写入）
  Future<void> importFromJson(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final db = await database;

    await db.transaction((txn) async {
      // 清空所有表
      await txn.delete('checkin_records');
      await txn.delete('checkin_items');
      await txn.delete('template_attribute_tags');
      await txn.delete('template_tags');
      await txn.delete('templates');
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

      // 导入模板
      final templateList = data['templates'] as List<dynamic>? ?? [];
      for (final item in templateList) {
        await txn.insert('templates', item as Map<String, dynamic>);
      }

      // 导入模板-树状标签关联
      final ttList = data['template_tags'] as List<dynamic>? ?? [];
      for (final item in ttList) {
        await txn.insert('template_tags', item as Map<String, dynamic>);
      }

      // 导入模板-属性标签关联
      final tatList = data['template_attribute_tags'] as List<dynamic>? ?? [];
      for (final item in tatList) {
        await txn.insert('template_attribute_tags', item as Map<String, dynamic>);
      }

      // 导入打卡事项
      final ciList = data['checkin_items'] as List<dynamic>? ?? [];
      for (final item in ciList) {
        await txn.insert('checkin_items', item as Map<String, dynamic>);
      }

      // 导入打卡记录
      final crList = data['checkin_records'] as List<dynamic>? ?? [];
      for (final item in crList) {
        await txn.insert('checkin_records', item as Map<String, dynamic>);
      }
    });
  }

  // ==================== Excel 导出 ====================

  /// 获取记录及标签路径（用于 Excel 导出）
  Future<List<Map<String, dynamic>>> getAllEntriesWithTagPaths({int? spaceId}) async {
    final entries = await getAllEntries(spaceId: spaceId);
    return _enrichToTagPaths(entries);
  }

  /// 按日期范围获取记录及标签路径（用于 Excel 导出）
  Future<List<Map<String, dynamic>>> getEntriesWithTagPathsByDateRange(
      DateTime start, DateTime end, {int? spaceId}) async {
    final entries = await getEntriesByDateRange(start, end, spaceId: spaceId);
    return _enrichToTagPaths(entries);
  }

  /// 将记录列表转换为含标签路径的导出格式
  Future<List<Map<String, dynamic>>> _enrichToTagPaths(List<Entry> entries) async {
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
        'contact_person': entry.contactPerson ?? '',
        'follow_up': entry.followUp ?? '',
        'photo_filenames': entry.photoFilenames,
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
