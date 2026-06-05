import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/audio_device_store.dart';
import 'package:client/src/app/live_session_controller.dart';
import 'package:client/src/live/live_session.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test(
    'connectWithRetry restores audio settings and retries LiveKit connect',
    () async {
      final session = _FakeLiveSession(failFirstConnect: true);
      var restoredDevices = 0;
      final controller = LiveSessionController(
        apiBaseUrl: 'https://api.example.test/api/v1',
        session: session,
        audioDeviceStore: const _FakeAudioDeviceStore(),
        audioDeviceRestorer: (_) async {
          restoredDevices += 1;
        },
      );

      await controller.connectWithRetry(_liveJoinResult);

      expect(session.connectAttempts, 2);
      expect(session.disconnects, 1);
      expect(session.inputVolumes, [0.35, 0.35]);
      expect(session.outputVolumes, [0.75, 0.75]);
      expect(restoredDevices, 2);
      expect(session.connectedUrl, 'wss://live.example.test');
      expect(session.connectedRoomName, 'room_live_1');
      expect(session.connectedMicMuted, isTrue);
    },
  );

  test('disconnect respects timeout when LiveKit teardown hangs', () async {
    final session = _FakeLiveSession(hangDisconnect: true);
    final controller = LiveSessionController(
      apiBaseUrl: 'https://api.example.test/api/v1',
      session: session,
      audioDeviceStore: const _FakeAudioDeviceStore(),
      audioDeviceRestorer: (_) async {},
    );

    await controller.disconnect(timeout: const Duration(milliseconds: 1));

    expect(session.disconnects, 1);
  });

  test('live session callbacks attach through controller boundary', () {
    final session = _FakeLiveSession();
    final controller = LiveSessionController(
      apiBaseUrl: 'https://api.example.test/api/v1',
      session: session,
      audioDeviceStore: const _FakeAudioDeviceStore(),
      audioDeviceRestorer: (_) async {},
    );
    var changes = 0;
    var removals = 0;
    final publishPermissions = <bool>[];
    void onChanged() => changes += 1;

    controller.attachSessionCallbacks(
      onChanged: onChanged,
      onForciblyRemoved: () => removals += 1,
      onPublishPermissionChanged: publishPermissions.add,
    );
    session.emitChange();
    session.onForciblyRemoved?.call();
    session.onPublishPermissionChanged?.call(false);

    expect(changes, 1);
    expect(removals, 1);
    expect(publishPermissions, [false]);

    controller.detachSessionCallbacks(onChanged: onChanged);
    session.emitChange();
    expect(changes, 1);
    expect(session.onForciblyRemoved, isNull);
    expect(session.onPublishPermissionChanged, isNull);
  });

  test('live session media controls proxy through controller', () async {
    final session = _FakeLiveSession();
    final controller = LiveSessionController(
      apiBaseUrl: 'https://api.example.test/api/v1',
      session: session,
      audioDeviceStore: const _FakeAudioDeviceStore(),
      audioDeviceRestorer: (_) async {},
    );

    await controller.setMicMuted(true);
    await controller.setCameraEnabled(true);
    await controller.setScreenShareEnabled(true, sourceId: 'screen_1');
    await controller.setOutputMuted(true);
    await controller.setInputVolume(0.4);
    await controller.setOutputVolume(0.6);

    expect(session.micMutes, [true]);
    expect(session.cameraEnables, [true]);
    expect(session.screenShareEnables, [true]);
    expect(session.screenShareSourceIds, ['screen_1']);
    expect(session.outputMutes, [true]);
    expect(session.inputVolumes, [0.4]);
    expect(session.outputVolumes, [0.6]);
  });
}

class _FakeAudioDeviceStore extends AudioDeviceStore {
  const _FakeAudioDeviceStore();

  @override
  Future<StoredAudioDevices> read() async {
    return const StoredAudioDevices(inputVolume: 0.35, outputVolume: 0.75);
  }
}

class _FakeLiveSession extends LiveSession {
  _FakeLiveSession({
    this.failFirstConnect = false,
    this.hangDisconnect = false,
  });

  final bool failFirstConnect;
  final bool hangDisconnect;
  int connectAttempts = 0;
  int disconnects = 0;
  final inputVolumes = <double>[];
  final outputVolumes = <double>[];
  final outputMutes = <bool>[];
  final micMutes = <bool>[];
  final cameraEnables = <bool>[];
  final screenShareEnables = <bool>[];
  final screenShareSourceIds = <String?>[];
  String? connectedUrl;
  String? connectedRoomName;
  bool? connectedMicMuted;

  void emitChange() => notifyListeners();

  @override
  Future<void> connect({
    required String url,
    required String token,
    required String roomName,
    required bool micMuted,
  }) async {
    connectAttempts += 1;
    if (failFirstConnect && connectAttempts == 1) {
      throw StateError('first connect failed');
    }
    connectedUrl = url;
    connectedRoomName = roomName;
    connectedMicMuted = micMuted;
  }

  @override
  Future<void> disconnect() {
    disconnects += 1;
    if (hangDisconnect) return Completer<void>().future;
    return Future<void>.value();
  }

  @override
  Future<void> setInputVolume(double volume) async {
    inputVolumes.add(volume);
  }

  @override
  Future<void> setOutputVolume(double volume) async {
    outputVolumes.add(volume);
  }

  @override
  Future<void> setOutputMuted(bool muted) async {
    outputMutes.add(muted);
  }

  @override
  Future<void> setMicMuted(bool muted) async {
    micMutes.add(muted);
  }

  @override
  Future<bool> setCameraEnabled(bool enabled) async {
    cameraEnables.add(enabled);
    return enabled;
  }

  @override
  Future<bool> setScreenShareEnabled(bool enabled, {String? sourceId}) async {
    screenShareEnables.add(enabled);
    screenShareSourceIds.add(sourceId);
    return enabled;
  }
}

const _sender = UserSummary(
  id: 'user_1',
  username: 'alice',
  displayName: 'Alice',
  avatarUrl: null,
  defaultAvatarKey: 'blue-3',
);

final _participant = LiveParticipant(
  liveSessionId: 'live_1',
  user: _sender,
  joinedAt: DateTime.utc(2026, 6, 1),
  micMuted: true,
  headphonesMuted: false,
  voiceBlocked: false,
  cameraOn: false,
  screenSharing: false,
  connectionState: 'joined',
);

final _liveJoinResult = LiveJoinResult(
  liveKit: LiveKitConnectionInfo(
    serverUrl: 'wss://live.example.test',
    token: 'token',
    tokenExpiresAt: DateTime.utc(2026, 6, 1, 1),
    roomName: 'room_live_1',
  ),
  participant: _participant,
  live: LiveState(
    roomId: 'room_1',
    participantCount: 1,
    participants: [_participant],
    updatedAt: DateTime.utc(2026, 6, 1),
  ),
);
