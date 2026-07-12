import '../auth/auth_client.dart';

typedef EmailVerificationAuthClientFactory =
    AuthClient Function(String baseUrl);
typedef EmailVerificationAccessTokenProvider = Future<String> Function();

class EmailVerificationController {
  EmailVerificationController({
    required this.apiBaseUrl,
    EmailVerificationAuthClientFactory? authClientFactory,
    this.accessTokenProvider,
  }) : _authClientFactory =
           authClientFactory ?? ((baseUrl) => AuthClient(baseUrl: baseUrl));

  final String apiBaseUrl;
  final EmailVerificationAuthClientFactory _authClientFactory;
  final EmailVerificationAccessTokenProvider? accessTokenProvider;

  Future<bool> isEmailAvailable(String email) {
    return _withClient((client) => client.isEmailAvailable(email));
  }

  Future<EmailVerificationInspection> inspect(String email) {
    return _withClient((client) => client.inspectEmailVerification(email));
  }

  Future<EmailVerificationChallenge> start(String email) {
    return _withClient((client) => client.startEmailVerification(email));
  }

  Future<EmailVerificationChallenge> inspectOrStart(String email) async {
    final inspection = await inspect(email);
    final reusable = inspection.reusableChallenge;
    if (reusable != null) return reusable;
    if (inspection.canSend) return start(email);
    throw AuthException(
      '验证码已发送，请在 ${inspection.retryAfterSeconds} 秒后重试',
      statusCode: 429,
      code: 'rate_limited',
    );
  }

  Future<EmailVerificationChallenge> inspectOrStartForCurrentUser(
    String email,
  ) async {
    final provider = accessTokenProvider;
    if (provider == null) return inspectOrStart(email);
    final accessToken = await provider();
    final inspection = await _withClient(
      (client) =>
          client.inspectEmailVerification(email, accessToken: accessToken),
    );
    final reusable = inspection.reusableChallenge;
    if (reusable != null) return reusable;
    if (inspection.canSend) {
      return _withClient(
        (client) =>
            client.startEmailVerification(email, accessToken: accessToken),
      );
    }
    throw AuthException(
      '验证码已发送，请在 ${inspection.retryAfterSeconds} 秒后重试',
      statusCode: 429,
      code: 'rate_limited',
    );
  }

  Future<EmailVerificationChallenge> resend(String challengeId) {
    return _withClient(
      (client) => client.resendEmailVerificationCode(challengeId),
    );
  }

  Future<String> verify({required String challengeId, required String code}) {
    return _withClient(
      (client) => client.verifyEmailVerificationCode(
        challengeId: challengeId,
        code: code,
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
