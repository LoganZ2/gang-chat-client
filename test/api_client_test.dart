import 'dart:convert';
import 'dart:typed_data';

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

  test('uploadImageAsset posts multipart image data', () async {
    final api = GangApiClient(
      baseUrl: 'http://example.test/api/v1',
      accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/uploads/images');
        expect(request.headers['authorization'], 'Bearer token');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        expect(request.bodyBytes, isNotEmpty);
        return http.Response(
          jsonEncode({
            'asset': {
              'id': 'asset_1',
              'url': '/assets/asset_1/avatar.png',
              'thumbnail_url': '/assets/asset_1/avatar.png',
              'mime_type': 'image/png',
            },
          }),
          201,
        );
      }),
    );

    final asset = await api.uploadImageAsset(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'avatar.png',
      purpose: 'avatar',
    );

    expect(asset.id, 'asset_1');
    expect(asset.mimeType, 'image/png');
    api.close();
  });

  test('listStickerPacks parses personal sticker assets', () async {
    final api = GangApiClient(
      baseUrl: 'http://example.test/api/v1',
      accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/sticker-packs');
        expect(request.url.queryParameters['scope'], 'personal');
        expect(request.headers['authorization'], 'Bearer token');
        return http.Response(
          jsonEncode({
            'packs': [
              {
                'id': 'stkp_1',
                'scope': 'personal',
                'room_id': null,
                'name': 'My Stickers',
                'sort_order': 10,
                'updated_at': '2026-06-02T08:00:00Z',
                'stickers': [
                  {
                    'id': 'stk_1',
                    'name': 'ok',
                    'sort_order': 20,
                    'asset': {
                      'id': 'asset_1',
                      'url': '/assets/asset_1/ok.webp',
                      'thumbnail_url': '/assets/asset_1/ok.webp',
                      'mime_type': 'image/webp',
                      'width': 128,
                      'height': 128,
                      'created_at': '2026-06-02T07:59:00Z',
                    },
                  },
                ],
              },
            ],
          }),
          200,
        );
      }),
    );

    final packs = await api.listStickerPacks();

    expect(packs.single.name, 'My Stickers');
    expect(packs.single.stickers.single.asset.mimeType, 'image/webp');
    expect(packs.single.stickers.single.asset.width, 128);
    api.close();
  });

  test('sticker pack management uses server sticker routes', () async {
    var requestIndex = 0;
    final api = GangApiClient(
      baseUrl: 'http://example.test/api/v1',
      accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
      httpClient: MockClient((request) async {
        requestIndex += 1;
        expect(request.headers['authorization'], 'Bearer token');

        switch (requestIndex) {
          case 1:
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/sticker-packs');
            expect(jsonDecode(request.body) as Map<String, Object?>, {
              'scope': 'personal',
              'name': 'My Stickers',
              'sort_order': 10,
            });
            return http.Response(jsonEncode(_stickerPackJson()), 201);
          case 2:
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/sticker-packs/stkp_1/stickers');
            expect(request.headers['idempotency-key'], isNotEmpty);
            expect(jsonDecode(request.body) as Map<String, Object?>, {
              'asset_id': 'asset_2',
              'name': 'hi',
              'sort_order': 20,
            });
            return http.Response(
              jsonEncode({
                'sticker': {
                  'id': 'stk_2',
                  'asset_id': 'asset_2',
                  'name': 'hi',
                  'sort_order': 20,
                },
              }),
              201,
            );
          case 3:
            expect(request.method, 'PATCH');
            expect(request.url.path, '/api/v1/sticker-packs/stkp_1');
            expect(jsonDecode(request.body) as Map<String, Object?>, {
              'name': 'Saved',
              'sort_order': 30,
            });
            return http.Response(
              jsonEncode(_stickerPackJson(name: 'Saved')),
              200,
            );
          case 4:
            expect(request.method, 'DELETE');
            expect(
              request.url.path,
              '/api/v1/sticker-packs/stkp_1/stickers/stk_2',
            );
            return http.Response(jsonEncode({'ok': true}), 200);
          case 5:
            expect(request.method, 'DELETE');
            expect(request.url.path, '/api/v1/sticker-packs/stkp_1');
            return http.Response(jsonEncode({'ok': true}), 200);
        }

        fail(
          'unexpected request $requestIndex ${request.method} ${request.url}',
        );
      }),
    );

    final pack = await api.createStickerPack(
      name: 'My Stickers',
      sortOrder: 10,
    );
    await api.addSticker(
      packId: pack.id,
      assetId: 'asset_2',
      name: 'hi',
      sortOrder: 20,
    );
    final updated = await api.updateStickerPack(
      packId: pack.id,
      name: 'Saved',
      sortOrder: 30,
    );
    await api.deleteSticker(packId: pack.id, stickerId: 'stk_2');
    await api.deleteStickerPack(pack.id);

    expect(updated.name, 'Saved');
    expect(requestIndex, 5);
    api.close();
  });

  test(
    'addSticker treats transient write failure as success when asset exists',
    () async {
      var requestIndex = 0;
      final idempotencyKeys = <String>[];
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          requestIndex += 1;
          expect(request.headers['authorization'], 'Bearer token');

          switch (requestIndex) {
            case 1:
              expect(request.method, 'POST');
              expect(request.url.path, '/api/v1/sticker-packs/stkp_1/stickers');
              idempotencyKeys.add(request.headers['idempotency-key']!);
              throw http.ClientException(
                'SocketException: Write failed (OS Error: connection aborted, errno = 10053)',
                request.url,
              );
            case 2:
              expect(request.method, 'GET');
              expect(request.url.path, '/api/v1/sticker-packs');
              expect(request.url.queryParameters['scope'], 'personal');
              return http.Response(
                jsonEncode(_personalStickerPacksJson(linkedAssetId: 'asset_2')),
                200,
              );
          }

          fail(
            'unexpected request $requestIndex ${request.method} ${request.url}',
          );
        }),
      );

      await api.addSticker(packId: 'stkp_1', assetId: 'asset_2', name: 'hi');

      expect(requestIndex, 2);
      expect(idempotencyKeys.single, isNotEmpty);
      api.close();
    },
  );

  test(
    'addSticker retries once after transient write failure when not linked',
    () async {
      var requestIndex = 0;
      final idempotencyKeys = <String>[];
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          requestIndex += 1;
          expect(request.headers['authorization'], 'Bearer token');

          switch (requestIndex) {
            case 1:
              expect(request.method, 'POST');
              expect(request.url.path, '/api/v1/sticker-packs/stkp_1/stickers');
              idempotencyKeys.add(request.headers['idempotency-key']!);
              throw http.ClientException(
                'SocketException: Write failed (OS Error: connection aborted, errno = 10053)',
                request.url,
              );
            case 2:
              expect(request.method, 'GET');
              expect(request.url.path, '/api/v1/sticker-packs');
              expect(request.url.queryParameters['scope'], 'personal');
              return http.Response(
                jsonEncode(_personalStickerPacksJson()),
                200,
              );
            case 3:
              expect(request.method, 'POST');
              expect(request.url.path, '/api/v1/sticker-packs/stkp_1/stickers');
              idempotencyKeys.add(request.headers['idempotency-key']!);
              expect(jsonDecode(request.body) as Map<String, Object?>, {
                'asset_id': 'asset_2',
                'name': 'hi',
              });
              return http.Response(
                jsonEncode({
                  'sticker': {
                    'id': 'stk_2',
                    'asset_id': 'asset_2',
                    'name': 'hi',
                    'sort_order': 10,
                  },
                }),
                201,
              );
          }

          fail(
            'unexpected request $requestIndex ${request.method} ${request.url}',
          );
        }),
      );

      await api.addSticker(packId: 'stkp_1', assetId: 'asset_2', name: 'hi');

      expect(requestIndex, 3);
      expect(idempotencyKeys, hasLength(2));
      expect(idempotencyKeys.first, isNotEmpty);
      expect(idempotencyKeys.first, idempotencyKeys.last);
      api.close();
    },
  );

  test(
    'addSticker recovers after repeated transient write failures once linked',
    () async {
      var requestIndex = 0;
      final idempotencyKeys = <String>[];
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          requestIndex += 1;
          expect(request.headers['authorization'], 'Bearer token');

          switch (requestIndex) {
            case 1:
              expect(request.method, 'POST');
              expect(request.url.path, '/api/v1/sticker-packs/stkp_1/stickers');
              idempotencyKeys.add(request.headers['idempotency-key']!);
              throw http.ClientException(
                'SocketException: Write failed (OS Error: connection aborted, errno = 10053)',
                request.url,
              );
            case 2:
              expect(request.method, 'GET');
              expect(request.url.path, '/api/v1/sticker-packs');
              return http.Response(
                jsonEncode(_personalStickerPacksJson()),
                200,
              );
            case 3:
              expect(request.method, 'POST');
              expect(request.url.path, '/api/v1/sticker-packs/stkp_1/stickers');
              idempotencyKeys.add(request.headers['idempotency-key']!);
              throw http.ClientException(
                'SocketException: Write failed (OS Error: connection aborted, errno = 10053)',
                request.url,
              );
            case 4:
              expect(request.method, 'GET');
              expect(request.url.path, '/api/v1/sticker-packs');
              return http.Response(
                jsonEncode(_personalStickerPacksJson(linkedAssetId: 'asset_2')),
                200,
              );
          }

          fail(
            'unexpected request $requestIndex ${request.method} ${request.url}',
          );
        }),
      );

      await api.addSticker(packId: 'stkp_1', assetId: 'asset_2', name: 'hi');

      expect(requestIndex, 4);
      expect(idempotencyKeys, hasLength(2));
      expect(idempotencyKeys.first, idempotencyKeys.last);
      api.close();
    },
  );

  test('updateProfile retries a transient socket write abort', () async {
    var requests = 0;
    final api = GangApiClient(
      baseUrl: 'http://example.test/api/v1',
      accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
      httpClient: MockClient((request) async {
        requests += 1;
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/v1/users/me/profile');
        expect(request.headers['authorization'], 'Bearer token');
        expect(jsonDecode(request.body) as Map<String, Object?>, {
          'avatar_asset_id': 'asset_1',
        });

        if (requests == 1) {
          throw http.ClientException(
            'SocketException: Write failed (OS Error: '
            '你的主机中的软件中止了一个已建立的连接, errno = 10053)',
            request.url,
          );
        }

        return http.Response(
          jsonEncode({
            'user': {
              'id': 'user_1',
              'uid': '1000001',
              'username': 'alice',
              'display_name': 'Alice',
              'avatar_url': '/assets/asset_1/avatar.png',
              'default_avatar_key': 'blue-3',
            },
          }),
          200,
        );
      }),
    );

    final user = await api.updateProfile(avatarAssetId: 'asset_1');

    expect(requests, 2);
    expect(user.avatarUrl, '/assets/asset_1/avatar.png');
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

Map<String, Object?> _stickerPackJson({String name = 'My Stickers'}) {
  return {
    'pack': {
      'id': 'stkp_1',
      'scope': 'personal',
      'room_id': null,
      'name': name,
      'sort_order': 10,
      'updated_at': '2026-06-02T08:00:00Z',
      'stickers': const [],
    },
  };
}

Map<String, Object?> _personalStickerPacksJson({String? linkedAssetId}) {
  return {
    'packs': [
      {
        'id': 'stkp_1',
        'scope': 'personal',
        'room_id': null,
        'name': 'My Stickers',
        'sort_order': 10,
        'updated_at': '2026-06-02T08:00:00Z',
        'stickers': [
          if (linkedAssetId != null)
            {
              'id': 'stk_2',
              'name': 'hi',
              'sort_order': 10,
              'asset': {
                'id': linkedAssetId,
                'url': '/assets/$linkedAssetId/hi.webp',
                'thumbnail_url': '/assets/$linkedAssetId/hi.webp',
                'mime_type': 'image/webp',
              },
            },
        ],
      },
    ],
  };
}
