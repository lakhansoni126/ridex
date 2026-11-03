import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/auth_repository.dart';

const _kAccess = 'ridex_access_token';
const _kRefresh = 'ridex_refresh_token';
const _kUser = 'ridex_user_json';

class TokenStore {
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<String?> readAccessToken() async {
    final prefs = await _ensure();
    return prefs.getString(_kAccess);
  }

  Future<String?> readRefreshToken() async {
    final prefs = await _ensure();
    return prefs.getString(_kRefresh);
  }

  Future<AuthUser?> readUser() async {
    final prefs = await _ensure();
    final raw = prefs.getString(_kUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required AuthUser user,
  }) async {
    final prefs = await _ensure();
    await prefs.setString(_kAccess, accessToken);
    await prefs.setString(_kRefresh, refreshToken);
    await prefs.setString(_kUser, jsonEncode(user.toJson()));
  }

  Future<void> saveUser(AuthUser user) async {
    final prefs = await _ensure();
    await prefs.setString(_kUser, jsonEncode(user.toJson()));
  }

  Future<void> writeTokens(String access, String refresh) async {
    final prefs = await _ensure();
    await prefs.setString(_kAccess, access);
    await prefs.setString(_kRefresh, refresh);
  }

  Future<void> clear() async {
    final prefs = await _ensure();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kUser);
  }

  Future<bool> hasAccessToken() async {
    final token = await readAccessToken();
    return token != null && token.isNotEmpty;
  }
}
