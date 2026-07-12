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

  Future<PasswordResetChallenge> start(String login) {
    return _withClient((client) => client.startPasswordReset(login));
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

  Future<void> claimForCurrentSession(String resetToken) async {
    final tokenProvider = accessTokenProvider;
    if (tokenProvider == null) {
      throw StateError('当前页面没有可用的登录会话');
    }
    final accessToken = await tokenProvider();
    return _withClient(
      (client) => client.claimPasswordResetForSession(
        accessToken: accessToken,
        resetToken: resetToken,
      ),
    );
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
