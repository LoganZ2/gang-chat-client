import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/live_display.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('liveParticipantByUserId returns matching participant', () {
    final live = _live(['alice', 'bob']);

    expect(liveParticipantByUserId(live, 'bob')?.user.displayName, 'User bob');
    expect(liveParticipantByUserId(live, 'missing'), isNull);
    expect(liveParticipantByUserId(null, 'bob'), isNull);
  });

  test('liveParticipantDisplayName uses fallback for missing live user', () {
    final live = _live(['alice']);

    expect(liveParticipantDisplayName(live, 'alice'), 'User alice');
    expect(liveParticipantDisplayName(live, 'missing'), '');
    expect(
      liveParticipantDisplayName(null, 'missing', fallback: 'Unknown'),
      'Unknown',
    );
  });

  test(
    'pickLiveStageShare prefers remote screen share then local fallback',
    () {
      final localShare = _Track('local', isScreenShare: true, isLocal: true);
      final remoteShare = _Track('remote', isScreenShare: true, isLocal: false);
      final camera = _Track('camera', isScreenShare: false, isLocal: false);

      expect(
        pickLiveStageShare(
          [camera, localShare, remoteShare],
          isScreenShare: (track) => track.isScreenShare,
          isLocal: (track) => track.isLocal,
        ),
        same(remoteShare),
      );
      expect(
        pickLiveStageShare(
          [camera, localShare],
          isScreenShare: (track) => track.isScreenShare,
          isLocal: (track) => track.isLocal,
        ),
        same(localShare),
      );
      expect(
        pickLiveStageShare(
          [camera],
          isScreenShare: (track) => track.isScreenShare,
          isLocal: (track) => track.isLocal,
        ),
        isNull,
      );
    },
  );

  test('stage share label and fullscreen guard are UI independent', () {
    expect(liveScreenShareStageLabel('Alice'), 'Alice 的屏幕');
    expect(liveScreenShareStageLabel(''), '屏幕共享');
    expect(
      canOpenLiveStageShareFullScreen(
        stageShareIdentity: 'alice',
        localUserId: 'bob',
      ),
      isTrue,
    );
    expect(
      canOpenLiveStageShareFullScreen(
        stageShareIdentity: 'alice',
        localUserId: 'alice',
      ),
      isFalse,
    );
  });

  test('live notices and failure messages stay outside UI', () {
    expect(liveForciblyRemovedNotice(), '你已被移出语音');
    expect(liveVoiceConnectFailureMessage('network'), '无法连接语音：network');
    expect(liveCameraOpenFailureMessage('denied'), '无法打开摄像头: denied');
    expect(liveScreenShareFailureMessage('denied'), '无法共享屏幕: denied');
  });

  test('liveScreenShareByIdentity resolves active fullscreen share', () {
    final screenShare = _Track('alice', isScreenShare: true, isLocal: false);
    final camera = _Track('alice', isScreenShare: false, isLocal: false);

    expect(
      liveScreenShareByIdentity(
        [camera, screenShare],
        identity: 'alice',
        trackIdentity: (track) => track.id,
        isScreenShare: (track) => track.isScreenShare,
      ),
      same(screenShare),
    );
    expect(
      liveScreenShareByIdentity(
        [screenShare],
        identity: null,
        trackIdentity: (track) => track.id,
        isScreenShare: (track) => track.isScreenShare,
      ),
      isNull,
    );
    expect(
      liveScreenShareByIdentity(
        [camera],
        identity: 'alice',
        trackIdentity: (track) => track.id,
        isScreenShare: (track) => track.isScreenShare,
      ),
      isNull,
    );
  });

  test('shouldExitMissingFullScreenShare exits only missing tracked share', () {
    final share = Object();

    expect(
      shouldExitMissingFullScreenShare(
        fullScreenShareIdentity: 'alice',
        fullScreenShare: null,
      ),
      isTrue,
    );
    expect(
      shouldExitMissingFullScreenShare(
        fullScreenShareIdentity: 'alice',
        fullScreenShare: share,
      ),
      isFalse,
    );
    expect(
      shouldExitMissingFullScreenShare(
        fullScreenShareIdentity: null,
        fullScreenShare: null,
      ),
      isFalse,
    );
  });

  test('ended local screen share patch gate follows joined selected room', () {
    expect(
      shouldPatchEndedLocalScreenShare(
        localScreenSharing: true,
        sessionScreenSharing: false,
        joinedLiveRoomId: 'room_1',
        selectedRoomId: 'room_1',
      ),
      isTrue,
    );
    expect(
      shouldPatchEndedLocalScreenShare(
        localScreenSharing: false,
        sessionScreenSharing: false,
        joinedLiveRoomId: 'room_1',
        selectedRoomId: 'room_1',
      ),
      isFalse,
    );
    expect(
      shouldPatchEndedLocalScreenShare(
        localScreenSharing: true,
        sessionScreenSharing: true,
        joinedLiveRoomId: 'room_1',
        selectedRoomId: 'room_1',
      ),
      isFalse,
    );
    expect(
      shouldPatchEndedLocalScreenShare(
        localScreenSharing: true,
        sessionScreenSharing: false,
        joinedLiveRoomId: 'room_2',
        selectedRoomId: 'room_1',
      ),
      isFalse,
    );
    expect(
      shouldPatchEndedLocalScreenShare(
        localScreenSharing: true,
        sessionScreenSharing: false,
        joinedLiveRoomId: null,
        selectedRoomId: 'room_1',
      ),
      isFalse,
    );
  });

  test(
    'screen source selection keeps existing source or falls back to first',
    () {
      final screen = _Track('screen', isScreenShare: true, isLocal: true);
      final window = _Track('window', isScreenShare: true, isLocal: true);

      expect(
        reconcileLiveScreenSourceSelection(
          [screen, window],
          selectedId: 'window',
          sourceId: (source) => source.id,
        ),
        'window',
      );
      expect(
        reconcileLiveScreenSourceSelection(
          [screen, window],
          selectedId: 'missing',
          sourceId: (source) => source.id,
        ),
        'screen',
      );
      expect(
        reconcileLiveScreenSourceSelection(
          <_Track>[],
          selectedId: 'missing',
          sourceId: (source) => source.id,
        ),
        isNull,
      );
    },
  );

  test('screen source lookup and confirmation require a selected id', () {
    final screen = _Track('screen', isScreenShare: true, isLocal: true);

    expect(
      liveScreenSourceById(
        [screen],
        selectedId: 'screen',
        sourceId: (source) => source.id,
      ),
      same(screen),
    );
    expect(
      liveScreenSourceById(
        [screen],
        selectedId: 'missing',
        sourceId: (source) => source.id,
      ),
      isNull,
    );
    expect(
      liveScreenSourceById<_Track>(
        null,
        selectedId: 'screen',
        sourceId: (source) => source.id,
      ),
      isNull,
    );
    expect(canConfirmLiveScreenSourceSelection('screen'), isTrue);
    expect(canConfirmLiveScreenSourceSelection(null), isFalse);
  });

  test('screen source picker state tracks loading selection and failures', () {
    final screen = _Track('screen', isScreenShare: true, isLocal: true);
    final window = _Track('window', isScreenShare: true, isLocal: true);
    const initial = LiveScreenSourcePickerState<_Track>();

    expect(canLoadLiveScreenSources(initial), isTrue);

    final started = liveScreenSourceLoadStarted(initial);

    expect(started.loading, isTrue);
    expect(started.error, isNull);
    expect(canLoadLiveScreenSources(started), isFalse);

    final loaded = liveScreenSourceLoadSucceeded(
      state: started,
      sources: [screen, window],
      sourceId: (source) => source.id,
    );

    expect(loaded.loading, isFalse);
    expect(loaded.sources, [screen, window]);
    expect(loaded.selectedId, 'screen');
    expect(loaded.error, isNull);

    final selected = liveScreenSourceSelectedChanged(loaded, 'window');

    expect(selected.selectedId, 'window');

    final reloaded = liveScreenSourceLoadSucceeded(
      state: selected,
      sources: [screen, window],
      sourceId: (source) => source.id,
    );

    expect(reloaded.selectedId, 'window');

    final failed = liveScreenSourceLoadFailed(
      state: liveScreenSourceLoadStarted(reloaded),
      failure: StateError('sources failed'),
    );

    expect(failed.loading, isFalse);
    expect(failed.sources, [screen, window]);
    expect(failed.selectedId, 'window');
    expect(failed.error, 'Bad state: sources failed');
  });

  test(
    'screen source list helpers expose body selected and thumbnail states',
    () {
      final screen = _Track('screen', isScreenShare: true, isLocal: true);

      expect(
        liveScreenSourceListBodyState<_Track>(null),
        LiveScreenSourceListBodyState.loading,
      );
      expect(
        liveScreenSourceListBodyState(<_Track>[]),
        LiveScreenSourceListBodyState.empty,
      );
      expect(
        liveScreenSourceListBodyState([screen]),
        LiveScreenSourceListBodyState.results,
      );

      expect(
        liveScreenSourceSelected(
          screen,
          selectedId: 'screen',
          sourceId: (source) => source.id,
        ),
        isTrue,
      );
      expect(
        liveScreenSourceSelected(
          screen,
          selectedId: 'window',
          sourceId: (source) => source.id,
        ),
        isFalse,
      );

      expect(
        visibleLiveScreenSourceThumbnail(
          thumbnail: const [1, 2],
          imageError: null,
        ),
        [1, 2],
      );
      expect(
        visibleLiveScreenSourceThumbnail(
          thumbnail: const <int>[],
          imageError: null,
        ),
        isNull,
      );
      expect(
        visibleLiveScreenSourceThumbnail(
          thumbnail: const [1],
          imageError: Object(),
        ),
        isNull,
      );
    },
  );

  test(
    'liveParticipantTileState highlights speaking or broadcasting users',
    () {
      final idle = liveParticipantTileState(
        _participant('alice'),
        speaking: false,
      );
      expect(idle.broadcasting, isFalse);
      expect(idle.highlighted, isFalse);
      expect(idle.micMutedForDisplay, isFalse);
      expect(idle.micActive, isFalse);

      final speaking = liveParticipantTileState(
        _participant('alice'),
        speaking: true,
      );
      expect(speaking.highlighted, isTrue);
      expect(speaking.micActive, isTrue);

      final broadcasting = liveParticipantTileState(
        _participant('alice', cameraOn: true),
        speaking: false,
      );
      expect(broadcasting.broadcasting, isTrue);
      expect(broadcasting.highlighted, isTrue);
      expect(broadcasting.micActive, isFalse);
    },
  );

  test(
    'liveParticipantTileState treats voice-blocked users as force-muted',
    () {
      final state = liveParticipantTileState(
        _participant('alice', voiceBlocked: true),
        speaking: true,
      );

      expect(state.micMutedForDisplay, isTrue);
      expect(state.micActive, isFalse);
      expect(state.highlighted, isTrue);
    },
  );

  test('live control display helpers describe toggled states', () {
    final mutedMic = liveMicControlState(micMuted: true, voiceBlocked: false);
    expect(mutedMic.tooltip, '取消静音');
    expect(mutedMic.mutedForDisplay, isTrue);
    expect(mutedMic.active, isFalse);
    expect(mutedMic.enabled, isTrue);

    final liveMic = liveMicControlState(micMuted: false, voiceBlocked: false);
    expect(liveMic.tooltip, '静音');
    expect(liveMic.mutedForDisplay, isFalse);
    expect(liveMic.active, isTrue);
    expect(liveMic.enabled, isTrue);

    final blockedMic = liveMicControlState(micMuted: false, voiceBlocked: true);
    expect(blockedMic.tooltip, '已被管理员禁言');
    expect(blockedMic.mutedForDisplay, isTrue);
    expect(blockedMic.active, isFalse);
    expect(blockedMic.enabled, isFalse);

    expect(liveHeadphonesControlTooltip(true), '取消耳机静音');
    expect(liveHeadphonesControlTooltip(false), '耳机静音');
    expect(liveCameraControlTooltip(true), '关闭摄像头');
    expect(liveCameraControlTooltip(false), '开启摄像头');
    expect(liveScreenShareControlTooltip(true), '停止共享屏幕');
    expect(liveScreenShareControlTooltip(false), '共享屏幕');
  });
}

LiveState _live(List<String> userIds) {
  return LiveState(
    roomId: 'room_1',
    participantCount: userIds.length,
    participants: [for (final id in userIds) _participant(id, micMuted: true)],
    updatedAt: DateTime.utc(2026, 6, 5),
  );
}

LiveParticipant _participant(
  String id, {
  bool micMuted = false,
  bool voiceBlocked = false,
  bool cameraOn = false,
  bool screenSharing = false,
}) {
  return LiveParticipant(
    liveSessionId: 'live_$id',
    user: UserSummary(
      id: id,
      username: 'user_$id',
      displayName: 'User $id',
      avatarUrl: null,
      defaultAvatarKey: 'blue-3',
    ),
    joinedAt: DateTime.utc(2026, 6, 5),
    micMuted: micMuted,
    headphonesMuted: false,
    voiceBlocked: voiceBlocked,
    cameraOn: cameraOn,
    screenSharing: screenSharing,
    connectionState: 'connected',
  );
}

class _Track {
  const _Track(this.id, {required this.isScreenShare, required this.isLocal});

  final String id;
  final bool isScreenShare;
  final bool isLocal;
}
