import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors.dart';
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
    this.sessionExpired = false,
  });

  final AuthStatus status;
  final AuthUser? user;
  final String? error;
  final bool busy;

  /// True when we were signed out because the refresh token was rejected.
  final bool sessionExpired;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? error,
    bool? busy,
    bool clearError = false,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: clearError ? null : (error ?? this.error),
        busy: busy ?? this.busy,
        sessionExpired: sessionExpired,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState(status: AuthStatus.unknown)) {
    _bootstrap();
  }

  final Ref _ref;

  TokenStore get _store => _ref.read(tokenStoreProvider);
  AuthRepository get _repo => _ref.read(authRepositoryProvider);

  Future<void> _bootstrap() async {
    try {
      final token = await _store.readAccessToken();
      final user = await _store.readUser();
      if (token == null || token.isEmpty || user == null) {
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }
      // Optimistic: show the cached profile immediately (works offline).
      state = AuthState(status: AuthStatus.authenticated, user: user);
      refreshProfile();
    } catch (e) {
      debugPrint('Auth bootstrap: $e');
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> refreshProfile() async {
    try {
      final me = await _repo.me();
      await _store.saveUser(me);
      if (mounted && state.status == AuthStatus.authenticated) {
        state = state.copyWith(user: me);
      }
    } catch (_) {
      // Offline or transient: keep cached profile.
    }
  }

  Future<bool> login(String email, String password) => _authenticate(
        () => _repo.login(email: email.trim(), password: password),
      );

  Future<bool> register({
    required String email,
    required String username,
    required String password,
    required String displayName,
  }) =>
      _authenticate(() => _repo.register(
            email: email.trim(),
            username: username.trim().toLowerCase(),
            password: password,
            displayName: displayName.trim(),
          ));

  Future<bool> _authenticate(Future<AuthTokens> Function() call) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final tokens = await call();
      await _store.saveSession(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        user: tokens.user,
      );
      state = AuthState(status: AuthStatus.authenticated, user: tokens.user);
      return true;
    } catch (e) {
      state = state.copyWith(busy: false, error: friendlyError(e));
      return false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  Future<void> updateProfile({String? displayName, String? bio}) async {
    final me = await _repo.updateMe(displayName: displayName, bio: bio);
    await _store.saveUser(me);
    state = state.copyWith(user: me);
  }

  Future<void> uploadAvatar(File image) async {
    final me = await _repo.uploadAvatar(image);
    await _store.saveUser(me);
    state = state.copyWith(user: me);
  }

  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    await _signOutLocally();
  }

  Future<void> logout() async {
    final refresh = await _store.readRefreshToken();
    try {
      if (refresh != null) await _repo.logout(refresh);
    } on ApiException catch (_) {
    } catch (_) {}
    await _signOutLocally();
  }

  /// Called by [ApiClient] when the refresh token is rejected.
  void onSessionExpired() {
    if (state.status != AuthStatus.authenticated) return;
    _signOutLocally(expired: true);
  }

  Future<void> _signOutLocally({bool expired = false}) async {
    try {
      await _ref.read(backgroundLocationServiceProvider).stopAll();
    } catch (_) {}
    await _store.clear();
    if (mounted) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        sessionExpired: expired,
        error: expired ? 'Your session expired. Please sign in again.' : null,
      );
    }
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier(ref));
