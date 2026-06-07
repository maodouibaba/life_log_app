import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../database/app_database.dart';

/// 坚果云 WebDAV 连接配置
class SyncConfig {
  final String url;
  final String username;
  final String password;

  SyncConfig({
    required this.url,
    required this.username,
    required this.password,
  });

  /// 规范化 URL（确保以 / 结尾）
  String get fullUrl {
    final u = url.trim();
    return u.endsWith('/') ? u : '$u/';
  }

  /// Basic Auth 头（第三方应用密码作为密码）
  String get basicAuth =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';
}

/// 云端备份文件信息
class RemoteFile {
  final String name;
  final int size;
  final DateTime modified;

  RemoteFile({
    required this.name,
    required this.size,
    required this.modified,
  });
}

/// WebDAV 同步服务
class SyncService {
  static const String _dirName = '生活记录备份';
  static const String _prefix = 'sync_';

  // ==================== 设置持久化 ====================

  /// 读取配置，未配置时返回 null
  static Future<SyncConfig?> loadConfig() async {
    final db = AppDatabase();
    try {
      final url = await db.getSetting('${_prefix}url');
      final username = await db.getSetting('${_prefix}username');
      final password = await db.getSetting('${_prefix}password');
      if (url == null || username == null || password == null) return null;
      if (url.isEmpty || username.isEmpty || password.isEmpty) return null;
      return SyncConfig(url: url, username: username, password: password);
    } catch (_) {
      return null;
    }
  }

  /// 保存配置
  static Future<void> saveConfig(SyncConfig config) async {
    final db = AppDatabase();
    await db.setSetting('${_prefix}url', config.url);
    await db.setSetting('${_prefix}username', config.username);
    await db.setSetting('${_prefix}password', config.password);
  }

  /// 清除配置
  static Future<void> clearConfig() async {
    final db = AppDatabase();
    await db.removeSetting('${_prefix}url');
    await db.removeSetting('${_prefix}username');
    await db.removeSetting('${_prefix}password');
  }

  // ==================== WebDAV 操作 ====================

  /// 测试 WebDAV 连接是否正常
  static Future<bool> testConnection(SyncConfig config) async {
    final client = http.Client();
    try {
      final uri = Uri.parse(config.fullUrl);
      final req = http.Request('PROPFIND', uri);
      req.headers['Authorization'] = config.basicAuth;
      req.headers['Depth'] = '0';
      final resp = await client
          .send(req)
          .timeout(const Duration(seconds: 15));
      return resp.statusCode == 207 || resp.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// 确保云端同步目录存在
  static Future<void> _ensureDir(http.Client client, SyncConfig config) async {
    final uri =
        Uri.parse('${config.fullUrl}${Uri.encodeComponent(_dirName)}');
    try {
      final req = http.Request('MKCOL', uri);
      req.headers['Authorization'] = config.basicAuth;
      await client.send(req);
    } catch (_) {
      // 目录已存在时服务器返回 405 Method Not Allowed，忽略
    }
  }

  /// 列出云端所有备份文件
  static Future<List<RemoteFile>> listBackups(SyncConfig config) async {
    final client = http.Client();
    try {
      await _ensureDir(client, config);

      final dirUrl =
          '${config.fullUrl}${Uri.encodeComponent(_dirName)}/';
      final req = http.Request('PROPFIND', Uri.parse(dirUrl));
      req.headers['Authorization'] = config.basicAuth;
      req.headers['Depth'] = '1';

      final resp = await client
          .send(req)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 207) {
        throw WebDavException('列出备份失败', resp.statusCode);
      }

      final body = await resp.stream.bytesToString();
      return _parsePropfind(body);
    } finally {
      client.close();
    }
  }

  /// 上传备份到坚果云
  /// 自动生成带时间戳的文件名，不会覆盖已有文件
  static Future<String> uploadBackup(SyncConfig config) async {
    final client = http.Client();
    try {
      await _ensureDir(client, config);

      // 导出本地数据
      final db = AppDatabase();
      final jsonContent = await db.exportToJson();

      // 生成文件名：生活记录备份_20260607_1430.json
      final now = DateTime.now();
      final ts =
          '${now.year}${_pad2(now.month)}${_pad2(now.day)}_${_pad2(now.hour)}${_pad2(now.minute)}';
      final fileName = '生活记录备份_$ts.json';

      // 上传
      final fileUrl =
          '${config.fullUrl}${Uri.encodeComponent(_dirName)}/${Uri.encodeComponent(fileName)}';
      final putReq = http.Request('PUT', Uri.parse(fileUrl));
      putReq.headers['Authorization'] = config.basicAuth;
      putReq.headers['Content-Type'] = 'application/json; charset=utf-8';
      putReq.body = jsonContent;

      final putResp = await client
          .send(putReq)
          .timeout(const Duration(seconds: 30));

      if (putResp.statusCode < 200 || putResp.statusCode >= 300) {
        throw WebDavException('上传失败', putResp.statusCode);
      }

      return fileName;
    } finally {
      client.close();
    }
  }

  /// 从坚果云下载指定备份文件的 JSON 文本
  static Future<String> downloadBackup(
      SyncConfig config, String fileName) async {
    final client = http.Client();
    try {
      final fileUrl =
          '${config.fullUrl}${Uri.encodeComponent(_dirName)}/${Uri.encodeComponent(fileName)}';
      final req = http.Request('GET', Uri.parse(fileUrl));
      req.headers['Authorization'] = config.basicAuth;

      final resp = await client
          .send(req)
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode != 200) {
        throw WebDavException('下载失败', resp.statusCode);
      }

      return await resp.stream.bytesToString();
    } finally {
      client.close();
    }
  }

  /// 删除云端指定备份文件
  static Future<void> deleteBackup(
      SyncConfig config, String fileName) async {
    final client = http.Client();
    try {
      final fileUrl =
          '${config.fullUrl}${Uri.encodeComponent(_dirName)}/${Uri.encodeComponent(fileName)}';
      final req = http.Request('DELETE', Uri.parse(fileUrl));
      req.headers['Authorization'] = config.basicAuth;

      final resp = await client
          .send(req)
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw WebDavException('删除失败', resp.statusCode);
      }
    } finally {
      client.close();
    }
  }

  // ==================== XML 解析 ====================

  /// 解析 PROPFIND 返回的 XML 多状态响应，提取文件列表
  static List<RemoteFile> _parsePropfind(String xml) {
    final files = <RemoteFile>[];
    final doc = XmlDocument.parse(xml);
    final responses = doc.findAllElements('response');

    for (final resp in responses) {
      final propstat = resp.findElements('propstat').firstOrNull;
      if (propstat == null) continue;

      final prop = propstat.findElements('prop').firstOrNull;
      if (prop == null) continue;

      // 跳过目录
      final rt = prop.findElements('resourcetype').firstOrNull;
      if (rt != null && rt.findElements('collection').isNotEmpty) continue;

      // 文件名
      final dn = prop.findElements('displayname').firstOrNull;
      final name = dn?.innerText ?? '';
      final cleanName = _normalizeFileName(name);
      if (cleanName.isEmpty || cleanName == _dirName) continue;
      if (!cleanName.endsWith('.json')) continue;

      // 文件大小
      int size = 0;
      final cl = prop.findElements('getcontentlength').firstOrNull;
      if (cl != null) size = int.tryParse(cl.innerText) ?? 0;

      // 修改时间
      DateTime modified = DateTime.now();
      final lm = prop.findElements('getlastmodified').firstOrNull;
      if (lm != null) {
        final parsed = _parseHttpDate(lm.innerText);
        if (parsed != null) modified = parsed;
      }

      files.add(RemoteFile(name: cleanName, size: size, modified: modified));
    }

    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  /// 从显示名提取干净的文件名
  static String _normalizeFileName(String raw) {
    final parts = raw.split('/');
    return parts.last;
  }

  /// 解析 HTTP 日期格式 "Sat, 07 Jun 2026 06:00:00 GMT"
  static DateTime? _parseHttpDate(String dateStr) {
    try {
      // 去掉星期前缀和尾部 " GMT"
      final cleaned = dateStr
          .replaceAll(RegExp(r'^[A-Za-z]+,\s*'), '')
          .replaceFirst(' GMT', '')
          .trim();
      final months = {
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      };
      final parts = cleaned.split(' ');
      if (parts.length < 4) return null;
      final day = int.tryParse(parts[0]);
      final month = months[parts[1].toLowerCase()];
      final year = int.tryParse(parts[2]);
      final timeParts = parts[3].split(':');
      final hour = int.tryParse(timeParts[0]);
      final min = int.tryParse(timeParts[1]);
      final sec = int.tryParse(timeParts[2]);
      if (day == null || month == null || year == null ||
          hour == null || min == null || sec == null) {
        return null;
      }
      return DateTime.utc(year, month, day, hour, min, sec);
    } catch (_) {
      return null;
    }
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}

/// WebDAV 异常
class WebDavException implements Exception {
  final String message;
  final int? statusCode;

  WebDavException(this.message, [this.statusCode]);

  @override
  String toString() {
    if (statusCode != null) return '$message ($statusCode)';
    return message;
  }
}
