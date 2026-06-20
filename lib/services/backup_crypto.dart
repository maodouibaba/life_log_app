import 'dart:convert';
import 'dart:math';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';

/// 备份加密服务
/// 使用 AES-256-CBC 加密，密码通过 PBKDF2 派生密钥
class BackupCrypto {
  /// 加密文件头标识
  static const String magicHeader = 'LIFE_LOG_ENC:';

  /// 检查文件内容是否为加密格式
  static bool isEncrypted(String content) {
    return content.startsWith(magicHeader);
  }

  /// 加密 JSON 文本，返回带标识头的密文字符串（Base64）
  static String encrypt(String plainText, String password) {
    // 生成随机盐值
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));

    // PBKDF2 派生密钥
    final key = enc.Key.fromUtf8(
      _pbkdf2(password, salt, 10000, 32),
    );

    // 生成随机 IV
    final iv = enc.IV.fromLength(16);
    for (int i = 0; i < 16; i++) {
      iv.bytes[i] = Random.secure().nextInt(256);
    }

    // AES-256-CBC 加密
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: iv);

    // 组装：salt(16) + iv(16) + ciphertext
    final combined = [
      ...salt,
      ...iv.bytes,
      ...encrypted.bytes,
    ];

    return '$magicHeader${base64Encode(combined)}';
  }

  /// 解密，返回原始 JSON 文本
  static String decrypt(String encryptedText, String password) {
    if (!isEncrypted(encryptedText)) {
      throw Exception('文件不是加密格式');
    }

    final base64Str = encryptedText.substring(magicHeader.length);
    final combined = base64Decode(base64Str);

    if (combined.length < 32) {
      throw Exception('数据格式错误');
    }

    // 提取 salt(16) + iv(16)
    final salt = combined.sublist(0, 16);
    final iv = enc.IV(combined.sublist(16, 32));
    final ciphertext = combined.sublist(32);

    // 派生密钥
    final key = enc.Key.fromUtf8(_pbkdf2(password, salt, 10000, 32));

    // AES-256-CBC 解密
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = enc.Encrypted(ciphertext);
    return encrypter.decrypt(encrypted, iv: iv);
  }

  /// PBKDF2 简易实现
  static String _pbkdf2(String password, List<int> salt, int iterations, int keyLength) {
    var key = password;
    for (int i = 0; i < iterations; i++) {
      final bytes = utf8.encode(key) + salt;
      key = sha256.convert(bytes).toString();
    }
    return key.substring(0, keyLength);
  }
}
