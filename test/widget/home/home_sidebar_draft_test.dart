import 'package:client/src/home/home_sidebar.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'room draft replaces subtitle without replacing last message time',
    (tester) async {
      final lastMessageAt = DateTime.now();
      final expectedTime =
          '${lastMessageAt.hour.toString().padLeft(2, '0')}:'
          '${lastMessageAt.minute.toString().padLeft(2, '0')}';
      final room = RoomCard(
        id: 'room_1',
        name: 'Draft room',
        avatarUrl: null,
        defaultAvatarKey: 'room-1',
        memberCount: 2,
        liveParticipantCount: 0,
        liveAvatarPreview: const [],
        lastMessage: LastMessagePreview(
          id: 'message_1',
          senderDisplayName: 'Logan',
          bodyPreview: 'latest message',
          createdAt: lastMessageAt,
        ),
        unreadCount: 0,
        updatedAt: lastMessageAt,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 180,
              child: HomeSidebar(
                width: 320,
                currentUser: _currentUser,
                servers: [room],
                timestampNow: lastMessageAt,
                roomDrafts: const {'room_1': 'draft\ncontent'},
                selectedServerId: null,
                joinedLiveRoomId: null,
                realtimeReconnecting: false,
                searchQuery: '',
                loading: false,
                error: null,
                settingsActive: false,
                createRoomActive: false,
                notificationsActive: false,
                logoutActive: false,
                hasPendingNotifications: false,
                pendingNotificationCount: 0,
                includeWindowChromeOffset: false,
                onServerSelected: (_) {},
                onCreateRoom: () {},
                onOpenNotifications: () {},
                onOpenSettings: () {},
                onLogout: () {},
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('home-sidebar-room-draft-room_1')),
        findsOneWidget,
      );
      expect(find.textContaining('[草稿] draft content'), findsOneWidget);
      expect(find.textContaining('latest message'), findsNothing);
      expect(find.text(expectedTime), findsOneWidget);
    },
  );

  testWidgets('user summary overlays the latest request latency signal', (
    tester,
  ) async {
    await _pumpLatencySidebar(tester);

    expect(find.byKey(const ValueKey('latency-signal-badge')), findsOneWidget);
    expect(_latencyBarColor(tester, 1), const Color(0xFF26B36F));

    await tester.tap(find.byKey(const ValueKey('latency-signal-badge')));
    await tester.pump();

    expect(find.text('96 ms'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('96 ms'), findsNothing);
  });

  testWidgets('latency card hover can be pinned until an outside tap', (
    tester,
  ) async {
    await _pumpLatencySidebar(tester);

    final badge = find.byKey(const ValueKey('latency-signal-badge'));
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: Offset.zero);
    addTearDown(hover.removePointer);
    await hover.moveTo(tester.getCenter(badge));
    await tester.pumpAndSettle();

    expect(find.text('96 ms'), findsOneWidget);

    await tester.tap(badge, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await hover.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('96 ms'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('96 ms'), findsNothing);
  });
}

Future<void> _pumpLatencySidebar(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ui.uiTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 120,
          child: HomeSidebar(
            width: 320,
            currentUser: _currentUser,
            servers: const [],
            timestampNow: DateTime.utc(2026, 7, 8, 9),
            selectedServerId: null,
            joinedLiveRoomId: null,
            realtimeReconnecting: false,
            requestRoundTrip: const Duration(milliseconds: 96),
            searchQuery: '',
            loading: false,
            error: null,
            settingsActive: false,
            createRoomActive: false,
            notificationsActive: false,
            logoutActive: false,
            hasPendingNotifications: false,
            pendingNotificationCount: 0,
            includeWindowChromeOffset: false,
            onServerSelected: (_) {},
            onCreateRoom: () {},
            onOpenNotifications: () {},
            onOpenSettings: () {},
            onLogout: () {},
          ),
        ),
      ),
    ),
  );
}

Color? _latencyBarColor(WidgetTester tester, int index) {
  final bar = tester.widget<DecoratedBox>(
    find.byKey(ValueKey('latency-signal-bar-$index')),
  );
  return (bar.decoration as BoxDecoration).color;
}

final _currentUser = CurrentUser(
  id: 'user_1',
  uid: '10000001',
  username: 'logan',
  displayName: 'Logan',
  bio: '',
  gender: 'secret',
  email: null,
  emailPublic: false,
  phoneNumber: null,
  phoneNumberPublic: false,
  avatarUrl: null,
  defaultAvatarKey: 'blue-3',
  isSuperuser: false,
  createdAt: DateTime.utc(2026, 6, 4),
);
