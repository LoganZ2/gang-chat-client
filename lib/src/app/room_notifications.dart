import '../protocol/models.dart';

enum RoomNotificationFilter { all, invites, roomNotifications }

bool isPendingRoomInvite(RoomInvite invite) {
  return invite.status.toLowerCase() == 'pending';
}

bool isAcceptedRoomInvite(RoomInvite invite) {
  return invite.status.toLowerCase() == 'accepted';
}

bool isRejectedRoomInvite(RoomInvite invite) {
  return invite.status.toLowerCase() == 'rejected';
}

bool canReviewNotificationInvite({
  required RoomInvite invite,
  required String? busyInviteId,
}) {
  return isPendingRoomInvite(invite) && busyInviteId == null;
}

int pendingRoomInviteCount(Iterable<RoomInvite> invites) {
  return invites.where(isPendingRoomInvite).length;
}

String roomInviteDecisionLabel(RoomInvite invite) {
  if (isAcceptedRoomInvite(invite)) return '已接受';
  if (isRejectedRoomInvite(invite)) return '已拒绝';
  return '';
}

String roomInviteRoleLabel(UserSummary inviter) {
  final role = inviter.roomRole?.trim().toLowerCase();
  return switch (role) {
    'owner' || 'creator' => '房主',
    'admin' || 'administrator' => '管理员',
    'member' => '成员',
    'superuser' => '超级用户',
    null || '' => '成员',
    _ => inviter.roomRole!.trim(),
  };
}

String roomInviteTimestampLabel(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

List<RoomInvite> roomInviteNotificationsForView({
  required Iterable<RoomInvite> invites,
  required String query,
  required RoomNotificationFilter filter,
}) {
  if (filter == RoomNotificationFilter.roomNotifications) {
    return const [];
  }

  final normalizedQuery = query.trim().toLowerCase();
  final filtered = [
    for (final invite in invites)
      if (_matchesRoomInvite(invite, normalizedQuery)) invite,
  ];
  filtered.sort(compareRoomInviteNotifications);
  return filtered;
}

int compareRoomInviteNotifications(RoomInvite a, RoomInvite b) {
  final pendingRank = _pendingRank(a).compareTo(_pendingRank(b));
  if (pendingRank != 0) return pendingRank;
  final createdRank = b.createdAt.compareTo(a.createdAt);
  if (createdRank != 0) return createdRank;
  return b.id.compareTo(a.id);
}

bool _matchesRoomInvite(RoomInvite invite, String normalizedQuery) {
  if (normalizedQuery.isEmpty) return true;
  return _roomInviteSearchText(invite).contains(normalizedQuery);
}

int _pendingRank(RoomInvite invite) {
  return isPendingRoomInvite(invite) ? 0 : 1;
}

String _roomInviteSearchText(RoomInvite invite) {
  final values = <String>[];

  void add(Object? value) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) values.add(text.toLowerCase());
  }

  final room = invite.room;
  add(invite.id);
  add(invite.status);
  add(room.id);
  add(room.rid);
  add(room.name);
  add(room.visibility);
  add(room.joinPolicy);
  add(room.memberCount);
  add(room.onlineMemberCount);
  add(room.liveParticipantCount);
  add(room.joinState);
  add(room.joined ? '已加入 joined' : '未加入 not joined');

  final inviter = invite.inviter;
  add(inviter.id);
  add(inviter.uid);
  add(inviter.username);
  add(inviter.displayName);
  add(inviter.defaultAvatarKey);
  add(inviter.bio);
  add(inviter.gender);
  add(inviter.email);
  add(inviter.phoneNumber);
  add(inviter.roomDisplayName);
  add(inviter.roomRole);
  add(roomInviteRoleLabel(inviter));
  add(inviter.isSuperuser ? '超级用户 superuser' : null);
  add(
    inviter.isOnline == null
        ? null
        : inviter.isOnline!
        ? '在线 online'
        : '离线 offline',
  );
  for (final commonRoom in inviter.commonRooms) {
    add(commonRoom.id);
    add(commonRoom.rid);
    add(commonRoom.name);
    add(commonRoom.visibility);
    add(commonRoom.remarkName);
    add(commonRoom.defaultAvatarKey);
    add(commonRoom.roomDisplayName);
    add(commonRoom.roomRole);
  }
  add(roomInviteTimestampLabel(invite.createdAt));
  if (invite.updatedAt != null) {
    add(roomInviteTimestampLabel(invite.updatedAt!));
  }
  add(roomInviteDecisionLabel(invite));

  return values.join('\n');
}
