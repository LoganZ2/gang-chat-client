import 'dart:ui' show PointerDeviceKind;

import 'package:client/src/config/app_config.dart';
import 'package:client/src/home/live_channel_pane.dart';
import 'package:client/src/live/live_session.dart';
import 'package:client/src/live/live_video_track_view.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/app_config_scope.dart';
import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

void main() {
  testWidgets('empty live channel uses Chinese empty copy without header tag', (
    tester,
  ) async {
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);

    await tester.pumpWidget(
      _host(searchController: searchController, live: _liveState(const [])),
    );

    expect(find.text('语音频道里还没有人'), findsOneWidget);
    expect(find.text('No one is in live channel'), findsNothing);
    expect(find.text('Live Channel'), findsNothing);
  });

  testWidgets(
    'current user live member card is square and shows connected statuses',
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

      await tester.pumpWidget(
        _host(
          searchController: searchController,
          live: live,
          speakingUserIds: const {'current_user'},
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
      final card = tester.widget<ui.PressableSurface>(cardFinder);
      final cardRect = tester.getRect(cardFinder);
      final avatarRect = tester.getRect(find.byWidget(avatar));
      final name = tester.widget<Text>(find.text('Room Me'));
      final nameRect = tester.getRect(find.text('Room Me'));
      final activityTag = find.byKey(
        const ValueKey<String>('live-member-activity:current_user'),
      );
      final activeTagRect = tester.getRect(activityTag);
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
      final cameraButtonFinder = find.byKey(
        const ValueKey<String>('live-member-status:camera:current_user'),
      );
      final shareButtonFinder = find.byKey(
        const ValueKey<String>('live-member-status:screen-share:current_user'),
      );

      expect(avatar.active, isFalse);
      expect(avatar.showBorder, isFalse);
      expect(card.height, closeTo(cardRect.width, 0.01));
      expect(avatarRect.center.dx, closeTo(cardRect.center.dx, 1));
      expect(name.textAlign, TextAlign.center);
      expect(name.style?.color, ui.UiColors.accent);
      expect(nameRect.top, greaterThan(avatarRect.bottom));
      expect(find.textContaining('(you)'), findsNothing);
      expect(find.text('正在说话'), findsNothing);
      expect(activityTag, findsOneWidget);
      expect(
        find.descendant(of: activityTag, matching: find.byIcon(Icons.mic)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: activityTag, matching: find.byType(DecoratedBox)),
        findsNothing,
      );
      expect(activeTagRect.right, lessThanOrEqualTo(cardRect.right));
      expect(activeTagRect.top, lessThan(nameRect.top));
      expect(activeTagRect.bottom, lessThan(avatarRect.top));
      expect(cardRect.bottom - headphonesButtonRect.bottom, lessThan(14));
      expect(micButtonRect.width, closeTo(micButtonRect.height, 0.01));
      expect(
        headphonesButtonRect.width,
        closeTo(headphonesButtonRect.height, 0.01),
      );
      expect(micButtonRect.right, closeTo(headphonesButtonRect.left, 0.01));
      expect(cameraButtonFinder, findsNothing);
      expect(shareButtonFinder, findsNothing);
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
    },
  );

  testWidgets('remote live member cards use participant avatar preset', (
    tester,
  ) async {
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);
    final remoteUser = _user(
      'phabe',
      'Phabe',
      roomRole: 'member',
    ).copyWith(defaultAvatarKey: 'green-2');
    final live = _liveState([
      _participant(id: 'live_phabe', user: remoteUser, micMuted: true),
    ]);

    await tester.pumpWidget(
      _host(searchController: searchController, live: live, height: 600),
    );

    final avatar = tester.widget<ui.Avatar>(
      find.byWidgetPredicate(
        (widget) =>
            widget is ui.Avatar && widget.label == 'Phabe' && widget.size == 42,
      ),
    );

    expect(avatar.defaultAvatarKey, 'green-2');
    final activityTag = find.byKey(
      const ValueKey<String>('live-member-activity:phabe'),
    );
    expect(find.text('正在收听'), findsNothing);
    expect(find.text('已静音'), findsNothing);
    expect(activityTag, findsNothing);
    expect(find.byTooltip('正在收听'), findsWidgets);
  });

  testWidgets(
    'live member media cards show top-left name and keep status controls',
    (tester) async {
      final searchController = TextEditingController();
      addTearDown(searchController.dispose);
      liveVideoTrackRendererForTest = (track, fit, mirrorLocal) {
        return ColoredBox(
          key: ValueKey<String>(
            'live-video-renderer:${track.identity}:${track.isScreenShare}',
          ),
          color: Colors.black,
        );
      };
      addTearDown(resetLiveVideoTrackRendererForTest);
      var stageSelections = 0;

      Future<void> pumpMediaCard({required bool screenShare}) async {
        final user = _currentUser.toSummary().copyWith(
          roomDisplayName: 'Room Me',
          roomRole: 'member',
        );
        final live = _liveState([
          _participant(
            id: 'live_self',
            user: user,
            cameraOn: !screenShare,
            screenSharing: screenShare,
          ),
        ]);

        await tester.pumpWidget(
          _host(
            searchController: searchController,
            live: live,
            videoTracks: [
              _liveVideoTrack(
                identity: 'current_user',
                isScreenShare: screenShare,
                isLocal: true,
              ),
            ],
            onStageSelectionChanged: (_) => stageSelections += 1,
          ),
        );
        await tester.pump();
      }

      await pumpMediaCard(screenShare: false);
      _expectMediaMemberCard(tester, activityIcon: Icons.videocam);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('live-video-renderer:current_user:false'),
        ),
      );
      expect(stageSelections, 1);

      await pumpMediaCard(screenShare: true);
      _expectMediaMemberCard(tester, activityIcon: Icons.screen_share_outlined);
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

  testWidgets('live buttons show hover info below their targets', (
    tester,
  ) async {
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);
    final live = _liveState([
      _participant(
        id: 'live_self',
        user: _currentUser.toSummary().copyWith(
          roomDisplayName: 'Room Me',
          roomRole: 'member',
        ),
      ),
    ]);

    await tester.pumpWidget(
      _host(searchController: searchController, live: live),
    );

    _expectBelowTooltip(tester, '关闭麦克风');
    _expectBelowTooltip(tester, '关闭耳机');
    _expectBelowTooltip(tester, '开启摄像头');

    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final cameraControl = find.byKey(
      const ValueKey<String>('live-control:camera'),
    );
    await hover.addPointer(location: tester.getCenter(cameraControl));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final cameraInfoText = find.text('开启摄像头');
    expect(cameraInfoText, findsOneWidget);
    expect(
      tester.getRect(cameraInfoText).top,
      greaterThan(tester.getRect(cameraControl).bottom),
    );

    await hover.removePointer();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

void _expectBelowTooltip(WidgetTester tester, String message) {
  expect(find.byTooltip(message), findsOneWidget);
  final tooltip = find.byWidgetPredicate(
    (widget) => widget is Tooltip && widget.message == message,
  );
  expect(tooltip, findsOneWidget);
  expect(tester.widget<Tooltip>(tooltip).preferBelow, isTrue);
  expect(tester.widget<Tooltip>(tooltip).verticalOffset, 24);
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
  ValueChanged<LiveStageSelection?>? onStageSelectionChanged,
  List<LiveVideoTrack> videoTracks = const [],
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
            videoTracks: videoTracks,
            stageSelection: const LiveStageSelection.none(),
            onStageSelectionChanged: onStageSelectionChanged ?? (_) {},
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

void _expectMediaMemberCard(
  WidgetTester tester, {
  required IconData activityIcon,
}) {
  final cardFinder = find.ancestor(
    of: find.text('Room Me'),
    matching: find.byType(ui.PressableSurface),
  );
  final card = tester.widget<ui.PressableSurface>(cardFinder);
  final cardRect = tester.getRect(cardFinder);
  final micButtonRect = tester.getRect(
    find.byKey(const ValueKey<String>('live-member-status:mic:current_user')),
  );
  final headphonesButtonRect = tester.getRect(
    find.byKey(
      const ValueKey<String>('live-member-status:headphones:current_user'),
    ),
  );
  final cameraButtonFinder = find.byKey(
    const ValueKey<String>('live-member-status:camera:current_user'),
  );
  final shareButtonFinder = find.byKey(
    const ValueKey<String>('live-member-status:screen-share:current_user'),
  );
  final nameFinder = find.descendant(
    of: cardFinder,
    matching: find.text('Room Me'),
  );
  final nameRect = tester.getRect(nameFinder);
  final activityTag = find.descendant(
    of: cardFinder,
    matching: find.byKey(
      const ValueKey<String>('live-member-activity:current_user'),
    ),
  );
  final tagRect = tester.getRect(activityTag);
  final videoRect = tester.getRect(
    find.descendant(of: cardFinder, matching: find.byType(LiveVideoTrackView)),
  );

  expect(card.height, closeTo(cardRect.width, 0.01));
  expect(
    find.descendant(of: cardFinder, matching: find.byType(LiveVideoTrackView)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: cardFinder, matching: find.byType(ui.Avatar)),
    findsNothing,
  );
  expect(nameFinder, findsOneWidget);
  expect(activityTag, findsOneWidget);
  expect(
    find.descendant(of: activityTag, matching: find.byIcon(activityIcon)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: activityTag, matching: find.byType(DecoratedBox)),
    findsNothing,
  );
  expect(cameraButtonFinder, findsNothing);
  expect(shareButtonFinder, findsNothing);
  expect(nameRect.left, lessThan(tagRect.left));
  expect(nameRect.top, lessThan(videoRect.top));
  expect(nameRect.bottom, lessThan(micButtonRect.top));
  expect(tagRect.top, lessThan(micButtonRect.top));
  expect(tagRect.right, lessThanOrEqualTo(cardRect.right));
  expect(micButtonRect.right, closeTo(headphonesButtonRect.left, 0.01));
  expect(cardRect.bottom - headphonesButtonRect.bottom, lessThan(14));
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

LiveVideoTrack _liveVideoTrack({
  required String identity,
  required bool isScreenShare,
  required bool isLocal,
}) {
  return LiveVideoTrack(
    identity: identity,
    track: _FakeVideoTrack(),
    isScreenShare: isScreenShare,
    isLocal: isLocal,
  );
}

class _FakeVideoTrack implements lk.VideoTrack {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
