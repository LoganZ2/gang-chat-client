import '../auth/auth_client.dart';

typedef PasswordResetAuthClientFactory = AuthClient Function(String baseUrl);
typedef PasswordResetAccessTokenProvider = Future<String> Function();

class PasswordResetController {
  PasswordResetController({
    required this.apiBaseUrl,
    PasswordResetAuthClientFactory? authClientFactory,
    this.accessTokenProvider,
  }) : _authClientFactory =
           authClientFactory ?? ((baseUrl) => AuthClient(baseUrl: baseUrl));

  final String apiBaseUrl;
  final PasswordResetAuthClientFactory _authClientFactory;
  final PasswordResetAccessTokenProvider? accessTokenProvider;
  String? _sessionAuthorizedEmail;

  bool isCurrentSessionAuthorizedFor(String? email) {
    final normalized = email?.trim().toLowerCase() ?? '';
    return normalized.isNotEmpty && _sessionAuthorizedEmail == normalized;
  }

  void clearCurrentSessionAuthorization() {
    _sessionAuthorizedEmail = null;
  }

  void invalidateAuthorizationIfEmailChanged(String? email) {
    final authorizedEmail = _sessionAuthorizedEmail;
    if (authorizedEmail == null) return;
    if (authorizedEmail != (email?.trim().toLowerCase() ?? '')) {
      clearCurrentSessionAuthorization();
    }
  }

  Future<PasswordResetChallenge> start(String login) {
    return _withClient((client) => client.startPasswordReset(login));
  }

  Future<PasswordResetInspection> inspect(String login) {
    return _withClient((client) => client.inspectPasswordReset(login));
  }

  Future<PasswordResetChallenge> resend(String challengeId) {
    return _withClient((client) => client.resendPasswordResetCode(challengeId));
  }

  Future<String> verify({required String challengeId, required String code}) {
    return _withClient(
      (client) =>
          client.verifyPasswordResetCode(challengeId: challengeId, code: code),
    );
  }

  Future<void> complete({
    required String resetToken,
    required String newPassword,
  }) {
    return _withClient(
      (client) => client.completePasswordReset(
        resetToken: resetToken,
        newPassword: newPassword,
      ),
    );
  }

  Future<void> claimForCurrentSession(
    String resetToken, {
    required String email,
  }) async {
    final tokenProvider = accessTokenProvider;
    if (tokenProvider == null) {
      throw StateError('当前页面没有可用的登录会话');
    }
    final accessToken = await tokenProvider();
    await _withClient(
      (client) => client.claimPasswordResetForSession(
        accessToken: accessToken,
        resetToken: resetToken,
      ),
    );
    _sessionAuthorizedEmail = email.trim().toLowerCase();
  }

  Future<T> _withClient<T>(Future<T> Function(AuthClient client) action) async {
    final client = _authClientFactory(apiBaseUrl);
    try {
      return await action(client);
    } finally {
      client.close();
    }
  }
}
