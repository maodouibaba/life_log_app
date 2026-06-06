import 'package:sqflite/sqflite.dart';

/// Web 专用：内存数据库
/// 实现 sqflite 的 Database 接口，用内存 Lists 模拟 SQLite
class WebDatabase implements Database {
  final Map<String, List<Map<String, Object?>>> _tables = {};
  int _nextId = 1;

  // ==================== Schema 管理 ====================

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    final createMatch =
        RegExp(r'CREATE TABLE\s+(?:IF NOT EXISTS\s+)?(\w+)', caseSensitive: false)
            .firstMatch(sql);
    if (createMatch != null) {
      _tables.putIfAbsent(createMatch.group(1)!, () => []);
    }
  }

  @override
  Future<void> close() async {
    _tables.clear();
    _isOpen = false;
  }

  bool _isOpen = true;

  @override
  bool get isOpen => _isOpen;

  @override
  String get path => 'in_memory';

  @override
  Database get database => this;

  // ==================== 查询 ====================

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    var rows = _tables[table] ?? <Map<String, Object?>>[];
    var result = rows.map((r) => Map<String, Object?>.from(r)).toList();

    if (where != null && where.isNotEmpty) {
      result = result.where((row) => _matchWhere(row, where, whereArgs)).toList();
    }

    if (orderBy != null && orderBy.isNotEmpty) {
      final parts = orderBy.split(' ');
      final col = parts[0].replaceAll(RegExp(r'\w+\.'), '');
      final desc = parts.length > 1 && parts[1].toUpperCase() == 'DESC';
      result.sort((a, b) {
        final va = a[col], vb = b[col];
        if (identical(va, vb)) return 0;
        if (va == null) return desc ? 1 : -1;
        if (vb == null) return desc ? -1 : 1;
        final cmp = va.toString().compareTo(vb.toString());
        return desc ? -cmp : cmp;
      });
    }

    if (offset != null && offset > 0 && offset < result.length) {
      result = result.sublist(offset);
    }
    if (limit != null && limit < result.length) {
      result = result.sublist(0, limit);
    }
    if (columns != null && columns.isNotEmpty) {
      result = result.map((row) => Map<String, Object?>.fromEntries(
            row.entries.where((e) => columns.contains(e.key)),
          )).toList();
    }
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
      String sql, [List<Object?>? arguments]) async {
    final fromMatch =
        RegExp(r'FROM\s+(\w+)', caseSensitive: false).firstMatch(sql);
    if (fromMatch == null) return [];
    final mainTable = fromMatch.group(1)!;
    final tableAlias =
        RegExp(r'FROM\s+\w+\s+(\w+)', caseSensitive: false).firstMatch(sql)?.group(1);

    // 提取 WHERE 和 ORDER BY
    var whereClause = _extractWhere(sql, arguments, tableAlias);
    final orderBy = _extractOrderBy(sql, tableAlias);

    // ---- JOIN 处理 ----
    // 解析 INNER JOIN ... ON ... 模式
    final joinMatch = RegExp(
        r'INNER\s+JOIN\s+(\w+)\s+(\w+)\s+ON\s+(\w+)\.(\w+)\s*=\s*(\w+)\.(\w+)',
        caseSensitive: false).firstMatch(sql);

    if (joinMatch != null) {
      final joinTable = joinMatch.group(1)!;      // 关联表名 e.g. entry_tags
      final joinAlias = joinMatch.group(2)!;        // 关联表别名 e.g. et
      final mainCol = joinMatch.group(4)!;          // 主表连接列 e.g. id
      final joinCol = joinMatch.group(6)!;           // 关联表连接列 e.g. tag_id

      // 改造 WHERE：去掉关联表别名，只保留关联表的条件
      var joinWhere = whereClause ?? '';
      if (joinAlias.isNotEmpty) {
        joinWhere = joinWhere.replaceAll('$joinAlias.', '');
      }

      // 先查关联表（如 entry_tags）获取主表 ID 列表
      final joinRows = await query(joinTable,
          where: joinWhere.isNotEmpty ? joinWhere : null,
          whereArgs: null);

      if (joinRows.isEmpty) return [];

      final mainIds = joinRows
          .map((r) => r[joinCol])
          .where((id) => id != null)
          .toSet();

      if (mainIds.isEmpty) return [];

      // 再查主表，用 ID 列表过滤
      final idList = mainIds.map((id) => id.toString()).join(',');
      return query(mainTable,
          where: '$mainCol IN ($idList)',
          orderBy: orderBy);
    }

    // ---- 无 JOIN 的简单查询 ----
    final rows = await query(mainTable, where: whereClause, orderBy: orderBy);

    // 处理 LEFT JOIN project_name
    if (sql.toUpperCase().contains('PROJECT_NAME')) {
      for (final row in rows) {
        final pid = row['project_id'];
        if (pid != null) {
          final pRows = await query('projects', where: 'id = ?', whereArgs: [pid]);
          if (pRows.isNotEmpty) row['project_name'] = pRows.first['name'];
        }
      }
    }
    return rows;
  }

  String? _extractWhere(String sql, List<Object?>? arguments, String? alias) {
    final whereMatch = RegExp(r'WHERE\s+(.+?)(?:ORDER\s+BY|LIMIT|GROUP\s+BY|$)',
        caseSensitive: false, dotAll: true).firstMatch(sql);
    if (whereMatch == null) return null;
    var clause = whereMatch.group(1)!.trim();
    if (alias != null) clause = clause.replaceAll('$alias.', '');
    clause = clause.replaceAll(RegExp(r'e\.'), '');
    clause = clause.replaceAll(RegExp(r't\.'), '');
    clause = clause.replaceAll(RegExp(r'at\.'), '');

    // 替换参数占位符
    if (arguments != null && arguments.isNotEmpty) {
      int idx = 0;
      clause = clause.replaceAllMapped('?', (_) {
        final arg = arguments[idx];
        idx++;
        if (arg == null) return 'NULL';
        if (arg is num) return '$arg';
        return "'${arg.toString().replaceAll("'", "''")}'";
      });
    }
    return clause;
  }

  String? _extractOrderBy(String sql, String? alias) {
    final m = RegExp(r'ORDER\s+BY\s+(.+?)(?:LIMIT|$)',
        caseSensitive: false, dotAll: true).firstMatch(sql);
    if (m == null) return null;
    var clause = m.group(1)!.trim();
    if (alias != null) clause = clause.replaceAll('$alias.', '');
    clause = clause.replaceAll(RegExp(r'\w+\.'), '');
    return clause;
  }

  // ==================== 写入 ====================

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    _tables.putIfAbsent(table, () => []);
    final row = Map<String, Object?>.from(values);
    if (row['id'] == null) row['id'] = _nextId++;
    _tables[table]!.add(row);
    return row['id'] as int;
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    final m = RegExp(r'INTO\s+(\w+)', caseSensitive: false).firstMatch(sql);
    if (m == null) return -1;
    return insert(m.group(1)!, {});
  }

  @override
  Future<int> update(String table, Map<String, Object?> values,
      {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async {
    final rows = _tables[table];
    if (rows == null) return 0;
    int count = 0;
    for (final row in rows) {
      if (where == null || _matchWhere(row, where, whereArgs)) {
        row.addAll(Map<String, Object?>.from(values));
        count++;
      }
    }
    return count;
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    return 0;
  }

  @override
  Future<int> delete(String table,
      {String? where, List<Object?>? whereArgs}) async {
    final rows = _tables[table];
    if (rows == null) return 0;
    if (where == null || where.isEmpty) {
      _tables[table] = [];
      return rows.length;
    }
    final before = rows.length;
    _tables[table] = rows.where((row) => !_matchWhere(row, where, whereArgs)).toList();
    return before - _tables[table]!.length;
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    return 0;
  }

  // ==================== 事务 ====================

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
      {bool? exclusive}) async {
    final txn = _WebTransaction(this);
    return action(txn);
  }

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action,
      {bool? exclusive}) async {
    return transaction(action, exclusive: exclusive);
  }

  // ==================== 批量 ====================

  @override
  Batch batch() => _WebBatch(this);

  // ==================== 游标（不支持） ====================

  @override
  Future<QueryCursor> queryCursor(String table,
      {int? bufferSize, List<String>? columns, bool? distinct, String? groupBy,
      String? having, int? limit, int? offset, String? orderBy, String? where,
      List<Object?>? whereArgs}) {
    throw UnimplementedError('queryCursor not supported on web');
  }

  @override
  Future<QueryCursor> rawQueryCursor(String sql, List<Object?>? arguments, {int? bufferSize}) async {
    throw UnimplementedError('rawQueryCursor not supported on web');
  }

  // ==================== Dev 方法（空实现） ====================

  @override
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) async => Future<T>.value(null as T);

  @override
  Future<T> devInvokeSqlMethod<T>(String method, String sql, [List<Object?>? arguments]) async => Future<T>.value(null as T);

  // ==================== WHERE 解析 ====================

  bool _matchWhere(Map<String, Object?> row, String where, List<Object?>? args) {
    int argIdx = 0;
    Object? nextArg() => (args != null && argIdx < args.length) ? args[argIdx++] : null;

    for (var cond in where.split(RegExp(r'\s+AND\s+'))) {
      cond = cond.trim();
      if (cond.isEmpty) continue;

      if (cond.toUpperCase().endsWith('IS NULL')) {
        final col = _col(cond.replaceFirst(RegExp(r'\s+IS\s+NULL\s*$', caseSensitive: false), ''));
        if (row[col] != null) return false; continue;
      }
      if (cond.toUpperCase().endsWith('IS NOT NULL')) {
        final col = _col(cond.replaceFirst(RegExp(r'\s+IS\s+NOT\s+NULL\s*$', caseSensitive: false), ''));
        if (row[col] == null) return false; continue;
      }

      final inMatch = RegExp(r'(\w+(?:\.\w+)?)\s+IN\s+\(([^)]+)\)', caseSensitive: false).firstMatch(cond);
      if (inMatch != null) {
        final col = _col(inMatch.group(1)!);
        final vals = inMatch.group(2)!.split(',').map((s) {
          final v = s.trim();
          return v == '?' ? nextArg() : _literal(v);
        }).toList();
        if (!vals.contains(row[col])) return false;
        continue;
      }

      final opMatch = RegExp(r'(\w+(?:\.\w+)?)\s*([=!<>]+)\s*(.+)').firstMatch(cond);
      if (opMatch == null) continue;
      final col = _col(opMatch.group(1)!);
      final op = opMatch.group(2)!;
      var valStr = opMatch.group(3)!.trim();
      final expected = valStr == '?' ? nextArg() : _literal(valStr);
      final actual = row[col];

      switch (op) {
        case '=': if (actual?.toString() != expected?.toString()) return false; break;
        case '!=': case '<>': if (actual?.toString() == expected?.toString()) return false; break;
        case '>': if (_cmp(actual, expected) <= 0) return false; break;
        case '<': if (_cmp(actual, expected) >= 0) return false; break;
        case '>=': if (_cmp(actual, expected) < 0) return false; break;
        case '<=': if (_cmp(actual, expected) > 0) return false; break;
      }
    }
    return true;
  }

  String _col(String s) => s.contains('.') ? s.split('.').last.trim() : s.trim();
  Object? _literal(String s) {
    if (s == 'NULL') return null;
    if (s.startsWith("'") && s.endsWith("'")) return s.substring(1, s.length - 1);
    return int.tryParse(s) ?? double.tryParse(s) ?? s;
  }
  int _cmp(Object? a, Object? b) {
    if (a is num && b is num) return a.compareTo(b);
    return (a?.toString() ?? '').compareTo(b?.toString() ?? '');
  }
}

class _WebTransaction implements Transaction {
  final WebDatabase _db;
  _WebTransaction(this._db);

  @override bool get isOpen => true;
  @override Database get database => _db;

  @override Future<void> execute(String sql, [List<Object?>? arguments]) async => _db.execute(sql, arguments);
  @override Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async =>
      _db.insert(table, values);
  @override Future<int> update(String table, Map<String, Object?> values,
      {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async =>
      _db.update(table, values, where: where, whereArgs: whereArgs);
  @override Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async =>
      _db.delete(table, where: where, whereArgs: whereArgs);
  @override Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs,
      String? groupBy, String? having, String? orderBy, int? limit, int? offset}) async =>
      _db.query(table, columns: columns, where: where, whereArgs: whereArgs, orderBy: orderBy);
  @override Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async =>
      _db.rawQuery(sql, arguments);
  @override Future<int> rawInsert(String sql, [List<Object?>? arguments]) async => _db.rawInsert(sql, arguments);
  @override Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async => 0;
  @override Future<int> rawDelete(String sql, [List<Object?>? arguments]) async => 0;
  @override Future<QueryCursor> queryCursor(String table,
      {int? bufferSize, List<String>? columns, bool? distinct, String? groupBy,
      String? having, int? limit, int? offset, String? orderBy, String? where,
      List<Object?>? whereArgs}) =>
      throw UnimplementedError();
  @override Future<QueryCursor> rawQueryCursor(String sql, List<Object?>? arguments, {int? bufferSize}) =>
      throw UnimplementedError();
  @override Future<T> devInvokeMethod<T>(String method, [Object? arguments]) async => null as T;
  @override Future<T> devInvokeSqlMethod<T>(String method, String sql, [List<Object?>? arguments]) async => null as T;
  @override Batch batch() => _WebBatch(_db);
}

class _WebBatch extends Batch {
  final WebDatabase _db;
  final List<Future<void> Function()> _ops = [];
  _WebBatch(this._db);

  @override
  int get length => _ops.length;

  @override void execute(String sql, [List<Object?>? arguments]) {}
  @override void insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) {
    _ops.add(() => _db.insert(table, values).then((_) {}));
  }
  @override void update(String table, Map<String, Object?> values,
      {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) {
    _ops.add(() => _db.update(table, values, where: where, whereArgs: whereArgs).then((_) {}));
  }
  @override void delete(String table, {String? where, List<Object?>? whereArgs}) {
    _ops.add(() => _db.delete(table, where: where, whereArgs: whereArgs).then((_) {}));
  }
  @override
  Future<List<Object?>> apply({bool? continueOnError, bool? noResult}) async {
    return commit(continueOnError: continueOnError, noResult: noResult);
  }
  @override void query(String table,
      {bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs,
      String? groupBy, String? having, String? orderBy, int? limit, int? offset}) {}
  @override void rawDelete(String sql, [List<Object?>? arguments]) {}
  @override void rawInsert(String sql, [List<Object?>? arguments]) {}
  @override void rawUpdate(String sql, [List<Object?>? arguments]) {}
  @override void rawQuery(String sql, [List<Object?>? arguments]) {}

  @override
  Future<List<Object?>> commit({bool? continueOnError, bool? exclusive, bool? noResult}) async {
    for (final op in _ops) {
      try {
        await op();
      } catch (_) {
        if (continueOnError != true) rethrow;
      }
    }
    _ops.clear();
    return [];
  }
}
