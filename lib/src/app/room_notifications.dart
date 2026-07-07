import '../protocol/models.dart';
import 'room_display.dart' as room_display;

enum RoomNotificationFilter { all, invites, applications, roomNotifications }

enum RoomNotificationItemType {
  invite,
  applicationRequested,
  applicationReviewed,
  roomEvent,
}

const kRoomEventNotificationMemberRemoved = 'member_removed';
const kRoomEventNotificationRolePromoted = 'role_promoted';
const kRoomEventNotificationRoleDemoted = 'role_demoted';
const kRoomEventNotificationCreatorTransferDemoted = 'creator_transfer_demoted';
const kRoomEventNotificationMentioned = 'mentioned';

const missingRoomNotificationRoomLabel = '房间不存在';
const missingRoomNotificationRoomAvatarLabel = '';
const missingRoomNotificationRoomAvatarKey = 'graphite-2';
const missingRoomNotificationUserLabel = '用户不存在';
const missingRoomNotificationUserAvatarLabel = '';
const missingRoomNotificationUserAvatarKey = 'graphite-2';

class RoomNotificationItem {
  const RoomNotificationItem._({
    required this.type,
    required this.id,
    required this.time,
    required this.pending,
    required this.newItem,
    this.invite,
    this.application,
    this.roomEvent,
  });

  factory RoomNotificationItem.invite(RoomInvite invite) {
    return RoomNotificationItem._(
      type: RoomNotificationItemType.invite,
      id: 'invite:${invite.id}',
      time: invite.createdAt,
      pending: isActionablePendingRoomInvite(invite),
      newItem: isActionablePendingRoomInvite(invite),
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
      newItem: isPendingRoomApplication(application),
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
      newItem: false,
      application: application,
    );
  }

  factory RoomNotificationItem.roomEvent(RoomEventNotification notification) {
    return RoomNotificationItem._(
      type: RoomNotificationItemType.roomEvent,
      id: 'room-event:${notification.id}',
      time: notification.createdAt,
      pending: false,
      newItem: notification.isUnread,
      roomEvent: notification,
    );
  }

  final RoomNotificationItemType type;
  final String id;
  final DateTime time;
  final bool pending;
  final bool newItem;
  final RoomInvite? invite;
  final RoomApplication? application;
  final RoomEventNotification? roomEvent;
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

bool isInvalidPendingRoomInvite(RoomInvite invite) {
  if (!isPendingRoomInvite(invite)) return false;
  final reason = invite.invalidReason?.trim();
  if (reason != null && reason.isNotEmpty) return true;
  return !invite.roomExists ||
      !invite.inviterExists ||
      _isLeftRoomRole(invite.inviter.roomRole);
}

bool isActionablePendingRoomInvite(RoomInvite invite) {
  return isPendingRoomInvite(invite) && !isInvalidPendingRoomInvite(invite);
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
  return isPendingRoomInvite(invite) &&
      !isInvalidPendingRoomInvite(invite) &&
      busyInviteId == null;
}

bool canWithdrawNotificationApplication({
  required RoomApplication application,
  required String? busyApplicationId,
}) {
  return isPendingRoomApplication(application) && busyApplicationId == null;
}

bool roomInviteAcceptRequiresApplication(
  RoomInvite invite, {
  Iterable<RoomInvite> roomInvites = const [],
}) {
  if (invite.room.joinPolicy != 'approval_required') return false;
  final relatedInvites = [
    invite,
    for (final other in roomInvites)
      if (other.id != invite.id &&
          other.room.id == invite.room.id &&
          isPendingRoomInvite(other) &&
          !isInvalidPendingRoomInvite(other))
        other,
  ];
  return !relatedInvites.any((item) => _isPrivilegedInviter(item.inviter));
}

bool _isPrivilegedInviter(UserSummary inviter) {
  if (inviter.isSuperuser) return true;
  final role = inviter.roomRole?.trim().toLowerCase();
  return switch (role) {
    'owner' || 'creator' || 'admin' || 'administrator' || 'superuser' => true,
    _ => false,
  };
}

int pendingRoomInviteCount(Iterable<RoomInvite> invites) {
  return invites.where(isActionablePendingRoomInvite).length;
}

int pendingRoomNotificationCount({
  required Iterable<RoomInvite> invites,
  required Iterable<RoomApplication> applications,
  Iterable<RoomEventNotification> roomEvents = const [],
}) {
  return pendingRoomInviteCount(invites) +
      applications.where(isPendingRoomApplication).length +
      unreadRoomEventNotificationCount(roomEvents);
}

int unreadRoomEventNotificationCount(
  Iterable<RoomEventNotification> notifications,
) {
  return notifications.where((notification) => notification.isUnread).length;
}

List<RoomEventNotification> markUnreadRoomEventNotificationsRead({
  required Iterable<RoomEventNotification> notifications,
  required DateTime readAt,
  Iterable<String>? notificationIds,
}) {
  final ids = notificationIds?.toSet();
  return [
    for (final notification in notifications)
      notification.isUnread && (ids == null || ids.contains(notification.id))
          ? notification.markRead(readAt)
          : notification,
  ];
}

String roomInviteDecisionLabel(RoomInvite invite) {
  if (isInvalidPendingRoomInvite(invite)) return '已失效';
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
    'owner' || 'creator' => '创建者',
    'admin' || 'administrator' => '管理员',
    'member' => '成员',
    'superuser' => '超级用户',
    'left' || 'left_room' || 'departed' => '已离开',
    null || '' => '成员',
    _ => inviter.roomRole!.trim(),
  };
}

String roomNotificationRoleLabel(String? role) {
  return switch (role?.trim().toLowerCase()) {
    'owner' || 'creator' => '创建者',
    'admin' || 'administrator' => '管理员',
    'member' => '成员',
    'superuser' => '超级用户',
    'left' || 'left_room' || 'departed' => '已离开',
    null || '' => '成员',
    _ => role!.trim(),
  };
}

String roomEventNotificationRoleActionLabel(
  RoomEventNotification notification,
) {
  return switch (notification.type) {
    kRoomEventNotificationRolePromoted => '晋升为',
    _ => '降职为',
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

String roomNotificationRoomLabel(PublicRoom room, {required bool roomExists}) {
  return roomExists ? room.name : missingRoomNotificationRoomLabel;
}

String roomNotificationRoomAvatarLabel(
  PublicRoom room, {
  required bool roomExists,
}) {
  return roomExists ? room.name : missingRoomNotificationRoomAvatarLabel;
}

String? roomNotificationRoomAvatarUrl(
  PublicRoom room, {
  required bool roomExists,
}) {
  return roomExists ? room.avatarUrl : null;
}

String roomNotificationRoomAvatarKey(
  PublicRoom room, {
  required bool roomExists,
}) {
  return roomExists
      ? room.defaultAvatarKey
      : missingRoomNotificationRoomAvatarKey;
}

bool roomNotificationRoomCardEnabled({required bool roomExists}) {
  return roomExists;
}

String roomNotificationUserLabel(UserSummary user, {required bool userExists}) {
  if (!userExists) return missingRoomNotificationUserLabel;
  final roomName = user.roomDisplayName?.trim();
  if (roomName != null && roomName.isNotEmpty) return roomName;
  final displayName = user.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  return user.username;
}

String roomNotificationUserAvatarLabel(
  UserSummary user, {
  required bool userExists,
}) {
  return userExists
      ? room_display.userAvatarLabel(user)
      : missingRoomNotificationUserAvatarLabel;
}

String? roomNotificationUserAvatarUrl(
  UserSummary user, {
  required bool userExists,
}) {
  return userExists ? user.avatarUrl : null;
}

String roomNotificationUserAvatarKey(
  UserSummary user, {
  required bool userExists,
}) {
  return userExists
      ? user.defaultAvatarKey
      : missingRoomNotificationUserAvatarKey;
}

List<RoomNotificationItem> roomNotificationsForView({
  required Iterable<RoomInvite> invites,
  required Iterable<RoomApplication> applications,
  Iterable<RoomEventNotification> roomEvents = const [],
  required String query,
  required RoomNotificationFilter filter,
}) {
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

  if (filter == RoomNotificationFilter.all ||
      filter == RoomNotificationFilter.roomNotifications) {
    for (final notification in roomEvents) {
      if (_matchesRoomEventNotification(notification, normalizedQuery)) {
        items.add(RoomNotificationItem.roomEvent(notification));
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

bool _matchesRoomEventNotification(
  RoomEventNotification notification,
  String normalizedQuery,
) {
  if (normalizedQuery.isEmpty) return true;
  return _roomEventNotificationSearchText(
    notification,
  ).contains(normalizedQuery);
}

int _itemPendingRank(RoomNotificationItem item) {
  return item.pending ? 0 : 1;
}

int _invitePendingRank(RoomInvite invite) {
  return isActionablePendingRoomInvite(invite) ? 0 : 1;
}

String _roomInviteSearchText(RoomInvite invite) {
  final values = <String>[];
  _addRoomSearchValues(values, invite.room);
  _addUserSearchValues(values, invite.inviter);
  _addSearchValue(values, invite.id);
  _addSearchValue(values, invite.status);
  _addSearchValue(values, invite.room.joined ? '已加入 joined' : '未加入 not joined');
  _addSearchValue(values, roomInviteRoleLabel(invite.inviter));
  _addSearchValue(
    values,
    invite.inviterExists
        ? null
        : '$missingRoomNotificationUserLabel 不存在 用户已不存在 user missing',
  );
  _addSearchValue(values, invite.invalidReason);
  _addSearchValue(
    values,
    isInvalidPendingRoomInvite(invite) ? '已失效 invalid' : null,
  );
  _addSearchValue(
    values,
    invite.roomExists
        ? null
        : '$missingRoomNotificationRoomLabel 不存在 房间已不存在 room missing',
  );
  _addSearchValue(values, roomInviteTimestampLabel(invite.createdAt));
  if (invite.updatedAt != null) {
    _addSearchValue(values, roomInviteTimestampLabel(invite.updatedAt!));
  }
  _addSearchValue(values, roomInviteDecisionLabel(invite));
  return values.join('\n');
}

bool _isLeftRoomRole(String? value) {
  final role = value?.trim().toLowerCase();
  return role == 'left' || role == 'left_room' || role == 'departed';
}

String _roomApplicationSearchText(RoomApplication application) {
  final values = <String>[];
  _addRoomSearchValues(values, application.room);
  _addSearchValue(values, application.id);
  _addSearchValue(values, application.status);
  _addSearchValue(values, application.reason);
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
    _addSearchValue(
      values,
      application.reviewerExists
          ? null
          : '$missingRoomNotificationUserLabel 不存在 用户已不存在 user missing',
    );
  }
  return values.join('\n');
}

String _roomEventNotificationSearchText(RoomEventNotification notification) {
  final values = <String>[];
  _addRoomSearchValues(values, notification.room);
  _addSearchValue(values, notification.id);
  _addSearchValue(values, notification.type);
  _addSearchValue(values, roomNotificationRoleLabel(notification.fromRole));
  _addSearchValue(values, roomNotificationRoleLabel(notification.toRole));
  _addSearchValue(values, roomInviteTimestampLabel(notification.createdAt));
  _addSearchValue(
    values,
    notification.roomExists
        ? null
        : '$missingRoomNotificationRoomLabel 不存在 房间已不存在 room missing',
  );
  final actor = notification.actor;
  if (actor != null) {
    _addUserSearchValues(values, actor);
    _addSearchValue(values, roomInviteRoleLabel(actor));
    _addSearchValue(
      values,
      notification.actorExists
          ? null
          : '$missingRoomNotificationUserLabel 不存在 用户已不存在 user missing',
    );
  }
  switch (notification.type) {
    case kRoomEventNotificationMemberRemoved:
      _addSearchValue(values, '踢出了 踢出房间 removed kicked');
      break;
    case kRoomEventNotificationRolePromoted:
      _addSearchValue(values, '晋升为 promotion promoted');
      break;
    case kRoomEventNotificationRoleDemoted:
      _addSearchValue(values, '降职为 demotion demoted');
      break;
    case kRoomEventNotificationCreatorTransferDemoted:
      _addSearchValue(values, '转让创建者 降职为 creator transferred');
      break;
    case kRoomEventNotificationMentioned:
      _addSearchValue(values, '提及 @ mentioned');
      break;
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
