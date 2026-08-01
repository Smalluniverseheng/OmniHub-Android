/// 云端同步数据加密（AES-256-CBC）
///
/// - 用户设置本地密码，SHA-256 派生密钥，密钥与密码只存本地，绝不上传
/// - 加密在端内完成：上行前加密，下拉后解密
/// - 密文带 `enc:v1:` 前缀（Map 包装为 {'_enc': 密文}），
///   未加密的历史数据与网页端写入的数据不受影响
library sync_crypto;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

import 'package:venera/foundation/appdata.dart';

class SyncCrypto {
  SyncCrypto._();

  static const String prefix = 'enc:v1:';
  static const String encKey = '_enc';

  /// 是否启用上行加密
  static bool get enabled => appdata.settings['syncEncEnabled'] == true;

  /// 本地是否已设置同步密码（密钥派生后仅存本地）
  static bool get hasKey =>
      (appdata.settings['syncEncKey']?.toString() ?? '').isNotEmpty;

  static enc.Key? _key() {
    final k = appdata.settings['syncEncKey']?.toString() ?? '';
    if (k.isEmpty) return null;
    try {
      return enc.Key.fromBase64(k);
    } catch (_) {
      return null;
    }
  }

  /// 设置/更换密码：派生密钥并保存（仅本地）
  static void setPassword(String password) {
    final digest =
        sha256.convert(utf8.encode('omnihub-sync-enc::$password'));
    appdata.settings['syncEncKey'] = base64Encode(digest.bytes);
    appdata.settings['syncEncEnabled'] = true;
    appdata.saveData();
  }

  /// 关闭加密（保留本地密钥，已加密的历史数据仍可下拉解密）
  static void disable() {
    appdata.settings['syncEncEnabled'] = false;
    appdata.saveData();
  }

  /// 校验输入的密码是否与本地密钥一致（用于更换密码前确认）
  static bool verifyPassword(String password) {
    final digest =
        sha256.convert(utf8.encode('omnihub-sync-enc::$password'));
    return base64Encode(digest.bytes) ==
        appdata.settings['syncEncKey']?.toString();
  }

  /// 加密文本 → 带前缀密文；未启用或无密钥时原样返回
  static String encryptText(String plain) {
    final key = _key();
    if (key == null) return plain;
    final iv = enc.IV.fromSecureRandom(16);
    final aes = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final cipher = aes.encrypt(plain, iv: iv);
    return prefix + base64Encode([...iv.bytes, ...cipher.bytes]);
  }

  /// 解密文本：带前缀则解密（无密钥返回 null），否则原样返回
  static String? decryptText(String s) {
    if (!s.startsWith(prefix)) return s;
    final key = _key();
    if (key == null) return null;
    try {
      final bytes = base64Decode(s.substring(prefix.length));
      final iv = enc.IV(Uint8List.sublistView(bytes, 0, 16));
      final aes = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return aes.decrypt(enc.Encrypted(Uint8List.sublistView(bytes, 16)),
          iv: iv);
    } catch (_) {
      return null;
    }
  }

  /// 加密 JSON 值 → {'_enc': 密文}
  static Map<String, dynamic> encryptValue(Map<String, dynamic> value) {
    return {encKey: encryptText(jsonEncode(value))};
  }

  /// 解密 JSON 值：{'_enc': …} 则解密还原（失败/无密钥返回 null），否则原样返回
  static Map<String, dynamic>? decryptValue(Map<String, dynamic> value) {
    final payload = value[encKey]?.toString();
    if (payload == null || payload.isEmpty) return value;
    final plain = decryptText(payload);
    if (plain == null) return null;
    try {
      final j = jsonDecode(plain);
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return null;
  }

  /// 值是否为加密包装
  static bool isEncryptedValue(Map<String, dynamic> value) =>
      (value[encKey]?.toString() ?? '').isNotEmpty;
}
