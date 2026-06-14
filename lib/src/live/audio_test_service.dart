import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../app/audio_levels.dart';

class AudioTestService {
  bool _requestedDeviceAccess = false;

  Future<void> ensureDeviceAccess() async {
    if (_requestedDeviceAccess) return;
    _requestedDeviceAccess = true;
    lk.LocalAudioTrack? track;
    try {
      track = await lk.LocalAudioTrack.create();
      await track.start();
      await track.stop();
    } catch (_) {
      // Device enumeration will surface the usable state. This call is only
      // here to trigger OS media permission before enumerateDevices().
    } finally {
      await _disposeTestTrack(track);
    }
  }

  Future<AudioTestHandle> startInputTest({
    required String? inputDeviceId,
    required double volume,
    required void Function(double level) onLevel,
  }) async {
    lk.LocalAudioTrack? track;
    _StartedAudioVisualizer? visualizer;
    try {
      track = await _createTestAudioTrack(inputDeviceId);
      await rtc.Helper.setVolume(
        normalizedAudioVolume(volume),
        track.mediaStreamTrack,
      );
      visualizer = await _startVisualizer(track, onLevel);
      return AudioTestHandle._(track: track, visualizer: visualizer);
    } catch (_) {
      await visualizer?.dispose();
      await _disposeTestTrack(track);
      rethrow;
    }
  }

  Future<AudioTestHandle> startOutputTest({
    required String? inputDeviceId,
    required String? outputDeviceId,
    required double volume,
    required void Function(double level) onLevel,
  }) async {
    lk.LocalAudioTrack? track;
    rtc.RTCVideoRenderer? renderer;
    _StartedAudioVisualizer? visualizer;
    try {
      track = await _createTestAudioTrack(inputDeviceId);
      renderer = rtc.RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = track.mediaStream;
      await renderer.setVolume(normalizedAudioVolume(volume));
      await _routeOutput(renderer, outputDeviceId);
      visualizer = await _startVisualizer(track, onLevel);
      return AudioTestHandle._(
        track: track,
        renderer: renderer,
        visualizer: visualizer,
      );
    } catch (_) {
      await visualizer?.dispose();
      await _disposeRenderer(renderer);
      await _disposeTestTrack(track);
      rethrow;
    }
  }

  Future<lk.LocalAudioTrack> _createTestAudioTrack(
    String? inputDeviceId,
  ) async {
    await ensureDeviceAccess();
    final track = await lk.LocalAudioTrack.create(
      lk.AudioCaptureOptions(deviceId: inputDeviceId),
    );
    await track.start();
    return track;
  }
}

class AudioTestHandle {
  AudioTestHandle._({
    required lk.LocalAudioTrack track,
    required _StartedAudioVisualizer visualizer,
    rtc.RTCVideoRenderer? renderer,
  }) : _track = track,
       _visualizer = visualizer,
       _renderer = renderer;

  lk.LocalAudioTrack? _track;
  _StartedAudioVisualizer? _visualizer;
  rtc.RTCVideoRenderer? _renderer;

  Future<void> setCaptureVolume(double volume) async {
    final track = _track;
    if (track == null) return;
    await rtc.Helper.setVolume(
      normalizedAudioVolume(volume),
      track.mediaStreamTrack,
    );
  }

  Future<void> setPlaybackVolume(double volume) async {
    final renderer = _renderer;
    if (renderer == null) return;
    await renderer.setVolume(normalizedAudioVolume(volume));
  }

  Future<void> routeOutput(String? outputDeviceId) async {
    await _routeOutput(_renderer, outputDeviceId);
  }

  Future<void> dispose() async {
    final visualizer = _visualizer;
    final renderer = _renderer;
    final track = _track;
    _visualizer = null;
    _renderer = null;
    _track = null;
    await visualizer?.dispose();
    await _disposeRenderer(renderer);
    await _disposeTestTrack(track);
  }
}

class _StartedAudioVisualizer {
  const _StartedAudioVisualizer(this.visualizer, this.listener);

  final lk.AudioVisualizer visualizer;
  final lk.EventsListener<lk.AudioVisualizerEvent> listener;

  Future<void> dispose() async {
    try {
      await visualizer.stop();
    } catch (_) {}
    try {
      await visualizer.dispose();
    } catch (_) {}
    try {
      await listener.dispose();
    } catch (_) {}
  }
}

Future<_StartedAudioVisualizer> _startVisualizer(
  lk.LocalAudioTrack track,
  void Function(double level) onLevel,
) async {
  final visualizer = lk.createVisualizer(
    track,
    options: const lk.AudioVisualizerOptions(
      barCount: 14,
      centeredBands: false,
    ),
  );
  final listener = visualizer.createListener();
  listener.on<lk.AudioVisualizerEvent>((event) {
    onLevel(audioLevelFromVisualizerBands(event.event));
  });
  try {
    await visualizer.start();
  } catch (_) {
    await _StartedAudioVisualizer(visualizer, listener).dispose();
    rethrow;
  }
  return _StartedAudioVisualizer(visualizer, listener);
}

Future<void> _routeOutput(
  rtc.RTCVideoRenderer? renderer,
  String? outputDeviceId,
) async {
  if (renderer == null || outputDeviceId == null) return;
  try {
    await renderer.audioOutput(outputDeviceId);
  } catch (_) {}
}

Future<void> _disposeTestTrack(lk.LocalAudioTrack? track) async {
  if (track == null) return;
  try {
    await track.stop();
  } catch (_) {}
  try {
    await track.dispose();
  } catch (_) {}
}

Future<void> _disposeRenderer(rtc.RTCVideoRenderer? renderer) async {
  if (renderer == null) return;
  try {
    renderer.srcObject = null;
  } catch (_) {}
  try {
    await renderer.dispose();
  } catch (_) {}
}
