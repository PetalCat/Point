import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralizes at-rest storage of sensitive local data (auth tokens, MLS state,
/// location cache, learned zones) — P1-13.
///
/// On Android, values are stored in Keystore-backed encrypted storage. On iOS,
/// flutter_secure_storage_darwin currently crashes on iOS 26 (excluded via the
/// Podfile patch), so we fall back to SharedPreferences there. That iOS gap is
/// tracked with P0-01 — iOS is not yet privacy-equivalent. When a real Keychain
/// MethodChannel lands, only this file changes.
class SecureStore {
  static final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Whether platform-secure (encrypted) storage is available.
  static bool get isEncrypted => defaultTargetPlatform == TargetPlatform.android;

  static Future<void> write(String key, String value) async {
    if (isEncrypted) {
      await _secure.write(key: key, value: value);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }
  }

  static Future<String?> read(String key) async {
    if (isEncrypted) {
      return _secure.read(key: key);
    } else {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
  }

  static Future<void> delete(String key) async {
    if (isEncrypted) {
      await _secure.delete(key: key);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    }
  }

  /// Read a value, migrating any legacy plaintext SharedPreferences copy into
  /// encrypted storage and wiping the plaintext original. Use for data that
  /// used to live in SharedPreferences before P1-13 (cache, zones).
  static Future<String?> readMigrating(String key) async {
    if (!isEncrypted) {
      // iOS path is already SharedPreferences-backed; nothing to migrate.
      return read(key);
    }
    final secure = await _secure.read(key: key);
    if (secure != null) return secure;
    // Fall back to a legacy plaintext value and migrate it.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(key);
    if (legacy != null) {
      await _secure.write(key: key, value: legacy);
      await prefs.remove(key); // wipe plaintext original
      return legacy;
    }
    return null;
  }
}
