import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/ui.dart';
import 'package:client/src/home/chat_pane.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _user = UserSummary(
  id: 'u1',
  username: 'logan',
  displayName: '加一',
  avatarUrl: null,
  defaultAvatarKey: 'blue-3',
  bio: '随便写点什么',
  gender: 'male',
  roomRole: 'admin',
  isOnline: true,
  commonRooms: [
    UserCommonRoom(id: 'r1', rid: 'R1', name: '摸鱼大队'),
    UserCommonRoom(id: 'r2', rid: 'R2', name: '技术交流'),
  ],
);

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: child),
    ),
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
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('管理员'), findsOneWidget);
    expect(find.text('男'), findsOneWidget);
    expect(find.text('随便写点什么'), findsOneWidget);
    expect(find.text('2 个共同房间'), findsOneWidget);
    expect(find.text('摸鱼大队'), findsOneWidget);
    expect(find.text('技术交流'), findsOneWidget);

    // Card disappears when the pointer leaves the avatar.
    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('@logan'), findsNothing);
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

  testWidgets('lazily resolves gender and common rooms on first hover', (
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
    expect(find.text('男'), findsOneWidget);
    expect(find.text('2 个共同房间'), findsOneWidget);
    expect(find.text('摸鱼大队'), findsOneWidget);
  });
}
