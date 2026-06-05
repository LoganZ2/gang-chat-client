import '../protocol/models.dart';

class RoomManagementPermissionState {
  const RoomManagementPermissionState({
    required this.canEditCreatorOnly,
    required this.canDeleteRoom,
  });

  final bool canEditCreatorOnly;
  final bool canDeleteRoom;
}

class RoomAccessState {
  const RoomAccessState({
    required this.canManageRoom,
    required this.canReviewJoinRequests,
  });

  final bool canManageRoom;
  final bool canReviewJoinRequests;

  bool showJoinRequestBadge(bool hasPendingRequests) {
    return canReviewJoinRequests && hasPendingRequests;
  }
}

class RoomLeaveConfirmationSpec {
  const RoomLeaveConfirmationSpec({
    required this.confirmDeleteIfEmpty,
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.expectedText,
  });

  final bool confirmDeleteIfEmpty;
  final String title;
  final String body;
  final String confirmLabel;
  final String? expectedText;

  bool get requiresStrongConfirmation => expectedText != null;
}

class RoomDeletionConfirmationSpec {
  const RoomDeletionConfirmationSpec({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.expectedText,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String expectedText;
}

String roomSubtitle(RoomCard room) {
  final live = room.liveParticipantCount;
  final online = room.onlineMemberCount;
  final last = room.lastMessage;
  if (last != null) {
    return '${room.memberCount} members · $online online · $live live · ${last.senderDisplayName}: ${last.bodyPreview}';
  }
  return '${room.memberCount} members · $online online · $live live';
}

String roomCopySuccessNotice(String label) {
  return '$label 已复制';
}

String roomCopyFailureMessage(Object error) {
  return '无法复制：$error';
}

String userUidCopySuccessNotice() {
  return 'UID 已复制';
}

String userUidCopyFailureMessage(Object error) {
  return '无法复制 UID：$error';
}

String roomOpenFailureMessage(Object error) {
  return '无法打开房间：$error';
}

String roomOptimisticOpenRefreshFailureNotice() {
  return '房间刷新失败，已先打开当前房间';
}

String roomUseGlobalProfileNotice() {
  return '保存后将使用全局默认用户名和默认头像';
}

String roomInfoSavedNotice() {
  return '房间信息已保存';
}

RoomLeaveConfirmationSpec roomLeaveConfirmationSpec({
  required RoomDetail room,
  required bool isInLive,
}) {
  final confirmDeleteIfEmpty = room.isCreator && room.memberCount <= 1;
  if (confirmDeleteIfEmpty) {
    return RoomLeaveConfirmationSpec(
      confirmDeleteIfEmpty: true,
      title: '退出并删除房间',
      body: '这是房间里的最后一位成员。退出会删除房间和所有房间内数据，请输入房间名确认。',
      confirmLabel: '退出并删除',
      expectedText: room.name,
    );
  }
  return RoomLeaveConfirmationSpec(
    confirmDeleteIfEmpty: false,
    title: '退出房间',
    body: isInLive
        ? '退出后会离开当前房间，并同时离开 Live Channel。'
        : '退出后你会从房间成员中移除，房间会从列表中消失。',
    confirmLabel: '退出',
  );
}

RoomDeletionConfirmationSpec roomDeletionConfirmationSpec(RoomDetail room) {
  return RoomDeletionConfirmationSpec(
    title: '删除房间',
    body: '将清空房间所有数据。这个动作不可恢复，请输入房间名确认。',
    confirmLabel: '删除房间',
    expectedText: room.name,
  );
}

String roomIdentifier(RoomDetail room) {
  return _nonEmpty(room.rid) ?? room.id;
}

String roomDescriptionText(RoomDetail room) {
  return _nonEmpty(room.description) ?? '暂无介绍';
}

String roomDisplayName(RoomDetail room) {
  final remark = _nonEmpty(room.remarkName);
  if (remark == null) return room.name;
  return '$remark (${room.name})';
}

String roomMemberSummary(RoomDetail room) {
  return '${room.memberCount} 名成员 · ${room.onlineMemberCount} 人在线';
}

String userPrimaryName(UserSummary user) {
  return _nonEmpty(user.roomDisplayName) ??
      _nonEmpty(user.displayName) ??
      user.username;
}

String userUidLabel(UserSummary user) {
  return user.uid ?? user.id;
}

String userUsernameLabel(UserSummary user) {
  return '@${user.username}';
}

String userIdentityMeta(UserSummary user) {
  return '${userUidLabel(user)} · ${userUsernameLabel(user)}';
}

String userSignatureText(UserSummary user) {
  return _nonEmpty(user.bio) ?? '暂无签名';
}

String? userRoomsSectionTitle({
  required UserSummary user,
  required CurrentUser currentUser,
}) {
  if (user.isSuperuser) return null;
  if (currentUser.isSuperuser || user.id == currentUser.id) {
    return '所有房间';
  }
  return '共同房间';
}

String roomRoleLabel(UserSummary user, {String? ownerUserId}) {
  final role = _nonEmpty(user.roomRole)?.toLowerCase();
  if (role == 'pending') return '待审批';
  if (user.isSuperuser || role == 'superuser') return '超级用户';
  if (user.id == ownerUserId || role == 'owner' || role == 'creator') {
    return '创建者';
  }
  if (role == 'admin' || role == 'administrator') return '管理员';
  return '普通成员';
}

String commonRoomTitle(UserCommonRoom room) {
  final rid = _nonEmpty(room.rid);
  final name = commonRoomDisplayName(room);
  if (rid == null) return name;
  return '$name · $rid';
}

String commonRoomDisplayName(UserCommonRoom room) {
  final remark = _nonEmpty(room.remarkName);
  if (remark == null) return room.name;
  return '$remark (${room.name})';
}

String visibilityLabel(String value) {
  return switch (value.toLowerCase()) {
    'public' => '公开',
    _ => '私有',
  };
}

String? commonRoomMeta(UserCommonRoom room) {
  final roomDisplayName = _nonEmpty(room.roomDisplayName);
  final roleLabel = roomRoleLabelFromValue(room.roomRole);
  final parts = [?roomDisplayName, ?roleLabel];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

UserSummary roomUserInfoProfile({
  required UserSummary user,
  required RoomDetail room,
  required CurrentUser currentUser,
}) {
  var profile = user;
  final createdBy = room.createdBy;
  if (createdBy != null && user.id == createdBy.id) {
    profile = profile.mergeMissing(createdBy);
  }
  if (user.id == currentUser.id) {
    profile = profile.mergeMissing(currentUser.toSummary());
  }
  final roomRole =
      profile.roomRole ??
      (createdBy != null && user.id == createdBy.id
          ? 'owner'
          : user.id == currentUser.id
          ? room.myMembership.role
          : null);
  return profile.copyWith(roomRole: roomRole);
}

List<UserCommonRoom> roomUserInfoCommonRooms({
  required UserSummary user,
  required RoomDetail selectedRoom,
  required CurrentUser currentUser,
  required bool includeSelectedRoom,
}) {
  if (user.isSuperuser) {
    return const [];
  }
  if (currentUser.isSuperuser || user.id == currentUser.id) {
    return includeSelectedRoom
        ? commonRoomsWithSelectedRoom(user: user, room: selectedRoom)
        : user.commonRooms;
  }
  if (includeSelectedRoom) {
    return commonRoomsWithSelectedRoom(user: user, room: selectedRoom);
  }
  return user.commonRooms;
}

List<UserCommonRoom> commonRoomsWithSelectedRoom({
  required UserSummary user,
  required RoomDetail room,
}) {
  return [
    UserCommonRoom(
      id: room.id,
      rid: room.rid,
      name: room.name,
      visibility: room.visibility,
      remarkName: room.remarkName,
      avatarUrl: room.avatarUrl,
      defaultAvatarKey: room.defaultAvatarKey,
      roomDisplayName: user.roomDisplayName,
      roomRole: user.roomRole,
    ),
    for (final commonRoom in user.commonRooms)
      if (commonRoom.id != room.id) commonRoom,
  ];
}

String? roomRoleLabelFromValue(String? value) {
  return switch (_nonEmpty(value)?.toLowerCase()) {
    'superuser' => '超级用户',
    'owner' || 'creator' => '创建者',
    'admin' || 'administrator' => '管理员',
    'member' => '普通成员',
    'pending' => '待审批',
    _ => null,
  };
}

String publicRoomJoinActionLabel(PublicRoom room, {required bool pending}) {
  if (room.joined) return '进入';
  if (pending) return '待审批';
  if (room.joinPolicy == 'approval_required') return '申请';
  return '加入';
}

bool publicRoomJoinActionable(PublicRoom room, {required bool pending}) {
  return room.joined || !pending;
}

RoomAccessState roomAccessState({
  required RoomDetail room,
  required CurrentUser currentUser,
}) {
  final canManageRoom = room.isAdmin || currentUser.isSuperuser;
  return RoomAccessState(
    canManageRoom: canManageRoom,
    canReviewJoinRequests: canManageRoom,
  );
}

RoomManagementPermissionState roomManagementPermissionState({
  required RoomDetail room,
  required CurrentUser currentUser,
}) {
  final currentUserIsSuperuser = currentUser.isSuperuser;
  return RoomManagementPermissionState(
    canEditCreatorOnly:
        room.isCreator || room.isSuperuser || currentUserIsSuperuser,
    canDeleteRoom: room.canDelete || currentUserIsSuperuser,
  );
}

String? roomProfileAvatarPath({
  required bool usingGlobalProfile,
  required String? currentUserAvatarUrl,
  required String? pendingAvatarUrl,
  required bool usingPresetAvatar,
  required String? personalAvatarUrl,
}) {
  if (usingGlobalProfile) return currentUserAvatarUrl;
  if (pendingAvatarUrl != null) return pendingAvatarUrl;
  if (usingPresetAvatar) return null;
  return personalAvatarUrl ?? currentUserAvatarUrl;
}

bool roomProfileUploadedAvatarSelected({
  required bool usingGlobalProfile,
  required bool usingPresetAvatar,
  required String? pendingAvatarUrl,
  required String? personalAvatarUrl,
}) {
  return !usingGlobalProfile &&
      !usingPresetAvatar &&
      (pendingAvatarUrl != null || personalAvatarUrl != null);
}

bool roomProfilePresetAvatarSelected({
  required bool usingGlobalProfile,
  required bool usingPresetAvatar,
}) {
  return !usingGlobalProfile && usingPresetAvatar;
}

String roomProfileDisplayName({
  required bool usingGlobalProfile,
  required String currentUserDisplayName,
  required String roomDisplayNameText,
}) {
  if (usingGlobalProfile) return currentUserDisplayName;
  return _nonEmpty(roomDisplayNameText) ?? currentUserDisplayName;
}

String? roomManagementAvatarPath({
  required bool usingPresetAvatar,
  required String? pendingAvatarUrl,
  required String? roomAvatarUrl,
}) {
  if (usingPresetAvatar) return null;
  return pendingAvatarUrl ?? roomAvatarUrl;
}

bool roomManagementUploadedAvatarSelected({required bool usingPresetAvatar}) {
  return !usingPresetAvatar;
}

String normalizeRoomNotificationPolicy(String value) {
  return switch (value.trim().toLowerCase()) {
    'mention' || 'mentions' || 'only_mentions' || 'mention_only' => 'mentions',
    'mute' || 'muted' || 'do_not_disturb' || 'dnd' => 'muted',
    _ => 'all',
  };
}

String normalizeRoomVisibility(String value) {
  return switch (value.trim().toLowerCase()) {
    'private' => 'private',
    _ => 'public',
  };
}

String normalizeRoomJoinPolicy(String value) {
  return switch (value.trim().toLowerCase()) {
    'open' || 'allow_anyone' || 'anyone' => 'open',
    'closed' || 'none' || 'deny_all' || 'no_one' => 'closed',
    _ => 'approval_required',
  };
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
