// ignore_for_file: unused_field

/// 数据同步接口（预留）
///
/// 后续实现坚果云 WebDAV 同步时会用到这个接口。
/// 当前为骨架代码，仅定义接口方法。
///
/// 同步方案：
/// 1. 本地数据序列化为 JSON
/// 2. 通过 WebDAV 协议上传到坚果云
/// 3. 其他设备从坚果云拉取 JSON 并恢复到本地数据库
///
class SyncService {
  // 单例
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  /// 是否已配置同步（坚果云账号密码）
  bool get isConfigured => _webdavUrl != null;

  String? _webdavUrl;
  String? _username;
  String? _password;

  /// 配置坚果云 WebDAV
  void configure(String url, String username, String password) {
    _webdavUrl = url;
    _username = username;
    _password = password;
  }

  /// 清除配置
  void clearConfig() {
    _webdavUrl = null;
    _username = null;
    _password = null;
  }

  /// 上传数据到坚果云（待实现）
  Future<bool> upload() async {
    // TODO: 实现 WebDAV 上传
    throw UnimplementedError('同步功能尚未实现');
  }

  /// 从坚果云下载数据（待实现）
  Future<bool> download() async {
    // TODO: 实现 WebDAV 下载
    throw UnimplementedError('同步功能尚未实现');
  }

  /// 检查坚果云连接（待实现）
  Future<bool> checkConnection() async {
    // TODO: 实现连接检查
    throw UnimplementedError('同步功能尚未实现');
  }
}
