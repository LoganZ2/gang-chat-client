import 'package:client/src/home/home_sidebar.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/ui.dart' as ui;
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
