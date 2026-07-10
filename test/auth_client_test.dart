import 'dart:convert';
import 'dart:io';

import 'package:client/src/auth/auth_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
