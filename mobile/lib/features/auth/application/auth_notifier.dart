import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/api/api_client.dart';
import '../../../data/api/auth_repository.dart';
import '../../../data/local/token_store.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.error,
    this.busy = false,
  });

  final AuthStatus status;
  final AuthUser? user;
  final String? error;
  final bool busy;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? error,
    bool? busy,
    bool clearError = false,
    bool clearUser = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: clearUser ? null : (user ?? this.user),
        error: clearError ? null : (error ?? this.error),
        busy: busy ?? this.busy,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref)
      : super(const AuthState(status: AuthStatus.unknown)) {
    _bootstrap();
  }

  final Ref _ref;

  TokenStore get _store => _ref.read(tokenStoreProvider);
  AuthRepository get _repo => _ref.read(authRepositoryProvider);

  Future<void> _bootstrap() async {
    try {
      final token = await _store.readAccessToken();
      final user = await _store.readUser();
      if (token != null && token.isNotEmpty && user != null) {
        state = AuthState(status: AuthStatus.authenticated, user: user);
        // Soft refresh profile in background
        try {
          final me = await _repo.me();
          await _store.saveSession(
            accessToken: token,
            refreshToken: (await _store.readRefreshToken()) ?? '',
            user: me,
          );
          state = AuthState(status: AuthStatus.authenticated, user: me);
        } catch (_) {}
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      debugPrint('Auth bootstrap: $e');
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final tokens = await _repo.login(email: email, password: password);
      await _store.saveSession(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        user: tokens.user,
      );
      state = AuthState(
        status: AuthStatus.authenticated,
        user: tokens.user,
        busy: false,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString());
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String username,
    required String password,
    required String displayName,
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final tokens = await _repo.register(
        email: email,
        username: username,
        password: password,
        displayName: displayName,
      );
      await _store.saveSession(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        user: tokens.user,
      );
      state = AuthState(
        status: AuthStatus.authenticated,
        user: tokens.user,
        busy: false,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    final refresh = await _store.readRefreshToken();
    try {
      if (refresh != null) await _repo.logout(refresh);
    } catch (_) {}
    await _store.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});
