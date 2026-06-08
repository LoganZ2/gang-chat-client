import 'dart:async';

import '../live/live_session.dart';
import '../live/audio_device_restorer.dart';
import '../live/livekit_url.dart';
import '../protocol/models.dart';
import 'audio_device_store.dart';

typedef AudioDeviceRestorer = Future<void> Function(AudioDeviceStore store);

class LiveSessionController {
  LiveSessionController({
    required this.apiBaseUrl,
    required this.audioDeviceStore,
    LiveSession? session,
    AudioDeviceRestorer? audioDeviceRestorer,
  }) : session = session ?? LiveSession(),
       _audioDeviceRestorer =
           audioDeviceRestorer ??
           ((store) async {
             await restoreStoredAudioDevices(store);
           });

  final String apiBaseUrl;
  final AudioDeviceStore audioDeviceStore;
  final LiveSession session;
  final AudioDeviceRestorer _audioDeviceRestorer;

  Future<List<ScreenSource>> listScreenSources() {
    return LiveSession.listScreenSources();
  }

  Future<void> refreshScreenSourceThumbnails() {
    return LiveSession.refreshScreenSourceThumbnails();
  }

  bool get isScreenSharing => session.isScreenSharing;
  Set<String> get speakingIdentities => session.speakingIdentities;
  List<LiveVideoTrack> get videoTracks => session.videoTracks;

  LiveVideoTrack? cameraFor(String userId) => session.cameraFor(userId);

  void attachSessionCallbacks({
    required void Function() onChanged,
    required void Function() onForciblyRemoved,
    required void Function(bool canPublish) onPublishPermissionChanged,
  }) {
    session.addListener(onChanged);
    session.onForciblyRemoved = onForciblyRemoved;
    session.onPublishPermissionChanged = onPublishPermissionChanged;
  }

  void detachSessionCallbacks({required void Function() onChanged}) {
    session.removeListener(onChanged);
    session.onForciblyRemoved = null;
    session.onPublishPermissionChanged = null;
  }

  Future<void> setMicMuted(bool muted) => session.setMicMuted(muted);

  Future<void> setCameraEnabled(bool enabled) {
    return session.setCameraEnabled(enabled);
  }

  Future<void> setScreenShareEnabled(bool enabled, {String? sourceId}) {
    return session.setScreenShareEnabled(enabled, sourceId: sourceId);
  }

  Future<void> setInputVolume(double volume) => session.setInputVolume(volume);

  Future<void> setOutputVolume(double volume) {
    return session.setOutputVolume(volume);
  }

  Future<void> setOutputMuted(bool muted) => session.setOutputMuted(muted);

  Future<void> connectWithRetry(
    LiveJoinResult result, {
    bool Function()? isCancelled,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
      if (isCancelled?.call() ?? false) throw '已取消加入直播';
      try {
        final liveKitUrl = resolveLiveKitServerUrl(
          serverUrl: result.liveKit.serverUrl,
          apiBaseUrl: apiBaseUrl,
        );
        await restoreStoredAudioSettings();
        await session.connect(
          url: liveKitUrl,
          token: result.liveKit.token,
          roomName: result.liveKit.roomName,
          micMuted: result.participant.micMuted,
        );
        return;
      } catch (e) {
        lastError = e;
        await disconnect();
      }
    }
    throw lastError ?? 'LiveKit 连接失败';
  }

  Future<void> restoreStoredAudioSettings() async {
    try {
      final stored = await audioDeviceStore.read();
      await session.setInputVolume(stored.inputVolume);
      await session.setOutputVolume(stored.outputVolume);
      await _audioDeviceRestorer(audioDeviceStore);
    } catch (_) {
      // Joining voice should still work with LiveKit's current/default device
      // if a stored local preference cannot be applied.
    }
  }

  Future<void> disconnect({Duration? timeout}) async {
    final disconnect = session.disconnect().catchError((_) {});
    if (timeout == null) {
      await disconnect;
      return;
    }
    Timer? timeoutTimer;
    final timeoutCompleter = Completer<void>();
    timeoutTimer = Timer(timeout, () {
      if (!timeoutCompleter.isCompleted) timeoutCompleter.complete();
    });
    try {
      await Future.any([disconnect, timeoutCompleter.future]);
    } catch (_) {}
    timeoutTimer.cancel();
  }

  void dispose() => session.dispose();
}
