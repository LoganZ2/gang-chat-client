import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/room_notifications.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('room invite notifications sort pending first then newest first', () {
    final accepted = _invite(
      'accepted_old',
      status: 'accepted',
      createdAt: DateTime.utc(2026, 6, 1, 8),
    );
    final pendingOld = _invite(
      'pending_old',
      status: 'pending',
      createdAt: DateTime.utc(2026, 6, 2, 8),
    );
    final rejectedNew = _invite(
      'rejected_new',
      status: 'rejected',
      createdAt: DateTime.utc(2026, 6, 3, 8),
    );
    final invalidNew = _invite(
      'invalid_new',
      status: 'pending',
      createdAt: DateTime.utc(2026, 6, 5, 8),
      invalidReason: 'inviter_left',
      inviter: _user('left_inviter', roomRole: 'left'),
    );
    final pendingNew = _invite(
      'pending_new',
      status: 'pending',
      createdAt: DateTime.utc(2026, 6, 4, 8),
    );

    final visible = roomInviteNotificationsForView(
      invites: [accepted, pendingOld, rejectedNew, invalidNew, pendingNew],
      query: '',
      filter: RoomNotificationFilter.all,
    );

    expect(visible.map((invite) => invite.id), [
      'pending_new',
      'pending_old',
      'invalid_new',
      'rejected_new',
      'accepted_old',
    ]);
    expect(pendingRoomInviteCount(visible), 2);
  });

  test('room invite notification search includes room and inviter fields', () {
    final invite = _invite(
      'invite_1',
      roomName: 'Design Lab',
      roomRid: 'R-2026',
      inviter: _user(
        'user_1',
        uid: '100001',
        username: 'mira',
        displayName: 'Mira Chen',
        roomRole: 'admin',
        roomDisplayName: 'Mira in Design',
        commonRooms: const [
          UserCommonRoom(
            id: 'shared_room',
            rid: 'S-1',
            name: 'Shared Room',
            remarkName: 'Shared Remark',
          ),
        ],
      ),
    );

    expect(
      roomInviteNotificationsForView(
        invites: [invite],
        query: 'design lab',
        filter: RoomNotificationFilter.invites,
      ),
      [invite],
    );
    expect(
      roomInviteNotificationsForView(
        invites: [invite],
        query: '管理员',
        filter: RoomNotificationFilter.all,
      ),
      [invite],
    );
    expect(
      roomInviteNotificationsForView(
        invites: [invite],
        query: 'Shared Remark',
        filter: RoomNotificationFilter.all,
      ),
      [invite],
    );
    expect(
      roomInviteNotificationsForView(
        invites: [invite],
        query: 'missing',
        filter: RoomNotificationFilter.all,
      ),
      isEmpty,
    );
    expect(
      roomInviteNotificationsForView(
        invites: [invite],
        query: '',
        filter: RoomNotificationFilter.roomNotifications,
      ),
      isEmpty,
    );
  });

  test('room invite notification display helpers format labels', () {
    final pending = _invite('pending', status: 'pending');
    final invalid = _invite(
      'invalid',
      status: 'pending',
      invalidReason: 'inviter_left',
      inviter: _user('left_inviter', roomRole: 'left'),
    );
    final deletedInviterWithoutReason = _invite(
      'deleted_inviter_without_reason',
      status: 'pending',
      inviterExists: false,
    );
    final accepted = _invite('accepted', status: 'accepted');
    final rejected = _invite('rejected', status: 'rejected');

    expect(
      canReviewNotificationInvite(invite: pending, busyInviteId: null),
      isTrue,
    );
    expect(
      canReviewNotificationInvite(invite: pending, busyInviteId: 'pending'),
      isFalse,
    );
    expect(
      canReviewNotificationInvite(invite: accepted, busyInviteId: null),
      isFalse,
    );
    expect(
      canReviewNotificationInvite(invite: invalid, busyInviteId: null),
      isFalse,
    );
    expect(
      canReviewNotificationInvite(
        invite: deletedInviterWithoutReason,
        busyInviteId: null,
      ),
      isFalse,
    );
    expect(isInvalidPendingRoomInvite(invalid), isTrue);
    expect(isInvalidPendingRoomInvite(deletedInviterWithoutReason), isTrue);
    expect(isActionablePendingRoomInvite(pending), isTrue);
    expect(isActionablePendingRoomInvite(invalid), isFalse);
    expect(isActionablePendingRoomInvite(deletedInviterWithoutReason), isFalse);
    expect(roomInviteDecisionLabel(invalid), '已失效');
    expect(roomInviteDecisionLabel(deletedInviterWithoutReason), '已失效');
    expect(roomInviteDecisionLabel(accepted), '已接受');
    expect(roomInviteDecisionLabel(rejected), '已拒绝');
    expect(roomInviteRoleLabel(_user('owner', roomRole: 'owner')), '创建者');
    expect(roomInviteRoleLabel(_user('admin', roomRole: 'admin')), '管理员');
    expect(roomInviteRoleLabel(_user('member', roomRole: 'member')), '成员');
    expect(roomInviteRoleLabel(_user('left', roomRole: 'left')), '已离开');
    expect(pendingRoomInviteCount([pending, invalid]), 1);
    expect(pendingRoomInviteCount([pending, deletedInviterWithoutReason]), 1);
    expect(
      roomInviteTimestampLabel(DateTime(2026, 6, 9, 8, 5)),
      '2026/06/09 08:05',
    );
  });

  test('deleted notification rooms display as missing room targets', () {
    final deleted = _invite(
      'deleted',
      roomName: 'Deleted Room',
      roomExists: false,
      invalidReason: 'room_missing',
    );

    expect(
      roomNotificationRoomLabel(deleted.room, roomExists: deleted.roomExists),
      '房间不存在',
    );
    expect(
      roomNotificationRoomAvatarLabel(
        deleted.room,
        roomExists: deleted.roomExists,
      ),
      '',
    );
    expect(
      roomNotificationRoomAvatarUrl(
        deleted.room,
        roomExists: deleted.roomExists,
      ),
      isNull,
    );
    expect(
      roomNotificationRoomAvatarKey(
        deleted.room,
        roomExists: deleted.roomExists,
      ),
      'graphite-2',
    );
    expect(
      roomNotificationRoomCardEnabled(roomExists: deleted.roomExists),
      isFalse,
    );
    expect(
      roomInviteNotificationsForView(
        invites: [deleted],
        query: '房间不存在',
        filter: RoomNotificationFilter.all,
      ),
      [deleted],
    );
    expect(
      roomInviteNotificationsForView(
        invites: [deleted],
        query: '不存在',
        filter: RoomNotificationFilter.all,
      ),
      [deleted],
    );
  });

  test('deleted notification users display as missing user targets', () {
    final deletedInviter = _invite(
      'deleted_inviter',
      inviter: _user(
        'deleted_inviter',
        displayName: 'Deleted Inviter',
        roomRole: 'left',
      ),
      inviterExists: false,
      invalidReason: 'inviter_deleted',
    );
    final deletedReviewer = _application(
      'deleted_reviewer',
      status: 'approved',
      reviewedAt: DateTime.utc(2026, 6, 7, 8),
      reviewer: _user(
        'deleted_reviewer',
        displayName: 'Deleted Reviewer',
        roomRole: 'owner',
      ),
      reviewerExists: false,
    );

    expect(
      roomNotificationUserLabel(
        deletedInviter.inviter,
        userExists: deletedInviter.inviterExists,
      ),
      '用户不存在',
    );
    expect(
      roomNotificationUserAvatarLabel(
        deletedInviter.inviter,
        userExists: deletedInviter.inviterExists,
      ),
      '',
    );
    expect(
      roomNotificationUserAvatarUrl(
        deletedInviter.inviter,
        userExists: deletedInviter.inviterExists,
      ),
      isNull,
    );
    expect(
      roomNotificationUserAvatarKey(
        deletedInviter.inviter,
        userExists: deletedInviter.inviterExists,
      ),
      'graphite-2',
    );
    expect(
      roomInviteNotificationsForView(
        invites: [deletedInviter],
        query: '用户不存在',
        filter: RoomNotificationFilter.all,
      ),
      [deletedInviter],
    );
    expect(
      roomNotificationsForView(
        invites: const [],
        applications: [deletedReviewer],
        query: '用户不存在',
        filter: RoomNotificationFilter.all,
      ).map((item) => item.id),
      [
        'application-reviewed:deleted_reviewer',
        'application-requested:deleted_reviewer',
      ],
    );
  });

  test('room notifications combine invites and applications for view', () {
    final pendingInvite = _invite(
      'pending_invite',
      status: 'pending',
      createdAt: DateTime.utc(2026, 6, 5, 8),
    );
    final pendingApplication = _application(
      'pending_application',
      status: 'pending',
      createdAt: DateTime.utc(2026, 6, 6, 8),
    );
    final approvedApplication = _application(
      'approved_application',
      status: 'approved',
      createdAt: DateTime.utc(2026, 6, 1, 8),
      updatedAt: DateTime.utc(2026, 6, 7, 8),
      reviewedAt: DateTime.utc(2026, 6, 7, 8),
      reviewer: _user(
        'reviewer_1',
        displayName: 'Robin Reviewer',
        roomRole: 'admin',
      ),
    );

    final visible = roomNotificationsForView(
      invites: [pendingInvite],
      applications: [approvedApplication, pendingApplication],
      query: '',
      filter: RoomNotificationFilter.all,
    );

    expect(visible.map((item) => item.id), [
      'application-requested:pending_application',
      'invite:pending_invite',
      'application-reviewed:approved_application',
      'application-requested:approved_application',
    ]);
    expect(
      pendingRoomNotificationCount(
        invites: [pendingInvite],
        applications: [pendingApplication, approvedApplication],
        roomEvents: [
          _roomEvent('unread_room_event'),
          _roomEvent('read_room_event', readAt: DateTime.utc(2026, 6, 8, 9)),
        ],
      ),
      3,
    );
  });

  test('room event notifications can be marked read locally', () {
    final alreadyReadAt = DateTime.utc(2026, 6, 8, 9);
    final readAt = DateTime.utc(2026, 6, 8, 10);
    final updated = markUnreadRoomEventNotificationsRead(
      notifications: [
        _roomEvent('unread_room_event'),
        _roomEvent('read_room_event', readAt: alreadyReadAt),
      ],
      readAt: readAt,
    );

    expect(updated.first.isUnread, isFalse);
    expect(updated.first.readAt, readAt);
    expect(updated.last.isUnread, isFalse);
    expect(updated.last.readAt, alreadyReadAt);
  });

  test('room event notification visual read can be limited to known ids', () {
    final readAt = DateTime.utc(2026, 6, 8, 10);
    final updated = markUnreadRoomEventNotificationsRead(
      notifications: [
        _roomEvent('old_room_event'),
        _roomEvent('fresh_room_event'),
      ],
      readAt: readAt,
      notificationIds: const {'old_room_event'},
    );

    expect(updated.first.isUnread, isFalse);
    expect(updated.first.readAt, readAt);
    expect(updated.last.isUnread, isTrue);
    expect(updated.last.readAt, isNull);
  });

  test('room event notifications filter and search room events', () {
    final promoted = _roomEvent(
      'promoted',
      type: kRoomEventNotificationRolePromoted,
      roomName: 'Launch Room',
      actor: _user(
        'actor_promoted',
        displayName: 'Morgan Admin',
        roomRole: 'owner',
      ),
      toRole: 'admin',
    );
    final removed = _roomEvent(
      'removed',
      type: kRoomEventNotificationMemberRemoved,
      createdAt: DateTime.utc(2026, 6, 8, 8),
    );

    final roomEventsOnly = roomNotificationsForView(
      invites: [_invite('invite_1')],
      applications: [_application('application_1')],
      roomEvents: [promoted, removed],
      query: '',
      filter: RoomNotificationFilter.roomNotifications,
    );
    expect(roomEventsOnly.map((item) => item.id), [
      'room-event:removed',
      'room-event:promoted',
    ]);
    expect(roomEventsOnly.every((item) => item.invite == null), isTrue);
    expect(roomEventsOnly.every((item) => item.application == null), isTrue);
    expect(roomEventsOnly.first.newItem, isTrue);

    expect(
      roomNotificationsForView(
        invites: const [],
        applications: const [],
        roomEvents: [promoted],
        query: 'Morgan Admin',
        filter: RoomNotificationFilter.all,
      ).single.roomEvent,
      promoted,
    );
    expect(
      roomNotificationsForView(
        invites: const [],
        applications: const [],
        roomEvents: [promoted],
        query: '管理员',
        filter: RoomNotificationFilter.all,
      ).single.roomEvent,
      promoted,
    );
    expect(
      roomNotificationsForView(
        invites: const [],
        applications: const [],
        roomEvents: [promoted],
        query: 'missing',
        filter: RoomNotificationFilter.all,
      ),
      isEmpty,
    );

    final readEvent = _roomEvent('read', readAt: DateTime.utc(2026, 6, 8, 9));
    expect(
      roomNotificationsForView(
        invites: const [],
        applications: const [],
        roomEvents: [readEvent],
        query: '',
        filter: RoomNotificationFilter.all,
      ).single.newItem,
      isFalse,
    );
  });

  test('room application notifications filter and search reviewer fields', () {
    final application = _application(
      'application_1',
      status: 'rejected',
      roomName: 'Launch Room',
      reviewedAt: DateTime.utc(2026, 6, 7, 8),
      reviewer: _user(
        'reviewer_1',
        username: 'robin',
        displayName: 'Robin Reviewer',
        roomRole: 'owner',
        roomDisplayName: 'Room Robin',
      ),
    );

    final applicationsOnly = roomNotificationsForView(
      invites: [_invite('invite_1')],
      applications: [application],
      query: '',
      filter: RoomNotificationFilter.applications,
    );
    expect(applicationsOnly.map((item) => item.type), [
      RoomNotificationItemType.applicationReviewed,
      RoomNotificationItemType.applicationRequested,
    ]);

    expect(
      roomNotificationsForView(
        invites: const [],
        applications: [application],
        query: 'Room Robin',
        filter: RoomNotificationFilter.all,
      ),
      isNotEmpty,
    );
    expect(
      roomNotificationsForView(
        invites: const [],
        applications: [application],
        query: 'missing',
        filter: RoomNotificationFilter.all,
      ),
      isEmpty,
    );
  });

  test('room application notification display helpers format labels', () {
    final pending = _application('pending', status: 'pending');
    final approved = _application('approved', status: 'approved');
    final rejected = _application('rejected', status: 'rejected');
    final withdrawn = _application('withdrawn', status: 'withdrawn');

    expect(
      canWithdrawNotificationApplication(
        application: pending,
        busyApplicationId: null,
      ),
      isTrue,
    );
    expect(
      canWithdrawNotificationApplication(
        application: pending,
        busyApplicationId: 'pending',
      ),
      isFalse,
    );
    expect(
      canWithdrawNotificationApplication(
        application: approved,
        busyApplicationId: null,
      ),
      isFalse,
    );
    expect(roomApplicationStatusLabel(approved), '已批准');
    expect(roomApplicationStatusLabel(rejected), '已拒绝');
    expect(roomApplicationStatusLabel(withdrawn), '已撤回');
    expect(roomApplicationReviewActionLabel(approved), '批准了您的申请');
    expect(roomApplicationReviewActionLabel(rejected), '拒绝了您的申请');
  });

  test('room invite application gate follows inviter role', () {
    expect(
      roomInviteAcceptRequiresApplication(
        _invite(
          'member',
          joinPolicy: 'approval_required',
          inviter: _user('member', roomRole: 'member'),
        ),
      ),
      isTrue,
    );
    expect(
      roomInviteAcceptRequiresApplication(
        _invite(
          'admin',
          joinPolicy: 'approval_required',
          inviter: _user('admin', roomRole: 'admin'),
        ),
      ),
      isFalse,
    );
    final memberInvite = _invite(
      'member-related',
      roomId: 'room_shared',
      joinPolicy: 'approval_required',
      inviter: _user('member', roomRole: 'member'),
    );
    final adminInvite = _invite(
      'admin-related',
      roomId: 'room_shared',
      joinPolicy: 'approval_required',
      inviter: _user('admin', roomRole: 'admin'),
    );
    expect(
      roomInviteAcceptRequiresApplication(
        memberInvite,
        roomInvites: [memberInvite, adminInvite],
      ),
      isFalse,
    );
    expect(
      roomInviteAcceptRequiresApplication(
        _invite(
          'super',
          joinPolicy: 'approval_required',
          inviter: _user('super', roomRole: 'superuser', isSuperuser: true),
        ),
      ),
      isFalse,
    );
    expect(
      roomInviteAcceptRequiresApplication(_invite('open', joinPolicy: 'open')),
      isFalse,
    );
  });
}

RoomInvite _invite(
  String id, {
  String status = 'pending',
  DateTime? createdAt,
  String roomName = 'Invite Room',
  String roomRid = 'R-1',
  String? roomId,
  String joinPolicy = 'closed',
  UserSummary? inviter,
  bool roomExists = true,
  bool inviterExists = true,
  String? invalidReason,
}) {
  return RoomInvite(
    id: id,
    status: status,
    room: PublicRoom(
      id: roomId ?? 'room_$id',
      rid: roomRid,
      name: roomName,
      avatarUrl: null,
      defaultAvatarKey: 'room-1',
      visibility: 'private',
      joinPolicy: joinPolicy,
      memberCount: 3,
      onlineMemberCount: 1,
      liveParticipantCount: 0,
      joined: false,
      joinState: 'none',
    ),
    inviter: inviter ?? _user('inviter_$id', roomRole: 'owner'),
    createdAt: createdAt ?? DateTime.utc(2026, 6, 5, 12),
    roomExists: roomExists,
    inviterExists: inviterExists,
    invalidReason: invalidReason,
  );
}

RoomApplication _application(
  String id, {
  String status = 'pending',
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? reviewedAt,
  String roomName = 'Application Room',
  String roomRid = 'A-1',
  UserSummary? reviewer,
  bool reviewerExists = true,
}) {
  return RoomApplication(
    id: id,
    status: status,
    room: PublicRoom(
      id: 'room_$id',
      rid: roomRid,
      name: roomName,
      avatarUrl: null,
      defaultAvatarKey: 'room-1',
      visibility: 'private',
      joinPolicy: 'approval_required',
      memberCount: 3,
      onlineMemberCount: 1,
      liveParticipantCount: 0,
      joined: false,
      joinState: 'pending',
    ),
    createdAt: createdAt ?? DateTime.utc(2026, 6, 5, 12),
    updatedAt: updatedAt ?? DateTime.utc(2026, 6, 5, 12),
    reviewedAt: reviewedAt,
    reviewer: reviewer,
    reviewerExists: reviewerExists,
  );
}

RoomEventNotification _roomEvent(
  String id, {
  String type = kRoomEventNotificationRoleDemoted,
  DateTime? createdAt,
  String roomName = 'Event Room',
  String roomRid = 'E-1',
  UserSummary? actor,
  bool actorExists = true,
  bool roomExists = true,
  String fromRole = 'owner',
  String toRole = 'admin',
  DateTime? readAt,
}) {
  return RoomEventNotification(
    id: id,
    type: type,
    room: PublicRoom(
      id: 'room_event_$id',
      rid: roomRid,
      name: roomName,
      avatarUrl: null,
      defaultAvatarKey: 'room-1',
      visibility: 'private',
      joinPolicy: 'approval_required',
      memberCount: 3,
      onlineMemberCount: 1,
      liveParticipantCount: 0,
      joined: false,
      joinState: 'none',
    ),
    actor: actor ?? _user('actor_$id', roomRole: 'owner'),
    createdAt: createdAt ?? DateTime.utc(2026, 6, 5, 12),
    actorExists: actorExists,
    roomExists: roomExists,
    fromRole: fromRole,
    toRole: toRole,
    readAt: readAt,
  );
}

UserSummary _user(
  String id, {
  String? uid,
  String? username,
  String? displayName,
  String? roomRole,
  String? roomDisplayName,
  bool isSuperuser = false,
  List<UserCommonRoom> commonRooms = const [],
}) {
  return UserSummary(
    id: id,
    uid: uid,
    username: username ?? 'user_$id',
    displayName: displayName ?? 'User $id',
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    roomRole: roomRole,
    roomDisplayName: roomDisplayName,
    isSuperuser: isSuperuser,
    commonRooms: commonRooms,
  );
}
