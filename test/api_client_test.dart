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

  test(
    'joinLive retries a transient socket write abort with one idempotency key',
    () async {
      var requests = 0;
      final idempotencyKeys = <String>[];
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          requests += 1;
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/rooms/room_1/live/join');
          expect(request.headers['authorization'], 'Bearer token');
          idempotencyKeys.add(request.headers['idempotency-key']!);

          if (requests == 1) {
            throw http.ClientException(
              'SocketException: Write failed (OS Error: '
              '你的主机中的软件中止了一个已建立的连接。, errno = 10053)',
              request.url,
            );
          }

          return http.Response(jsonEncode(_liveJoinJson()), 200);
        }),
      );

      final result = await api.joinLive(
        roomId: 'room_1',
        clientLiveSessionId: 'clive_1',
        source: 'room_card_speaker',
      );

      expect(requests, 2);
      expect(idempotencyKeys, hasLength(2));
      expect(idempotencyKeys.first, isNotEmpty);
      expect(idempotencyKeys.first, idempotencyKeys.last);
      expect(result.liveKit.serverUrl, 'wss://voice.example.com');
      expect(result.live.participantCount, 1);
      api.close();
    },
  );

  test('listSessions parses recent account activity array', () async {
    final api = GangApiClient(
      baseUrl: 'http://example.test/api/v1',
      accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/auth/sessions');
        expect(request.headers['authorization'], 'Bearer token');
        return http.Response(
          jsonEncode([
            {
              'id': 'session_1',
              'user_agent': 'Flutter test',
              'ip_address': '127.0.0.1',
              'location': 'Local',
              'created_at': 1780300800,
              'last_used_at': 1780300860,
              'expires_at': 1782892800,
              'is_current': true,
            },
          ]),
          200,
        );
      }),
    );

    final sessions = await api.listSessions();

    expect(sessions, hasLength(1));
    expect(sessions.single.location, 'Local');
    expect(sessions.single.isCurrent, isTrue);
    api.close();
  });
}

Map<String, Object?> _liveJoinJson() {
  final participant = {
    'live_session_id': 'live_1',
    'user': {'id': 'user_1', 'username': 'alice', 'display_name': 'Alice'},
    'joined_at': '2026-05-31T14:00:00Z',
    'mic_muted': true,
    'headphones_muted': false,
    'voice_blocked': false,
    'camera_on': false,
    'screen_sharing': false,
    'connection_state': 'joining',
  };

  return {
    'livekit': {
      'server_url': 'wss://voice.example.com',
      'token': 'livekit-token',
      'token_expires_at': '2026-05-31T14:10:00Z',
      'room_name': 'room_1',
    },
    'participant': participant,
    'live': {
      'room_id': 'room_1',
      'participant_count': 1,
      'participants': [participant],
      'updated_at': '2026-05-31T14:00:00Z',
    },
  };
}
