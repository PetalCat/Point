import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers.dart';
import '../services/api_service.dart';

class AuthState {
  final bool isLoggedIn;
  final bool isLoading;
  final String? userId;
  final String? displayName;
  final bool isAdmin;
  final String? token;
  final String? error;

  const AuthState({
    this.isLoggedIn = false,
    this.isLoading = true,
    this.userId,
    this.displayName,
    this.isAdmin = false,
    this.token,
    this.error,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    bool? isLoading,
    String? userId,
    String? displayName,
    bool? isAdmin,
    String? token,
    String? error,
    bool clearError = false,
    bool clearToken = false,
    bool clearUserId = false,
    bool clearDisplayName = false,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isLoading: isLoading ?? this.isLoading,
      userId: clearUserId ? null : (userId ?? this.userId),
      displayName: clearDisplayName ? null : (displayName ?? this.displayName),
      isAdmin: isAdmin ?? this.isAdmin,
      token: clearToken ? null : (token ?? this.token),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    _init();
    return const AuthState();
  }

  Future<void> _init() async {
    final apiService = ref.read(apiServiceProvider);
    final authService = ref.read(authServiceProvider);
    try {
      final token = await authService.getToken();
      if (token != null) {
        final userId = await authService.getUserId();
        final displayName = await authService.getDisplayName();
        apiService.setToken(token);
        state = state.copyWith(
          token: token,
          userId: userId,
          displayName: displayName,
          isLoggedIn: true,
          isLoading: false,
        );
        return;
      }
    } catch (_) {
      // If restoring session fails, stay logged out
    }
    state = state.copyWith(isLoading: false);
  }

  Future<bool> register(
    String username,
    String displayName,
    String password, {
    String? inviteCode,
  }) async {
    final apiService = ref.read(apiServiceProvider);
    final authService = ref.read(authServiceProvider);
    state = state.copyWith(clearError: true);
    try {
      final response = await apiService.register(
        username,
        displayName,
        password,
        inviteCode: inviteCode,
      );
      await authService.saveAuth(
        response.token,
        response.userId,
        response.displayName,
        response.isAdmin,
      );
      apiService.setToken(response.token);
      state = state.copyWith(
        token: response.token,
        userId: response.userId,
        displayName: response.displayName,
        isAdmin: response.isAdmin,
        isLoggedIn: true,
        clearError: true,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> login(String username, String password) async {
    final apiService = ref.read(apiServiceProvider);
    final authService = ref.read(authServiceProvider);
    state = state.copyWith(clearError: true);
    try {
      final response = await apiService.login(username, password);
      await authService.saveAuth(
        response.token,
        response.userId,
        response.displayName,
        response.isAdmin,
      );
      apiService.setToken(response.token);
      state = state.copyWith(
        token: response.token,
        userId: response.userId,
        displayName: response.displayName,
        isAdmin: response.isAdmin,
        isLoggedIn: true,
        clearError: true,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    final authService = ref.read(authServiceProvider);
    await authService.logout();
    state = const AuthState(
      isLoggedIn: false,
      isLoading: false,
    );
  }
}
