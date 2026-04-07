import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService;
  final AuthService _authService;

  bool _isLoggedIn = false;
  bool _isLoading = true;
  String? _userId;
  String? _displayName;
  bool _isAdmin = false;
  String? _token;
  String? _error;

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get userId => _userId;
  String? get displayName => _displayName;
  bool get isAdmin => _isAdmin;
  String? get token => _token;
  String? get error => _error;

  AuthProvider(this._apiService, this._authService) {
    _init();
  }

  Future<void> _init() async {
    try {
      final token = await _authService.getToken();
      if (token != null) {
        _token = token;
        _userId = await _authService.getUserId();
        _displayName = await _authService.getDisplayName();
        _isLoggedIn = true;
        _apiService.setToken(token);
      }
    } catch (_) {
      // If restoring session fails, stay logged out
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> register(
    String username,
    String displayName,
    String password, {
    String? inviteCode,
  }) async {
    _error = null;
    notifyListeners();
    try {
      final response = await _apiService.register(
        username,
        displayName,
        password,
        inviteCode: inviteCode,
      );
      await _authService.saveAuth(
        response.token,
        response.userId,
        response.displayName,
        response.isAdmin,
      );
      _token = response.token;
      _userId = response.userId;
      _displayName = response.displayName;
      _isAdmin = response.isAdmin;
      _isLoggedIn = true;
      _apiService.setToken(response.token);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    _error = null;
    notifyListeners();
    try {
      final response = await _apiService.login(username, password);
      await _authService.saveAuth(
        response.token,
        response.userId,
        response.displayName,
        response.isAdmin,
      );
      _token = response.token;
      _userId = response.userId;
      _displayName = response.displayName;
      _isAdmin = response.isAdmin;
      _isLoggedIn = true;
      _apiService.setToken(response.token);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _token = null;
    _userId = null;
    _displayName = null;
    _isAdmin = false;
    _isLoggedIn = false;
    _error = null;
    notifyListeners();
  }
}
