import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'utf8_json.dart';

typedef AccessTokenProvider = Future<String> Function({bool forceRefresh});
typedef UploadProgressCallback =
    void Function({required int sentBytes, required int totalBytes});

class DownloadedFile {
  const DownloadedFile({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

class UploadTransferController {
  Completer<void>? _resumeCompleter;
  bool _cancelled = false;

  bool get isPaused => _resumeCompleter != null;
  bool get isCancelled => _cancelled;

  void pause() {
    if (_cancelled || _resumeCompleter != null) return;
    _resumeCompleter = Completer<void>();
  }

  void resume() {
    final completer = _resumeCompleter;
    if (completer == null) return;
    _resumeCompleter = null;
    if (!completer.isCompleted) completer.complete();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    resume();
  }

  Future<void> waitIfPaused() async {
    while (!_cancelled) {
      final completer = _resumeCompleter;
      if (completer == null) return;
      await completer.future;
    }
  }
}

class UploadCancelledException implements Exception {
  const UploadCancelledException();

  @override
  String toString() => 'Upload cancelled';
}

abstract interface class GangApi {
  Future<CurrentUser> me();

  Future<CurrentUser> updateAccount({
    String? username,
    String? email,
    bool? emailPublic,
    String? phoneNumber,
    bool? phoneNumberPublic,
    String? language,
  });

  Future<CurrentUser> updateProfile({
    String? displayName,
    String? bio,
    String? gender,
    String? avatarAssetId,
    String? defaultAvatarKey,
  });

  Future<UploadedAsset> uploadImageAsset({
    required Uint8List bytes,
    required String filename,
    String purpose = 'image',
  });

  Future<UploadedAsset> uploadFileAsset({
    required Uint8List bytes,
    required String filename,
    String purpose = 'message_file',
    UploadProgressCallback? onProgress,
    UploadTransferController? controller,
  });

  Future<List<StickerPack>> listStickerPacks({
    String scope = 'personal',
    String? roomId,
  });

  Future<StickerPack> createStickerPack({
    required String name,
    String scope = 'personal',
    String? roomId,
    int? sortOrder,
  });

  Future<StickerPack> updateStickerPack({
    required String packId,
    String? name,
    int? sortOrder,
  });

  Future<void> deleteStickerPack(String packId);

  Future<void> addSticker({
    required String packId,
    required String assetId,
    required String name,
    int? sortOrder,
    String? idempotencyKey,
    String scope = 'personal',
    String? roomId,
  });

  Future<void> deleteSticker({
    required String packId,
    required String stickerId,
    String scope = 'personal',
    String? roomId,
  });

  Future<Sticker> updateSticker({
    required String packId,
    required String stickerId,
    String? name,
    int? sortOrder,
  });

  Future<StickerPack> reorderStickers({
    required String packId,
    required List<String> stickerIds,
  });

  Future<DownloadedFile> downloadStickers({required List<String> stickerIds});

  Future<StickerPack> saveSticker({
    required String roomId,
    required String stickerId,
    String targetScope = 'personal',
    String? targetPackId,
    String? name,
    int? sortOrder,
  });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    bool revokeOtherSessions = true,
  });

  Future<List<UserSession>> listSessions();

  Future<void> deleteMyAccount({required bool confirm});

  Future<RoomPage> listRooms({int limit = 50, String? cursor});

  Future<RoomDetail> createRoom({
    required String name,
    String? description,
    String? visibility,
    String? joinPolicy,
    bool? aiVoiceAnnouncementsEnabled,
    String? avatarAssetId,
    String? defaultAvatarKey,
    String? idempotencyKey,
  });

  Future<RoomDetail> getRoom(String roomId);

  Future<RoomDetail> updateRoom({
    required String roomId,
    String? name,
    String? description,
    String? visibility,
    String? joinPolicy,
    bool? aiVoiceAnnouncementsEnabled,
    String? avatarAssetId,
    String? defaultAvatarKey,
  });

  Future<RoomDetail> updateMyRoomSettings({
    required String roomId,
    String? remarkName,
    String? notificationPolicy,
    String? roomDisplayName,
    String? avatarAssetId,
    String? defaultAvatarKey,
  });

  Future<void> leaveRoom({
    required String roomId,
    bool confirmDeleteIfEmpty = false,
  });

  Future<void> deleteRoom({
    required String roomId,
    required String confirmName,
  });

  Future<RoomMember> updateRoomMemberRole({
    required String roomId,
    required String userId,
    required String role,
  });

  Future<RoomDetail> transferRoomCreator({
    required String roomId,
    required String userId,
  });

  Future<List<PublicRoom>> searchRooms({required String query, int limit = 20});

  Future<JoinRoomResult> joinRoom(String roomId);

  Future<RoomMemberPage> listRoomMembers(
    String roomId, {
    int limit = 100,
    String? cursor,
  });

  Future<RoomMemberProfile> getRoomMemberProfile({
    required String roomId,
    required String userId,
  });

  Future<RoomInvite> inviteMember({
    required String roomId,
    required String userId,
  });

  Future<List<RoomInvite>> listRoomInvites({String status = 'pending'});

  Future<JoinRoomResult> reviewRoomInvite({
    required String inviteId,
    required bool accept,
  });

  Future<List<UserSummary>> searchUsers({
    required String query,
    int limit = 20,
  });

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
    String type = 'text',
    List<MessageAttachment> attachments = const [],
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
  Future<CurrentUser> updateAccount({
    String? username,
    String? email,
    bool? emailPublic,
    String? phoneNumber,
    bool? phoneNumberPublic,
    String? language,
  }) async {
    final body = <String, Object?>{};
    if (username != null) body['username'] = username;
    if (email != null) body['email'] = email;
    if (emailPublic != null) body['email_public'] = emailPublic;
    if (phoneNumber != null) body['phone_number'] = phoneNumber;
    if (phoneNumberPublic != null) {
      body['phone_number_public'] = phoneNumberPublic;
    }
    if (language != null) body['language'] = language;
    final decoded = await _sendJson((token) {
      return _httpClient.patch(
        _uri('/users/me/account'),
        headers: _headers(token),
        body: encodeJsonBody(body),
      );
    });
    return CurrentUser.fromJson(decoded['user']! as Map<String, Object?>);
  }

  @override
  Future<CurrentUser> updateProfile({
    String? displayName,
    String? bio,
    String? gender,
    String? avatarAssetId,
    String? defaultAvatarKey,
  }) async {
    final body = <String, Object?>{};
    if (displayName != null) body['display_name'] = displayName;
    if (bio != null) body['bio'] = bio;
    if (gender != null) body['gender'] = gender;
    if (avatarAssetId != null) body['avatar_asset_id'] = avatarAssetId;
    if (defaultAvatarKey != null) body['default_avatar_key'] = defaultAvatarKey;
    final decoded = await _sendJson((token) {
      return _httpClient.patch(
        _uri('/users/me/profile'),
        headers: _headers(token),
        body: encodeJsonBody(body),
      );
    }, retryTransientFailures: true);
    return CurrentUser.fromJson(decoded['user']! as Map<String, Object?>);
  }

  @override
  Future<UploadedAsset> uploadImageAsset({
    required Uint8List bytes,
    required String filename,
    String purpose = 'image',
  }) async {
    return _uploadAsset(
      path: '/uploads/images',
      bytes: bytes,
      filename: filename,
      purpose: purpose,
    );
  }

  @override
  Future<UploadedAsset> uploadFileAsset({
    required Uint8List bytes,
    required String filename,
    String purpose = 'message_file',
    UploadProgressCallback? onProgress,
    UploadTransferController? controller,
  }) async {
    return _uploadAsset(
      path: '/uploads/files',
      bytes: bytes,
      filename: filename,
      purpose: purpose,
      onProgress: onProgress,
      controller: controller,
    );
  }

  Future<UploadedAsset> _uploadAsset({
    required String path,
    required Uint8List bytes,
    required String filename,
    required String purpose,
    UploadProgressCallback? onProgress,
    UploadTransferController? controller,
  }) async {
    final decoded = await _sendJson((token) async {
      final request = http.MultipartRequest('POST', _uri(path));
      request.headers['authorization'] = 'Bearer $token';
      request.fields['purpose'] = purpose;
      final file = onProgress == null && controller == null
          ? http.MultipartFile.fromBytes('file', bytes, filename: filename)
          : http.MultipartFile(
              'file',
              _uploadByteStream(
                bytes,
                onProgress: onProgress,
                controller: controller,
              ),
              bytes.length,
              filename: filename,
            );
      request.files.add(file);
      final streamed = await _httpClient.send(request);
      return http.Response.fromStream(streamed);
    }, retryTransientFailures: true);
    return UploadedAsset.fromJson(decoded['asset']! as Map<String, Object?>);
  }

  @override
  Future<List<StickerPack>> listStickerPacks({
    String scope = 'personal',
    String? roomId,
  }) async {
    final query = {'scope': scope};
    if (roomId != null) query['room_id'] = roomId;
    final decoded = await _sendJson((token) {
      return _httpClient.get(
        _uri('/sticker-packs', query),
        headers: _headers(token),
      );
    }, retryTransientFailures: true);
    return (decoded['packs'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map(StickerPack.fromJson)
        .toList();
  }

  @override
  Future<StickerPack> createStickerPack({
    required String name,
    String scope = 'personal',
    String? roomId,
    int? sortOrder,
  }) async {
    final body = <String, Object?>{'scope': scope, 'name': name};
    if (roomId != null) body['room_id'] = roomId;
    if (sortOrder != null) body['sort_order'] = sortOrder;
    final decoded = await _sendJson((token) {
      return _httpClient.post(
        _uri('/sticker-packs'),
        headers: _headers(token),
        body: encodeJsonBody(body),
      );
    });
    return StickerPack.fromJson(decoded['pack']! as Map<String, Object?>);
  }

  @override
  Future<StickerPack> updateStickerPack({
    required String packId,
    String? name,
    int? sortOrder,
  }) async {
    final body = <String, Object?>{};
    if (name != null) body['name'] = name;
    if (sortOrder != null) body['sort_order'] = sortOrder;
    final decoded = await _sendJson((token) {
      return _httpClient.patch(
        _uri('/sticker-packs/$packId'),
        headers: _headers(token),
        body: encodeJsonBody(body),
      );
    });
    return StickerPack.fromJson(decoded['pack']! as Map<String, Object?>);
  }

  @override
  Future<void> deleteStickerPack(String packId) async {
    await _sendJson((token) {
      return _httpClient.delete(
        _uri('/sticker-packs/$packId'),
        headers: _headers(token),
      );
    });
  }

  @override
  Future<void> addSticker({
    required String packId,
    required String assetId,
    required String name,
    int? sortOrder,
    String? idempotencyKey,
    String scope = 'personal',
    String? roomId,
  }) async {
    final body = <String, Object?>{'asset_id': assetId, 'name': name};
    if (sortOrder != null) body['sort_order'] = sortOrder;
    final requestIdempotencyKey = idempotencyKey ?? newUuid();
    Future<void> send() {
      return _sendJson((token) {
        return _httpClient.post(
          _uri('/sticker-packs/$packId/stickers'),
          headers: _headers(token, idempotencyKey: requestIdempotencyKey),
          body: encodeJsonBody(body),
        );
      });
    }

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await send();
        return;
      } on ApiException catch (e) {
        if (!_isRetryableHttpFailure(e.statusCode)) rethrow;
        if (await _stickerAssetAlreadyLinked(
          packId: packId,
          assetId: assetId,
          scope: scope,
          roomId: roomId,
        )) {
          return;
        }
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 120 * attempt));
      } on http.ClientException catch (e) {
        if (!_isRetryableTransportFailure(e)) rethrow;
        if (await _stickerAssetAlreadyLinked(
          packId: packId,
          assetId: assetId,
          scope: scope,
          roomId: roomId,
        )) {
          return;
        }
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 120 * attempt));
      }
    }
  }

  Future<bool> _stickerAssetAlreadyLinked({
    required String packId,
    required String assetId,
    required String scope,
    String? roomId,
  }) async {
    try {
      final packs = await listStickerPacks(scope: scope, roomId: roomId);
      for (final pack in packs) {
        if (pack.id != packId) continue;
        for (final sticker in pack.stickers) {
          if (sticker.asset.id == assetId) return true;
        }
      }
    } catch (_) {
      // If verification is also unavailable, let the caller retry once.
    }
    return false;
  }

  Future<bool> _stickerAlreadyDeleted({
    required String packId,
    required String stickerId,
    required String scope,
    String? roomId,
  }) async {
    try {
      final packs = await listStickerPacks(scope: scope, roomId: roomId);
      for (final pack in packs) {
        if (pack.id != packId) continue;
        return !pack.stickers.any((sticker) => sticker.id == stickerId);
      }
    } catch (_) {
      // If verification also fails, let the delete path retry.
    }
    return false;
  }

  @override
  Future<void> deleteSticker({
    required String packId,
    required String stickerId,
    String scope = 'personal',
    String? roomId,
  }) async {
    Future<void> send() {
      return _sendJson((token) {
        return _httpClient.delete(
          _uri('/sticker-packs/$packId/stickers/$stickerId'),
          headers: _headers(token),
        );
      });
    }

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await send();
        return;
      } on ApiException catch (e) {
        if (e.statusCode == 404) return;
        if (!_isRetryableHttpFailure(e.statusCode)) rethrow;
        if (await _stickerAlreadyDeleted(
          packId: packId,
          stickerId: stickerId,
          scope: scope,
          roomId: roomId,
        )) {
          return;
        }
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 120 * attempt));
      } on http.ClientException catch (e) {
        if (!_isRetryableTransportFailure(e)) rethrow;
        if (await _stickerAlreadyDeleted(
          packId: packId,
          stickerId: stickerId,
          scope: scope,
          roomId: roomId,
        )) {
          return;
        }
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 120 * attempt));
      }
    }
  }

  @override
  Future<Sticker> updateSticker({
    required String packId,
    required String stickerId,
    String? name,
    int? sortOrder,
  }) async {
    final body = <String, Object?>{};
    if (name != null) body['name'] = name;
    if (sortOrder != null) body['sort_order'] = sortOrder;
    final decoded = await _sendJson((token) {
      return _httpClient.patch(
        _uri('/sticker-packs/$packId/stickers/$stickerId'),
        headers: _headers(token),
        body: encodeJsonBody(body),
      );
    });
    return Sticker.fromJson(decoded['sticker']! as Map<String, Object?>);
  }

  @override
  Future<StickerPack> reorderStickers({
    required String packId,
    required List<String> stickerIds,
  }) async {
    final decoded = await _sendJson((token) {
      return _httpClient.post(
        _uri('/sticker-packs/$packId/stickers/reorder'),
        headers: _headers(token),
        body: encodeJsonBody({'sticker_ids': stickerIds}),
      );
    });
    return StickerPack.fromJson(decoded['pack']! as Map<String, Object?>);
  }

  @override
  Future<DownloadedFile> downloadStickers({
    required List<String> stickerIds,
  }) async {
    final response = await _sendWithAuth((token) {
      return _httpClient.get(
        _uri('/stickers/download', {'ids': stickerIds.join(',')}),
        headers: {'authorization': 'Bearer $token'},
      );
    });
    _throwIfFailed(response);
    return DownloadedFile(
      bytes: response.bodyBytes,
      filename: _downloadFilename(response),
      mimeType: response.headers['content-type'] ?? 'application/octet-stream',
    );
  }

  @override
  Future<StickerPack> saveSticker({
    required String roomId,
    required String stickerId,
    String targetScope = 'personal',
    String? targetPackId,
    String? name,
    int? sortOrder,
  }) async {
    final body = <String, Object?>{
      'sticker_id': stickerId,
      'target_scope': targetScope,
    };
    if (targetPackId != null) body['target_pack_id'] = targetPackId;
    if (name != null) body['name'] = name;
    if (sortOrder != null) body['sort_order'] = sortOrder;
    final decoded = await _sendJson((token) {
      return _httpClient.post(
        _uri('/rooms/$roomId/stickers/save'),
        headers: _headers(token),
        body: encodeJsonBody(body),
      );
    });
    return StickerPack.fromJson(decoded['pack']! as Map<String, Object?>);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    bool revokeOtherSessions = true,
  }) async {
    await _sendJson((token) {
      return _httpClient.post(
        _uri('/auth/password'),
        headers: _headers(token),
        body: encodeJsonBody({
          'current_password': currentPassword,
          'new_password': newPassword,
          'revoke_other_sessions': revokeOtherSessions,
        }),
      );
    });
  }

  @override
  Future<List<UserSession>> listSessions() async {
    final decoded = await _sendJsonValue((token) {
      return _httpClient.get(_uri('/auth/sessions'), headers: _headers(token));
    }, retryTransientFailures: true);
    final items = decoded is List
        ? decoded.cast<Object?>()
        : decoded is Map<String, Object?>
        ? decoded['items'] as List<Object?>? ??
              decoded['sessions'] as List<Object?>? ??
              const []
        : const [];
    return items
        .cast<Map<String, Object?>>()
        .map(UserSession.fromJson)
        .toList();
  }

  @override
  Future<void> deleteMyAccount({required bool confirm}) async {
    await _sendJson((token) {
      return _httpClient.delete(
        _uri('/users/me/account'),
        headers: _headers(token),
        body: encodeJsonBody({'confirm': confirm}),
      );
    });
  }

  @override
  Future<RoomPage> listRooms({int limit = 50, String? cursor}) async {
    final query = {'limit': '$limit'};
    if (cursor != null) query['cursor'] = cursor;
    final decoded = await _sendJson((token) {
      return _httpClient.get(_uri('/rooms', query), headers: _headers(token));
    }, retryTransientFailures: true);
    return RoomPage.fromJson(decoded);
  }

  @override
  Future<RoomDetail> createRoom({
    required String name,
    String? description,
    String? visibility,
    String? joinPolicy,
    bool? aiVoiceAnnouncementsEnabled,
    String? avatarAssetId,
    String? defaultAvatarKey,
    String? idempotencyKey,
  }) async {
    final decoded = await _sendJson((token) {
      final body = <String, Object?>{'name': name};
      if (description != null) body['description'] = description;
      if (visibility != null) body['visibility'] = visibility;
      if (joinPolicy != null) body['join_policy'] = joinPolicy;
      if (aiVoiceAnnouncementsEnabled != null) {
        body['ai_voice_announcements_enabled'] = aiVoiceAnnouncementsEnabled;
      }
      if (avatarAssetId != null) body['avatar_asset_id'] = avatarAssetId;
      if (defaultAvatarKey != null) {
        body['default_avatar_key'] = defaultAvatarKey;
      }
      return _httpClient.post(
        _uri('/rooms'),
        headers: _headers(token, idempotencyKey: idempotencyKey ?? newUuid()),
        body: encodeJsonBody(body),
      );
    });
    return RoomDetail.fromJson(decoded['room']! as Map<String, Object?>);
  }

  @override
  Future<RoomDetail> getRoom(String roomId) async {
    final decoded = await _sendJson((token) {
      return _httpClient.get(_uri('/rooms/$roomId'), headers: _headers(token));
    }, retryTransientFailures: true);
    return RoomDetail.fromJson(decoded['room']! as Map<String, Object?>);
  }

  @override
  Future<RoomDetail> updateRoom({
    required String roomId,
    String? name,
    String? description,
    String? visibility,
    String? joinPolicy,
    bool? aiVoiceAnnouncementsEnabled,
    String? avatarAssetId,
    String? defaultAvatarKey,
  }) async {
    final body = <String, Object?>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (visibility != null) body['visibility'] = visibility;
    if (joinPolicy != null) body['join_policy'] = joinPolicy;
    if (aiVoiceAnnouncementsEnabled != null) {
      body['ai_voice_announcements_enabled'] = aiVoiceAnnouncementsEnabled;
    }
    if (avatarAssetId != null) body['avatar_asset_id'] = avatarAssetId;
    if (defaultAvatarKey != null) body['default_avatar_key'] = defaultAvatarKey;
    final decoded = await _sendJson((token) {
      return _httpClient.patch(
        _uri('/rooms/$roomId'),
        headers: _headers(token),
        body: encodeJsonBody(body),
      );
    }, retryTransientFailures: true);
    return RoomDetail.fromJson(decoded['room']! as Map<String, Object?>);
  }

  @override
  Future<RoomDetail> updateMyRoomSettings({
    required String roomId,
    String? remarkName,
    String? notificationPolicy,
    String? roomDisplayName,
    String? avatarAssetId,
    String? defaultAvatarKey,
  }) async {
    final body = <String, Object?>{};
    if (remarkName != null) body['remark_name'] = remarkName;
    if (notificationPolicy != null) {
      body['notification_policy'] = notificationPolicy;
    }
    if (roomDisplayName != null) body['room_display_name'] = roomDisplayName;
    if (avatarAssetId != null) body['avatar_asset_id'] = avatarAssetId;
    if (defaultAvatarKey != null) body['default_avatar_key'] = defaultAvatarKey;
    final decoded = await _sendJson((token) {
      return _httpClient.patch(
        _uri('/rooms/$roomId/me'),
        headers: _headers(token),
        body: encodeJsonBody(body),
      );
    }, retryTransientFailures: true);
    return RoomDetail.fromJson(decoded['room']! as Map<String, Object?>);
  }

  @override
  Future<void> leaveRoom({
    required String roomId,
    bool confirmDeleteIfEmpty = false,
  }) async {
    await _sendJson((token) {
      return _httpClient.delete(
        _uri('/rooms/$roomId/members/me'),
        headers: _headers(token),
        body: encodeJsonBody({
          if (confirmDeleteIfEmpty) 'confirm_delete_if_empty': true,
        }),
      );
    });
  }

  @override
  Future<void> deleteRoom({
    required String roomId,
    required String confirmName,
  }) async {
    await _sendJson((token) {
      return _httpClient.delete(
        _uri('/rooms/$roomId'),
        headers: _headers(token),
        body: encodeJsonBody({'confirm_name': confirmName}),
      );
    });
  }

  @override
  Future<RoomMember> updateRoomMemberRole({
    required String roomId,
    required String userId,
    required String role,
  }) async {
    final decoded = await _sendJson((token) {
      return _httpClient.patch(
        _uri('/rooms/$roomId/members/$userId'),
        headers: _headers(token),
        body: encodeJsonBody({'role': role}),
      );
    });
    return RoomMember.fromJson(decoded['member']! as Map<String, Object?>);
  }

  @override
  Future<RoomDetail> transferRoomCreator({
    required String roomId,
    required String userId,
  }) async {
    final decoded = await _sendJson((token) {
      return _httpClient.patch(
        _uri('/rooms/$roomId/creator'),
        headers: _headers(token),
        body: encodeJsonBody({'user_id': userId}),
      );
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
    }, retryTransientFailures: true);
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
  Future<RoomMemberPage> listRoomMembers(
    String roomId, {
    int limit = 100,
    String? cursor,
  }) async {
    final query = {'limit': '$limit'};
    if (cursor != null) query['cursor'] = cursor;
    final decoded = await _sendJson((token) {
      return _httpClient.get(
        _uri('/rooms/$roomId/members', query),
        headers: _headers(token),
      );
    }, retryTransientFailures: true);
    return RoomMemberPage.fromJson(decoded);
  }

  @override
  Future<RoomMemberProfile> getRoomMemberProfile({
    required String roomId,
    required String userId,
  }) async {
    final decoded = await _sendJson((token) {
      return _httpClient.get(
        _uri('/rooms/$roomId/members/$userId/profile'),
        headers: _headers(token),
      );
    }, retryTransientFailures: true);
    return RoomMemberProfile.fromJson(
      decoded['profile']! as Map<String, Object?>,
    );
  }

  @override
  Future<RoomInvite> inviteMember({
    required String roomId,
    required String userId,
  }) async {
    final decoded = await _sendJson((token) {
      return _httpClient.post(
        _uri('/rooms/$roomId/invites'),
        headers: _headers(token, idempotencyKey: newUuid()),
        body: encodeJsonBody({'user_id': userId}),
      );
    });
    return RoomInvite.fromJson(decoded['invite']! as Map<String, Object?>);
  }

  @override
  Future<List<RoomInvite>> listRoomInvites({String status = 'pending'}) async {
    final decoded = await _sendJson((token) {
      return _httpClient.get(
        _uri('/room-invites', {'status': status}),
        headers: _headers(token),
      );
    }, retryTransientFailures: true);
    return (decoded['invites'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map(RoomInvite.fromJson)
        .toList();
  }

  @override
  Future<JoinRoomResult> reviewRoomInvite({
    required String inviteId,
    required bool accept,
  }) async {
    final decoded = await _sendJson((token) {
      return _httpClient.patch(
        _uri('/room-invites/$inviteId'),
        headers: _headers(token),
        body: encodeJsonBody({'decision': accept ? 'accept' : 'reject'}),
      );
    });
    final roomJson = decoded['room'] as Map<String, Object?>?;
    if (roomJson != null) {
      return JoinRoomResult(room: RoomDetail.fromJson(roomJson));
    }
    if (decoded['join_request'] != null) {
      return const JoinRoomResult(pending: true);
    }
    return const JoinRoomResult();
  }

  @override
  Future<List<UserSummary>> searchUsers({
    required String query,
    int limit = 20,
  }) async {
    final decoded = await _sendJson((token) {
      return _httpClient.get(
        _uri('/users/search', {'q': query, 'limit': '$limit'}),
        headers: _headers(token),
      );
    }, retryTransientFailures: true);
    return (decoded['users'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map(UserSummary.fromJson)
        .toList();
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
    }, retryTransientFailures: true);
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
        body: encodeJsonBody({'decision': approve ? 'approve' : 'reject'}),
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
    }, retryTransientFailures: true);
    return MessagePage.fromJson(decoded);
  }

  @override
  Future<Message> sendMessage({
    required String roomId,
    required String clientMessageId,
    required String body,
    String type = 'text',
    List<MessageAttachment> attachments = const [],
    String? idempotencyKey,
  }) async {
    final requestIdempotencyKey = idempotencyKey ?? newUuid();
    final decoded = await _sendJson((token) {
      final requestBody = <String, Object?>{
        'client_message_id': clientMessageId,
        'body': body,
      };
      if (type != 'text') requestBody['type'] = type;
      if (attachments.isNotEmpty) {
        requestBody['attachments'] = attachments
            .map((attachment) => attachment.toJson())
            .toList();
      }
      return _httpClient.post(
        _uri('/rooms/$roomId/messages'),
        headers: _headers(token, idempotencyKey: requestIdempotencyKey),
        body: encodeJsonBody(requestBody),
      );
    }, retryTransientFailures: true);
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
        body: encodeJsonBody({'last_read_message_id': lastReadMessageId}),
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
    }, retryTransientFailures: true);
    return LiveState.fromJson(decoded['live']! as Map<String, Object?>);
  }

  @override
  Future<LiveJoinResult> joinLive({
    required String roomId,
    required String clientLiveSessionId,
    required String source,
    String? idempotencyKey,
  }) {
    final requestIdempotencyKey = idempotencyKey ?? newUuid();
    return _sendJson((token) {
      return _httpClient.post(
        _uri('/rooms/$roomId/live/join'),
        headers: _headers(token, idempotencyKey: requestIdempotencyKey),
        body: encodeJsonBody({
          'client_live_session_id': clientLiveSessionId,
          'source': source,
        }),
      );
    }, retryTransientFailures: true).then(LiveJoinResult.fromJson);
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
        body: encodeJsonBody(body),
      );
    });
    return LiveParticipant.fromJson(
      decoded['participant']! as Map<String, Object?>,
    );
  }

  Future<Map<String, Object?>> _sendJson(
    Future<http.Response> Function(String accessToken) send, {
    bool retryTransientFailures = false,
  }) async {
    final decoded = await _sendJsonValue(
      send,
      retryTransientFailures: retryTransientFailures,
    );
    return decoded as Map<String, Object?>;
  }

  Future<Object?> _sendJsonValue(
    Future<http.Response> Function(String accessToken) send, {
    bool retryTransientFailures = false,
  }) async {
    http.Response response;
    try {
      response = await _sendWithAuth(send);
    } on http.ClientException catch (e) {
      if (!retryTransientFailures || !_isRetryableTransportFailure(e)) {
        rethrow;
      }
      response = await _sendWithAuth(send);
    }
    if (retryTransientFailures &&
        _isRetryableHttpFailure(response.statusCode)) {
      response = await _sendWithAuth(send);
    }
    _throwIfFailed(response);
    final decoded = decodeJsonBody(response);
    return decoded ?? {};
  }

  Future<http.Response> _sendWithAuth(
    Future<http.Response> Function(String accessToken) send,
  ) async {
    var token = await accessTokenProvider();
    var response = await send(token);
    if (response.statusCode == 401) {
      token = await accessTokenProvider(forceRefresh: true);
      response = await send(token);
    }
    return response;
  }

  bool _isRetryableTransportFailure(http.ClientException error) {
    final message = error.message.toLowerCase();
    return message.contains('connection closed') ||
        message.contains('connection reset') ||
        message.contains('broken pipe') ||
        message.contains('write failed') ||
        message.contains('connection abort') ||
        message.contains('errno = 10053') ||
        message.contains('errno=10053');
  }

  bool _isRetryableHttpFailure(int statusCode) {
    return statusCode == 502 || statusCode == 503 || statusCode == 504;
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
      'accept': jsonAcceptHeader,
      'content-type': jsonUtf8ContentType,
    };
    if (idempotencyKey != null) headers['idempotency-key'] = idempotencyKey;
    return headers;
  }

  String _downloadFilename(http.Response response) {
    final disposition = response.headers['content-disposition'] ?? '';
    final encoded = RegExp(
      r"filename\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(disposition);
    if (encoded != null) {
      return Uri.decodeComponent(encoded.group(1)!);
    }
    final quoted = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
    if (quoted != null) return quoted.group(1)!;
    final unquoted = RegExp(r'filename=([^;]+)').firstMatch(disposition);
    if (unquoted != null) return unquoted.group(1)!.trim();
    final mimeType = response.headers['content-type'] ?? '';
    return mimeType.contains('zip') ? 'stickers.zip' : 'sticker';
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
      final decoded = decodeJsonBody(response) as Map<String, Object?>;
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
      '请求失败 (${response.statusCode})',
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

Stream<List<int>> _uploadByteStream(
  Uint8List bytes, {
  UploadProgressCallback? onProgress,
  UploadTransferController? controller,
}) async* {
  const chunkSize = 64 * 1024;
  final total = bytes.length;
  onProgress?.call(sentBytes: 0, totalBytes: total);
  var sent = 0;
  while (sent < total) {
    if (controller?.isCancelled ?? false) {
      throw const UploadCancelledException();
    }
    await controller?.waitIfPaused();
    if (controller?.isCancelled ?? false) {
      throw const UploadCancelledException();
    }
    final end = (sent + chunkSize) > total ? total : sent + chunkSize;
    yield Uint8List.sublistView(bytes, sent, end);
    sent = end;
    onProgress?.call(sentBytes: sent, totalBytes: total);
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
