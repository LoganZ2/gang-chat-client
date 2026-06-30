import 'dart:async';

import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/ui.dart';
import 'package:client/src/home/chat_pane.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _user = UserSummary(
  id: 'u1',
  username: 'logan',
  displayName: '加一',
  avatarUrl: null,
  defaultAvatarKey: 'blue-3',
  uid: '10001',
  bio: '随便写点什么',
  gender: 'male',
  roomRole: 'admin',
  isOnline: true,
  commonRooms: [
    UserCommonRoom(id: 'r1', rid: 'R1', name: '摸鱼大队'),
    UserCommonRoom(id: 'r2', rid: 'R2', name: '技术交流'),
  ],
);

const _currentUser = CurrentUser(
  id: 'u1',
  uid: '10001',
  username: 'logan',
  displayName: '加一',
  bio: '',
  gender: 'secret',
  email: null,
  emailPublic: false,
  phoneNumber: null,
  phoneNumberPublic: false,
  avatarUrl: null,
  defaultAvatarKey: 'blue-3',
  isSuperuser: false,
  createdAt: null,
);

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('hover over a message avatar reveals the profile card', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AvatarHoverCardForTest(user: _user)));

    // Card stays hidden until the pointer enters the avatar.
    expect(find.text('@logan'), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();

    expect(find.text('@logan'), findsOneWidget);
    expect(find.text('加一'), findsWidgets);
    expect(find.text('♂'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('管理员'), findsOneWidget);
    expect(find.text('男'), findsNothing);
    expect(
      tester.widget<Text>(find.text('♂')).style?.color,
      genderMark('male')?.color,
    );
    expect(
      tester.widget<Text>(find.text('♂')).style?.fontWeight,
      FontWeight.w900,
    );
    expect(find.text('随便写点什么'), findsOneWidget);
    expect(find.text('2 个共同房间'), findsOneWidget);
    expect(find.text('摸鱼大队'), findsOneWidget);
    expect(find.text('技术交流'), findsOneWidget);
    expect(find.text('UID: 10001'), findsOneWidget);

    // Card disappears when the pointer leaves the avatar.
    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsNothing);
  });

  testWidgets('hover card shows voice instead of online presence tag', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AvatarHoverCardForTest(user: _user, inLive: true)),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();

    expect(find.text('在线'), findsNothing);
    expect(find.text('离线'), findsNothing);
    expect(find.text('语音'), findsOneWidget);
    final avatar = tester.widget<Avatar>(
      find.byWidgetPredicate((widget) => widget is Avatar && widget.size == 48),
    );
    expect(avatar.active, isTrue);
    expect(avatar.activeBorderColor, UiColors.presenceVoice);
    expect(avatar.paintBorderOnForeground, isTrue);
  });

  testWidgets('hover card treats current user as online without summary flag', (
    tester,
  ) async {
    const lightweightSelf = UserSummary(
      id: 'u1',
      username: 'logan',
      displayName: '加一',
      avatarUrl: null,
      defaultAvatarKey: 'blue-3',
    );

    await tester.pumpWidget(
      _host(
        const AvatarHoverCardForTest(
          user: lightweightSelf,
          currentUser: _currentUser,
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();

    expect(find.text('在线'), findsOneWidget);
    final avatar = tester.widget<Avatar>(
      find.byWidgetPredicate((widget) => widget is Avatar && widget.size == 48),
    );
    expect(avatar.active, isTrue);
    expect(avatar.activeBorderColor, isNull);
    expect(avatar.paintBorderOnForeground, isTrue);
  });

  testWidgets('hover card hides room role outside room context', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AvatarHoverCardForTest(user: _user, showRoomRole: false)),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();

    expect(find.text('@logan'), findsOneWidget);
    expect(find.text('管理员'), findsNothing);
  });

  testWidgets('moving the cursor onto the card keeps it open', (tester) async {
    await tester.pumpWidget(_host(const AvatarHoverCardForTest(user: _user)));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);

    // Move onto the card itself — it should stay open past the close delay.
    await gesture.moveTo(tester.getCenter(find.text('@logan')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);
  });

  testWidgets('profile card identity text can be selected and copied', (
    tester,
  ) async {
    final clipboardWrites = <String>[];
    _mockClipboard(clipboardWrites);

    await tester.pumpWidget(_host(const AvatarHoverCardForTest(user: _user)));

    await _ensureUserProfileCardOpen(tester);
    await _copyReadOnlyField(
      tester,
      _user.displayName,
      clipboardWrites: clipboardWrites,
    );
    await _ensureUserProfileCardOpen(tester);
    await _copyReadOnlyField(
      tester,
      '@${_user.username}',
      copyStartOffset: 1,
      expectedCopy: _user.username,
      clipboardWrites: clipboardWrites,
    );
    await _ensureUserProfileCardOpen(tester);
    await _copyReadOnlyField(
      tester,
      'UID: ${_user.uid}',
      copyStartOffset: 'UID: '.length,
      expectedCopy: _user.uid!,
      clipboardWrites: clipboardWrites,
    );

    expect(clipboardWrites, [_user.displayName, _user.username, _user.uid]);
  });

  testWidgets('common room avatar opens a room profile card', (tester) async {
    await tester.pumpWidget(_host(const AvatarHoverCardForTest(user: _user)));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);

    final commonRoomAvatar = find.byWidgetPredicate(
      (widget) => widget is Avatar && widget.label == '摸鱼大队',
    );
    expect(commonRoomAvatar, findsOneWidget);

    await gesture.moveTo(tester.getCenter(commonRoomAvatar));
    await tester.pumpAndSettle();

    expect(find.text('RID: R1'), findsOneWidget);
  });

  testWidgets('nested room card keeps the parent user card open', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AvatarHoverCardForTest(user: _user)));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);

    final commonRoomAvatar = find.byWidgetPredicate(
      (widget) => widget is Avatar && widget.label == '摸鱼大队',
    );
    await gesture.moveTo(tester.getCenter(commonRoomAvatar));
    await tester.pumpAndSettle();
    expect(find.text('RID: R1'), findsOneWidget);

    await gesture.moveTo(tester.getCenter(find.text('RID: R1')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('@logan'), findsOneWidget);
    expect(find.text('RID: R1'), findsOneWidget);
  });

  testWidgets('tapping the avatar again closes the profile card', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AvatarHoverCardForTest(user: _user)));

    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);

    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsNothing);
  });

  testWidgets('click pinning is independent from hover-opened cards', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AvatarHoverCardForTest(user: _user)));

    final avatar = find.byType(Avatar).first;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(avatar));
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);

    await tester.tap(avatar);
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);

    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);

    await tester.tap(avatar);
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsNothing);
  });

  testWidgets('nested room enter button invokes the common room callback', (
    tester,
  ) async {
    PublicRoom? openedRoom;
    await tester.pumpWidget(
      _host(
        AvatarHoverCardForTest(
          user: _user,
          onEnterCommonRoom: (room) => openedRoom = room,
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();

    final commonRoomAvatar = find.byWidgetPredicate(
      (widget) => widget is Avatar && widget.label == '摸鱼大队',
    );
    await gesture.moveTo(tester.getCenter(commonRoomAvatar));
    await tester.pumpAndSettle();

    await tester.tap(find.text('进入房间'));
    await tester.pumpAndSettle();

    expect(openedRoom?.id, 'r1');
  });

  testWidgets('opening another common room closes the previous room card', (
    tester,
  ) async {
    const siblingUser = UserSummary(
      id: 'u1',
      username: 'logan',
      displayName: 'Logan',
      avatarUrl: null,
      defaultAvatarKey: 'blue-3',
      commonRooms: [
        UserCommonRoom(id: 'r1', rid: 'R1', name: 'Room One'),
        UserCommonRoom(id: 'r2', rid: 'R2', name: 'Room Two'),
      ],
    );
    await tester.pumpWidget(
      _host(const AvatarHoverCardForTest(user: siblingUser)),
    );

    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);

    final firstCommonRoomAvatar = find.byWidgetPredicate(
      (widget) => widget is Avatar && widget.label == 'Room One',
    );
    final secondCommonRoomAvatar = find.byWidgetPredicate(
      (widget) => widget is Avatar && widget.label == 'Room Two',
    );
    expect(firstCommonRoomAvatar, findsOneWidget);
    expect(secondCommonRoomAvatar, findsOneWidget);

    await tester.tap(firstCommonRoomAvatar);
    await tester.pumpAndSettle();
    expect(find.text('RID: R1'), findsOneWidget);

    await tester.tap(secondCommonRoomAvatar);
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);
    expect(find.text('RID: R1'), findsNothing);
    expect(find.text('RID: R2'), findsOneWidget);
  });

  testWidgets('common rooms overflow scrolls instead of showing summary row', (
    tester,
  ) async {
    const manyRoomsUser = UserSummary(
      id: 'u1',
      username: 'logan',
      displayName: 'Logan',
      avatarUrl: null,
      defaultAvatarKey: 'blue-3',
      commonRooms: [
        UserCommonRoom(id: 'r1', rid: 'R1', name: 'Room One'),
        UserCommonRoom(id: 'r2', rid: 'R2', name: 'Room Two'),
        UserCommonRoom(id: 'r3', rid: 'R3', name: 'Room Three'),
        UserCommonRoom(id: 'r4', rid: 'R4', name: 'Room Four'),
        UserCommonRoom(id: 'r5', rid: 'R5', name: 'Room Five'),
        UserCommonRoom(id: 'r6', rid: 'R6', name: 'Room Six'),
      ],
    );

    await tester.pumpWidget(
      _host(const AvatarHoverCardForTest(user: manyRoomsUser)),
    );

    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();

    expect(find.text('6 个共同房间'), findsOneWidget);
    expect(find.text('等 6 个房间'), findsNothing);
    expect(find.byType(Scrollbar), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Room Six'),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Room Six'), findsOneWidget);
  });

  testWidgets('clicking an earlier card rolls back later nested cards', (
    tester,
  ) async {
    const creator = UserSummary(
      id: 'creator',
      username: 'creator',
      displayName: 'Creator',
      avatarUrl: null,
      defaultAvatarKey: 'green-2',
    );
    const rollbackUser = UserSummary(
      id: 'u1',
      username: 'logan',
      displayName: 'Logan',
      avatarUrl: null,
      defaultAvatarKey: 'blue-3',
      commonRooms: [UserCommonRoom(id: 'r1', rid: 'R1', name: 'Room One')],
    );

    await tester.pumpWidget(
      _host(
        AvatarHoverCardForTest(
          user: rollbackUser,
          onResolveRoomProfile: (room) async {
            return PublicRoom(
              id: room.id,
              rid: room.rid,
              name: room.name,
              avatarUrl: null,
              defaultAvatarKey: 'room-1',
              visibility: 'private',
              joinPolicy: 'closed',
              memberCount: 2,
              onlineMemberCount: 1,
              liveParticipantCount: 0,
              joined: true,
              joinState: 'joined',
              createdBy: creator,
            );
          },
          onResolveProfile: (user) async {
            if (user.id == creator.id) {
              return user.copyWith(bio: 'Creator bio', isOnline: true);
            }
            return user;
          },
        ),
      ),
    );

    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);

    final commonRoomAvatar = find.byWidgetPredicate(
      (widget) => widget is Avatar && widget.label == 'Room One',
    );
    await tester.tap(commonRoomAvatar);
    await tester.pumpAndSettle();
    expect(find.text('RID: R1'), findsOneWidget);

    final creatorAvatar = find.byWidgetPredicate(
      (widget) => widget is Avatar && widget.label == 'Creator',
    );
    await tester.tap(creatorAvatar);
    await tester.pumpAndSettle();
    expect(find.text('@creator'), findsOneWidget);
    expect(find.text('Creator bio'), findsOneWidget);

    final roomCardAvatar = find.byWidgetPredicate(
      (widget) =>
          widget is Avatar && widget.label == 'Room One' && widget.size == 48,
    );
    await tester.tap(roomCardAvatar);
    await tester.pumpAndSettle();
    expect(find.text('@creator'), findsNothing);
    expect(find.text('Creator bio'), findsNothing);
    expect(find.text('RID: R1'), findsOneWidget);
    expect(find.text('@logan'), findsOneWidget);

    final userCardAvatar = find.byWidgetPredicate(
      (widget) =>
          widget is Avatar && widget.label == 'Logan' && widget.size == 48,
    );
    await tester.tap(userCardAvatar);
    await tester.pumpAndSettle();
    expect(find.text('RID: R1'), findsNothing);
    expect(find.text('@logan'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsNothing);
  });

  testWidgets('common room avatar waits for the latest room profile', (
    tester,
  ) async {
    var resolveCalls = 0;
    await tester.pumpWidget(
      _host(
        AvatarHoverCardForTest(
          user: _user,
          onResolveRoomProfile: (room) async {
            resolveCalls += 1;
            return PublicRoom(
              id: room.id,
              rid: room.rid,
              name: 'Fresh Room',
              avatarUrl: null,
              defaultAvatarKey: 'room-1',
              visibility: 'private',
              joinPolicy: 'closed',
              description: 'Latest room summary',
              memberCount: 9,
              onlineMemberCount: 3,
              liveParticipantCount: 0,
              joined: true,
              joinState: 'joined',
            );
          },
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();

    final commonRoomAvatar = find.byWidgetPredicate(
      (widget) => widget is Avatar && widget.label == '摸鱼大队',
    );
    await gesture.moveTo(tester.getCenter(commonRoomAvatar));
    await tester.pumpAndSettle();

    expect(resolveCalls, 1);
    expect(find.text('Fresh Room'), findsOneWidget);
    expect(find.text('Latest room summary'), findsOneWidget);
    expect(find.text('9 名成员'), findsOneWidget);
  });

  testWidgets('tap opens the profile card until an outside tap', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AvatarHoverCardForTest(user: _user)));

    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();
    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsNothing);
  });

  testWidgets('resolves gender and common rooms before opening', (
    tester,
  ) async {
    // The message summary lacks gender/common rooms; the resolver supplies them.
    const lightweight = UserSummary(
      id: 'u1',
      username: 'logan',
      displayName: '加一',
      avatarUrl: null,
      defaultAvatarKey: 'blue-3',
    );
    var calls = 0;
    Future<UserSummary> resolve(UserSummary sender) async {
      calls++;
      return _user;
    }

    await tester.pumpWidget(
      _host(
        AvatarHoverCardForTest(user: lightweight, onResolveProfile: resolve),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('♂'), findsOneWidget);
    expect(find.text('男'), findsNothing);
    expect(find.text('2 个共同房间'), findsOneWidget);
    expect(find.text('摸鱼大队'), findsOneWidget);
  });

  testWidgets('refreshes the resolved profile each time the card opens', (
    tester,
  ) async {
    const lightweight = UserSummary(
      id: 'u1',
      username: 'logan',
      displayName: 'Initial User',
      avatarUrl: null,
      defaultAvatarKey: 'blue-3',
    );
    var calls = 0;
    Future<UserSummary> resolve(UserSummary sender) async {
      calls += 1;
      return sender.copyWith(
        displayName: 'Fresh User $calls',
        bio: 'Fresh bio $calls',
        isOnline: calls.isEven,
      );
    }

    await tester.pumpWidget(
      _host(
        AvatarHoverCardForTest(user: lightweight, onResolveProfile: resolve),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final avatarCenter = tester.getCenter(find.byType(Avatar).first);
    await gesture.moveTo(avatarCenter);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Fresh User 1'), findsOneWidget);
    expect(find.text('Fresh bio 1'), findsOneWidget);

    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Fresh User 1'), findsNothing);

    await gesture.moveTo(avatarCenter);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Fresh User 1'), findsNothing);
    expect(find.text('Fresh User 2'), findsOneWidget);
    expect(find.text('Fresh bio 2'), findsOneWidget);
  });

  testWidgets('waits for resolved profile before showing the card', (
    tester,
  ) async {
    const lightweight = UserSummary(
      id: 'u1',
      username: 'logan',
      displayName: '加一',
      avatarUrl: null,
      defaultAvatarKey: 'blue-3',
      isOnline: false,
    );
    final completer = Completer<UserSummary>();
    var calls = 0;
    Future<UserSummary> resolve(UserSummary sender) {
      calls++;
      return completer.future;
    }

    await tester.pumpWidget(
      _host(
        AvatarHoverCardForTest(user: lightweight, onResolveProfile: resolve),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(Avatar).first));
    await tester.pump();

    expect(calls, 1);
    expect(find.text('@logan'), findsNothing);
    expect(find.text('离线'), findsNothing);

    completer.complete(_user);
    await tester.pumpAndSettle();

    expect(find.text('@logan'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('离线'), findsNothing);
  });
}

Future<void> _ensureUserProfileCardOpen(WidgetTester tester) async {
  final marker = find.text('@${_user.username}');
  if (marker.evaluate().isEmpty) {
    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
  }
  expect(marker, findsOneWidget);
  expect(find.byType(ReadOnlySelectableText), findsWidgets);
}

Finder _readOnlyFieldWithText(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is EditableText && widget.controller.text == text,
  );
}

Future<void> _copyReadOnlyField(
  WidgetTester tester,
  String text, {
  int copyStartOffset = 0,
  String? expectedCopy,
  required List<String> clipboardWrites,
}) async {
  final editableFinder = _readOnlyFieldWithText(text);
  final editableValues = find
      .byType(EditableText)
      .evaluate()
      .map((element) => (element.widget as EditableText).controller.text)
      .toList();
  final textFieldValues = find
      .byType(TextField)
      .evaluate()
      .map((element) => (element.widget as TextField).controller?.text)
      .toList();
  final readOnlyCount = find.byType(ReadOnlySelectableText).evaluate().length;
  expect(
    editableFinder,
    findsOneWidget,
    reason:
        'ReadOnlySelectableText count: $readOnlyCount, '
        'TextField values: $textFieldValues, '
        'EditableText values: $editableValues',
  );

  await tester.tap(editableFinder, buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
  final editableTextState = tester.state<EditableTextState>(editableFinder);
  expect(
    editableTextState.textEditingValue.selection,
    TextSelection(baseOffset: copyStartOffset, extentOffset: text.length),
  );
  expect(find.text('Ctrl+C'), findsOneWidget);
  expect(find.text('Ctrl+A'), findsNothing);

  final menuGesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await menuGesture.addPointer(location: tester.getCenter(editableFinder));
  await menuGesture.moveTo(tester.getCenter(find.text('Ctrl+C')));
  await tester.pump(const Duration(milliseconds: 200));
  expect(editableFinder, findsOneWidget);
  await menuGesture.removePointer();

  await tester.tap(find.text('Ctrl+C'));
  await tester.pumpAndSettle();
  expect(clipboardWrites.last, expectedCopy ?? text);
}

void _mockClipboard(List<String> writes) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          writes.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
          return null;
        }
        if (call.method == 'Clipboard.hasStrings') {
          return const <String, dynamic>{'value': false};
        }
        return null;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}
