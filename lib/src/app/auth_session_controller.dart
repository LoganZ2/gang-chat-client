import 'dart:async';

import '../auth/auth_client.dart';
import '../auth/token_store.dart';

typedef AuthClientFactory = AuthClient Function(String baseUrl);
typedef AuthSessionListener = void Function();

class AuthRequest {
  const AuthRequest.login({required this.login, required this.password})
    : username = null,
      emailVerificationToken = null,
      registering = false;

  const AuthRequest.register({
    required this.username,
    required this.login,
    required this.password,
    required this.emailVerificationToken,
  }) : registering = true;

  final bool registering;
  final String? username;
  final String? emailVerificationToken;
  final String login;
  final String password;
}

enum AuthRestoreStatus { missingRefreshToken, restored, refreshFailed }

class AuthRestoreResult {
  const AuthRestoreResult._(this.status, {this.error});

  const AuthRestoreResult.missingRefreshToken()
    : this._(AuthRestoreStatus.missingRefreshToken);

  const AuthRestoreResult.restored() : this._(AuthRestoreStatus.restored);

  const AuthRestoreResult.refreshFailed(Object error)
    : this._(AuthRestoreStatus.refreshFailed, error: error);

  final AuthRestoreStatus status;
  final Object? error;

  bool get hasSession => status == AuthRestoreStatus.restored;
}

class AuthSessionController {
  AuthSessionController({
    required TokenStore tokenStore,
    required this.apiBaseUrl,
    AuthClientFactory? authClientFactory,
  }) : _tokenStore = tokenStore,
       _authClientFactory =
           authClientFactory ?? ((baseUrl) => AuthClient(baseUrl: baseUrl));

  final TokenStore _tokenStore;
  final String apiBaseUrl;
  final AuthClientFactory _authClientFactory;

  AuthSession? _session;
  Timer? _refreshTimer;
  Future<String>? _refreshInFlight;
  final List<AuthSessionListener> _listeners = <AuthSessionListener>[];

  static const Duration _refreshRetryDelay = Duration(seconds: 30);

  AuthSession? get session => _session;

  void addListener(AuthSessionListener listener) {
    _listeners.add(listener);
  }

  void removeListener(AuthSessionListener listener) {
    _listeners.remove(listener);
  }

  Future<AuthRestoreResult> restoreSession() async {
    final String? refreshToken;
    try {
      refreshToken = await _tokenStore.readRefreshToken();
    } catch (e) {
      _clearSession();
      return AuthRestoreResult.refreshFailed(e);
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      _clearSession();
      return const AuthRestoreResult.missingRefreshToken();
    }

    final client = _authClientFactory(apiBaseUrl);
    try {
      final session = await client.refresh(refreshToken);
      _setSession(session);
      _scheduleTokenRefresh(session);
      await _writeRefreshTokenBestEffort(session.refreshToken);
      return const AuthRestoreResult.restored();
    } catch (e) {
      if (_isTerminalRefreshFailure(e)) {
        await _tokenStore.clearRefreshToken();
      }
      _clearSession();
      return AuthRestoreResult.refreshFailed(e);
    } finally {
      client.close();
    }
  }

  Future<AuthSession> authenticate(AuthRequest request) async {
    final client = _authClientFactory(apiBaseUrl);
    try {
      if (request.registering) {
        return await client.register(
          username: request.username!,
          email: request.login,
          password: request.password,
          emailVerificationToken: request.emailVerificationToken!,
        );
      }
      return await client.login(
        login: request.login,
        password: request.password,
      );
    } finally {
      client.close();
    }
  }

  Future<bool> isUsernameAvailable(String username) async {
    final client = _authClientFactory(apiBaseUrl);
    try {
      return await client.isUsernameAvailable(username);
    } finally {
      client.close();
    }
  }

  Future<bool> isEmailAvailable(String email) async {
    final client = _authClientFactory(apiBaseUrl);
    try {
      return await client.isEmailAvailable(email);
    } finally {
      client.close();
    }
  }

  Future<void> acceptSession(AuthSession session) async {
    await _tokenStore.writeRefreshToken(session.refreshToken);
    await _tokenStore.writeApiBaseUrl(apiBaseUrl);
    _setSession(session);
    _scheduleTokenRefresh(session);
  }

  AuthSession? beginLogout() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshInFlight = null;
    final session = _session;
    _clearSession();
    return session;
  }

  Future<void> finishLogout(AuthSession? session) async {
    await _tokenStore.clearRefreshToken();
    if (session == null) return;

    final client = _authClientFactory(apiBaseUrl);
    try {
      await client.logout(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
    } catch (_) {
      // Local logout should win even if the server revoke request fails.
    } finally {
      client.close();
    }
  }

  Future<String> accessToken({bool forceRefresh = false}) {
    final activeRefresh = _refreshInFlight;
    if (activeRefresh != null) return activeRefresh;

    final session = _session;
    if (session == null) return Future.error(StateError('not authenticated'));
    if (forceRefresh) return _refreshAccessToken();
    if (!session.isAccessTokenExpiringSoon()) {
      return Future.value(session.accessToken);
    }
    return _refreshAccessToken();
  }

  Future<String> _refreshAccessToken() {
    final activeRefresh = _refreshInFlight;
    if (activeRefresh != null) return activeRefresh;

    final session = _session;
    if (session == null) return Future.error(StateError('not authenticated'));

    final refresh = _refreshSession(session.refreshToken);
    _refreshInFlight = refresh;
    unawaited(
      refresh.then<void>(
        (_) => _refreshInFlight = null,
        onError: (_) => _refreshInFlight = null,
      ),
    );
    return refresh;
  }

  Future<String> _refreshSession(String refreshToken) async {
    final client = _authClientFactory(apiBaseUrl);
    try {
      final session = await client.refresh(refreshToken);
      _setSession(session);
      _scheduleTokenRefresh(session);
      await _writeRefreshTokenBestEffort(session.refreshToken);
      return session.accessToken;
    } catch (e) {
      if (_isTerminalRefreshFailure(e)) {
        await _tokenStore.clearRefreshToken();
        _clearSession();
      } else {
        _scheduleRefreshRetry(refreshToken);
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  void _scheduleTokenRefresh(AuthSession session) {
    _refreshTimer?.cancel();
    final delay = session.accessTokenExpiresAt
        .subtract(const Duration(seconds: 60))
        .difference(DateTime.now());
    _refreshTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _refreshAccessToken().catchError((_) => '');
    });
  }

  void _scheduleRefreshRetry(String refreshToken) {
    final session = _session;
    if (session == null || session.refreshToken != refreshToken) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshRetryDelay, () {
      _refreshAccessToken().catchError((_) => '');
    });
  }

  bool _isTerminalRefreshFailure(Object error) {
    return error is AuthException && error.isUnauthorized;
  }

  Future<void> _writeRefreshTokenBestEffort(String refreshToken) async {
    try {
      await _tokenStore.writeRefreshToken(refreshToken);
    } catch (_) {
      // Keep the in-memory rotated token. A later refresh can persist it again.
    }
  }

  void _setSession(AuthSession session) {
    _session = session;
    _notifyListeners();
  }

  void _clearSession() {
    if (_session == null) return;
    _session = null;
    _notifyListeners();
  }

  void _notifyListeners() {
    for (final listener in List<AuthSessionListener>.of(_listeners)) {
      listener();
    }
  }

  void dispose() {
    _refreshTimer?.cancel();
    _listeners.clear();
  }
}
