import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:archive/archive_io.dart';
import '../database/app_database.dart';
import '../services/photo_service.dart';

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

  // 同步模式：覆写 或 合并
  static const String modeMerge = 'merge';
  static const String modeOverwrite = 'overwrite';

  /// 获取当前同步模式（默认覆写）
  static Future<String> getSyncMode() async {
    final db = AppDatabase();
    try {
      return await db.getSetting('${_prefix}mode') ?? modeOverwrite;
    } catch (_) {
      return modeOverwrite;
    }
  }

  /// 设置同步模式
  static Future<void> setSyncMode(String mode) async {
    final db = AppDatabase();
    await db.setSetting('${_prefix}mode', mode);
  }

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

  /// 上传 ZIP 备份文件（含照片）
  static Future<String> uploadBackupZip(SyncConfig config) async {
    final client = http.Client();
    try {
      await _ensureDir(client, config);

      // 导出本地数据
      final db = AppDatabase();
      final jsonContent = await db.exportToJson();

      // 收集照片
      final entries = await db.getAllEntries();
      final photoFiles = <String>{};
      for (final e in entries) {
        photoFiles.addAll(e.photoFilenames);
      }

      // 打包 ZIP
      final archive = Archive();
      final jsonBytes = utf8.encode(jsonContent);
      archive.addFile(ArchiveFile('生活记录备份.json', jsonBytes.length, jsonBytes));

      for (final fileName in photoFiles) {
        try {
          final photoService = PhotoService();
          final bytes = await photoService.getPhotoBytes(fileName);
          if (bytes != null) {
            archive.addFile(ArchiveFile('photos/$fileName', bytes.length, bytes));
          }
        } catch (_) {}
      }

      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) throw Exception('ZIP 编码失败');

      // 生成文件名
      final now = DateTime.now();
      final ts = '${now.year}${_pad2(now.month)}${_pad2(now.day)}_${_pad2(now.hour)}${_pad2(now.minute)}';
      final fileName = '生活记录备份_$ts.zip';

      // 上传
      final fileUrl =
          '${config.fullUrl}${Uri.encodeComponent(_dirName)}/${Uri.encodeComponent(fileName)}';
      final putReq = http.Request('PUT', Uri.parse(fileUrl));
      putReq.headers['Authorization'] = config.basicAuth;
      putReq.headers['Content-Type'] = 'application/zip';
      putReq.bodyBytes = encoded;

      final putResp = await client
          .send(putReq)
          .timeout(const Duration(seconds: 60)); // ZIP 较大，超时加长

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
  /// 使用 href 而非 displayname（href 在所有 PROPFIND 响应中必定存在）
  /// 注意：xml 包的 findElements 对带命名空间的元素有兼容问题，
  /// 所以这里全部用手动遍历 children 代替。
  static List<RemoteFile> _parsePropfind(String xml) {
    final files = <RemoteFile>[];
    final doc = XmlDocument.parse(xml);
    final root = doc.rootElement;

    // 手动递归查找 response 元素（避开 xml 包的命名空间问题）
    List<XmlElement> findChildrenByLocalName(XmlElement el, String name) {
      final r = <XmlElement>[];
      if (el.name.local == name) r.add(el);
      for (final c in el.children) {
        if (c is XmlElement) r.addAll(findChildrenByLocalName(c, name));
      }
      return r;
    }

    final responses = findChildrenByLocalName(root, 'response');

    for (final resp in responses) {
      // 手动查找 propstat 子元素
      XmlElement? propstat;
      for (final c in resp.children) {
        if (c is XmlElement && c.name.local == 'propstat') {
          propstat = c;
          break;
        }
      }
      if (propstat == null) continue;

      // 手动查找 prop 子元素
      XmlElement? prop;
      for (final c in propstat.children) {
        if (c is XmlElement && c.name.local == 'prop') {
          prop = c;
          break;
        }
      }
      if (prop == null) continue;

      // 跳过目录（检查 resourcetype 是否包含 collection）
      final rtNode = _findChildByLocalName(prop, 'resourcetype');
      if (rtNode != null) {
        final collection = _findChildByLocalName(rtNode, 'collection');
        if (collection != null) continue;
      }

      // 从 href 提取文件名（比 displayname 更可靠）
      final hrefEl = _findChildByLocalName(resp, 'href');
      if (hrefEl == null) continue;
      final href = hrefEl.innerText.trim();

      final fileName = href.split('/').last;
      if (fileName.isEmpty) continue;

      // URL 解码文件名（可能包含中文百分号编码）
      final cleanName = Uri.decodeComponent(fileName);
      if (cleanName == _dirName) continue;
      if (!cleanName.endsWith('.json')) continue;

      // 文件大小
      int size = 0;
      final clNode = _findChildByLocalName(prop, 'getcontentlength');
      if (clNode != null) size = int.tryParse(clNode.innerText) ?? 0;

      // 修改时间
      DateTime modified = DateTime.now();
      final lmNode = _findChildByLocalName(prop, 'getlastmodified');
      if (lmNode != null) {
        final parsed = _parseHttpDate(lmNode.innerText);
        if (parsed != null) modified = parsed;
      }

      files.add(RemoteFile(name: cleanName, size: size, modified: modified));
    }

    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  /// 在元素的直接子元素中查找指定 localName 的 XmlElement
  static XmlElement? _findChildByLocalName(XmlElement parent, String localName) {
    for (final c in parent.children) {
      if (c is XmlElement && c.name.local == localName) return c;
    }
    return null;
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
      return DateTime.utc(year, month, day, hour, min, sec).toLocal();
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
