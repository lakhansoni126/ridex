import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config.dart';

typedef TokenReader = Future<String?> Function();
typedef TokenWriter = Future<void> Function(String access, String refresh);
typedef RefreshHandler = Future<bool> Function();

/// HTTP client for RideX REST API with JWT attach + single-flight 401 refresh.
class ApiClient {
  ApiClient({
    http.Client? client,
    required TokenReader readAccessToken,
    required TokenReader readRefreshToken,
    required TokenWriter writeTokens,
    required Future<void> Function() clearTokens,
    this.onSessionExpired,
  })  : _client = client ?? http.Client(),
        _readAccessToken = readAccessToken,
        _readRefreshToken = readRefreshToken,
        _writeTokens = writeTokens,
        _clearTokens = clearTokens;

  static const _timeout = Duration(seconds: 20);
  static const _uploadTimeout = Duration(seconds: 90);

  /// Invoked once when the refresh token is rejected, so the app can route
  /// back to sign-in instead of failing every request silently.
  final void Function()? onSessionExpired;

  final http.Client _client;
  final TokenReader _readAccessToken;
  final TokenReader _readRefreshToken;
  final TokenWriter _writeTokens;
  final Future<void> Function() _clearTokens;

  Future<bool>? _refreshInFlight;

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${ApiConfig.restBaseUrl}$normalized')
        .replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers({
    bool auth = true,
    bool json = true,
    Map<String, String>? extra,
  }) async {
    final headers = <String, String>{
      if (json) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?extra,
    };
    if (auth) {
      final token = await _readAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) =>
      _send(() async => _client.get(
            _uri(path, query),
            headers: await _headers(auth: auth, json: false),
          ));

  Future<http.Response> post(
    String path, {
    Object? body,
    bool auth = true,
    Map<String, String>? query,
  }) =>
      _send(() async => _client.post(
            _uri(path, query),
            headers: await _headers(auth: auth),
            body: body == null
                ? null
                : body is String
                    ? body
                    : jsonEncode(body),
          ));

  Future<http.Response> patch(
    String path, {
    Object? body,
    bool auth = true,
  }) =>
      _send(() async => _client.patch(
            _uri(path),
            headers: await _headers(auth: auth),
            body: body == null
                ? null
                : body is String
                    ? body
                    : jsonEncode(body),
          ));

  Future<http.Response> delete(
    String path, {
    Object? body,
    bool auth = true,
  }) =>
      _send(() async => _client.delete(
            _uri(path),
            headers: await _headers(auth: auth),
            body: body == null
                ? null
                : body is String
                    ? body
                    : jsonEncode(body),
          ));

  /// Multipart POST (e.g. community posts with images).
  ///
  /// [files] is a factory because a `MultipartFile` stream can only be sent
  /// once; a retry after a token refresh needs fresh instances.
  Future<http.Response> postMultipart(
    String path, {
    required Map<String, String> fields,
    Future<List<http.MultipartFile>> Function()? files,
    bool auth = true,
  }) =>
      _send(() async {
        final request = http.MultipartRequest('POST', _uri(path));
        request.fields.addAll(fields);
        if (files != null) request.files.addAll(await files());
        final headers = await _headers(auth: auth, json: false);
        request.headers.addAll(headers);
        final streamed = await _client.send(request).timeout(_uploadTimeout);
        return http.Response.fromStream(streamed);
      }, timeout: _uploadTimeout);

  Future<http.Response> _send(
    Future<http.Response> Function() send, {
    Duration timeout = _timeout,
  }) async {
    Future<http.Response> attempt() async {
      try {
        return await send().timeout(timeout);
      } on TimeoutException {
        throw NetworkException(
            'The request timed out. Check your connection and try again.');
      } on SocketException {
        throw NetworkException(
            "You're offline. Check your connection and try again.");
      } on http.ClientException {
        throw NetworkException(
            "Couldn't reach RideX. Check your connection and try again.");
      } on HandshakeException {
        throw NetworkException('Secure connection failed. Please try again.');
      }
    }

    final response = await attempt();
    if (response.statusCode != 401) return response;

    final hadToken = (await _readAccessToken())?.isNotEmpty ?? false;
    if (!hadToken) return response;

    final refreshed = await _refreshTokens();
    if (!refreshed) return response;
    return attempt();
  }

  Future<bool> _refreshTokens() async {
    if (_refreshInFlight != null) return _refreshInFlight!;

    _refreshInFlight = () async {
      try {
        final refresh = await _readRefreshToken();
        if (refresh == null || refresh.isEmpty) {
          await _clearTokens();
          onSessionExpired?.call();
          return false;
        }
        final response = await _client
            .post(
              _uri('/auth/refresh'),
              headers: await _headers(auth: false),
              body: jsonEncode({'refresh_token': refresh}),
            )
            .timeout(_timeout);
        if (response.statusCode == 401 || response.statusCode == 403) {
          await _clearTokens();
          onSessionExpired?.call();
          return false;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          // Server hiccup: keep the session, let the caller retry later.
          return false;
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final access = data['access_token'] as String?;
        final newRefresh = data['refresh_token'] as String?;
        if (access == null || newRefresh == null) {
          await _clearTokens();
          return false;
        }
        await _writeTokens(access, newRefresh);
        return true;
      } catch (e, st) {
        debugPrint('ApiClient refresh failed: $e\n$st');
        await _clearTokens();
        return false;
      } finally {
        _refreshInFlight = null;
      }
    }();

    return _refreshInFlight!;
  }

  static Map<String, dynamic> decodeMap(http.Response response) {
    _ensureOk(response);
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static List<dynamic> decodeList(http.Response response) {
    _ensureOk(response);
    return jsonDecode(response.body) as List<dynamic>;
  }

  static void _ensureOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }
}

/// Connectivity failure (offline, DNS, TLS, timeout).
class NetworkException implements Exception {
  NetworkException(this.message);

  final String message;

  @override
  String toString() => 'NetworkException: $message';
}

class ApiException implements Exception {
  ApiException({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  String get message {
    try {
      final data = jsonDecode(body);
      if (data is Map && data['detail'] != null) {
        final detail = data['detail'];
        if (detail is String) return detail;
        return detail.toString();
      }
    } catch (_) {}
    return 'Request failed ($statusCode)';
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
