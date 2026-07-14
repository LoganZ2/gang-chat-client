import 'dart:convert';

import 'package:client/src/app/email_verification_controller.dart';
import 'package:client/src/auth/auth_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'current-user verification opens active challenge when inspect omits id',
    () async {
      final requestedPaths = <String>[];
      final authorizationHeaders = <String?>[];
      final controller = EmailVerificationController(
        apiBaseUrl: 'https://api.example.test/api/v1',
        accessTokenProvider: () async => 'access-token',
        authClientFactory: (baseUrl) => AuthClient(
          baseUrl: baseUrl,
          httpClient: MockClient((request) async {
            requestedPaths.add(request.url.path);
            authorizationHeaders.add(request.headers['authorization']);
            if (request.url.path ==
                '/api/v1/users/me/email-verification/inspect') {
              return _jsonResponse({'can_send': false, 'retry_after': 42});
            }
            if (request.url.path ==
                '/api/v1/users/me/email-verification/start') {
              return _jsonResponse({
                'challenge_id': 'existing-challenge',
                'retry_after': 42,
              });
            }
            return http.Response('unexpected request', 404);
          }),
        ),
      );

      final challenge = await controller.inspectOrStartForCurrentUser(
        'new@example.test',
      );

      expect(challenge.id, 'existing-challenge');
      expect(challenge.retryAfterSeconds, 42);
      expect(requestedPaths, [
        '/api/v1/users/me/email-verification/inspect',
        '/api/v1/users/me/email-verification/start',
      ]);
      expect(authorizationHeaders, [
        'Bearer access-token',
        'Bearer access-token',
      ]);
    },
  );
}

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
