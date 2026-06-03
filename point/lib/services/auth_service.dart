import 'secure_store.dart';

class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'user_id';
  static const _displayNameKey = 'display_name';
  static const _isAdminKey = 'is_admin';

  // Storage backend (Android Keystore-encrypted, iOS SharedPreferences fallback)
  // is centralized in SecureStore — see P0-01/P1-13 notes there.
  Future<void> _write(String key, String value) => SecureStore.write(key, value);
  Future<String?> _read(String key) => SecureStore.read(key);
  Future<void> _delete(String key) => SecureStore.delete(key);

  Future<void> saveAuth(
    String token,
    String userId,
    String displayName,
    bool isAdmin,
  ) async {
    await _write(_tokenKey, token);
    await _write(_userIdKey, userId);
    await _write(_displayNameKey, displayName);
    await _write(_isAdminKey, isAdmin.toString());
  }

  Future<String?> getToken() => _read(_tokenKey);
  Future<String?> getUserId() => _read(_userIdKey);
  Future<String?> getDisplayName() => _read(_displayNameKey);

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  Future<void> logout() async {
    await _delete(_tokenKey);
    await _delete(_userIdKey);
    await _delete(_displayNameKey);
    await _delete(_isAdminKey);
  }
}
