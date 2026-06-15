import 'dart:async';
import 'dart:io' show HttpOverrides, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../app/audio_levels.dart';
import '../protocol/models.dart' show musicBoxBotIdentity;
import 'audio_output_rebinder.dart';
import 'screen_share_quality.dart';
import 'system_audio_devices.dart';

/// A capturable desktop source (a whole screen or a single window), used to
/// populate the screen-share picker. Wraps flutter_webrtc's source so the UI
/// doesn't depend on the WebRTC types directly.
class ScreenSource {
  const ScreenSource({
    required this.id,
    required this.name,
    required this.thumbnail,
    required this.isWindow,
    String? thumbnailKey,
    this.thumbnailUpdates,
  }) : thumbnailKey = thumbnailKey ?? id;

  final String id;
  final String name;
  final Uint8List? thumbnail;
  final bool isWindow;
  final String thumbnailKey;
  final Stream<Uint8List>? thumbnailUpdates;
}

class _ScreenSourceThumbnailUpdate {
  const _ScreenSourceThumbnailUpdate({
    required this.sourceId,
    required this.thumbnail,
  });

  final String sourceId;
  final Uint8List thumbnail;
}

final _screenSourceWhitespacePattern = RegExp(r'\s+');
final _screenSourceThumbnailCache = <String, Uint8List>{};
final _screenSourceDirectThumbnailKeys = <String>{};
final _screenSourceThumbnailUpdateController =
    StreamController<_ScreenSourceThumbnailUpdate>.broadcast();
StreamSubscription<rtc.DesktopCapturerSource>?
_screenSourceThumbnailSubscription;

const _ignoredShareWindowNameParts = <String>[
  'nvidia geforce overlay',
  'nvidia overlay',
  'geforce overlay',
];

// libwebrtc's RTCDesktopSource thumbnails shear on Retina screens (same stride
// bug the live share sidesteps via ScreenCaptureKit). For screen sources we grab
// the thumbnail natively (CGDisplayCreateImage) instead, which is undistorted.
const _screenThumbnailChannel = MethodChannel('gang_chat/screen_thumbnail');

Future<Uint8List?> _captureNativeScreenThumbnail(String displayId) async {
  if (kIsWeb || !Platform.isMacOS) return null;
  try {
    final bytes = await _screenThumbnailChannel.invokeMethod<Uint8List>(
      'captureScreenThumbnail',
      {'displayId': displayId, 'maxWidth': 320},
    );
    if (bytes != null && bytes.isNotEmpty) return bytes;
  } catch (_) {}
  return null;
}

@visibleForTesting
List<ScreenSource> filterScreenSourcesForPicker(
  Iterable<ScreenSource> sources,
) {
  final visible = <ScreenSource>[];
  final seenIds = <String>{};

  for (final source in sources) {
    final normalizedName = _normalizeScreenSourceName(source.name);
    if (source.isWindow) {
      if (_isIgnoredShareWindowName(normalizedName)) continue;
    }
    if (seenIds.add(source.thumbnailKey)) visible.add(source);
  }

  return visible;
}

String _normalizeScreenSourceName(String name) {
  return name.trim().toLowerCase().replaceAll(
    _screenSourceWhitespacePattern,
    ' ',
  );
}

bool _isIgnoredShareWindowName(String normalizedName) {
  return _ignoredShareWindowNameParts.any(normalizedName.contains);
}

String _thumbnailKeyForDesktopSource(rtc.DesktopCapturerSource source) {
  final type = source.type == rtc.SourceType.Screen ? 'screen' : 'window';
  return '$type:${source.id}';
}

Uint8List? _rememberScreenSourceThumbnail({
  required String sourceId,
  required Uint8List? thumbnail,
}) {
  if (thumbnail != null && thumbnail.isNotEmpty) {
    _screenSourceThumbnailCache[sourceId] = thumbnail;
    return thumbnail;
  }
  return _screenSourceThumbnailCache[sourceId];
}

void _rememberAndEmitScreenSourceThumbnail({
  required String sourceId,
  required Uint8List? thumbnail,
}) {
  final remembered = _rememberScreenSourceThumbnail(
    sourceId: sourceId,
    thumbnail: thumbnail,
  );
  if (remembered == null || remembered.isEmpty) return;
  _screenSourceThumbnailUpdateController.add(
    _ScreenSourceThumbnailUpdate(sourceId: sourceId, thumbnail: remembered),
  );
}

Stream<Uint8List> _cacheScreenSourceThumbnailUpdates(
  String sourceId,
  Stream<Uint8List> updates,
) {
  return updates.map((thumbnail) {
    _rememberAndEmitScreenSourceThumbnail(
      sourceId: sourceId,
      thumbnail: thumbnail,
    );
    return thumbnail;
  });
}

Stream<Uint8List> _screenSourceThumbnailUpdates(String sourceId) {
  return _screenSourceThumbnailUpdateController.stream
      .where((update) => update.sourceId == sourceId)
      .map((update) => update.thumbnail);
}

void _ensureScreenSourceThumbnailCacheSubscription() {
  _screenSourceThumbnailSubscription ??= rtc
      .desktopCapturer
      .onThumbnailChanged
      .stream
      .listen((source) {
        final thumbnailKey = _thumbnailKeyForDesktopSource(source);
        if (source.type == rtc.SourceType.Screen &&
            _screenSourceDirectThumbnailKeys.contains(thumbnailKey)) {
          return;
        }
        _rememberAndEmitScreenSourceThumbnail(
          sourceId: thumbnailKey,
          thumbnail: source.thumbnail,
        );
      });
}

Future<Uint8List?> _loadInitialScreenSourceThumbnail(
  rtc.DesktopCapturerSource source,
  String thumbnailKey,
) async {
  final isScreen = source.type == rtc.SourceType.Screen;
  if (isScreen) {
    // macOS reports the screen source id as the CGDirectDisplayID, which the
    // native capture path also uses to select the display.
    final directThumbnail = await _captureNativeScreenThumbnail(source.id);
    if (directThumbnail != null && directThumbnail.isNotEmpty) {
      _screenSourceDirectThumbnailKeys.add(thumbnailKey);
      return _rememberScreenSourceThumbnail(
        sourceId: thumbnailKey,
        thumbnail: directThumbnail,
      );
    }
    _screenSourceDirectThumbnailKeys.remove(thumbnailKey);
  }
  return _rememberScreenSourceThumbnail(
    sourceId: thumbnailKey,
    thumbnail: source.thumbnail,
  );
}

@visibleForTesting
Uint8List? cachedScreenSourceThumbnailForTest(String sourceId) {
  return _screenSourceThumbnailCache[sourceId];
}

@visibleForTesting
void resetScreenSourceThumbnailCacheForTest() {
  _screenSourceThumbnailCache.clear();
  _screenSourceDirectThumbnailKeys.clear();
}

@visibleForTesting
Stream<Uint8List> cacheScreenSourceThumbnailUpdatesForTest(
  String sourceId,
  Stream<Uint8List> updates,
) {
  return _cacheScreenSourceThumbnailUpdates(sourceId, updates);
}

@visibleForTesting
Stream<Uint8List> screenSourceThumbnailUpdatesForTest(String sourceId) {
  return _screenSourceThumbnailUpdates(sourceId);
}

/// A single video track currently published in the live room, tagged with
/// whose it is and whether it's a camera or a screen share. The UI uses these
/// to render participant video tiles.
class LiveVideoTrack {
  const LiveVideoTrack({
    required this.identity,
    required this.track,
    required this.isScreenShare,
    required this.isLocal,
  });

  final String identity;
  final lk.VideoTrack track;
  final bool isScreenShare;
  final bool isLocal;
}

/// Wraps a [lk.Room] and exposes a small UI-friendly snapshot of who is
/// currently speaking, whose microphone is muted, and which video tracks are
/// live.
///
/// The server signs LiveKit tokens with `identity == user.id`, so a LiveKit
/// participant's [lk.Participant.identity] matches `UserSummary.id` from the
/// protocol layer. The UI uses that as the join key.
class LiveSession extends ChangeNotifier {
  /// [outputRebinderFactory] builds the recovery hook that re-routes WebRTC
  /// audio output after macOS swaps the default endpoint (e.g. a Bluetooth
  /// headset flipping its A2DP/HFP profile when the mic opens or closes). It
  /// is started while connected and stopped on disconnect; null disables the
  /// recovery (tests, non-macOS). The default wires a real macOS rebinder.
  LiveSession({AudioOutputRebinder? Function(LiveSession session)?
      outputRebinderFactory})
    : _outputRebinderFactory =
          outputRebinderFactory ?? _defaultOutputRebinderFactory;

  final AudioOutputRebinder? Function(LiveSession session)
      _outputRebinderFactory;
  AudioOutputRebinder? _outputRebinder;

  lk.Room? _room;
  lk.CancelListenFunc? _cancelEvents;
  String? _roomName;
  bool _connecting = false;
  bool _screenSharing = false;
  bool _canPublish = true;
  double _inputVolume = 1.0;
  double _outputVolume = 1.0;
  double _musicBoxVolume = 1.0;
  bool _outputMuted = false;
  // The deviceId to capture the mic from, in WebRTC's macOS format
  // (stringified CoreAudio AudioDeviceID). Null means the ADM's current/default
  // device. Applied when the mic track is published; a change while connected
  // republishes the track on the new device.
  String? _inputDeviceId;

  // Target max height (px) for the local screen share — one of
  // [screenShareHeightOptions]. Defaults to native (1080 cap). Applied at the
  // next share; a change while sharing re-scales the live publication.
  int _screenShareMaxHeight = defaultScreenShareMaxHeight;

  final Set<String> _speakingIdentities = <String>{};
  final Map<String, bool> _micMutedByIdentity = <String, bool>{};

  /// Fired when the server force-disconnects the local participant from
  /// LiveKit (an admin `kick` -> `RemoveParticipant`). The UI uses this to drop
  /// its joined state and exit the voice panel without auto-reconnecting. Only
  /// raised for involuntary removals, not for our own [disconnect].
  void Function()? onForciblyRemoved;

  /// Fired when LiveKit reports the local participant's publish permission
  /// changed (an admin `block_voice` -> canPublish=false, or `restore_voice` ->
  /// canPublish=true). [canPublish] is the new value. The UI reconciles the
  /// mic button: disabled while false, re-enabled (still muted) when restored.
  void Function(bool canPublish)? onPublishPermissionChanged;

  bool get isConnected =>
      _room?.connectionState == lk.ConnectionState.connected;
  bool get isConnecting => _connecting;
  bool get isScreenSharing => _screenSharing;
  String? get roomName => _roomName;

  /// Whether LiveKit currently grants the local participant publish rights.
  /// False once an admin `block_voice` revokes it; LiveKit is the source of
  /// truth here, not any locally-tracked flag.
  bool get canPublish => _canPublish;
  double get inputVolume => _inputVolume;
  double get outputVolume => _outputVolume;

  /// Local listening volume applied only to the music box bot's audio track,
  /// independent of [outputVolume] (which covers every other remote speaker).
  double get musicBoxVolume => _musicBoxVolume;
  bool get outputMuted => _outputMuted;

  /// Target max height (px) for the local screen share.
  int get screenShareMaxHeight => _screenShareMaxHeight;

  /// Whether the local microphone is muted according to the LiveKit track
  /// itself (server-side mutes by an admin are reflected here, unlike a
  /// locally-tracked bool). Returns true when not connected or unpublished.
  bool get localMicMuted {
    final local = _room?.localParticipant;
    if (local == null) return true;
    return _isMicMuted(local);
  }

  Set<String> get speakingIdentities => Set.unmodifiable(_speakingIdentities);
  Map<String, bool> get micMutedByIdentity =>
      Map.unmodifiable(_micMutedByIdentity);

  bool isSpeaking(String userId) => _speakingIdentities.contains(userId);

  /// All live video tracks (local + remote, camera + screen share) that the UI
  /// can currently render. Rebuilt on demand from the room's participants.
  List<LiveVideoTrack> get videoTracks {
    final room = _room;
    if (room == null) return const [];
    final result = <LiveVideoTrack>[];

    void collect(lk.Participant participant, {required bool isLocal}) {
      for (final pub in participant.videoTrackPublications) {
        final track = pub.track;
        if (track == null) continue;
        // A muted publication still has a (now-stopped) track attached. livekit
        // mutes rather than unpublishes the camera when it's turned off, so
        // rendering it would paint a black rectangle instead of letting the UI
        // fall back to the avatar. Skip muted tracks entirely.
        if (pub.muted) continue;
        if (!isLocal && pub is lk.RemoteTrackPublication && !pub.subscribed) {
          continue;
        }
        if (track is! lk.VideoTrack) continue;
        result.add(
          LiveVideoTrack(
            identity: participant.identity,
            track: track,
            isScreenShare: pub.source == lk.TrackSource.screenShareVideo,
            isLocal: isLocal,
          ),
        );
      }
    }

    final local = room.localParticipant;
    if (local != null) collect(local, isLocal: true);
    for (final remote in room.remoteParticipants.values) {
      collect(remote, isLocal: false);
    }
    return result;
  }

  /// The first screen-share track for [userId], if any. Returns null when that
  /// participant isn't sharing (or the track isn't subscribed yet).
  LiveVideoTrack? screenShareFor(String userId) {
    for (final t in videoTracks) {
      if (t.identity == userId && t.isScreenShare) return t;
    }
    return null;
  }

  /// The first camera track for [userId], if any.
  LiveVideoTrack? cameraFor(String userId) {
    for (final t in videoTracks) {
      if (t.identity == userId && !t.isScreenShare) return t;
    }
    return null;
  }

  /// Connect to a LiveKit room. If already in [roomName], aligns mic state
  /// and returns. Otherwise disconnects from the current room first.
  Future<void> connect({
    required String url,
    required String token,
    required String roomName,
    required bool micMuted,
  }) async {
    if (_room != null && _roomName == roomName && isConnected) {
      await setMicMuted(micMuted);
      return;
    }
    await disconnect();

    _connecting = true;
    notifyListeners();

    final room = lk.Room(
      roomOptions: lk.RoomOptions(
        // Adaptive stream sizes the subscribed quality to the rendering
        // widget's pixel size. When a screen share is viewed in the small
        // (non-fullscreen) stage, that requests a low-quality layer; combined
        // with dynacast (which pauses layers nobody subscribes to at full
        // quality on the sender), the publisher drops to its lowest temporal
        // layer and the share renders at a few fps — choppy until you go
        // fullscreen and the renderer grows enough to request full quality.
        // Keep subscriptions at full quality so the share is smooth at any
        // tile size; the camera-tile bandwidth saving isn't worth a degraded
        // screen share for a small group.
        adaptiveStream: false,
        dynacast: true,
        // Don't stop the OS audio capture session when the mic is muted.
        // The default (true) calls MediaStreamTrack.stop() on mute, which
        // tears down the shared input device and can cut audio for other apps
        // using the same mic (e.g. WeChat voice). Muting now only stops
        // sending audio; the device stays open (system mic indicator stays
        // lit) and unmute is instant.
        defaultAudioCaptureOptions: lk.AudioCaptureOptions(
          stopAudioCaptureOnMute: false,
          deviceId: _inputDeviceId,
        ),
        defaultVideoPublishOptions: lk.VideoPublishOptions(
          // The capture rate (ScreenShareCaptureOptions.maxFrameRate) only sets
          // how fast the grabber samples the screen. What viewers actually
          // receive is governed by the *publish* encoding, which — when left
          // null — falls back to LiveKit's screenShareH1080FPS15 preset, hard
          // capped at 15fps. Set it explicitly so the encoder isn't the
          // bottleneck. maxBitrate must scale with the frame rate or the
          // encoder starves frames to stay under budget. 1080p60 is given a
          // 16 Mbps ceiling so the encoder isn't bitrate-starved.
          screenShareEncoding: lk.VideoEncoding(
            maxFramerate: 60,
            maxBitrate: 16000 * 1000,
          ),
        ),
      ),
    );
    _room = room;
    _roomName = roomName;
    _screenSharing = false;
    _canPublish = true;
    _cancelEvents = room.events.listen(_onEvent);

    try {
      await HttpOverrides.runZoned(
        () => room.connect(url, token),
        findProxyFromEnvironment: (uri, environment) => 'DIRECT',
      );
      // Seed publish permission from the token LiveKit just validated: a
      // voice-banned user joins with canPublish=false, and we must not try to
      // publish the mic below (LiveKit would reject it).
      _canPublish = room.localParticipant?.permissions.canPublish ?? true;
      // Publish the microphone track. The OS will prompt for permission on
      // the first publish. Skip it entirely when publishing is blocked.
      if (_canPublish) {
        await room.localParticipant?.setMicrophoneEnabled(!micMuted);
      }
      await _applyInputVolume();
      await _applyOutputVolume();
      await _applyMusicBoxVolume();
      _refreshAllMicStates();
      _startOutputRebinder();
    } catch (e) {
      await _cancelEvents?.call();
      _cancelEvents = null;
      _stopOutputRebinder();
      try {
        await room.dispose();
      } catch (_) {}
      _room = null;
      _roomName = null;
      _connecting = false;
      _screenSharing = false;
      _speakingIdentities.clear();
      _micMutedByIdentity.clear();
      notifyListeners();
      throw LiveSessionConnectException(url: url, cause: e);
    }

    _connecting = false;
    notifyListeners();
  }

  /// Mute/unmute the local microphone. Safe to call when not connected.
  Future<void> setMicMuted(bool muted) async {
    final local = _room?.localParticipant;
    if (local == null) return;
    await local.setMicrophoneEnabled(!muted);
    await _applyInputVolume();
    _refreshAllMicStates();
    notifyListeners();
  }

  Future<void> setInputVolume(double volume) async {
    _inputVolume = normalizedAudioVolume(volume);
    await _applyInputVolume();
  }

  /// Select the microphone capture device. [deviceId] is WebRTC's macOS format
  /// (stringified CoreAudio AudioDeviceID), or null for the system default. Takes
  /// effect at the next publish; when already publishing, republishes the mic on
  /// the new device, preserving the current mute state.
  Future<void> setInputDeviceId(String? deviceId) async {
    if (_inputDeviceId == deviceId) return;
    _inputDeviceId = deviceId;
    final local = _room?.localParticipant;
    if (local == null) return;
    // Republish only if a mic track exists; otherwise the new id is picked up
    // by the next setMicrophoneEnabled(true).
    final wasMuted = _isMicMuted(local);
    final hasTrack = local.audioTrackPublications.isNotEmpty;
    if (!hasTrack) return;
    try {
      await local.setMicrophoneEnabled(
        false,
        audioCaptureOptions: lk.AudioCaptureOptions(
          stopAudioCaptureOnMute: false,
          deviceId: _inputDeviceId,
        ),
      );
      await local.setMicrophoneEnabled(
        !wasMuted,
        audioCaptureOptions: lk.AudioCaptureOptions(
          stopAudioCaptureOnMute: false,
          deviceId: _inputDeviceId,
        ),
      );
      await _applyInputVolume();
      _refreshAllMicStates();
      notifyListeners();
    } catch (_) {
      // Selection is best-effort; keep the existing capture on failure.
    }
  }

  Future<void> setOutputVolume(double volume) async {
    _outputVolume = normalizedAudioVolume(volume);
    await _applyOutputVolume();
  }

  Future<void> setMusicBoxVolume(double volume) async {
    _musicBoxVolume = normalizedAudioVolume(volume);
    await _applyMusicBoxVolume();
  }

  Future<void> setOutputMuted(bool muted) async {
    _outputMuted = muted;
    await _applyOutputVolume();
  }

  /// Start or stop sharing the screen. [sourceId] is a desktop capturer source
  /// id (see [listScreenSources]); when null the platform default is used.
  /// Returns the resulting share state. Throws if capture fails (e.g. the user
  /// cancels the OS picker) — the caller is responsible for surfacing that.
  Future<bool> setScreenShareEnabled(bool enabled, {String? sourceId}) async {
    final local = _room?.localParticipant;
    if (local == null) return false;
    if (enabled) {
      // A concrete maxFrameRate is required: livekit's desktop
      // ScreenShareCaptureOptions sends `mandatory: {frameRate: maxFrameRate}`,
      // and when maxFrameRate is null (the default) that becomes a null value.
      // flutter_webrtc's native constraint parser then calls GetValue<int> on
      // that null, throwing std::bad_variant_access and hard-crashing the
      // process. Passing a real frame rate keeps the value a valid double.
      //
      // On macOS (flutter_webrtc 1.4.0+) full-screen capture goes through
      // ScreenCaptureKit, which samples at the display's native resolution and
      // ignores params.dimensions — so dimensions here only bounds non-SCKit
      // platforms. The encoding (and defaultVideoPublishOptions in connect())
      // still governs what viewers receive. To cap resolution on macOS we scale
      // the published encoding down after publishing (_applyScreenShareScale).
      final target = screenShareResolutionForHeight(_screenShareMaxHeight);
      final options = lk.ScreenShareCaptureOptions(
        sourceId: sourceId,
        maxFrameRate: 60.0,
        params: lk.VideoParameters(
          dimensions: lk.VideoDimensions(target.width, target.height),
          encoding: const lk.VideoEncoding(
            maxFramerate: 60,
            maxBitrate: 16000 * 1000,
          ),
        ),
      );
      await local.setScreenShareEnabled(
        true,
        screenShareCaptureOptions: options,
      );
      _screenSharing = true;
      await _applyScreenShareScale();
    } else {
      await local.setScreenShareEnabled(false);
      _screenSharing = false;
    }
    notifyListeners();
    return _screenSharing;
  }

  /// Set the target max height for the local screen share. Persists in-session;
  /// re-scales the live publication immediately when a share is running.
  Future<void> setScreenShareMaxHeight(int height) async {
    final normalized = normalizedScreenShareMaxHeight(height);
    if (_screenShareMaxHeight == normalized) return;
    _screenShareMaxHeight = normalized;
    if (_screenSharing) {
      await _applyScreenShareScale();
    }
    notifyListeners();
  }

  /// Scale the published screen-share encoding so it is sent at no more than
  /// [_screenShareMaxHeight]. macOS captures at the display's native resolution
  /// (ScreenCaptureKit ignores capture dimensions), so the encoder's
  /// `scaleResolutionDownBy` is the only lever that actually reduces the pixels
  /// we send. Best-effort: a missing sender or stats leaves the share unscaled.
  Future<void> _applyScreenShareScale() async {
    final local = _room?.localParticipant;
    if (local == null) return;
    final pub = local.getTrackPublicationBySource(
      lk.TrackSource.screenShareVideo,
    );
    final track = pub?.track;
    if (track is! lk.LocalVideoTrack) return;
    final sender = track.sender;
    if (sender == null) return;

    // The source height we're capturing. getSenderStats() reports the encoded
    // frame size once frames flow; until then fall back to the configured
    // target so we never scale up.
    var sourceHeight = _screenShareMaxHeight;
    try {
      final stats = await track.getSenderStats();
      for (final s in stats) {
        final h = s.frameHeight;
        if (h != null && h > sourceHeight) sourceHeight = h.toInt();
      }
    } catch (_) {
      // No stats yet; the next call (or capture-side dimensions on
      // Windows/Linux) handles it.
    }

    final scale = screenShareScaleDownBy(
      sourceHeight: sourceHeight,
      targetHeight: _screenShareMaxHeight,
    );
    try {
      final params = sender.parameters;
      final encodings = params.encodings;
      if (encodings == null || encodings.isEmpty) return;
      var changed = false;
      for (final encoding in encodings) {
        if (encoding.scaleResolutionDownBy != scale) {
          encoding.scaleResolutionDownBy = scale;
          changed = true;
        }
      }
      if (changed) {
        params.encodings = encodings;
        await sender.setParameters(params);
      }
    } catch (_) {
      // setParameters is best-effort; a failure leaves the prior scale in place.
    }
  }

  /// Start or stop the local camera. Returns the resulting state. Throws if
  /// capture fails (no camera, permission denied) — the caller surfaces it.
  Future<bool> setCameraEnabled(bool enabled) async {
    final local = _room?.localParticipant;
    if (local == null) return false;
    await local.setCameraEnabled(enabled);
    notifyListeners();
    return enabled;
  }

  /// Enumerate capturable desktop sources (screens and windows) for the
  /// share picker. Best-effort: returns an empty list if enumeration fails.
  static Future<List<ScreenSource>> listScreenSources() async {
    try {
      _ensureScreenSourceThumbnailCacheSubscription();
      final sources = await rtc.desktopCapturer.getSources(
        types: [rtc.SourceType.Screen, rtc.SourceType.Window],
        thumbnailSize: rtc.ThumbnailSize(640, 360),
      );
      final screenSources = <ScreenSource>[];
      for (final s in sources) {
        final isWindow = s.type == rtc.SourceType.Window;
        final name = s.name.trim();
        final thumbnailKey = _thumbnailKeyForDesktopSource(s);
        final thumbnail = await _loadInitialScreenSourceThumbnail(
          s,
          thumbnailKey,
        );
        screenSources.add(
          ScreenSource(
            id: s.id,
            name: name.isEmpty ? (isWindow ? '窗口' : '屏幕') : name,
            thumbnail: thumbnail,
            isWindow: isWindow,
            thumbnailKey: thumbnailKey,
            thumbnailUpdates: _screenSourceThumbnailUpdates(thumbnailKey),
          ),
        );
      }
      return filterScreenSourcesForPicker(screenSources);
    } catch (_) {
      return const [];
    }
  }

  /// Ask flutter_webrtc to refresh source thumbnails. On Windows the initial
  /// getSources() call does not include thumbnail bytes; they arrive through
  /// onThumbnailChanged after updateSources(). macOS screen thumbnails come
  /// from a native capture (to avoid the sheared RTCDesktopSource thumbnail),
  /// so refresh those directly rather than through onThumbnailChanged.
  static Future<void> refreshScreenSourceThumbnails() async {
    try {
      _ensureScreenSourceThumbnailCacheSubscription();
      await rtc.desktopCapturer.updateSources(
        types: [rtc.SourceType.Screen, rtc.SourceType.Window],
      );
      await _refreshNativeScreenThumbnails();
    } catch (_) {}
  }

  static Future<void> _refreshNativeScreenThumbnails() async {
    for (final thumbnailKey in _screenSourceDirectThumbnailKeys.toList()) {
      final displayId = thumbnailKey.startsWith('screen:')
          ? thumbnailKey.substring('screen:'.length)
          : thumbnailKey;
      final thumbnail = await _captureNativeScreenThumbnail(displayId);
      if (thumbnail != null && thumbnail.isNotEmpty) {
        _rememberAndEmitScreenSourceThumbnail(
          sourceId: thumbnailKey,
          thumbnail: thumbnail,
        );
      }
    }
  }

  Future<void> disconnect() async {
    final room = _room;
    final cancel = _cancelEvents;
    _cancelEvents = null;
    _stopOutputRebinder();
    _room = null;
    _roomName = null;
    _connecting = false;
    _screenSharing = false;
    _canPublish = true;
    _speakingIdentities.clear();
    _micMutedByIdentity.clear();
    if (cancel != null) {
      try {
        await cancel();
      } catch (_) {}
    }
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
    }
    notifyListeners();
  }

  @override
  void dispose() {
    final room = _room;
    final cancel = _cancelEvents;
    _cancelEvents = null;
    _stopOutputRebinder();
    _room = null;
    _roomName = null;
    _screenSharing = false;
    _speakingIdentities.clear();
    _micMutedByIdentity.clear();
    cancel?.call();
    if (room != null) {
      // Best-effort async cleanup; swallow errors.
      room.disconnect().catchError((_) {}).whenComplete(() {
        try {
          room.dispose();
        } catch (_) {}
      });
    }
    super.dispose();
  }

  // ---- Event handling -------------------------------------------------------

  void _onEvent(lk.RoomEvent event) {
    if (event is lk.ActiveSpeakersChangedEvent) {
      _speakingIdentities
        ..clear()
        ..addAll(event.speakers.map((p) => p.identity));
      notifyListeners();
      return;
    }
    if (event is lk.ParticipantConnectedEvent) {
      _micMutedByIdentity[event.participant.identity] = _isMicMuted(
        event.participant,
      );
      unawaited(_applyOutputVolume());
      unawaited(_applyMusicBoxVolume());
      notifyListeners();
      return;
    }
    if (event is lk.ParticipantDisconnectedEvent) {
      _micMutedByIdentity.remove(event.participant.identity);
      _speakingIdentities.remove(event.participant.identity);
      notifyListeners();
      return;
    }
    // An admin block_voice / restore_voice flips the local participant's
    // publish permission server-side; LiveKit pushes it down here. Track only
    // the local participant — remote permission changes don't affect our UI.
    if (event is lk.ParticipantPermissionsUpdatedEvent) {
      final local = _room?.localParticipant;
      if (local != null && event.participant.identity == local.identity) {
        final next = event.permissions.canPublish;
        if (next != _canPublish) {
          _canPublish = next;
          notifyListeners();
          onPublishPermissionChanged?.call(next);
        }
      }
      return;
    }
    // Video subscription / publish lifecycle: rebuild the rendered track list.
    if (event is lk.TrackSubscribedEvent ||
        event is lk.TrackUnsubscribedEvent ||
        event is lk.LocalTrackPublishedEvent ||
        event is lk.LocalTrackUnpublishedEvent ||
        event is lk.TrackPublishedEvent ||
        event is lk.TrackUnpublishedEvent ||
        event is lk.TrackMutedEvent ||
        event is lk.TrackUnmutedEvent) {
      unawaited(_applyInputVolume());
      unawaited(_applyOutputVolume());
      unawaited(_applyMusicBoxVolume());
      _refreshAllMicStates();
      // A local screen-share track can be stopped from the OS (e.g. the
      // "stop sharing" bar); keep our flag honest.
      _screenSharing = _localHasScreenShare();
      notifyListeners();
      return;
    }
    if (event is lk.RoomDisconnectedEvent) {
      _screenSharing = false;
      _speakingIdentities.clear();
      _micMutedByIdentity.clear();
      notifyListeners();
      // An admin kick force-disconnects us via RemoveParticipant; LiveKit
      // reports it as participantRemoved. Distinguish it from our own
      // disconnect() (which clears _cancelEvents before the event can fire, so
      // this handler never runs for a voluntary leave) and from transient
      // network drops, so the UI can exit the voice panel without auto-
      // reconnecting into a room we were just removed from.
      if (event.reason == lk.DisconnectReason.participantRemoved ||
          event.reason == lk.DisconnectReason.roomDeleted) {
        onForciblyRemoved?.call();
      }
      return;
    }
  }

  bool _localHasScreenShare() {
    final local = _room?.localParticipant;
    if (local == null) return false;
    return local.videoTrackPublications.any(
      (pub) =>
          pub.source == lk.TrackSource.screenShareVideo && pub.track != null,
    );
  }

  void _refreshAllMicStates() {
    final room = _room;
    if (room == null) return;
    final local = room.localParticipant;
    if (local != null) {
      _micMutedByIdentity[local.identity] = _isMicMuted(local);
    }
    for (final p in room.remoteParticipants.values) {
      _micMutedByIdentity[p.identity] = _isMicMuted(p);
    }
  }

  static bool _isMicMuted(lk.Participant participant) {
    final pubs = participant.audioTrackPublications;
    if (pubs.isEmpty) return true;
    return pubs.every((pub) => pub.muted);
  }

  Future<void> _applyInputVolume() async {
    final local = _room?.localParticipant;
    if (local == null) return;
    for (final pub in local.audioTrackPublications) {
      final track = pub.track;
      if (track == null) continue;
      try {
        await rtc.Helper.setVolume(_inputVolume, track.mediaStreamTrack);
      } catch (_) {}
    }
  }

  Future<void> _applyOutputVolume() async {
    final room = _room;
    if (room == null) return;
    final volume = _outputMuted ? 0.0 : _outputVolume;
    for (final participant in room.remoteParticipants.values) {
      // The music box bot has its own independent volume knob; leave it to
      // _applyMusicBoxVolume so the two don't fight over the same track.
      if (participant.identity == musicBoxBotIdentity) continue;
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track == null) continue;
        try {
          await rtc.Helper.setVolume(volume, track.mediaStreamTrack);
        } catch (_) {}
      }
    }
  }

  Future<void> _applyMusicBoxVolume() async {
    final room = _room;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      if (participant.identity != musicBoxBotIdentity) continue;
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track == null) continue;
        try {
          await rtc.Helper.setVolume(_musicBoxVolume, track.mediaStreamTrack);
        } catch (_) {}
      }
    }
  }

  // Re-bind WebRTC's audio output to the live default endpoint and re-apply
  // every track volume. Invoked by [_outputRebinder] after macOS swaps the
  // default output (the Bluetooth A2DP/HFP profile flip), where WebRTC would
  // otherwise keep rendering into the torn-down endpoint as noise.
  Future<void> _reapplyAudioRouting() async {
    if (_room == null) return;
    await _applyOutputVolume();
    await _applyMusicBoxVolume();
  }

  void _startOutputRebinder() {
    _stopOutputRebinder();
    final rebinder = _outputRebinderFactory(this);
    _outputRebinder = rebinder;
    rebinder?.start();
  }

  void _stopOutputRebinder() {
    final rebinder = _outputRebinder;
    _outputRebinder = null;
    if (rebinder != null) unawaited(rebinder.stop());
  }

  /// Drives the output-rebinder lifecycle without a live LiveKit connection, so
  /// the macOS A2DP/HFP recovery wiring can be exercised in tests. Production
  /// code reaches these through [connect]/[disconnect].
  @visibleForTesting
  void debugStartOutputRebinder() => _startOutputRebinder();

  @visibleForTesting
  void debugStopOutputRebinder() => _stopOutputRebinder();
}

// Default macOS recovery for the Bluetooth A2DP/HFP profile flip: re-select the
// current system default output on each WebRTC device-change so the CoreAudio
// ADM rebuilds its playout unit against the live endpoint, then re-apply
// volumes. Returns null off macOS, where the flip doesn't apply.
AudioOutputRebinder? _defaultOutputRebinderFactory(LiveSession session) {
  if (kIsWeb || !Platform.isMacOS) return null;
  final systemAudio = SystemAudioDevices();
  return AudioOutputRebinder(
    deviceChanges: lk.Hardware.instance.onDeviceChange.stream.map((_) {}),
    currentOutputDeviceId: systemAudio.currentOutputDeviceId,
    selectOutput: (deviceId) async {
      await rtc.Helper.selectAudioOutput(deviceId);
    },
    onRebound: session._reapplyAudioRouting,
  );
}

class LiveSessionConnectException implements Exception {
  const LiveSessionConnectException({required this.url, required this.cause});

  final String url;
  final Object cause;

  @override
  String toString() {
    return '无法连接到 $url 的 LiveKit：${_describeError(cause)}';
  }
}

String _describeError(Object error) {
  final message = _tryReadMessage(error);
  final nested = _tryReadNestedError(error);
  if (message != null && nested != null) {
    return '$message (${_describeError(nested)})';
  }
  if (message != null) return message;

  final text = error.toString();
  if (text.startsWith('Instance of ')) return error.runtimeType.toString();
  return text;
}

String? _tryReadMessage(Object error) {
  try {
    final value = (error as dynamic).message;
    if (value is String && value.isNotEmpty) return value;
  } catch (_) {}
  return null;
}

Object? _tryReadNestedError(Object error) {
  try {
    final value = (error as dynamic).error;
    if (value is Object) return value;
  } catch (_) {}
  return null;
}
