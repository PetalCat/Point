import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralizes at-rest storage of sensitive local data (auth tokens, MLS state,
/// location cache, learned zones) — P0-01 / P1-13.
///
/// - Android: Keystore-backed encrypted storage via flutter_secure_storage.
/// - iOS: native Keychain via a MethodChannel (KeychainChannel.swift), because
///   flutter_secure_storage_darwin crashes on iOS 26.
/// - Other/unknown platforms: SharedPreferences fallback.
class SecureStore {
  static const _keychain = MethodChannel('dev.petalcat.point/keychain');

  static final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// Whether values are stored in platform-secure (encrypted) storage.
  static bool get isEncrypted => _isAndroid || _isIOS;

  static Future<void> write(String key, String value) async {
    if (_isAndroid) {
      await _secure.write(key: key, value: value);
    } else if (_isIOS) {
      await _keychain.invokeMethod('write', {'key': key, 'value': value});
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }
  }

  static Future<String?> read(String key) async {
    if (_isAndroid) {
      return _secure.read(key: key);
    } else if (_isIOS) {
      final v = await _keychain.invokeMethod<String?>('read', {'key': key});
      return v;
    } else {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
  }

  static Future<void> delete(String key) async {
    if (_isAndroid) {
      await _secure.delete(key: key);
    } else if (_isIOS) {
      await _keychain.invokeMethod('delete', {'key': key});
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
      return read(key);
    }
    final secure = await read(key);
    if (secure != null) return secure;
    // Fall back to a legacy plaintext value and migrate it.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(key);
    if (legacy != null) {
      await write(key, legacy);
      await prefs.remove(key); // wipe plaintext original
      return legacy;
    }
    return null;
  }
}
