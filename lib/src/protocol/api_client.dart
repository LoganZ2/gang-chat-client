import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';

typedef AccessTokenProvider = Future<String> Function({bool forceRefresh});

abstract interface class GangApi {
  Future<CurrentUser> me();

  Future<RoomPage> listRooms({int limit = 50, String? cursor});

  Future<RoomDetail> createRoom({
    required String name,
    String? avatarAssetId,
    String? idempotencyKey,
  });

  Future<RoomDetail> getRoom(String roomId);

  Future<List<PublicRoom>> searchRooms({required String query, int limit = 20});

  Future<JoinRoomResult> joinRoom(String roomId);

  Future<List<JoinRequest>> listJoinRequests(
    String roomId, {
    String status = 'pending',
  });

  Future<void> reviewJoinRequest({
    required String roomId,
    required String requestId,
    required bool approve,
  });

  Future<MessagePage> listMessages({
    required String roomId,
    int limit = 50,
    String? before,
  });

  Future<Message> sendMessage({
    required String roomId,
    required String clientMessageId,
    required String body,
    String? idempotencyKey,
  });

  Future<int> markRead({
    required String roomId,
    required String lastReadMessageId,
  });

  Future<LiveState> getLiveState(String roomId);

  Future<LiveJoinResult> joinLive({
    required String roomId,
    required String clientLiveSessionId,
    required String source,
    String? idempotencyKey,
  });

  Future<LiveParticipant> updateMyLiveState({
    required String roomId,
    bool? micMuted,
    bool? cameraOn,
    bool? screenSharing,
    String? connectionState,
  });

  void close();
}

class GangApiClient implements GangApi {
  GangApiClient({
    required this.baseUrl,
    required this.accessTokenProvider,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final AccessTokenProvider accessTokenProvider;
  final http.Client _httpClient;

  @override
  Future<CurrentUser> me() async {
    final decoded = await _sendJson((token) {
      return _httpClient.get(_uri('/me'), headers: _headers(token));
    });
    return CurrentUser.fromJson(decoded);
  }

  @override
  Future<RoomPage> listRooms({int limit = 50, String? cursor}) async {
    final query = {'limit': '$limit'};
    if (cursor != null) query['cursor'] = cursor;
    final decoded = await _sendJson((token) {
      return _httpClient.get(_uri('/rooms', query), headers: _headers(token));
    });
    return RoomPage.fromJson(decoded);
  }

  @override
  Future<RoomDetail> createRoom({
    required String name,
    String? avatarAssetId,
    String? idempotencyKey,
  }) async {
    final decoded = await _sendJson((token) {
      final body = <String, Object?>{'name': name};
      if (avatarAssetId != null) body['avatar_asset_id'] = avatarAssetId;
      return _httpClient.post(
        _uri('/rooms'),
        headers: _headers(token, idempotencyKey: idempotencyKey ?? newUuid()),
        body: jsonEncode(body),
      );
    });
    return RoomDetail.fromJson(decoded['room']! as Map<String, Object?>);
  }

  @override
  Future<RoomDetail> getRoom(String roomId) async {
    final decoded = await _sendJson((token) {
      return _httpClient.get(_uri('/rooms/$roomId'), headers: _headers(token));
    });
    return RoomDetail.fromJson(decoded['room']! as Map<String, Object?>);
  }

  @override
  Future<List<PublicRoom>> searchRooms({
    required String query,
    int limit = 20,
  }) async {
    final decoded = await _sendJson((token) {
      return _httpClient.get(
        _uri('/rooms/search', {'q': query, 'limit': '$limit'}),
        headers: _headers(token),
      );
    });
    return (decoded['rooms'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map(PublicRoom.fromJson)
        .toList();
  }

  @override
  Future<JoinRoomResult> joinRoom(String roomId) async {
    final decoded = await _sendJson((token) {
      return _httpClient.post(
        _uri('/rooms/$roomId/join'),
        headers: _headers(token, idempotencyKey: newUuid()),
      );
    });
    final roomJson = decoded['room'] as Map<String, Object?>?;
    if (roomJson != null) {
      return JoinRoomResult(room: RoomDetail.fromJson(roomJson));
    }
    // approval_required path: server returns {"join_request": {...}} with 202.
    return const JoinRoomResult(pending: true);
  }

  @override
  Future<List<JoinRequest>> listJoinRequests(
    String roomId, {
    String status = 'pending',
  }) async {
    final decoded = await _sendJson((token) {
      return _httpClient.get(
        _uri('/rooms/$roomId/join-requests', {'status': status}),
        headers: _headers(token),
      );
    });
    return (decoded['requests'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map(JoinRequest.fromJson)
        .toList();
  }

  @override
  Future<void> reviewJoinRequest({
    required String roomId,
    required String requestId,
    required bool approve,
  }) async {
    await _sendJson((token) {
      return _httpClient.patch(
        _uri('/rooms/$roomId/join-requests/$requestId'),
        headers: _headers(token),
        body: jsonEncode({'decision': approve ? 'approve' : 'reject'}),
      );
    });
  }

  @override
  Future<MessagePage> listMessages({
    required String roomId,
    int limit = 50,
    String? before,
  }) async {
    final query = {'limit': '$limit'};
    if (before != null) query['before'] = before;
    final decoded = await _sendJson((token) {
      return _httpClient.get(
        _uri('/rooms/$roomId/messages', query),
        headers: _headers(token),
      );
    });
    return MessagePage.fromJson(decoded);
  }

  @override
  Future<Message> sendMessage({
    required String roomId,
    required String clientMessageId,
    required String body,
    String? idempotencyKey,
  }) async {
    final decoded = await _sendJson((token) {
      return _httpClient.post(
        _uri('/rooms/$roomId/messages'),
        headers: _headers(token, idempotencyKey: idempotencyKey ?? newUuid()),
        body: jsonEncode({'client_message_id': clientMessageId, 'body': body}),
      );
    });
    return Message.fromJson(decoded['message']! as Map<String, Object?>);
  }

  @override
  Future<int> markRead({
    required String roomId,
    required String lastReadMessageId,
  }) async {
    final decoded = await _sendJson((token) {
      return _httpClient.post(
        _uri('/rooms/$roomId/read'),
        headers: _headers(token),
        body: jsonEncode({'last_read_message_id': lastReadMessageId}),
      );
    });
    return decoded['unread_count']! as int;
  }

  @override
  Future<LiveState> getLiveState(String roomId) async {
    final decoded = await _sendJson((token) {
      return _httpClient.get(
        _uri('/rooms/$roomId/live'),
        headers: _headers(token),
      );
    });
    return LiveState.fromJson(decoded['live']! as Map<String, Object?>);
  }

  @override
  Future<LiveJoinResult> joinLive({
    required String roomId,
    required String clientLiveSessionId,
    required String source,
    String? idempotencyKey,
  }) {
    return _sendJson((token) {
      return _httpClient.post(
        _uri('/rooms/$roomId/live/join'),
        headers: _headers(token, idempotencyKey: idempotencyKey ?? newUuid()),
        body: jsonEncode({
          'client_live_session_id': clientLiveSessionId,
          'source': source,
        }),
      );
    }).then(LiveJoinResult.fromJson);
  }

  @override
  Future<LiveParticipant> updateMyLiveState({
    required String roomId,
    bool? micMuted,
    bool? cameraOn,
    bool? screenSharing,
    String? connectionState,
  }) async {
    final body = <String, Object?>{};
    if (micMuted != null) body['mic_muted'] = micMuted;
    if (cameraOn != null) body['camera_on'] = cameraOn;
    if (screenSharing != null) body['screen_sharing'] = screenSharing;
    if (connectionState != null) body['connection_state'] = connectionState;
    final decoded = await _sendJson((token) {
      return _httpClient.patch(
        _uri('/rooms/$roomId/live/me'),
        headers: _headers(token),
        body: jsonEncode(body),
      );
    });
    return LiveParticipant.fromJson(
      decoded['participant']! as Map<String, Object?>,
    );
  }

  Future<Map<String, Object?>> _sendJson(
    Future<http.Response> Function(String accessToken) send,
  ) async {
    var token = await accessTokenProvider();
    var response = await send(token);
    if (response.statusCode == 401) {
      token = await accessTokenProvider(forceRefresh: true);
      response = await send(token);
    }
    _throwIfFailed(response);
    if (response.body.isEmpty) return {};
    return jsonDecode(response.body) as Map<String, Object?>;
  }

  void _throwIfFailed(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw ApiException.fromResponse(response);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse('$normalizedBase$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  Map<String, String> _headers(String accessToken, {String? idempotencyKey}) {
    final headers = {
      'authorization': 'Bearer $accessToken',
      'content-type': 'application/json',
    };
    if (idempotencyKey != null) headers['idempotency-key'] = idempotencyKey;
    return headers;
  }

  @override
  void close() => _httpClient.close();
}

class RoomPage {
  const RoomPage({required this.rooms, required this.nextCursor});

  final List<RoomCard> rooms;
  final String? nextCursor;

  factory RoomPage.fromJson(Map<String, Object?> json) {
    return RoomPage(
      rooms: (json['rooms']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(RoomCard.fromJson)
          .toList(),
      nextCursor: json['next_cursor'] as String?,
    );
  }
}

class MessagePage {
  const MessagePage({
    required this.messages,
    required this.hasMore,
    required this.nextBefore,
  });

  final List<Message> messages;
  final bool hasMore;
  final String? nextBefore;

  factory MessagePage.fromJson(Map<String, Object?> json) {
    return MessagePage(
      messages: (json['messages']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(Message.fromJson)
          .toList(),
      hasMore: json['has_more']! as bool,
      nextBefore: json['next_before'] as String?,
    );
  }
}

class ApiException implements Exception {
  ApiException(
    this.message, {
    required this.statusCode,
    required this.code,
    required this.requestId,
  });

  final String message;
  final int statusCode;
  final String code;
  final String? requestId;

  factory ApiException.fromResponse(http.Response response) {
    final headerRequestId = response.headers['x-request-id'];
    try {
      final decoded = jsonDecode(response.body) as Map<String, Object?>;
      final error = decoded['error'] as Map<String, Object?>?;
      final message = error?['message'] as String?;
      final code = error?['code'] as String?;
      final requestId = error?['request_id'] as String? ?? headerRequestId;
      if (message != null && message.isNotEmpty) {
        return ApiException(
          message,
          statusCode: response.statusCode,
          code: code ?? 'request_failed',
          requestId: requestId,
        );
      }
    } catch (_) {
      // Fall through to the status-based message.
    }
    return ApiException(
      'Request failed (${response.statusCode})',
      statusCode: response.statusCode,
      code: 'request_failed',
      requestId: headerRequestId,
    );
  }

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() {
    if (requestId == null) return message;
    return '$message (request $requestId)';
  }
}

String newClientId(String prefix) => '${prefix}_${newUuid()}';

String newUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
  final value = bytes.map(hex).join();
  return [
    value.substring(0, 8),
    value.substring(8, 12),
    value.substring(12, 16),
    value.substring(16, 20),
    value.substring(20),
  ].join('-');
}
