import 'package:http/http.dart' as http;

import '../protocol/models.dart';
import '../protocol/utf8_json.dart';

class AuthClient {
  AuthClient({required this.baseUrl, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;

  Future<AuthSession> register({
    required String username,
    required String email,
    required String password,
  }) {
    return _postAuth('/auth/register', {
      'username': username,
      'email': email,
      'password': password,
    });
  }

  Future<AuthSession> login({required String login, required String password}) {
    return _postAuth('/auth/login', {'login': login, 'password': password});
  }

  Future<AuthSession> refresh(String refreshToken) {
    return _postAuth('/auth/refresh', {'refresh_token': refreshToken});
  }

  Future<void> logout({String? accessToken, String? refreshToken}) async {
    final response = await _httpClient.post(
      _uri('/auth/logout'),
      headers: _headers(accessToken: accessToken),
      body: encodeJsonBody({'refresh_token': refreshToken}),
    );
    _throwIfFailed(response);
  }

  Future<CurrentUser> me(String accessToken) async {
    final response = await _httpClient.get(
      _uri('/me'),
      headers: _headers(accessToken: accessToken),
    );
    _throwIfFailed(response);
    return CurrentUser.fromJson(
      decodeJsonBody(response)! as Map<String, Object?>,
    );
  }

  Future<List<UserSession>> listSessions(String accessToken) async {
    final response = await _httpClient.get(
      _uri('/auth/sessions'),
      headers: _headers(accessToken: accessToken),
    );
    _throwIfFailed(response);
    final decoded = decodeJsonBody(response) as List<Object?>;
    return decoded
        .cast<Map<String, Object?>>()
        .map(UserSession.fromJson)
        .toList();
  }

  Future<void> revokeSession({
    required String accessToken,
    required String sessionId,
  }) async {
    final response = await _httpClient.delete(
      _uri('/auth/sessions/$sessionId'),
      headers: _headers(accessToken: accessToken),
    );
    _throwIfFailed(response);
  }

  Future<void> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
    bool revokeOtherSessions = true,
  }) async {
    final response = await _httpClient.post(
      _uri('/auth/password'),
      headers: _headers(accessToken: accessToken),
      body: encodeJsonBody({
        'current_password': currentPassword,
        'new_password': newPassword,
        'revoke_other_sessions': revokeOtherSessions,
      }),
    );
    _throwIfFailed(response);
  }

  Future<AuthSession> _postAuth(String path, Map<String, Object?> body) async {
    final response = await _httpClient.post(
      _uri(path),
      headers: _headers(),
      body: encodeJsonBody(body),
    );
    _throwIfFailed(response);
    return AuthSession.fromJson(
      decodeJsonBody(response)! as Map<String, Object?>,
    );
  }

  void _throwIfFailed(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw AuthException.fromResponse(response);
  }

  Uri _uri(String path) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$normalizedBase$path');
  }

  Map<String, String> _headers({String? accessToken}) {
    return {
      'accept': jsonAcceptHeader,
      'content-type': jsonUtf8ContentType,
      if (accessToken != null) 'authorization': 'Bearer $accessToken',
    };
  }

  void close() => _httpClient.close();
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;
  final CurrentUser user;

  factory AuthSession.fromJson(Map<String, Object?> json) {
    final expiresAtJson = json['access_token_expires_at'] as String?;
    final expiresInJson = json['expires_in'];
    final accessTokenExpiresAt = expiresAtJson == null
        ? DateTime.now().add(Duration(seconds: expiresInJson! as int))
        : DateTime.parse(expiresAtJson);
    return AuthSession(
      accessToken: json['access_token']! as String,
      refreshToken: json['refresh_token']! as String,
      accessTokenExpiresAt: accessTokenExpiresAt,
      user: CurrentUser.fromJson(json['user']! as Map<String, Object?>),
    );
  }

  bool isAccessTokenExpiringSoon({
    Duration threshold = const Duration(seconds: 60),
  }) {
    return DateTime.now().add(threshold).isAfter(accessTokenExpiresAt);
  }
}

class AuthException implements Exception {
  AuthException(this.message, {required this.statusCode, required this.code});

  final String message;
  final int statusCode;
  final String code;

  factory AuthException.fromResponse(http.Response response) {
    try {
      final decoded = decodeJsonBody(response) as Map<String, Object?>;
      final error = decoded['error'] as Map<String, Object?>?;
      final message = error?['message'] as String?;
      final code = error?['code'] as String?;
      if (message != null && message.isNotEmpty) {
        return AuthException(
          message,
          statusCode: response.statusCode,
          code: code ?? 'request_failed',
        );
      }
    } catch (_) {
      // Fall through to the status-based message.
    }
    return AuthException(
      'Request failed (${response.statusCode})',
      statusCode: response.statusCode,
      code: 'request_failed',
    );
  }

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}
