import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/password_reset_controller.dart';
import 'package:client/src/auth/auth_client.dart';

void main() {
  test('password reset grant follows the active session and email', () async {
    final client = _ClaimingAuthClient();
    final controller = PasswordResetController(
      apiBaseUrl: 'https://api.example.test',
      accessTokenProvider: () async => 'access-token',
      authClientFactory: (_) => client,
    );

    expect(
      controller.isCurrentSessionAuthorizedFor('kai@example.test'),
      isFalse,
    );

    await controller.claimForCurrentSession(
      'reset-token',
      email: ' Kai@Example.Test ',
    );

    expect(client.claims, ['access-token:reset-token']);
    expect(
      controller.isCurrentSessionAuthorizedFor('kai@example.test'),
      isTrue,
    );
    expect(
      controller.isCurrentSessionAuthorizedFor('other@example.test'),
      isFalse,
    );

    controller.invalidateAuthorizationIfEmailChanged('other@example.test');
    expect(
      controller.isCurrentSessionAuthorizedFor('kai@example.test'),
      isFalse,
    );
    controller.invalidateAuthorizationIfEmailChanged('kai@example.test');
    expect(
      controller.isCurrentSessionAuthorizedFor('kai@example.test'),
      isFalse,
    );

    controller.clearCurrentSessionAuthorization();
    expect(
      controller.isCurrentSessionAuthorizedFor('kai@example.test'),
      isFalse,
    );
  });
}

class _ClaimingAuthClient extends AuthClient {
  _ClaimingAuthClient() : super(baseUrl: 'https://unused.test');

  final List<String> claims = [];

  @override
  Future<void> claimPasswordResetForSession({
    required String accessToken,
    required String resetToken,
  }) async {
    claims.add('$accessToken:$resetToken');
  }

  @override
  void close() {}
}
