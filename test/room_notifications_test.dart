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
    final pendingNew = _invite(
      'pending_new',
      status: 'pending',
      createdAt: DateTime.utc(2026, 6, 4, 8),
    );

    final visible = roomInviteNotificationsForView(
      invites: [accepted, pendingOld, rejectedNew, pendingNew],
      query: '',
      filter: RoomNotificationFilter.all,
    );

    expect(visible.map((invite) => invite.id), [
      'pending_new',
      'pending_old',
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
    expect(roomInviteDecisionLabel(accepted), '已接受');
    expect(roomInviteDecisionLabel(rejected), '已拒绝');
    expect(roomInviteRoleLabel(_user('owner', roomRole: 'owner')), '房主');
    expect(roomInviteRoleLabel(_user('admin', roomRole: 'admin')), '管理员');
    expect(roomInviteRoleLabel(_user('member', roomRole: 'member')), '成员');
    expect(
      roomInviteTimestampLabel(DateTime(2026, 6, 9, 8, 5)),
      '2026/06/09 08:05',
    );
  });
}

RoomInvite _invite(
  String id, {
  String status = 'pending',
  DateTime? createdAt,
  String roomName = 'Invite Room',
  String roomRid = 'R-1',
  UserSummary? inviter,
}) {
  return RoomInvite(
    id: id,
    status: status,
    room: PublicRoom(
      id: 'room_$id',
      rid: roomRid,
      name: roomName,
      avatarUrl: null,
      defaultAvatarKey: 'room-1',
      visibility: 'private',
      joinPolicy: 'closed',
      memberCount: 3,
      onlineMemberCount: 1,
      liveParticipantCount: 0,
      joined: false,
      joinState: 'none',
    ),
    inviter: inviter ?? _user('inviter_$id', roomRole: 'owner'),
    createdAt: createdAt ?? DateTime.utc(2026, 6, 5, 12),
  );
}

UserSummary _user(
  String id, {
  String? uid,
  String? username,
  String? displayName,
  String? roomRole,
  String? roomDisplayName,
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
    commonRooms: commonRooms,
  );
}
