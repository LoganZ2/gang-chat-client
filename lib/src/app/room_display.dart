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
    final sender = _nonEmpty(last.senderDisplayName) ?? '用户';
    final body = _nonEmpty(last.bodyPreview) ?? '消息';
    return '$sender · $body';
  }
  return '${room.memberCount} 名成员 · $online 人在线 · $live 人语音';
}

String roomSidebarSubtitle(RoomCard room) {
  final last = room.lastMessage;
  if (last != null) {
    if (last.type == 'system') {
      return '[系统] ${_systemLastMessagePreview(last)}';
    }
    final sender = _nonEmpty(last.senderDisplayName) ?? '用户';
    final body = _nonEmpty(last.bodyPreview) ?? '消息';
    return '$sender · $body';
  }

  final parts = ['${room.memberCount} 名成员'];
  if (room.liveParticipantCount > 0) {
    parts.add('${room.liveParticipantCount} 人语音');
  }
  return parts.join(' · ');
}

String _systemLastMessagePreview(LastMessagePreview last) {
  final sender = _nonEmpty(last.senderDisplayName);
  final body = _nonEmpty(last.bodyPreview);
  final parts = [?sender, ?body];
  if (parts.isEmpty) return '系统消息';
  return parts.join(' ');
}

String roomSidebarLastMessageTime(RoomCard room, {DateTime? now}) {
  final last = room.lastMessage;
  if (last == null) return '';
  return roomSidebarTimestamp(last.createdAt, now: now);
}

String roomSidebarTimestamp(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final date = DateTime(local.year, local.month, local.day);
  final dayDelta = today.difference(date).inDays;
  final time = _formatClock(local);

  if (dayDelta == 0) return time;
  if (dayDelta == 1) return '昨天 $time';
  if (dayDelta == 2) return '前天 $time';
  if (dayDelta >= 3 && dayDelta < 7) return _weekdayLabel(local.weekday);
  return '${local.year}/${_twoDigits(local.month)}/${_twoDigits(local.day)}';
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

String? roomDescriptionValue(RoomDetail room) {
  return _nonEmpty(room.description);
}

String roomDescriptionText(RoomDetail room) {
  return roomDescriptionValue(room) ?? '暂无介绍';
}

String roomDisplayName(RoomDetail room) {
  final remark = _nonEmpty(room.remarkName);
  if (remark == null) return room.name;
  return '$remark (${room.name})';
}

PublicRoom publicRoomFromRoomDetail(RoomDetail room) {
  return PublicRoom(
    id: room.id,
    rid: room.rid,
    name: roomDisplayName(room),
    avatarUrl: room.avatarUrl,
    defaultAvatarKey: room.defaultAvatarKey,
    visibility: room.visibility,
    joinPolicy: room.joinPolicy,
    description: room.description,
    memberCount: room.memberCount,
    onlineMemberCount: room.onlineMemberCount,
    liveParticipantCount: room.live.participantCount,
    joined: true,
    joinState: 'joined',
    createdBy: room.createdBy,
    personalProfile: room.personalProfile,
    myMembership: room.myMembership,
  );
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

String? userSignatureText(UserSummary user) {
  return _nonEmpty(user.bio);
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
  return '成员';
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

String commonRoomAvatarLabel(UserCommonRoom room) {
  return _nonEmpty(room.name) ?? commonRoomDisplayName(room);
}

String visibilityLabel(String value) {
  return switch (value.toLowerCase()) {
    'public' => '公开',
    _ => '私有',
  };
}

String roomJoinPolicyLabel(String value) {
  return switch (normalizeRoomJoinPolicy(value)) {
    'open' => '开放',
    'closed' => '关闭',
    _ => '需审批',
  };
}

String? commonRoomMeta(UserCommonRoom room) {
  final roomDisplayName = _nonEmpty(room.roomDisplayName);
  final roleLabel = roomRoleLabelFromValue(room.roomRole);
  final parts = [?roomDisplayName, ?roleLabel];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

String? userPresenceLabel(UserSummary user) {
  final isOnline = user.isOnline;
  if (isOnline == null) return null;
  return isOnline ? '在线' : '离线';
}

String currentUserPresenceLabel(
  CurrentUser user, {
  required bool inLive,
  bool reconnecting = false,
}) {
  if (reconnecting) return '重连中';
  if (inLive) return '语音';
  return userPresenceLabel(user.toSummary()) ?? '在线';
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
    'member' => '成员',
    'pending' => '待审批',
    _ => null,
  };
}

String publicRoomJoinActionLabel(PublicRoom room, {required bool pending}) {
  if (room.joined) return '进入';
  if (pending) return '待审批';
  if (room.joinPolicy == 'closed') return '不可加入';
  return '加入';
}

bool publicRoomJoinActionable(PublicRoom room, {required bool pending}) {
  if (room.joined) return true;
  if (pending) return false;
  return room.joinPolicy != 'closed';
}

bool publicRoomJoinRequiresApplication(PublicRoom room) {
  return !room.joined && room.joinPolicy == 'approval_required';
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

String _formatClock(DateTime value) {
  return '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _weekdayLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => '星期一',
    DateTime.tuesday => '星期二',
    DateTime.wednesday => '星期三',
    DateTime.thursday => '星期四',
    DateTime.friday => '星期五',
    DateTime.saturday => '星期六',
    DateTime.sunday => '星期日',
    _ => '星期日',
  };
}
