import 'package:client/src/home/room_profile_card.dart';
import 'package:client/src/home/home_notifications.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _currentUser = CurrentUser(
  id: 'u_current',
  uid: '1000002',
  username: 'current',
  displayName: 'Current User',
  bio: '',
  gender: 'secret',
  email: null,
  emailPublic: false,
  phoneNumber: null,
  phoneNumberPublic: false,
  avatarUrl: null,
  defaultAvatarKey: 'green-2',
  isSuperuser: false,
  createdAt: null,
);

const _creator = UserSummary(
  id: 'u_creator',
  username: 'creator',
  displayName: 'Room Creator',
  avatarUrl: null,
  defaultAvatarKey: 'blue-3',
);

final _joinedRoom = PublicRoom(
  id: 'room_1',
  rid: 'R10001',
  name: 'Launch Room',
  description: '用于发布前沟通的语音频道。',
  avatarUrl: null,
  defaultAvatarKey: 'room-2',
  visibility: 'private',
  joinPolicy: 'closed',
  memberCount: 12,
  onlineMemberCount: 3,
  liveParticipantCount: 1,
  joined: true,
  joinState: 'joined',
  createdBy: _creator,
  personalProfile: RoomPersonalProfile(
    displayName: 'Current In Room',
    avatarUrl: null,
    defaultAvatarKey: 'mint-2',
  ),
  myMembership: RoomMembership(
    joinedAt: DateTime.utc(2026, 6, 1),
    role: 'admin',
  ),
);

Widget _host(Widget child) {
  return MaterialApp(
    theme: uiTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('hover over a room avatar reveals the room profile card', (
    tester,
  ) async {
    PublicRoom? openedRoom;
    await tester.pumpWidget(
      _host(
        RoomHoverCardForTest(
          room: _joinedRoom,
          currentUser: _currentUser,
          onEnterRoom: (room) => openedRoom = room,
        ),
      ),
    );

    expect(find.text('RID: R10001'), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();

    expect(find.text('Launch Room'), findsWidgets);
    expect(find.text('12 名成员'), findsOneWidget);
    expect(find.text('用于发布前沟通的语音频道。'), findsOneWidget);
    expect(find.text('创建者'), findsOneWidget);
    expect(find.text('Room Creator'), findsOneWidget);
    expect(find.text('我的房间内信息'), findsOneWidget);
    expect(find.text('Current In Room'), findsOneWidget);
    expect(find.text('管理员'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('RID: R10001'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('进入房间')).dy,
      greaterThan(tester.getTopLeft(find.text('RID: R10001')).dy),
    );

    await tester.tap(find.text('进入房间'));
    await tester.pumpAndSettle();
    expect(openedRoom?.id, 'room_1');
  });

  testWidgets('tap pins a room profile card until an outside tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(RoomHoverCardForTest(room: _joinedRoom, currentUser: _currentUser)),
    );

    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
    expect(find.text('RID: R10001'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('RID: R10001'), findsNothing);
  });

  testWidgets('deleted notification rooms do not open room profile cards', (
    tester,
  ) async {
    final invite = RoomInvite(
      id: 'invite_deleted',
      status: 'pending',
      room: PublicRoom(
        id: 'room_deleted',
        rid: 'R404',
        name: 'Deleted Room',
        description: 'This should not be visible.',
        avatarUrl: '/deleted.png',
        defaultAvatarKey: 'room-2',
        visibility: 'private',
        joinPolicy: 'closed',
        memberCount: 0,
        onlineMemberCount: 0,
        liveParticipantCount: 0,
        joined: false,
        joinState: 'none',
        createdBy: _creator,
      ),
      inviter: _creator,
      createdAt: DateTime.utc(2026, 6, 1),
      roomExists: false,
      invalidReason: 'room_missing',
    );

    await tester.pumpWidget(
      _host(
        HomeNotificationsPane(
          invites: [invite],
          applications: const [],
          loading: false,
          error: null,
          busyInviteId: null,
          busyApplicationId: null,
          currentUser: _currentUser,
          onClose: () {},
          onRefresh: () {},
          onReviewInvite: (_, _) async {},
          onWithdrawApplication: (_) async {},
          onOpenRoom: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('房间不存在'), findsOneWidget);
    expect(find.text('空'), findsOneWidget);
    expect(find.text('Deleted Room'), findsNothing);

    final avatarFinder = find.byKey(
      const ValueKey('notification-room-avatar-invite_deleted'),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(avatarFinder));
    await tester.pumpAndSettle();
    expect(find.text('Deleted Room'), findsNothing);
    expect(find.text('RID: R404'), findsNothing);

    await tester.tap(avatarFinder);
    await tester.pumpAndSettle();
    expect(find.text('Deleted Room'), findsNothing);
    expect(find.text('RID: R404'), findsNothing);
  });

  testWidgets('deleted notification users display missing user placeholders', (
    tester,
  ) async {
    final invite = RoomInvite(
      id: 'invite_deleted_user',
      status: 'pending',
      room: PublicRoom(
        id: 'room_1',
        rid: 'R100',
        name: 'Invite Room',
        avatarUrl: null,
        defaultAvatarKey: 'room-2',
        visibility: 'private',
        joinPolicy: 'closed',
        memberCount: 2,
        onlineMemberCount: 0,
        liveParticipantCount: 0,
        joined: false,
        joinState: 'none',
      ),
      inviter: const UserSummary(
        id: 'user_deleted',
        username: 'deleted',
        displayName: 'Deleted User',
        avatarUrl: '/deleted-user.png',
        defaultAvatarKey: 'blue-3',
        roomRole: 'left',
      ),
      createdAt: DateTime.utc(2026, 6, 1),
      inviterExists: false,
      invalidReason: 'inviter_deleted',
    );

    await tester.pumpWidget(
      _host(
        HomeNotificationsPane(
          invites: [invite],
          applications: const [],
          loading: false,
          error: null,
          busyInviteId: null,
          busyApplicationId: null,
          currentUser: _currentUser,
          onClose: () {},
          onRefresh: () {},
          onReviewInvite: (_, _) async {},
          onWithdrawApplication: (_) async {},
          onOpenRoom: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('用户不存在'), findsOneWidget);
    expect(find.text('空'), findsOneWidget);
    expect(find.text('Deleted User'), findsNothing);
  });
}
