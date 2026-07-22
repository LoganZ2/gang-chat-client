import 'dart:convert';
import 'dart:io';

import 'package:client/src/auth/auth_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('auth requests report the supplied client system user agent', () async {
    late http.Request capturedRequest;
    final client = AuthClient(
      baseUrl: 'https://api.example.test',
      userAgent: 'GangChat Client (Android)',
      httpClient: MockClient((request) async {
        capturedRequest = request;
        return _authResponse();
      }),
    );

    await client.login(login: 'alice', password: 'secret');

    expect(capturedRequest.headers['user-agent'], 'GangChat Client (Android)');
    client.close();
  });

  test('auth checks normalized username availability', () async {
    late Uri requestedUri;
    final client = AuthClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({'available': false}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final available = await client.isUsernameAvailable(' Taken_Name ');

    expect(available, isFalse);
    expect(requestedUri.path, '/auth/username-availability');
    expect(requestedUri.queryParameters['username'], 'Taken_Name');
    client.close();
  });

  test('username availability uses the auth TLS fallback chain', () async {
    var directCalls = 0;
    var fallbackCalls = 0;
    final client = AuthClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient((request) async {
        directCalls += 1;
        throw HandshakeException('connection terminated');
      }),
      environmentProxyClientFactory: () => MockClient((request) async {
        fallbackCalls += 1;
        return http.Response(
          jsonEncode({'available': true}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      handshakeRetryDelays: const [Duration.zero, Duration.zero],
    );

    final available = await client.isUsernameAvailable('available_name');

    expect(available, isTrue);
    expect(directCalls, 2);
    expect(fallbackCalls, 1);
    client.close();
  });

  test('auth checks normalized email availability', () async {
    late Uri requestedUri;
    final client = AuthClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode({'available': false}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final available = await client.isEmailAvailable(' Taken@Example.Test ');

    expect(available, isFalse);
    expect(requestedUri.path, '/auth/email-availability');
    expect(requestedUri.queryParameters['email'], 'Taken@Example.Test');
    client.close();
  });

  test('auth retries a TLS handshake failure on the direct client', () async {
    var calls = 0;
    var fallbackCalls = 0;
    final client = AuthClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient((request) async {
        calls += 1;
        if (calls == 1) throw HandshakeException('connection terminated');
        return _authResponse();
      }),
      environmentProxyClientFactory: () => MockClient((request) async {
        fallbackCalls += 1;
        return _authResponse();
      }),
      handshakeRetryDelays: const [Duration.zero, Duration.zero],
    );

    final session = await client.login(login: 'alice', password: 'secret');

    expect(session.user.username, 'alice');
    expect(calls, 2);
    expect(fallbackCalls, 0);
    client.close();
  });

  test('auth falls back to the environment proxy after TLS retries', () async {
    var directCalls = 0;
    var fallbackCalls = 0;
    final client = AuthClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient((request) async {
        directCalls += 1;
        throw HandshakeException('connection terminated');
      }),
      environmentProxyClientFactory: () => MockClient((request) async {
        fallbackCalls += 1;
        return _authResponse();
      }),
      handshakeRetryDelays: const [Duration.zero, Duration.zero],
    );

    final session = await client.login(login: 'alice', password: 'secret');

    expect(session.user.username, 'alice');
    expect(directCalls, 2);
    expect(fallbackCalls, 1);
    client.close();
  });

  test('auth does not retry unrelated transport failures', () async {
    var directCalls = 0;
    var fallbackCalls = 0;
    final client = AuthClient(
      baseUrl: 'https://api.example.test',
      httpClient: MockClient((request) async {
        directCalls += 1;
        throw http.ClientException('connection reset', request.url);
      }),
      environmentProxyClientFactory: () => MockClient((request) async {
        fallbackCalls += 1;
        return _authResponse();
      }),
      handshakeRetryDelays: const [Duration.zero, Duration.zero],
    );

    await expectLater(
      client.login(login: 'alice', password: 'secret'),
      throwsA(isA<http.ClientException>()),
    );

    expect(directCalls, 1);
    expect(fallbackCalls, 0);
    client.close();
  });

  test('registration email verification sends the complete protocol', () async {
    final requests = <http.Request>[];
    final client = AuthClient(
      baseUrl: 'https://api.example.test/api/v1',
      httpClient: MockClient((request) async {
        requests.add(request);
        switch (request.url.path) {
          case '/api/v1/auth/email-verification/inspect':
            return http.Response(
              jsonEncode({'can_send': true, 'retry_after': 0}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          case '/api/v1/auth/email-verification/start':
          case '/api/v1/auth/email-verification/resend':
            return http.Response(
              jsonEncode({
                'challenge_id': 'email-challenge',
                'retry_after': 60,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          case '/api/v1/auth/email-verification/verify':
            return http.Response(
              jsonEncode({'verification_token': 'verified-email-token'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          case '/api/v1/auth/register':
            return _authResponse();
        }
        return http.Response('not found', 404);
      }),
    );

    final inspection = await client.inspectEmailVerification(
      ' kai@example.test ',
    );
    final started = await client.startEmailVerification('kai@example.test');
    final resent = await client.resendEmailVerificationCode(started.id);
    final token = await client.verifyEmailVerificationCode(
      challengeId: resent.id,
      code: '123456',
    );
    await client.register(
      username: 'kai',
      email: 'kai@example.test',
      password: 'secret-password',
      emailVerificationToken: token,
    );

    expect(inspection.canSend, isTrue);
    expect(started.retryAfterSeconds, 60);
    expect(token, 'verified-email-token');
    expect(jsonDecode(requests.first.body), {'email': 'kai@example.test'});
    expect(jsonDecode(requests[3].body), {
      'challenge_id': 'email-challenge',
      'code': '123456',
    });
    expect(jsonDecode(requests.last.body), {
      'username': 'kai',
      'email': 'kai@example.test',
      'password': 'secret-password',
      'email_verification_token': 'verified-email-token',
    });
    client.close();
  });

  test(
    'authenticated email verification uses the current-user routes',
    () async {
      final requests = <http.Request>[];
      final client = AuthClient(
        baseUrl: 'https://api.example.test/api/v1',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/inspect')) {
            return http.Response(
              jsonEncode({'can_send': true, 'retry_after': 0}),
              200,
            );
          }
          return http.Response(
            jsonEncode({'challenge_id': 'challenge', 'retry_after': 60}),
            200,
          );
        }),
      );

      await client.inspectEmailVerification(
        'bound@example.test',
        accessToken: 'access-token',
      );
      await client.startEmailVerification(
        'bound@example.test',
        accessToken: 'access-token',
      );

      expect(requests.map((request) => request.url.path), [
        '/api/v1/users/me/email-verification/inspect',
        '/api/v1/users/me/email-verification/start',
      ]);
      expect(
        requests.every(
          (request) =>
              request.headers['authorization'] == 'Bearer access-token',
        ),
        isTrue,
      );
      client.close();
    },
  );

  test('password reset client sends the complete protocol payloads', () async {
    final requests = <http.Request>[];
    final client = AuthClient(
      baseUrl: 'https://api.example.test/api/v1',
      httpClient: MockClient((request) async {
        requests.add(request);
        switch (request.url.path) {
          case '/api/v1/auth/password-reset/inspect':
            return http.Response(
              jsonEncode({
                'can_send': true,
                'masked_email': 'k***@example.test',
                'retry_after': 0,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          case '/api/v1/auth/password-reset/start':
          case '/api/v1/auth/password-reset/resend':
            return http.Response(
              jsonEncode({
                'challenge_id': 'challenge-1',
                'masked_email': 'k***@example.test',
                'retry_after': 60,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          case '/api/v1/auth/password-reset/verify':
            return http.Response(
              jsonEncode({'reset_token': 'reset-token'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          case '/api/v1/auth/password-reset/complete':
          case '/api/v1/auth/password-reset/claim':
            return http.Response(
              jsonEncode({'ok': true}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
        }
        return http.Response('not found', 404);
      }),
    );

    final inspection = await client.inspectPasswordReset(' kai ');
    final started = await client.startPasswordReset(' kai ');
    final resent = await client.resendPasswordResetCode(started.id);
    final token = await client.verifyPasswordResetCode(
      challengeId: started.id,
      code: '123456',
    );
    await client.completePasswordReset(
      resetToken: token,
      newPassword: 'new-password',
    );
    await client.claimPasswordResetForSession(
      accessToken: 'access-token',
      resetToken: token,
    );

    expect(inspection.canSend, isTrue);
    expect(started.maskedEmail, 'k***@example.test');
    expect(resent.retryAfterSeconds, 60);
    expect(token, 'reset-token');
    expect(jsonDecode(requests.first.body), {'login': 'kai'});
    expect(jsonDecode(requests[3].body), {
      'challenge_id': 'challenge-1',
      'code': '123456',
    });
    expect(requests.last.headers['authorization'], 'Bearer access-token');
    client.close();
  });
}

http.Response _authResponse() {
  return http.Response(
    jsonEncode({
      'access_token': 'access-token',
      'refresh_token': 'refresh-token',
      'expires_in': 900,
      'user': {
        'id': 'user-1',
        'uid': '10000001',
        'username': 'alice',
        'display_name': 'Alice',
      },
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
