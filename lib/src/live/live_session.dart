import 'dart:io' show HttpOverrides;

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

/// A capturable desktop source (a whole screen or a single window), used to
/// populate the screen-share picker. Wraps flutter_webrtc's source so the UI
/// doesn't depend on the WebRTC types directly.
class ScreenSource {
  const ScreenSource({
    required this.id,
    required this.name,
    required this.thumbnail,
    required this.isWindow,
  });

  final String id;
  final String name;
  final Uint8List? thumbnail;
  final bool isWindow;
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
  LiveSession();

  lk.Room? _room;
  lk.CancelListenFunc? _cancelEvents;
  String? _roomName;
  bool _connecting = false;
  bool _screenSharing = false;
  bool _canPublish = true;

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
      roomOptions: const lk.RoomOptions(
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
        defaultVideoPublishOptions: lk.VideoPublishOptions(
          // The capture rate (ScreenShareCaptureOptions.maxFrameRate) only sets
          // how fast the grabber samples the screen. What viewers actually
          // receive is governed by the *publish* encoding, which — when left
          // null — falls back to LiveKit's screenShareH1080FPS15 preset, hard
          // capped at 15fps. Set it explicitly so the encoder isn't the
          // bottleneck. maxBitrate must scale with the frame rate or the
          // encoder starves frames to stay under budget. 720p60 ≈ 4 Mbps.
          screenShareEncoding: lk.VideoEncoding(
            maxFramerate: 60,
            maxBitrate: 4000 * 1000,
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
      _refreshAllMicStates();
    } catch (e) {
      await _cancelEvents?.call();
      _cancelEvents = null;
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
    _refreshAllMicStates();
    notifyListeners();
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
      // flutter_webrtc 1.2.1's native constraint parser then calls GetValue<int>
      // on that null, throwing std::bad_variant_access and hard-crashing the
      // process. Passing a real frame rate keeps the value a valid double.
      //
      // params sets the capture resolution; the matching publish encoding lives
      // in defaultVideoPublishOptions (see connect()). Keep both at 720p60.
      final options = lk.ScreenShareCaptureOptions(
        sourceId: sourceId,
        maxFrameRate: 60.0,
        params: const lk.VideoParameters(
          dimensions: lk.VideoDimensionsPresets.h720_169,
          encoding: lk.VideoEncoding(
            maxFramerate: 60,
            maxBitrate: 4000 * 1000,
          ),
        ),
      );
      await local.setScreenShareEnabled(true, screenShareCaptureOptions: options);
      _screenSharing = true;
    } else {
      await local.setScreenShareEnabled(false);
      _screenSharing = false;
    }
    notifyListeners();
    return _screenSharing;
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
      final sources = await rtc.desktopCapturer.getSources(
        types: [rtc.SourceType.Screen, rtc.SourceType.Window],
        thumbnailSize: rtc.ThumbnailSize(320, 180),
      );
      return sources
          .map(
            (s) => ScreenSource(
              id: s.id,
              name: s.name.isEmpty ? '未命名来源' : s.name,
              thumbnail: s.thumbnail,
              isWindow: s.type == rtc.SourceType.Window,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> disconnect() async {
    final room = _room;
    final cancel = _cancelEvents;
    _cancelEvents = null;
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
      _micMutedByIdentity[event.participant.identity] =
          _isMicMuted(event.participant);
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
}

class LiveSessionConnectException implements Exception {
  const LiveSessionConnectException({
    required this.url,
    required this.cause,
  });

  final String url;
  final Object cause;

  @override
  String toString() {
    return 'Could not connect to LiveKit at $url: ${_describeError(cause)}';
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
