import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io' show HttpOverrides;

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../protocol/models.dart';

/// Fetches a publish-only LiveKit token for the hidden screen-audio aux
/// participant. Implemented by the app layer (wired to `GangApi`), keeping
/// this class decoupled from the API client.
typedef ScreenAudioTokenProvider =
    Future<ScreenAudioToken> Function(String roomId);

/// Publishes screen-share audio as an independent `TrackSource.screenShareAudio`
/// track through a *second* LiveKit Room whose PeerConnections live on an
/// isolated WebRTC factory.
///
/// The isolated factory is fully separate from the primary microphone factory:
/// macOS feeds it through `FlutterScreenAudioDevice`/ScreenCaptureKit, while
/// Windows creates the screen-audio track on a second native factory and feeds
/// it from WASAPI loopback. This removes the shared `AudioState` that would
/// otherwise fan mic capture into the screen-audio send stream and race its
/// capture checker (the fatal `audio_send_stream.cc:393` `RTC_CHECK`).
///
/// The aux participant joins with identity `<ownerId>--screen-audio`, is
/// publish-only (`canSubscribe=false`), and never appears in the roster (no
/// `live_participants` row is created for it). Receivers merge its audio into
/// the owner's `screenShareVolume` via the existing `_applyScreenShareVolume`
/// logic, which iterates all `screenShareAudio` publications across all remote
/// participants.
class ScreenAudioPublisher {
  ScreenAudioPublisher({required this.tokenProvider});

  final ScreenAudioTokenProvider tokenProvider;

  lk.Room? _room;

  bool get isPublishing => _room != null;

  /// Connects the aux room and publishes the screen-audio track.
  ///
  /// [liveKitUrl] is the resolved LiveKit server URL (same as the main room).
  /// [roomName] is the LiveKit room name (== roomID). The aux token is fetched
  /// on demand so it is always fresh regardless of how long the user has been
  /// in the call.
  Future<void> start({
    required String liveKitUrl,
    required String roomName,
  }) async {
    debugPrint(
      'screen-audio: starting publisher (url=$liveKitUrl, room=$roomName)',
    );
    final tokenResult = await tokenProvider(roomName);
    debugPrint(
      'screen-audio: token acquired (identity=${tokenResult.identity})',
    );

    final engine = lk.Engine(
      connectOptions: const lk.ConnectOptions(),
      roomOptions: const lk.RoomOptions(),
      peerConnectionCreate: _createScreenAudioPeerConnection,
    );
    final room = lk.Room(engine: engine);
    _room = room;

    debugPrint('screen-audio: connecting aux room...');
    await HttpOverrides.runZoned(
      () => room.connect(liveKitUrl, tokenResult.token),
      findProxyFromEnvironment: (uri, environment) => 'DIRECT',
    );
    debugPrint('screen-audio: aux room connected');

    final local = room.localParticipant;
    if (local == null) {
      throw StateError(
        'screen-audio aux room connected without a local participant',
      );
    }

    // Create the audio track on the isolated factory. Its audio is pulled from
    // FlutterScreenAudioDevice (the second factory's ADM), which the
    // ScreenCaptureKit capturer feeds via enqueueSampleBuffer:.
    debugPrint('screen-audio: creating track on factory-2...');
    final stream = await rtc.createScreenAudioTrack();
    debugPrint('screen-audio: track created');
    // ignore: invalid_use_of_internal_member
    final track = lk.LocalAudioTrack(
      lk.TrackSource.screenShareAudio,
      stream,
      stream.getAudioTracks().first,
      const lk.AudioCaptureOptions(),
    );

    debugPrint('screen-audio: publishing track...');
    await local.publishAudioTrack(track);
    debugPrint('screen-audio: track published successfully');
  }

  /// Disconnects the aux room and releases the track + factory resources.
  Future<void> stop() async {
    final room = _room;
    _room = null;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
    }
  }

  static Future<rtc.RTCPeerConnection> _createScreenAudioPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic>? constraints,
  ]) {
    return rtc.createScreenAudioPeerConnection(
      configuration,
      constraints ?? const {},
    );
  }
}
