import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:client/src/protocol/api_client.dart';

void main() {
  test(
    'listMessages retries once after a transient closed connection',
    () async {
      var requests = 0;
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          requests += 1;
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/rooms/room_1/messages');
          expect(request.url.queryParameters['limit'], '50');
          expect(request.headers['authorization'], 'Bearer token');

          if (requests == 1) {
            throw http.ClientException(
              'Connection closed before full header was received',
              request.url,
            );
          }

          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'id': 'msg_1',
                  'room_id': 'room_1',
                  'sender': {
                    'id': 'user_1',
                    'username': 'alice',
                    'display_name': 'Alice',
                  },
                  'client_message_id': 'cmsg_1',
                  'body': 'hello',
                  'created_at': '2026-05-31T14:00:00Z',
                },
              ],
              'has_more': false,
              'next_before': null,
            }),
            200,
          );
        }),
      );

      final page = await api.listMessages(roomId: 'room_1');

      expect(requests, 2);
      expect(page.messages.single.body, 'hello');
      api.close();
    },
  );

  test('sendMessage does not retry a dropped connection', () async {
    var requests = 0;
    final api = GangApiClient(
      baseUrl: 'http://example.test/api/v1',
      accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
      httpClient: MockClient((request) async {
        requests += 1;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/rooms/room_1/messages');
        throw http.ClientException('Connection reset by peer', request.url);
      }),
    );

    await expectLater(
      api.sendMessage(
        roomId: 'room_1',
        clientMessageId: 'cmsg_1',
        body: 'hello',
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(requests, 1);
    api.close();
  });
}
