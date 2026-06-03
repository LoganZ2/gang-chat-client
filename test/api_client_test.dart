import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:client/src/protocol/api_client.dart';
import 'package:client/src/protocol/models.dart';

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
    'sendMessage keeps Chinese JSON UTF-8 without response charset',
    () async {
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/rooms/room_1/messages');
          expect(request.headers['accept'], 'application/json');
          expect(
            request.headers['content-type'],
            'application/json; charset=utf-8',
          );
          expect(
            jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, Object?>,
            {'client_message_id': 'cmsg_1', 'body': '你好，世界'},
          );

          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'message': {
                  'id': 'msg_1',
                  'room_id': 'room_1',
                  'sender': {
                    'id': 'user_1',
                    'username': 'alice',
                    'display_name': 'Alice',
                  },
                  'client_message_id': 'cmsg_1',
                  'body': '服务端中文',
                  'created_at': '2026-05-31T14:00:00Z',
                },
              }),
            ),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final message = await api.sendMessage(
        roomId: 'room_1',
        clientMessageId: 'cmsg_1',
        body: '你好，世界',
      );

      expect(message.body, '服务端中文');
      api.close();
    },
  );

  test('sendMessage can send and parse a sticker attachment', () async {
    final stickerAsset = UploadedAsset(
      id: 'asset_1',
      url: '/assets/asset_1/ok.webp',
      thumbnailUrl: null,
      mimeType: 'image/webp',
    );
    final stickerAttachment = MessageAttachment(
      type: 'sticker',
      stickerId: 'sticker_1',
      name: 'ok',
      asset: stickerAsset,
    );
    final api = GangApiClient(
      baseUrl: 'http://example.test/api/v1',
      accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/rooms/room_1/messages');
        expect(
          jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, Object?>,
          {
            'client_message_id': 'cmsg_1',
            'body': '[ok]',
            'type': 'sticker',
            'attachments': [stickerAttachment.toJson()],
          },
        );

        return http.Response(
          jsonEncode({
            'message': {
              'id': 'msg_1',
              'room_id': 'room_1',
              'sender': {
                'id': 'user_1',
                'username': 'alice',
                'display_name': 'Alice',
              },
              'client_message_id': 'cmsg_1',
              'type': 'sticker',
              'body': '[ok]',
              'attachments': [stickerAttachment.toJson()],
              'created_at': '2026-05-31T14:00:00Z',
            },
          }),
          201,
        );
      }),
    );

    final message = await api.sendMessage(
      roomId: 'room_1',
      clientMessageId: 'cmsg_1',
      body: '[ok]',
      type: 'sticker',
      attachments: [stickerAttachment],
    );

    expect(message.type, 'sticker');
    expect(message.stickerAttachment?.asset?.url, '/assets/asset_1/ok.webp');
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

  test('uploadImageAsset retries a transient socket write abort', () async {
    var requests = 0;
    final api = GangApiClient(
      baseUrl: 'http://example.test/api/v1',
      accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
      httpClient: MockClient((request) async {
        requests += 1;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/uploads/images');
        expect(request.headers['authorization'], 'Bearer token');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        expect(request.bodyBytes, isNotEmpty);

        if (requests == 1) {
          throw http.ClientException(
            'SocketException: Write failed (OS Error: '
            '你的主机中的软件中止了一个已建立的连接。, errno = 10053)',
            request.url,
          );
        }

        return http.Response(
          jsonEncode({
            'asset': {
              'id': 'asset_1',
              'url': '/assets/asset_1/sticker.png',
              'thumbnail_url': '/assets/asset_1/sticker.png',
              'mime_type': 'image/png',
              'width': 128,
              'height': 128,
            },
          }),
          201,
        );
      }),
    );

    final asset = await api.uploadImageAsset(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'sticker.png',
      purpose: 'sticker',
    );

    expect(requests, 2);
    expect(asset.id, 'asset_1');
    expect(asset.width, 128);
    api.close();
  });

  test('uploadImageAsset retries a transient 503 response', () async {
    var requests = 0;
    final api = GangApiClient(
      baseUrl: 'http://example.test/api/v1',
      accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
      httpClient: MockClient((request) async {
        requests += 1;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/uploads/images');
        expect(request.headers['authorization'], 'Bearer token');

        if (requests == 1) {
          return http.Response('service unavailable', 503);
        }

        return http.Response(
          jsonEncode({
            'asset': {
              'id': 'asset_1',
              'url': '/assets/asset_1/sticker.png',
              'thumbnail_url': '/assets/asset_1/sticker.png',
              'mime_type': 'image/png',
            },
          }),
          201,
        );
      }),
    );

    final asset = await api.uploadImageAsset(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'sticker.png',
      purpose: 'sticker',
    );

    expect(requests, 2);
    expect(asset.id, 'asset_1');
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
    'sticker item management uses rename reorder and download routes',
    () async {
      var requestIndex = 0;
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          requestIndex += 1;
          expect(request.headers['authorization'], 'Bearer token');

          switch (requestIndex) {
            case 1:
              expect(request.method, 'PATCH');
              expect(
                request.url.path,
                '/api/v1/sticker-packs/stkp_1/stickers/stk_1',
              );
              expect(jsonDecode(request.body) as Map<String, Object?>, {
                'name': 'ok',
              });
              return http.Response(
                jsonEncode({'sticker': _stickerJson(name: 'ok (2)')}),
                200,
              );
            case 2:
              expect(request.method, 'POST');
              expect(
                request.url.path,
                '/api/v1/sticker-packs/stkp_1/stickers/reorder',
              );
              expect(jsonDecode(request.body) as Map<String, Object?>, {
                'sticker_ids': ['stk_2', 'stk_1'],
              });
              return http.Response(
                jsonEncode(
                  _stickerPackJson(
                    stickers: [
                      _stickerJson(id: 'stk_2', sortOrder: 10),
                      _stickerJson(id: 'stk_1', sortOrder: 20),
                    ],
                  ),
                ),
                200,
              );
            case 3:
              expect(request.method, 'GET');
              expect(request.url.path, '/api/v1/stickers/download');
              expect(request.url.queryParameters['ids'], 'stk_1,stk_2');
              return http.Response.bytes(
                Uint8List.fromList([80, 75, 3, 4]),
                200,
                headers: {
                  'content-type': 'application/zip',
                  'content-disposition': 'attachment; filename="stickers.zip"',
                },
              );
          }

          fail(
            'unexpected request $requestIndex ${request.method} ${request.url}',
          );
        }),
      );

      final renamed = await api.updateSticker(
        packId: 'stkp_1',
        stickerId: 'stk_1',
        name: 'ok',
      );
      final reordered = await api.reorderStickers(
        packId: 'stkp_1',
        stickerIds: ['stk_2', 'stk_1'],
      );
      final downloaded = await api.downloadStickers(
        stickerIds: ['stk_1', 'stk_2'],
      );

      expect(renamed.name, 'ok (2)');
      expect(reordered.stickers.first.id, 'stk_2');
      expect(downloaded.filename, 'stickers.zip');
      expect(downloaded.mimeType, 'application/zip');
      expect(downloaded.bytes, [80, 75, 3, 4]);
      expect(requestIndex, 3);
      api.close();
    },
  );

  test('downloadStickers prefers UTF-8 filename star header', () async {
    final api = GangApiClient(
      baseUrl: 'http://example.test/api/v1',
      accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/stickers/download');
        return http.Response.bytes(
          Uint8List.fromList([80, 75, 3, 4]),
          200,
          headers: {
            'content-type': 'application/zip',
            'content-disposition':
                'attachment; filename="stickers.zip"; '
                "filename*=UTF-8''%E8%A1%A8%E6%83%85.zip",
          },
        );
      }),
    );

    final downloaded = await api.downloadStickers(stickerIds: ['stk_1']);

    expect(downloaded.filename, '表情.zip');
    api.close();
  });

  test(
    'deleteSticker treats transient close as success when sticker is gone',
    () async {
      var requestIndex = 0;
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          requestIndex += 1;
          expect(request.headers['authorization'], 'Bearer token');

          switch (requestIndex) {
            case 1:
              expect(request.method, 'DELETE');
              expect(
                request.url.path,
                '/api/v1/sticker-packs/stkp_1/stickers/stk_2',
              );
              throw http.ClientException(
                'Connection closed before full header was received',
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
          }

          fail(
            'unexpected request $requestIndex ${request.method} ${request.url}',
          );
        }),
      );

      await api.deleteSticker(packId: 'stkp_1', stickerId: 'stk_2');

      expect(requestIndex, 2);
      api.close();
    },
  );

  test(
    'deleteSticker retries a transient close when sticker remains',
    () async {
      var requestIndex = 0;
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          requestIndex += 1;
          expect(request.headers['authorization'], 'Bearer token');

          switch (requestIndex) {
            case 1:
              expect(request.method, 'DELETE');
              expect(
                request.url.path,
                '/api/v1/sticker-packs/stkp_1/stickers/stk_2',
              );
              throw http.ClientException(
                'Connection closed before full header was received',
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
            case 3:
              expect(request.method, 'DELETE');
              expect(
                request.url.path,
                '/api/v1/sticker-packs/stkp_1/stickers/stk_2',
              );
              return http.Response(jsonEncode({'ok': true}), 200);
          }

          fail(
            'unexpected request $requestIndex ${request.method} ${request.url}',
          );
        }),
      );

      await api.deleteSticker(packId: 'stkp_1', stickerId: 'stk_2');

      expect(requestIndex, 3);
      api.close();
    },
  );

  test(
    'deleteSticker treats transient 503 as success when sticker is gone',
    () async {
      var requestIndex = 0;
      final api = GangApiClient(
        baseUrl: 'http://example.test/api/v1',
        accessTokenProvider: ({bool forceRefresh = false}) async => 'token',
        httpClient: MockClient((request) async {
          requestIndex += 1;
          expect(request.headers['authorization'], 'Bearer token');

          switch (requestIndex) {
            case 1:
              expect(request.method, 'DELETE');
              expect(
                request.url.path,
                '/api/v1/sticker-packs/stkp_1/stickers/stk_2',
              );
              return http.Response('service unavailable', 503);
            case 2:
              expect(request.method, 'GET');
              expect(request.url.path, '/api/v1/sticker-packs');
              expect(request.url.queryParameters['scope'], 'personal');
              return http.Response(
                jsonEncode(_personalStickerPacksJson()),
                200,
              );
          }

          fail(
            'unexpected request $requestIndex ${request.method} ${request.url}',
          );
        }),
      );

      await api.deleteSticker(packId: 'stkp_1', stickerId: 'stk_2');

      expect(requestIndex, 2);
      api.close();
    },
  );

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

Map<String, Object?> _stickerPackJson({
  String name = 'My Stickers',
  List<Map<String, Object?>> stickers = const [],
}) {
  return {
    'pack': {
      'id': 'stkp_1',
      'scope': 'personal',
      'room_id': null,
      'name': name,
      'sort_order': 10,
      'updated_at': '2026-06-02T08:00:00Z',
      'stickers': stickers,
    },
  };
}

Map<String, Object?> _stickerJson({
  String id = 'stk_1',
  String name = 'ok',
  int sortOrder = 10,
}) {
  final assetId = 'asset_$id';
  return {
    'id': id,
    'name': name,
    'sort_order': sortOrder,
    'asset': {
      'id': assetId,
      'url': '/assets/$assetId/ok.webp',
      'thumbnail_url': '/assets/$assetId/ok.webp',
      'mime_type': 'image/webp',
      'width': 128,
      'height': 128,
      'created_at': '2026-06-02T07:59:00Z',
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
