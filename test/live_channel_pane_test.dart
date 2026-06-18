import 'package:client/src/config/app_config.dart';
import 'package:client/src/home/live_channel_pane.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/app_config_scope.dart';
import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'current user live member avatar stays borderless while speaking',
    (tester) async {
      final searchController = TextEditingController();
      addTearDown(searchController.dispose);
      const currentUser = CurrentUser(
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
      final live = LiveState(
        roomId: 'room_1',
        participantCount: 1,
        participants: [
          LiveParticipant(
            liveSessionId: 'live_self',
            user: currentUser.toSummary(),
            joinedAt: DateTime.utc(2026, 6, 11, 9),
            micMuted: false,
            headphonesMuted: false,
            voiceBlocked: false,
            cameraOn: false,
            screenSharing: false,
            connectionState: 'connected',
          ),
        ],
        updatedAt: DateTime.utc(2026, 6, 11, 9),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: AppConfigScope(
            config: const AppConfig(
              apiBaseUrl: 'https://api.test/api/v1',
              assetBaseUrl: 'https://assets.test',
            ),
            child: Scaffold(
              body: SizedBox(
                width: 720,
                height: 520,
                child: LiveChannelPane(
                  title: 'Test room',
                  avatarUrl: null,
                  live: live,
                  currentUser: currentUser,
                  loading: false,
                  joined: true,
                  joining: false,
                  micMuted: false,
                  headphonesMuted: false,
                  voiceBlocked: false,
                  cameraOn: false,
                  screenSharing: false,
                  speakingUserIds: const {'current_user'},
                  videoTracks: const [],
                  stageSelection: const LiveStageSelection.none(),
                  onStageSelectionChanged: (_) {},
                  onEnterFullScreen: (_) {},
                  onBackToChat: () {},
                  onJoin: () {},
                  onLeave: () {},
                  onToggleMic: () {},
                  onToggleHeadphones: () {},
                  onToggleCamera: () {},
                  onToggleShare: () {},
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
        ),
      );

      final avatar = tester.widget<ui.Avatar>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ui.Avatar &&
              widget.label == currentUser.displayName &&
              widget.size == 42,
        ),
      );
      expect(avatar.active, isFalse);
      expect(avatar.showBorder, isFalse);
    },
  );
}
