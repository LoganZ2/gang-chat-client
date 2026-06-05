class UserCommonRoom {
  const UserCommonRoom({
    required this.id,
    required this.rid,
    required this.name,
    this.visibility = 'private',
    this.remarkName,
    this.avatarUrl,
    this.defaultAvatarKey = 'room-1',
    this.roomDisplayName,
    this.roomRole,
  });

  final String id;
  final String rid;
  final String name;
  final String visibility;
  final String? remarkName;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final String? roomDisplayName;
  final String? roomRole;

  factory UserCommonRoom.fromJson(Map<String, Object?> json) {
    return UserCommonRoom(
      id: _stringFromJson(json, const ['id', 'room_id']) ?? '',
      rid: _stringFromJson(json, const ['rid', 'room_rid']) ?? '',
      name: _stringFromJson(json, const ['name', 'room_name']) ?? '',
      visibility:
          _stringFromJson(json, const ['visibility', 'room_visibility']) ??
          'private',
      remarkName: _stringFromJson(json, const [
        'remark_name',
        'room_remark',
        'room_remark_name',
      ]),
      avatarUrl: _stringFromJson(json, const ['avatar_url', 'room_avatar_url']),
      defaultAvatarKey:
          _stringFromJson(json, const [
            'default_avatar_key',
            'room_default_avatar_key',
          ]) ??
          'room-1',
      roomDisplayName: _stringFromJson(json, const [
        'room_display_name',
        'room_username',
        'room_nickname',
        'room_remark',
        'member_display_name',
      ]),
      roomRole:
          _stringFromJson(json, const ['room_role', 'membership_role']) ??
          _stringFromJson(_nullableMap(json['membership']), const ['role']),
    );
  }

  bool get isUsable => id.trim().isNotEmpty && name.trim().isNotEmpty;
}

class UserSummary {
  const UserSummary({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    this.uid,
    this.bio,
    this.gender,
    this.email,
    this.emailPublic,
    this.phoneNumber,
    this.phoneNumberPublic,
    this.roomDisplayName,
    this.roomRole,
    this.isSuperuser = false,
    this.isOnline,
    this.commonRooms = const [],
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final String? uid;
  final String? bio;
  final String? gender;
  final String? email;
  final bool? emailPublic;
  final String? phoneNumber;
  final bool? phoneNumberPublic;
  final String? roomDisplayName;
  final String? roomRole;
  final bool isSuperuser;
  final bool? isOnline;
  final List<UserCommonRoom> commonRooms;

  factory UserSummary.fromJson(Map<String, Object?> json) {
    final username = json['username']! as String;
    return UserSummary(
      id: json['id']! as String,
      username: username,
      displayName: json['display_name'] as String? ?? username,
      avatarUrl: json['avatar_url'] as String?,
      defaultAvatarKey: json['default_avatar_key'] as String? ?? 'blue-3',
      uid: _stringFromJson(json, const ['uid', 'user_uid']),
      bio: _stringFromJson(json, const ['bio', 'signature']),
      gender: _stringFromJson(json, const ['gender']),
      email: _stringFromJson(json, const ['email']),
      emailPublic: _boolFromJson(json, const ['email_public']),
      phoneNumber: _stringFromJson(json, const ['phone_number', 'phone']),
      phoneNumberPublic: _boolFromJson(json, const [
        'phone_number_public',
        'phone_public',
      ]),
      roomDisplayName: _stringFromJson(json, const [
        'room_display_name',
        'room_username',
        'room_nickname',
        'room_remark',
        'remark_name',
        'remark',
      ]),
      roomRole:
          _stringFromJson(json, const ['room_role', 'membership_role']) ??
          _stringFromJson(_nullableMap(json['membership']), const ['role']) ??
          _stringFromJson(json, const ['role']),
      isSuperuser: json['is_superuser'] as bool? ?? false,
      isOnline:
          _boolFromJson(json, const ['is_online', 'online']) ??
          _onlineFromStatus(
            _stringFromJson(json, const [
              'presence',
              'presence_status',
              'status',
              'connection_state',
            ]),
          ),
      commonRooms: _listOfMaps(
        json['common_rooms'],
      ).map(UserCommonRoom.fromJson).where((room) => room.isUsable).toList(),
    );
  }

  UserSummary copyWith({
    String? displayName,
    String? avatarUrl,
    String? defaultAvatarKey,
    String? uid,
    String? bio,
    String? gender,
    String? email,
    bool? emailPublic,
    String? phoneNumber,
    bool? phoneNumberPublic,
    String? roomDisplayName,
    String? roomRole,
    bool? isSuperuser,
    bool? isOnline,
    List<UserCommonRoom>? commonRooms,
  }) {
    return UserSummary(
      id: id,
      username: username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      defaultAvatarKey: defaultAvatarKey ?? this.defaultAvatarKey,
      uid: uid ?? this.uid,
      bio: bio ?? this.bio,
      gender: gender ?? this.gender,
      email: email ?? this.email,
      emailPublic: emailPublic ?? this.emailPublic,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      phoneNumberPublic: phoneNumberPublic ?? this.phoneNumberPublic,
      roomDisplayName: roomDisplayName ?? this.roomDisplayName,
      roomRole: roomRole ?? this.roomRole,
      isSuperuser: isSuperuser ?? this.isSuperuser,
      isOnline: isOnline ?? this.isOnline,
      commonRooms: commonRooms ?? this.commonRooms,
    );
  }

  UserSummary mergeMissing(UserSummary fallback) {
    String? nonEmptyOrFallback(String? value, String? fallback) {
      if (value != null && value.trim().isNotEmpty) return value;
      return fallback;
    }

    return UserSummary(
      id: id,
      username: username,
      displayName: displayName.trim().isEmpty
          ? fallback.displayName
          : displayName,
      avatarUrl: avatarUrl ?? fallback.avatarUrl,
      defaultAvatarKey: defaultAvatarKey,
      uid: nonEmptyOrFallback(uid, fallback.uid),
      bio: nonEmptyOrFallback(bio, fallback.bio),
      gender: nonEmptyOrFallback(gender, fallback.gender),
      email: nonEmptyOrFallback(email, fallback.email),
      emailPublic: emailPublic ?? fallback.emailPublic,
      phoneNumber: nonEmptyOrFallback(phoneNumber, fallback.phoneNumber),
      phoneNumberPublic: phoneNumberPublic ?? fallback.phoneNumberPublic,
      roomDisplayName: nonEmptyOrFallback(
        roomDisplayName,
        fallback.roomDisplayName,
      ),
      roomRole: nonEmptyOrFallback(roomRole, fallback.roomRole),
      isSuperuser: isSuperuser || fallback.isSuperuser,
      isOnline: isOnline ?? fallback.isOnline,
      commonRooms: commonRooms.isNotEmpty ? commonRooms : fallback.commonRooms,
    );
  }
}

class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.uid,
    required this.username,
    required this.displayName,
    required this.bio,
    required this.gender,
    required this.email,
    required this.emailPublic,
    required this.phoneNumber,
    required this.phoneNumberPublic,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    required this.isSuperuser,
    required this.createdAt,
    this.usernameUpdatedAt,
    this.canChangeUsernameAt,
    this.status,
  });

  final String id;
  final String uid;
  final String username;
  final String displayName;
  final String bio;
  final String gender;
  final String? email;
  final bool emailPublic;
  final String? phoneNumber;
  final bool phoneNumberPublic;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final bool isSuperuser;
  final DateTime? usernameUpdatedAt;
  final DateTime? canChangeUsernameAt;
  final DateTime? createdAt;
  final String? status;

  factory CurrentUser.fromJson(Map<String, Object?> json) {
    final username = json['username']! as String;
    final id = json['id']! as String;
    return CurrentUser(
      id: id,
      uid: json['uid'] as String? ?? id,
      username: username,
      displayName: json['display_name'] as String? ?? username,
      bio: json['bio'] as String? ?? '',
      gender: json['gender'] as String? ?? 'secret',
      email: json['email'] as String?,
      emailPublic: json['email_public'] as bool? ?? false,
      phoneNumber: json['phone_number'] as String?,
      phoneNumberPublic: json['phone_number_public'] as bool? ?? false,
      avatarUrl: json['avatar_url'] as String?,
      defaultAvatarKey: json['default_avatar_key'] as String? ?? 'blue-3',
      isSuperuser: json['is_superuser'] as bool? ?? false,
      usernameUpdatedAt: _parseDateTime(json['username_updated_at']),
      canChangeUsernameAt: _parseDateTime(json['can_change_username_at']),
      createdAt: _parseDateTime(json['created_at']),
      status: json['status'] as String?,
    );
  }

  UserSummary toSummary() {
    return UserSummary(
      id: id,
      uid: uid,
      username: username,
      displayName: displayName,
      bio: bio,
      gender: gender,
      email: email,
      emailPublic: emailPublic,
      phoneNumber: phoneNumber,
      phoneNumberPublic: phoneNumberPublic,
      avatarUrl: avatarUrl,
      defaultAvatarKey: defaultAvatarKey,
      isSuperuser: isSuperuser,
      isOnline: _onlineFromStatus(status) ?? true,
    );
  }
}

class UserSession {
  const UserSession({
    required this.id,
    required this.userAgent,
    required this.ipAddress,
    required this.location,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
    required this.revokedAt,
    required this.isCurrent,
  });

  final String id;
  final String? userAgent;
  final String? ipAddress;
  final String location;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final bool isCurrent;

  factory UserSession.fromJson(Map<String, Object?> json) {
    return UserSession(
      id: json['id']! as String,
      userAgent: json['user_agent'] as String?,
      ipAddress: json['ip_address'] as String?,
      location: json['location'] as String? ?? '未知地点',
      createdAt: _fromUnixSeconds(json['created_at']! as int),
      lastUsedAt: _fromUnixSeconds(json['last_used_at']! as int),
      expiresAt: _fromUnixSeconds(json['expires_at']! as int),
      revokedAt: _nullableUnixSeconds(json['revoked_at']),
      isCurrent: json['is_current']! as bool,
    );
  }

  bool get isActive => revokedAt == null && expiresAt.isAfter(DateTime.now());
}

class UploadedAsset {
  const UploadedAsset({
    required this.id,
    required this.url,
    required this.thumbnailUrl,
    required this.mimeType,
    this.filename,
    this.sizeBytes,
    this.width,
    this.height,
    this.createdAt,
  });

  final String id;
  final String url;
  final String? thumbnailUrl;
  final String mimeType;
  final String? filename;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final DateTime? createdAt;

  factory UploadedAsset.fromJson(Map<String, Object?> json) {
    return UploadedAsset(
      id: json['id']! as String,
      url: json['url']! as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      filename: json['filename'] as String?,
      sizeBytes: _nullableInt(json['size_bytes']),
      width: _nullableInt(json['width']),
      height: _nullableInt(json['height']),
      createdAt: _parseDateTime(json['created_at']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'url': url,
      'thumbnail_url': thumbnailUrl,
      'mime_type': mimeType,
      if (filename != null) 'filename': filename,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      'width': width,
      'height': height,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

class StickerPack {
  const StickerPack({
    required this.id,
    required this.scope,
    required this.roomId,
    required this.name,
    required this.stickers,
    required this.sortOrder,
    required this.updatedAt,
  });

  final String id;
  final String scope;
  final String? roomId;
  final String name;
  final List<Sticker> stickers;
  final int sortOrder;
  final DateTime? updatedAt;

  factory StickerPack.fromJson(Map<String, Object?> json) {
    return StickerPack(
      id: json['id']! as String,
      scope: json['scope'] as String? ?? 'personal',
      roomId: json['room_id'] as String?,
      name: json['name'] as String? ?? 'Stickers',
      stickers: _listOfMaps(json['stickers']).map(Sticker.fromJson).toList(),
      sortOrder: _nullableInt(json['sort_order']) ?? 10,
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'scope': scope,
      'room_id': roomId,
      'name': name,
      'stickers': stickers.map((sticker) => sticker.toJson()).toList(),
      'sort_order': sortOrder,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class Sticker {
  const Sticker({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.asset,
  });

  final String id;
  final String name;
  final int sortOrder;
  final UploadedAsset asset;

  factory Sticker.fromJson(Map<String, Object?> json) {
    return Sticker(
      id: json['id']! as String,
      name: json['name'] as String? ?? 'sticker',
      sortOrder: _nullableInt(json['sort_order']) ?? 10,
      asset: UploadedAsset.fromJson(json['asset']! as Map<String, Object?>),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'sort_order': sortOrder,
      'asset': asset.toJson(),
    };
  }
}

class MessageAttachment {
  const MessageAttachment({
    required this.type,
    this.stickerId,
    this.name,
    this.asset,
  });

  final String type;
  final String? stickerId;
  final String? name;
  final UploadedAsset? asset;

  factory MessageAttachment.fromJson(Map<String, Object?> json) {
    final assetJson = _nullableMap(json['asset']);
    return MessageAttachment(
      type: json['type'] as String? ?? 'file',
      stickerId: json['sticker_id'] as String?,
      name: json['name'] as String?,
      asset: assetJson == null ? null : UploadedAsset.fromJson(assetJson),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'type': type,
      if (stickerId != null) 'sticker_id': stickerId,
      if (name != null) 'name': name,
      if (asset != null) 'asset': asset!.toJson(),
    };
  }
}

class LastMessagePreview {
  const LastMessagePreview({
    required this.id,
    required this.senderDisplayName,
    required this.bodyPreview,
    required this.createdAt,
  });

  final String id;
  final String senderDisplayName;
  final String bodyPreview;
  final DateTime createdAt;

  factory LastMessagePreview.fromJson(Map<String, Object?> json) {
    return LastMessagePreview(
      id: json['id']! as String,
      senderDisplayName: json['sender_display_name']! as String,
      bodyPreview: json['body_preview']! as String,
      createdAt: DateTime.parse(json['created_at']! as String),
    );
  }
}

class RoomCard {
  const RoomCard({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    required this.memberCount,
    required this.liveParticipantCount,
    required this.liveAvatarPreview,
    required this.lastMessage,
    required this.unreadCount,
    required this.updatedAt,
    this.rid = '',
    this.visibility = 'private',
    this.remarkName,
    this.description = '',
    this.notificationPolicy = 'all',
    this.onlineMemberCount = 0,
  });

  final String id;
  final String name;
  final String rid;
  final String visibility;
  final String? remarkName;
  final String description;
  final String notificationPolicy;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final int memberCount;
  final int onlineMemberCount;
  final int liveParticipantCount;
  final List<UserSummary> liveAvatarPreview;
  final LastMessagePreview? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;

  factory RoomCard.fromJson(Map<String, Object?> json) {
    return RoomCard(
      id: json['id']! as String,
      name: json['name']! as String,
      rid: json['rid'] as String? ?? '',
      visibility: json['visibility'] as String? ?? 'private',
      remarkName: _stringFromJson(json, const ['remark_name', 'room_remark']),
      description:
          _stringFromJson(json, const ['description', 'intro', 'bio']) ?? '',
      notificationPolicy:
          _stringFromJson(json, const ['notification_policy']) ?? 'all',
      avatarUrl: json['avatar_url'] as String?,
      defaultAvatarKey: json['default_avatar_key'] as String? ?? 'room-1',
      memberCount: json['member_count']! as int,
      onlineMemberCount:
          _intFromJson(json, const ['online_member_count', 'online_count']) ??
          0,
      liveParticipantCount: json['live_participant_count'] as int? ?? 0,
      liveAvatarPreview: _listOfMaps(
        json['live_avatar_preview'],
      ).map(UserSummary.fromJson).toList(),
      lastMessage: _nullableMap(json['last_message']) == null
          ? null
          : LastMessagePreview.fromJson(_nullableMap(json['last_message'])!),
      unreadCount: json['unread_count'] as int? ?? 0,
      updatedAt: DateTime.parse(json['updated_at']! as String),
    );
  }

  String get displayName {
    final remark = _nonEmptyString(remarkName);
    if (remark == null) return name;
    return '$remark ($name)';
  }

  /// Returns a copy with selected fields overridden. Used when merging a
  /// server-pushed public snapshot (room_updated) over an existing card: the
  /// snapshot carries no per-user fields, so the caller re-supplies the local
  /// [unreadCount] to keep it from being reset to 0.
  RoomCard copyWith({int? unreadCount}) {
    return RoomCard(
      id: id,
      name: name,
      rid: rid,
      visibility: visibility,
      remarkName: remarkName,
      description: description,
      notificationPolicy: notificationPolicy,
      avatarUrl: avatarUrl,
      defaultAvatarKey: defaultAvatarKey,
      memberCount: memberCount,
      onlineMemberCount: onlineMemberCount,
      liveParticipantCount: liveParticipantCount,
      liveAvatarPreview: liveAvatarPreview,
      lastMessage: lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt,
    );
  }
}

/// A room as seen from search results — the viewer may or may not already be
/// a member. [joinState] is one of `none`, `pending`, `joined` and drives the
/// join button's affordance.
class PublicRoom {
  const PublicRoom({
    required this.id,
    required this.rid,
    required this.name,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    required this.visibility,
    required this.joinPolicy,
    required this.memberCount,
    required this.liveParticipantCount,
    required this.joined,
    required this.joinState,
    this.onlineMemberCount = 0,
  });

  final String id;
  final String rid;
  final String name;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final String visibility;
  final String joinPolicy;
  final int memberCount;
  final int onlineMemberCount;
  final int liveParticipantCount;
  final bool joined;
  final String joinState;

  factory PublicRoom.fromJson(Map<String, Object?> json) {
    return PublicRoom(
      id: json['id']! as String,
      rid: json['rid'] as String? ?? '',
      name: json['name']! as String,
      avatarUrl: json['avatar_url'] as String?,
      defaultAvatarKey: json['default_avatar_key'] as String? ?? 'room-1',
      visibility: json['visibility'] as String? ?? 'public',
      joinPolicy: json['join_policy'] as String? ?? 'approval_required',
      memberCount: json['member_count'] as int? ?? 0,
      onlineMemberCount:
          _intFromJson(json, const ['online_member_count', 'online_count']) ??
          0,
      liveParticipantCount: json['live_participant_count'] as int? ?? 0,
      joined: json['joined'] as bool? ?? false,
      joinState: json['join_state'] as String? ?? 'none',
    );
  }
}

/// Result of POST /rooms/:id/join. Either we joined and got the full room
/// detail back, or the room needs approval and we got a pending request.
class JoinRoomResult {
  const JoinRoomResult({this.room, this.pending = false});

  final RoomDetail? room;
  final bool pending;

  bool get joined => room != null;
}

class RoomMembership {
  const RoomMembership({required this.joinedAt, required this.role});

  final DateTime joinedAt;
  final String role;

  factory RoomMembership.fromJson(Map<String, Object?> json) {
    return RoomMembership(
      joinedAt: DateTime.parse(json['joined_at']! as String),
      role: json['role'] as String? ?? 'member',
    );
  }
}

class RoomPersonalProfile {
  const RoomPersonalProfile({
    this.displayName,
    this.avatarUrl,
    this.defaultAvatarKey,
  });

  final String? displayName;
  final String? avatarUrl;
  final String? defaultAvatarKey;

  factory RoomPersonalProfile.fromJson(Map<String, Object?>? json) {
    if (json == null) return const RoomPersonalProfile();
    return RoomPersonalProfile(
      displayName: _stringFromJson(json, const [
        'display_name',
        'room_display_name',
        'room_username',
        'room_nickname',
      ]),
      avatarUrl: _stringFromJson(json, const ['avatar_url']),
      defaultAvatarKey: _stringFromJson(json, const ['default_avatar_key']),
    );
  }

  bool get isEmpty =>
      _nonEmptyString(displayName) == null &&
      _nonEmptyString(avatarUrl) == null &&
      _nonEmptyString(defaultAvatarKey) == null;
}

/// A pending request to join an approval-required room, as seen by an admin
/// reviewing the room's join queue.
class JoinRequest {
  const JoinRequest({
    required this.id,
    required this.status,
    required this.user,
    required this.createdAt,
  });

  final String id;
  final String status;
  final UserSummary user;
  final DateTime createdAt;

  factory JoinRequest.fromJson(Map<String, Object?> json) {
    return JoinRequest(
      id: json['id']! as String,
      status: json['status'] as String? ?? 'pending',
      user: UserSummary.fromJson(json['user']! as Map<String, Object?>),
      createdAt: DateTime.parse(json['created_at']! as String),
    );
  }
}

class RoomMemberPage {
  const RoomMemberPage({required this.members, required this.nextCursor});

  final List<RoomMember> members;
  final String? nextCursor;

  factory RoomMemberPage.fromJson(Map<String, Object?> json) {
    return RoomMemberPage(
      members: _listOfMaps(json['members']).map(RoomMember.fromJson).toList(),
      nextCursor: _stringFromJson(json, const ['next_cursor']),
    );
  }
}

class RoomMember {
  const RoomMember({
    required this.user,
    required this.role,
    required this.joinedAt,
    this.roomDisplayName,
    this.remarkName,
    this.textMutedUntil,
    this.isOnline,
  });

  final UserSummary user;
  final String role;
  final DateTime joinedAt;
  final String? roomDisplayName;
  final String? remarkName;
  final String? textMutedUntil;
  final bool? isOnline;

  factory RoomMember.fromJson(Map<String, Object?> json) {
    final userJson = json['user']! as Map<String, Object?>;
    final baseUser = UserSummary.fromJson(userJson);
    final membership = _nullableMap(json['membership']);
    final role =
        _stringFromJson(json, const ['role', 'room_role', 'membership_role']) ??
        _stringFromJson(membership, const ['role']) ??
        baseUser.roomRole ??
        'member';
    final roomDisplayName =
        _stringFromJson(json, const [
          'room_display_name',
          'room_username',
          'room_nickname',
          'member_display_name',
        ]) ??
        _stringFromJson(membership, const [
          'room_display_name',
          'room_username',
          'room_nickname',
          'member_display_name',
        ]) ??
        baseUser.roomDisplayName;
    final remarkName =
        _stringFromJson(json, const ['remark_name', 'remark']) ??
        _stringFromJson(membership, const ['remark_name', 'remark']);
    final textMutedUntil =
        _stringFromJson(json, const ['text_muted_until']) ??
        _stringFromJson(membership, const ['text_muted_until']);
    final isOnline =
        _boolFromJson(json, const ['is_online', 'online']) ??
        _boolFromJson(_nullableMap(json['presence']), const [
          'is_online',
          'online',
        ]) ??
        _onlineFromStatus(
          _stringFromJson(json, const [
                'presence',
                'presence_status',
                'status',
                'connection_state',
              ]) ??
              _stringFromJson(_nullableMap(json['presence']), const [
                'status',
                'connection_state',
              ]),
        );
    final user = baseUser.copyWith(
      roomDisplayName: roomDisplayName,
      roomRole: role,
      isOnline: isOnline,
    );
    return RoomMember(
      user: user,
      role: role,
      joinedAt:
          _parseDateTime(json['joined_at']) ??
          _parseDateTime(membership?['joined_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      roomDisplayName: roomDisplayName,
      remarkName: remarkName,
      textMutedUntil: textMutedUntil,
      isOnline: isOnline,
    );
  }
}

class RoomMemberProfile {
  const RoomMemberProfile({
    required this.user,
    required this.role,
    required this.joinedAt,
    this.roomDisplayName,
    this.roomAvatarUrl,
    this.roomDefaultAvatarKey,
    this.textMutedUntil,
  });

  final UserSummary user;
  final String role;
  final DateTime joinedAt;
  final String? roomDisplayName;
  final String? roomAvatarUrl;
  final String? roomDefaultAvatarKey;
  final String? textMutedUntil;

  factory RoomMemberProfile.fromJson(Map<String, Object?> json) {
    final baseUser = UserSummary.fromJson(
      json['user']! as Map<String, Object?>,
    );
    final role =
        _stringFromJson(json, const ['role', 'room_role', 'membership_role']) ??
        baseUser.roomRole ??
        'member';
    final roomDisplayName = _stringFromJson(json, const [
      'room_display_name',
      'room_username',
      'room_nickname',
      'member_display_name',
    ]);
    final roomAvatarUrl = _stringFromJson(json, const ['room_avatar_url']);
    final roomDefaultAvatarKey = _stringFromJson(json, const [
      'room_default_avatar_key',
      'default_avatar_key',
    ]);
    final isOnline =
        baseUser.isOnline ??
        _boolFromJson(json, const ['is_online', 'online']) ??
        _onlineFromStatus(
          _stringFromJson(json, const [
            'presence',
            'presence_status',
            'status',
            'connection_state',
          ]),
        );
    final user = baseUser.copyWith(
      roomDisplayName: roomDisplayName,
      roomRole: role,
      avatarUrl: roomAvatarUrl ?? baseUser.avatarUrl,
      defaultAvatarKey: roomDefaultAvatarKey ?? baseUser.defaultAvatarKey,
      isOnline: isOnline,
    );
    return RoomMemberProfile(
      user: user,
      role: role,
      joinedAt:
          _parseDateTime(json['joined_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      roomDisplayName: roomDisplayName,
      roomAvatarUrl: roomAvatarUrl,
      roomDefaultAvatarKey: roomDefaultAvatarKey,
      textMutedUntil: _stringFromJson(json, const ['text_muted_until']),
    );
  }
}

class RoomInvite {
  const RoomInvite({
    required this.id,
    required this.status,
    required this.room,
    required this.inviter,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String status;
  final PublicRoom room;
  final UserSummary inviter;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory RoomInvite.fromJson(Map<String, Object?> json) {
    return RoomInvite(
      id: json['id']! as String,
      status: json['status'] as String? ?? 'pending',
      room: PublicRoom.fromJson(json['room']! as Map<String, Object?>),
      inviter: UserSummary.fromJson(json['inviter']! as Map<String, Object?>),
      createdAt:
          _parseDateTime(json['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }
}

class RoomDetail {
  const RoomDetail({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    required this.memberCount,
    required this.myMembership,
    required this.live,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.rid = '',
    this.visibility = 'private',
    this.description = '',
    this.joinPolicy = 'approval_required',
    this.remarkName,
    this.notificationPolicy = 'all',
    this.personalProfile = const RoomPersonalProfile(),
    this.aiVoiceAnnouncementsEnabled = true,
    this.canDeleteRoom,
    this.onlineMemberCount = 0,
  });

  final String id;
  final String name;
  final String rid;
  final String visibility;
  final String description;
  final String joinPolicy;
  final String? remarkName;
  final String notificationPolicy;
  final RoomPersonalProfile personalProfile;
  final bool aiVoiceAnnouncementsEnabled;
  final bool? canDeleteRoom;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final int memberCount;
  final int onlineMemberCount;
  final UserSummary? createdBy;
  final RoomMembership myMembership;
  final LiveState live;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory RoomDetail.fromJson(Map<String, Object?> json) {
    return RoomDetail(
      id: json['id']! as String,
      name: json['name']! as String,
      rid: json['rid'] as String? ?? '',
      visibility: json['visibility'] as String? ?? 'private',
      description:
          _stringFromJson(json, const ['description', 'intro', 'bio']) ?? '',
      joinPolicy: json['join_policy'] as String? ?? 'approval_required',
      remarkName: _stringFromJson(json, const ['remark_name', 'room_remark']),
      notificationPolicy:
          _stringFromJson(json, const ['notification_policy']) ?? 'all',
      personalProfile: RoomPersonalProfile.fromJson(
        _nullableMap(json['personal_profile']) ??
            _nullableMap(json['my_room_profile']) ??
            _nullableMap(json['room_profile']),
      ),
      aiVoiceAnnouncementsEnabled:
          _boolFromJson(json, const [
            'ai_voice_announcements_enabled',
            'ai_voice_auto_broadcast',
          ]) ??
          true,
      canDeleteRoom: _boolFromJson(json, const [
        'can_delete_room',
        'can_delete',
      ]),
      avatarUrl: json['avatar_url'] as String?,
      defaultAvatarKey: json['default_avatar_key'] as String? ?? 'room-1',
      memberCount: json['member_count']! as int,
      onlineMemberCount:
          _intFromJson(json, const ['online_member_count', 'online_count']) ??
          0,
      createdBy: _nullableMap(json['created_by']) == null
          ? null
          : UserSummary.fromJson(_nullableMap(json['created_by'])!),
      myMembership: RoomMembership.fromJson(
        json['my_membership']! as Map<String, Object?>,
      ),
      live: LiveState.fromJson(json['live']! as Map<String, Object?>),
      createdAt: DateTime.parse(json['created_at']! as String),
      updatedAt: DateTime.parse(json['updated_at']! as String),
    );
  }

  /// Whether the current user can administer this room (review join requests,
  /// etc.). Mirrors the server's admin check: owner, admin, or superuser.
  bool get isAdmin {
    final role = myMembership.role.toLowerCase();
    return role == 'owner' ||
        role == 'creator' ||
        role == 'admin' ||
        role == 'administrator' ||
        role == 'superuser';
  }

  bool get isCreator {
    final role = myMembership.role.toLowerCase();
    return role == 'owner' || role == 'creator';
  }

  bool get isSuperuser => myMembership.role.toLowerCase() == 'superuser';

  bool get canDelete => canDeleteRoom ?? (isCreator || isSuperuser);

  /// Returns a copy with the current user's membership role replaced. Used to
  /// apply a `room_role_changed` SSE event (promote/demote) without re-fetching
  /// the whole room detail.
  RoomDetail copyWithRole(String role) {
    return RoomDetail(
      id: id,
      name: name,
      rid: rid,
      visibility: visibility,
      description: description,
      joinPolicy: joinPolicy,
      remarkName: remarkName,
      notificationPolicy: notificationPolicy,
      personalProfile: personalProfile,
      aiVoiceAnnouncementsEnabled: aiVoiceAnnouncementsEnabled,
      canDeleteRoom: canDeleteRoom,
      avatarUrl: avatarUrl,
      defaultAvatarKey: defaultAvatarKey,
      memberCount: memberCount,
      onlineMemberCount: onlineMemberCount,
      createdBy: createdBy,
      myMembership: RoomMembership(joinedAt: myMembership.joinedAt, role: role),
      live: live,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  RoomCard toCard() {
    return RoomCard(
      id: id,
      name: name,
      rid: rid,
      visibility: visibility,
      remarkName: remarkName,
      description: description,
      notificationPolicy: notificationPolicy,
      avatarUrl: avatarUrl,
      defaultAvatarKey: defaultAvatarKey,
      memberCount: memberCount,
      onlineMemberCount: onlineMemberCount,
      liveParticipantCount: live.participantCount,
      liveAvatarPreview: live.participants.map((p) => p.user).take(5).toList(),
      lastMessage: null,
      unreadCount: 0,
      updatedAt: updatedAt,
    );
  }
}

class Message {
  const Message({
    required this.id,
    required this.roomId,
    required this.sender,
    required this.clientMessageId,
    this.type = 'text',
    required this.body,
    required this.createdAt,
    this.attachments = const [],
    this.pending = false,
    this.failed = false,
  });

  final String id;
  final String roomId;
  final UserSummary sender;
  final String clientMessageId;
  final String type;
  final String body;
  final DateTime createdAt;
  final List<MessageAttachment> attachments;
  final bool pending;
  final bool failed;

  MessageAttachment? get stickerAttachment {
    if (type != 'sticker') return null;
    for (final attachment in attachments) {
      if (attachment.type == 'sticker' && attachment.asset != null) {
        return attachment;
      }
    }
    return null;
  }

  Iterable<MessageAttachment> get fileAttachments {
    return attachments.where((attachment) => attachment.type == 'file');
  }

  factory Message.fromJson(Map<String, Object?> json) {
    final senderCommonRooms = _listOfMaps(
      json['sender_common_rooms'],
    ).map(UserCommonRoom.fromJson).where((room) => room.isUsable).toList();
    final sender = UserSummary.fromJson(json['sender']! as Map<String, Object?>)
        .copyWith(
          roomDisplayName: _stringFromJson(json, const [
            'sender_room_display_name',
            'sender_room_username',
            'sender_room_nickname',
            'sender_room_remark',
          ]),
          roomRole: _stringFromJson(json, const [
            'sender_room_role',
            'sender_membership_role',
          ]),
          commonRooms: senderCommonRooms.isEmpty ? null : senderCommonRooms,
        );
    return Message(
      id: json['id']! as String,
      roomId: json['room_id']! as String,
      sender: sender,
      clientMessageId: json['client_message_id']! as String,
      type: json['type'] as String? ?? 'text',
      body: json['body'] as String? ?? '',
      attachments: _listOfMaps(
        json['attachments'],
      ).map(MessageAttachment.fromJson).toList(),
      createdAt: DateTime.parse(json['created_at']! as String),
    );
  }

  factory Message.local({
    required String roomId,
    required UserSummary sender,
    required String clientMessageId,
    required String body,
    String type = 'text',
    List<MessageAttachment> attachments = const [],
  }) {
    return Message(
      id: clientMessageId,
      roomId: roomId,
      sender: sender,
      clientMessageId: clientMessageId,
      type: type,
      body: body,
      createdAt: DateTime.now().toUtc(),
      attachments: attachments,
      pending: true,
    );
  }

  Message markFailed() {
    return Message(
      id: id,
      roomId: roomId,
      sender: sender,
      clientMessageId: clientMessageId,
      type: type,
      body: body,
      createdAt: createdAt,
      attachments: attachments,
      failed: true,
    );
  }
}

class LiveParticipant {
  const LiveParticipant({
    required this.liveSessionId,
    required this.user,
    required this.joinedAt,
    required this.micMuted,
    required this.headphonesMuted,
    required this.voiceBlocked,
    required this.cameraOn,
    required this.screenSharing,
    required this.connectionState,
  });

  final String liveSessionId;
  final UserSummary user;
  final DateTime joinedAt;
  final bool micMuted;
  final bool headphonesMuted;

  /// A persistent room-level voice ban set by an admin (`block_voice`). While
  /// true the participant's LiveKit publish permission is revoked: the mic is
  /// force-muted and self-unmute requests are rejected by the server. Survives
  /// reconnects until an admin runs `restore_voice`. Defaults to false for
  /// servers that don't send the field.
  final bool voiceBlocked;
  final bool cameraOn;
  final bool screenSharing;
  final String connectionState;

  factory LiveParticipant.fromJson(Map<String, Object?> json) {
    final commonRooms = _listOfMaps(
      json['common_rooms'],
    ).map(UserCommonRoom.fromJson).where((room) => room.isUsable).toList();
    final user = UserSummary.fromJson(json['user']! as Map<String, Object?>)
        .copyWith(
          roomDisplayName: _stringFromJson(json, const [
            'room_display_name',
            'room_username',
            'room_nickname',
            'room_remark',
          ]),
          roomRole: _stringFromJson(json, const [
            'room_role',
            'membership_role',
          ]),
          commonRooms: commonRooms.isEmpty ? null : commonRooms,
        );
    return LiveParticipant(
      liveSessionId: json['live_session_id']! as String,
      user: user,
      joinedAt: DateTime.parse(json['joined_at']! as String),
      micMuted: json['mic_muted']! as bool,
      headphonesMuted: json['headphones_muted'] as bool? ?? false,
      voiceBlocked: json['voice_blocked'] as bool? ?? false,
      cameraOn: json['camera_on']! as bool,
      screenSharing: json['screen_sharing']! as bool,
      connectionState: json['connection_state']! as String,
    );
  }
}

class LiveState {
  const LiveState({
    required this.roomId,
    required this.participantCount,
    required this.participants,
    required this.updatedAt,
  });

  final String roomId;
  final int participantCount;
  final List<LiveParticipant> participants;
  final DateTime updatedAt;

  factory LiveState.fromJson(Map<String, Object?> json) {
    return LiveState(
      roomId: json['room_id']! as String,
      participantCount: json['participant_count']! as int,
      participants: _listOfMaps(
        json['participants'],
      ).map(LiveParticipant.fromJson).toList(),
      updatedAt: DateTime.parse(json['updated_at']! as String),
    );
  }
}

class LiveKitConnectionInfo {
  const LiveKitConnectionInfo({
    required this.serverUrl,
    required this.token,
    required this.tokenExpiresAt,
    required this.roomName,
  });

  final String serverUrl;
  final String token;
  final DateTime tokenExpiresAt;
  final String roomName;

  factory LiveKitConnectionInfo.fromJson(Map<String, Object?> json) {
    return LiveKitConnectionInfo(
      serverUrl: json['server_url']! as String,
      token: json['token']! as String,
      tokenExpiresAt: DateTime.parse(json['token_expires_at']! as String),
      roomName: json['room_name']! as String,
    );
  }
}

class LiveJoinResult {
  const LiveJoinResult({
    required this.liveKit,
    required this.participant,
    required this.live,
  });

  final LiveKitConnectionInfo liveKit;
  final LiveParticipant participant;
  final LiveState live;

  factory LiveJoinResult.fromJson(Map<String, Object?> json) {
    return LiveJoinResult(
      liveKit: LiveKitConnectionInfo.fromJson(
        json['livekit']! as Map<String, Object?>,
      ),
      participant: LiveParticipant.fromJson(
        json['participant']! as Map<String, Object?>,
      ),
      live: LiveState.fromJson(json['live']! as Map<String, Object?>),
    );
  }
}

List<Map<String, Object?>> _listOfMaps(Object? value) {
  return (value as List<Object?>? ?? const [])
      .cast<Map<String, Object?>>()
      .toList();
}

Map<String, Object?>? _nullableMap(Object? value) {
  return value == null ? null : value as Map<String, Object?>;
}

String? _stringFromJson(Map<String, Object?>? json, List<String> keys) {
  if (json == null) return null;
  for (final key in keys) {
    final value = json[key];
    final text = switch (value) {
      String text => text,
      int number => number.toString(),
      _ => null,
    };
    if (text != null && text.trim().isNotEmpty) return text;
  }
  return null;
}

String? _nonEmptyString(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

bool? _boolFromJson(Map<String, Object?>? json, List<String> keys) {
  if (json == null) return null;
  for (final key in keys) {
    final value = json[key];
    if (value is bool) return value;
  }
  return null;
}

int? _intFromJson(Map<String, Object?>? json, List<String> keys) {
  if (json == null) return null;
  for (final key in keys) {
    final value = _nullableInt(json[key]);
    if (value != null) return value;
  }
  return null;
}

bool? _onlineFromStatus(String? value) {
  final status = value?.trim().toLowerCase();
  if (status == null || status.isEmpty) return null;
  return switch (status) {
    'online' ||
    'active' ||
    'connected' ||
    'joining' ||
    'joined' ||
    '在线' => true,
    'offline' || 'inactive' || 'disconnected' || 'left' || '离线' => false,
    _ => null,
  };
}

DateTime? _parseDateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime _fromUnixSeconds(int value) {
  return DateTime.fromMillisecondsSinceEpoch(value * 1000);
}

DateTime? _nullableUnixSeconds(Object? value) {
  if (value is! int) return null;
  return _fromUnixSeconds(value);
}
