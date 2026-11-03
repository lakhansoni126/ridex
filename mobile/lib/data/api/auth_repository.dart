import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_client.dart';

class AuthUser {
  AuthUser({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatarPath,
    this.bio,
  });

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String? avatarPath;
  final String? bio;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String,
        avatarPath: json['avatar_path'] as String?,
        bio: json['bio'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'display_name': displayName,
        'avatar_path': avatarPath,
        'bio': bio,
      };
}

class AuthTokens {
  AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<AuthTokens> register({
    required String email,
    required String username,
    required String password,
    required String displayName,
  }) async {
    final response = await _api.post(
      '/auth/register',
      auth: false,
      body: {
        'email': email,
        'username': username,
        'password': password,
        'display_name': displayName,
      },
    );
    return AuthTokens.fromJson(ApiClient.decodeMap(response));
  }

  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post(
      '/auth/login',
      auth: false,
      body: {'email': email, 'password': password},
    );
    return AuthTokens.fromJson(ApiClient.decodeMap(response));
  }

  Future<AuthTokens> refresh(String refreshToken) async {
    final response = await _api.post(
      '/auth/refresh',
      auth: false,
      body: {'refresh_token': refreshToken},
    );
    return AuthTokens.fromJson(ApiClient.decodeMap(response));
  }

  Future<void> logout(String refreshToken) async {
    await _api.post(
      '/auth/logout',
      auth: false,
      body: {'refresh_token': refreshToken},
    );
  }

  Future<AuthUser> me() async {
    final response = await _api.get('/users/me');
    return AuthUser.fromJson(ApiClient.decodeMap(response));
  }

  Future<AuthUser> updateMe({String? displayName, String? bio}) async {
    final response = await _api.patch('/users/me', body: {
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
    });
    return AuthUser.fromJson(ApiClient.decodeMap(response));
  }

  Future<AuthUser> uploadAvatar(File image) async {
    final response = await _api.postMultipart(
      '/users/me/avatar',
      fields: const {},
      files: () async => [
        await http.MultipartFile.fromPath('avatar', image.path),
      ],
    );
    return AuthUser.fromJson(ApiClient.decodeMap(response));
  }

  /// Permanently deletes the account (required for store compliance).
  Future<void> deleteAccount() async {
    ApiClient.decodeMap(await _api.delete('/users/me'));
  }
}
