import '../auth/auth_client.dart';

typedef EmailVerificationAuthClientFactory =
    AuthClient Function(String baseUrl);

class EmailVerificationController {
  EmailVerificationController({
    required this.apiBaseUrl,
    EmailVerificationAuthClientFactory? authClientFactory,
  }) : _authClientFactory =
           authClientFactory ?? ((baseUrl) => AuthClient(baseUrl: baseUrl));

  final String apiBaseUrl;
  final EmailVerificationAuthClientFactory _authClientFactory;

  Future<EmailVerificationInspection> inspect(String email) {
    return _withClient((client) => client.inspectEmailVerification(email));
  }

  Future<EmailVerificationChallenge> start(String email) {
    return _withClient((client) => client.startEmailVerification(email));
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
