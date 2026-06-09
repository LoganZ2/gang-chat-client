import '../protocol/models.dart';

enum RoomNotificationFilter { all, invites, applications, roomNotifications }

enum RoomNotificationItemType {
  invite,
  applicationRequested,
  applicationReviewed,
}

class RoomNotificationItem {
  const RoomNotificationItem._({
    required this.type,
    required this.id,
    required this.time,
    required this.pending,
    this.invite,
    this.application,
  });

  factory RoomNotificationItem.invite(RoomInvite invite) {
    return RoomNotificationItem._(
      type: RoomNotificationItemType.invite,
      id: 'invite:${invite.id}',
      time: invite.createdAt,
      pending: isPendingRoomInvite(invite),
      invite: invite,
    );
  }

  factory RoomNotificationItem.applicationRequested(
    RoomApplication application,
  ) {
    return RoomNotificationItem._(
      type: RoomNotificationItemType.applicationRequested,
      id: 'application-requested:${application.id}',
      time: application.createdAt,
      pending: isPendingRoomApplication(application),
      application: application,
    );
  }

  factory RoomNotificationItem.applicationReviewed(
    RoomApplication application,
  ) {
    return RoomNotificationItem._(
      type: RoomNotificationItemType.applicationReviewed,
      id: 'application-reviewed:${application.id}',
      time: application.reviewedAt ?? application.updatedAt,
      pending: false,
      application: application,
    );
  }

  final RoomNotificationItemType type;
  final String id;
  final DateTime time;
  final bool pending;
  final RoomInvite? invite;
  final RoomApplication? application;
}

bool isPendingRoomInvite(RoomInvite invite) {
  return invite.status.toLowerCase() == 'pending';
}

bool isAcceptedRoomInvite(RoomInvite invite) {
  return invite.status.toLowerCase() == 'accepted';
}

bool isRejectedRoomInvite(RoomInvite invite) {
  return invite.status.toLowerCase() == 'rejected';
}

bool isPendingRoomApplication(RoomApplication application) {
  return application.status.toLowerCase() == 'pending';
}

bool isApprovedRoomApplication(RoomApplication application) {
  return application.status.toLowerCase() == 'approved';
}

bool isRejectedRoomApplication(RoomApplication application) {
  return application.status.toLowerCase() == 'rejected';
}

bool isWithdrawnRoomApplication(RoomApplication application) {
  return application.status.toLowerCase() == 'withdrawn';
}

bool isReviewedRoomApplication(RoomApplication application) {
  return isApprovedRoomApplication(application) ||
      isRejectedRoomApplication(application);
}

bool canReviewNotificationInvite({
  required RoomInvite invite,
  required String? busyInviteId,
}) {
  return isPendingRoomInvite(invite) && busyInviteId == null;
}

bool canWithdrawNotificationApplication({
  required RoomApplication application,
  required String? busyApplicationId,
}) {
  return isPendingRoomApplication(application) && busyApplicationId == null;
}

int pendingRoomInviteCount(Iterable<RoomInvite> invites) {
  return invites.where(isPendingRoomInvite).length;
}

int pendingRoomNotificationCount({
  required Iterable<RoomInvite> invites,
  required Iterable<RoomApplication> applications,
}) {
  return pendingRoomInviteCount(invites) +
      applications.where(isPendingRoomApplication).length;
}

String roomInviteDecisionLabel(RoomInvite invite) {
  if (isAcceptedRoomInvite(invite)) return '已接受';
  if (isRejectedRoomInvite(invite)) return '已拒绝';
  return '';
}

String roomApplicationStatusLabel(RoomApplication application) {
  if (isApprovedRoomApplication(application)) return '已批准';
  if (isRejectedRoomApplication(application)) return '已拒绝';
  if (isWithdrawnRoomApplication(application)) return '已撤回';
  return '';
}

String roomApplicationReviewActionLabel(RoomApplication application) {
  if (isApprovedRoomApplication(application)) return '批准了您的申请';
  if (isRejectedRoomApplication(application)) return '拒绝了您的申请';
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

List<RoomNotificationItem> roomNotificationsForView({
  required Iterable<RoomInvite> invites,
  required Iterable<RoomApplication> applications,
  required String query,
  required RoomNotificationFilter filter,
}) {
  if (filter == RoomNotificationFilter.roomNotifications) {
    return const [];
  }

  final normalizedQuery = query.trim().toLowerCase();
  final items = <RoomNotificationItem>[];

  if (filter == RoomNotificationFilter.all ||
      filter == RoomNotificationFilter.invites) {
    for (final invite in invites) {
      if (_matchesRoomInvite(invite, normalizedQuery)) {
        items.add(RoomNotificationItem.invite(invite));
      }
    }
  }

  if (filter == RoomNotificationFilter.all ||
      filter == RoomNotificationFilter.applications) {
    for (final application in applications) {
      if (!_matchesRoomApplication(application, normalizedQuery)) {
        continue;
      }
      items.add(RoomNotificationItem.applicationRequested(application));
      if (isReviewedRoomApplication(application) &&
          application.reviewedAt != null &&
          application.reviewer != null) {
        items.add(RoomNotificationItem.applicationReviewed(application));
      }
    }
  }

  items.sort(compareRoomNotificationItems);
  return items;
}

List<RoomInvite> roomInviteNotificationsForView({
  required Iterable<RoomInvite> invites,
  required String query,
  required RoomNotificationFilter filter,
}) {
  if (filter != RoomNotificationFilter.all &&
      filter != RoomNotificationFilter.invites) {
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

int compareRoomNotificationItems(
  RoomNotificationItem a,
  RoomNotificationItem b,
) {
  final pendingRank = _itemPendingRank(a).compareTo(_itemPendingRank(b));
  if (pendingRank != 0) return pendingRank;
  final timeRank = b.time.compareTo(a.time);
  if (timeRank != 0) return timeRank;
  return b.id.compareTo(a.id);
}

int compareRoomInviteNotifications(RoomInvite a, RoomInvite b) {
  final pendingRank = _invitePendingRank(a).compareTo(_invitePendingRank(b));
  if (pendingRank != 0) return pendingRank;
  final createdRank = b.createdAt.compareTo(a.createdAt);
  if (createdRank != 0) return createdRank;
  return b.id.compareTo(a.id);
}

bool _matchesRoomInvite(RoomInvite invite, String normalizedQuery) {
  if (normalizedQuery.isEmpty) return true;
  return _roomInviteSearchText(invite).contains(normalizedQuery);
}

bool _matchesRoomApplication(
  RoomApplication application,
  String normalizedQuery,
) {
  if (normalizedQuery.isEmpty) return true;
  return _roomApplicationSearchText(application).contains(normalizedQuery);
}

int _itemPendingRank(RoomNotificationItem item) {
  return item.pending ? 0 : 1;
}

int _invitePendingRank(RoomInvite invite) {
  return isPendingRoomInvite(invite) ? 0 : 1;
}

String _roomInviteSearchText(RoomInvite invite) {
  final values = <String>[];
  _addRoomSearchValues(values, invite.room);
  _addUserSearchValues(values, invite.inviter);
  _addSearchValue(values, invite.id);
  _addSearchValue(values, invite.status);
  _addSearchValue(values, invite.room.joined ? '已加入 joined' : '未加入 not joined');
  _addSearchValue(values, roomInviteRoleLabel(invite.inviter));
  _addSearchValue(values, roomInviteTimestampLabel(invite.createdAt));
  if (invite.updatedAt != null) {
    _addSearchValue(values, roomInviteTimestampLabel(invite.updatedAt!));
  }
  _addSearchValue(values, roomInviteDecisionLabel(invite));
  return values.join('\n');
}

String _roomApplicationSearchText(RoomApplication application) {
  final values = <String>[];
  _addRoomSearchValues(values, application.room);
  _addSearchValue(values, application.id);
  _addSearchValue(values, application.status);
  _addSearchValue(values, roomApplicationStatusLabel(application));
  _addSearchValue(values, roomApplicationReviewActionLabel(application));
  _addSearchValue(values, roomInviteTimestampLabel(application.createdAt));
  _addSearchValue(values, roomInviteTimestampLabel(application.updatedAt));
  if (application.reviewedAt != null) {
    _addSearchValue(values, roomInviteTimestampLabel(application.reviewedAt!));
  }
  final reviewer = application.reviewer;
  if (reviewer != null) {
    _addUserSearchValues(values, reviewer);
    _addSearchValue(values, roomInviteRoleLabel(reviewer));
  }
  return values.join('\n');
}

void _addRoomSearchValues(List<String> values, PublicRoom room) {
  _addSearchValue(values, room.id);
  _addSearchValue(values, room.rid);
  _addSearchValue(values, room.name);
  _addSearchValue(values, room.visibility);
  _addSearchValue(values, room.joinPolicy);
  _addSearchValue(values, room.memberCount);
  _addSearchValue(values, room.onlineMemberCount);
  _addSearchValue(values, room.liveParticipantCount);
  _addSearchValue(values, room.joinState);
}

void _addUserSearchValues(List<String> values, UserSummary user) {
  _addSearchValue(values, user.id);
  _addSearchValue(values, user.uid);
  _addSearchValue(values, user.username);
  _addSearchValue(values, user.displayName);
  _addSearchValue(values, user.defaultAvatarKey);
  _addSearchValue(values, user.bio);
  _addSearchValue(values, user.gender);
  _addSearchValue(values, user.email);
  _addSearchValue(values, user.phoneNumber);
  _addSearchValue(values, user.roomDisplayName);
  _addSearchValue(values, user.roomRole);
  _addSearchValue(values, user.isSuperuser ? '超级用户 superuser' : null);
  _addSearchValue(
    values,
    user.isOnline == null
        ? null
        : user.isOnline!
        ? '在线 online'
        : '离线 offline',
  );
  for (final commonRoom in user.commonRooms) {
    _addSearchValue(values, commonRoom.id);
    _addSearchValue(values, commonRoom.rid);
    _addSearchValue(values, commonRoom.name);
    _addSearchValue(values, commonRoom.visibility);
    _addSearchValue(values, commonRoom.remarkName);
    _addSearchValue(values, commonRoom.defaultAvatarKey);
    _addSearchValue(values, commonRoom.roomDisplayName);
    _addSearchValue(values, commonRoom.roomRole);
  }
}

void _addSearchValue(List<String> values, Object? value) {
  final text = value?.toString().trim();
  if (text != null && text.isNotEmpty) values.add(text.toLowerCase());
}
