import 'package:client/src/config/app_config.dart';
import 'package:client/src/home/live_channel_pane.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/app_config_scope.dart';
import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'current user live member card centers identity and shows flat statuses',
    (tester) async {
      final searchController = TextEditingController();
      addTearDown(searchController.dispose);
      final user = _currentUser.toSummary().copyWith(
        roomDisplayName: 'Room Me',
        roomRole: 'member',
      );
      final live = _liveState([
        _participant(id: 'live_self', user: user, headphonesMuted: true),
      ]);
      var shareToggles = 0;

      await tester.pumpWidget(
        _host(
          searchController: searchController,
          live: live,
          speakingUserIds: const {'current_user'},
          onToggleShare: () => shareToggles += 1,
        ),
      );

      final avatar = tester.widget<ui.Avatar>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ui.Avatar &&
              widget.label == 'Room Me' &&
              widget.size == 42,
        ),
      );
      final cardFinder = find.ancestor(
        of: find.text('Room Me'),
        matching: find.byType(ui.PressableSurface),
      );
      final cardRect = tester.getRect(cardFinder);
      final avatarRect = tester.getRect(find.byWidget(avatar));
      final name = tester.widget<Text>(find.text('Room Me'));
      final nameRect = tester.getRect(find.text('Room Me'));
      final activeLabelRect = tester.getRect(find.text('正在说话'));
      final micButtonRect = tester.getRect(
        find.byKey(
          const ValueKey<String>('live-member-status:mic:current_user'),
        ),
      );
      final headphonesButtonRect = tester.getRect(
        find.byKey(
          const ValueKey<String>('live-member-status:headphones:current_user'),
        ),
      );
      final cameraButtonRect = tester.getRect(
        find.byKey(
          const ValueKey<String>('live-member-status:camera:current_user'),
        ),
      );
      final shareButtonFinder = find.byKey(
        const ValueKey<String>('live-member-status:screen-share:current_user'),
      );
      final shareButtonRect = tester.getRect(shareButtonFinder);

      expect(avatar.active, isFalse);
      expect(avatar.showBorder, isFalse);
      expect(avatarRect.center.dx, closeTo(cardRect.center.dx, 1));
      expect(name.textAlign, TextAlign.center);
      expect(name.style?.color, ui.UiColors.accent);
      expect(nameRect.top, greaterThan(avatarRect.bottom));
      expect(find.textContaining('(you)'), findsNothing);
      expect(activeLabelRect.right, lessThanOrEqualTo(cardRect.right));
      expect(activeLabelRect.top, lessThan(nameRect.top));
      expect(activeLabelRect.bottom, lessThan(avatarRect.top));
      expect(cardRect.bottom - shareButtonRect.bottom, lessThan(14));
      expect(micButtonRect.width, closeTo(micButtonRect.height, 0.01));
      expect(
        headphonesButtonRect.width,
        closeTo(headphonesButtonRect.height, 0.01),
      );
      expect(cameraButtonRect.width, closeTo(cameraButtonRect.height, 0.01));
      expect(shareButtonRect.width, closeTo(shareButtonRect.height, 0.01));
      expect(micButtonRect.right, closeTo(headphonesButtonRect.left, 0.01));
      expect(headphonesButtonRect.right, closeTo(cameraButtonRect.left, 0.01));
      expect(cameraButtonRect.right, closeTo(shareButtonRect.left, 0.01));
      expect(
        find.descendant(of: cardFinder, matching: find.byType(ui.ButtonIcon)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('live-member-status:mic:current_user'),
          ),
          matching: find.byIcon(Icons.mic),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>(
              'live-member-status:headphones:current_user',
            ),
          ),
          matching: find.byIcon(Icons.headset_off),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('live-member-status:camera:current_user'),
          ),
          matching: find.byIcon(Icons.videocam_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>(
              'live-member-status:screen-share:current_user',
            ),
          ),
          matching: find.byIcon(Icons.screen_share_outlined),
        ),
        findsOneWidget,
      );
      await tester.tap(shareButtonFinder);
      expect(shareToggles, 1);
    },
  );

  testWidgets('live member names use self and room role colors', (
    tester,
  ) async {
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);
    final live = _liveState([
      _participant(
        id: 'live_self',
        user: _currentUser.toSummary().copyWith(
          roomDisplayName: 'Room Self',
          roomRole: 'member',
        ),
      ),
      _participant(
        id: 'live_member',
        user: _user('member', 'Room Member', roomRole: 'member'),
      ),
      _participant(
        id: 'live_admin',
        user: _user('admin', 'Room Admin', roomRole: 'admin'),
      ),
      _participant(
        id: 'live_owner',
        user: _user('owner', 'Room Owner', roomRole: 'owner'),
      ),
      _participant(
        id: 'live_superuser',
        user: _user(
          'superuser',
          'Room Root',
          roomRole: 'member',
          isSuperuser: true,
        ),
      ),
    ]);

    await tester.pumpWidget(
      _host(searchController: searchController, live: live, height: 620),
    );

    expect(
      tester.widget<Text>(find.text('Room Self')).style?.color,
      ui.UiColors.accent,
    );
    expect(
      tester.widget<Text>(find.text('Room Member')).style?.color,
      ui.UiColors.roleMember,
    );
    expect(
      tester.widget<Text>(find.text('Room Admin')).style?.color,
      ui.UiColors.roleAdmin,
    );
    expect(
      tester.widget<Text>(find.text('Room Owner')).style?.color,
      ui.UiColors.roleCreator,
    );
    expect(
      tester.widget<Text>(find.text('Room Root')).style?.color,
      ui.UiColors.roleSuperuser,
    );
  });
}

const _currentUser = CurrentUser(
  id: 'current_user',
  uid: '1000000',
  username: 'me',
  displayName: 'Me',
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

Widget _host({
  required TextEditingController searchController,
  required LiveState live,
  Set<String> speakingUserIds = const {},
  double width = 720,
  double height = 520,
  VoidCallback? onToggleMic,
  VoidCallback? onToggleHeadphones,
  VoidCallback? onToggleCamera,
  VoidCallback? onToggleShare,
}) {
  return MaterialApp(
    theme: ui.uiTheme(),
    home: AppConfigScope(
      config: const AppConfig(
        apiBaseUrl: 'https://api.test/api/v1',
        assetBaseUrl: 'https://assets.test',
      ),
      child: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: LiveChannelPane(
            title: 'Test room',
            avatarUrl: null,
            live: live,
            currentUser: _currentUser,
            loading: false,
            joined: true,
            joining: false,
            micMuted: false,
            headphonesMuted: false,
            voiceBlocked: false,
            cameraOn: false,
            screenSharing: false,
            speakingUserIds: speakingUserIds,
            videoTracks: const [],
            stageSelection: const LiveStageSelection.none(),
            onStageSelectionChanged: (_) {},
            onEnterFullScreen: (_) {},
            onBackToChat: () {},
            onJoin: () {},
            onLeave: () {},
            onToggleMic: onToggleMic ?? () {},
            onToggleHeadphones: onToggleHeadphones ?? () {},
            onToggleCamera: onToggleCamera ?? () {},
            onToggleShare: onToggleShare ?? () {},
            musicBox: null,
            musicBoxOpen: false,
            musicBoxSearchController: searchController,
            musicBoxSearchResults: const [],
            musicBoxSearching: false,
            musicBoxSearchError: null,
            musicBoxSource: 'netease',
            onToggleMusicBox: () {},
            onMusicBoxTogglePlayback: () {},
            onMusicBoxSkip: () {},
            onMusicBoxQueueResult: (_) {},
            onMusicBoxRemoveItem: (_) {},
            onMusicBoxSourceChanged: (_) {},
            inputVolume: 1,
            outputVolume: 1,
            musicBoxVolume: 1,
            screenShareVolume: 1,
            onInputVolumeChanged: (_) {},
            onOutputVolumeChanged: (_) {},
            onMusicBoxVolumeChanged: (_) {},
            onScreenShareVolumeChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}

LiveState _liveState(List<LiveParticipant> participants) {
  return LiveState(
    roomId: 'room_1',
    participantCount: participants.length,
    participants: participants,
    updatedAt: DateTime.utc(2026, 6, 11, 9),
  );
}

LiveParticipant _participant({
  required String id,
  required UserSummary user,
  bool micMuted = false,
  bool headphonesMuted = false,
  bool cameraOn = false,
  bool screenSharing = false,
}) {
  return LiveParticipant(
    liveSessionId: id,
    user: user,
    joinedAt: DateTime.utc(2026, 6, 11, 9),
    micMuted: micMuted,
    headphonesMuted: headphonesMuted,
    voiceBlocked: false,
    cameraOn: cameraOn,
    screenSharing: screenSharing,
    connectionState: 'connected',
  );
}

UserSummary _user(
  String id,
  String name, {
  required String roomRole,
  bool isSuperuser = false,
}) {
  return UserSummary(
    id: id,
    username: id,
    displayName: name,
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    roomDisplayName: name,
    roomRole: roomRole,
    isSuperuser: isSuperuser,
  );
}
