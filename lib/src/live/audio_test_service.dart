import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
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
      visualizer = await _startVisualizer(track, onLevel);
      return AudioTestHandle._(track: track, visualizer: visualizer);
    } catch (_) {
      await visualizer?.dispose();
      await _disposeTestTrack(track);
      rethrow;
    }
  }

  Future<AudioTestHandle> startOutputTest({
    required double volume,
    required void Function(double level) onLevel,
  }) async {
    AudioPlayer? player;
    Timer? levelTimer;
    try {
      player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(
        BytesSource(_outputTestToneWav, mimeType: 'audio/wav'),
        volume: normalizedAudioVolume(volume),
      );
      onLevel(1.0);
      levelTimer = Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => onLevel(1.0),
      );
      return AudioTestHandle._(outputPlayer: player, levelTimer: levelTimer);
    } catch (_) {
      levelTimer?.cancel();
      await _disposeOutputPlayer(player);
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
    lk.LocalAudioTrack? track,
    _StartedAudioVisualizer? visualizer,
    AudioPlayer? outputPlayer,
    Timer? levelTimer,
  }) : _track = track,
       _visualizer = visualizer,
       _outputPlayer = outputPlayer,
       _levelTimer = levelTimer;

  lk.LocalAudioTrack? _track;
  _StartedAudioVisualizer? _visualizer;
  AudioPlayer? _outputPlayer;
  Timer? _levelTimer;

  Future<void> setCaptureVolume(double volume) async {
    // Input-test levels are scaled in app state. Do not write the local
    // capture track volume here: on desktop that can leak into system mic gain.
  }

  Future<void> setPlaybackVolume(double volume) async {
    final player = _outputPlayer;
    if (player == null) return;
    await player.setVolume(normalizedAudioVolume(volume));
  }

  Future<void> dispose() async {
    final visualizer = _visualizer;
    final player = _outputPlayer;
    final levelTimer = _levelTimer;
    final track = _track;
    _visualizer = null;
    _outputPlayer = null;
    _levelTimer = null;
    _track = null;
    levelTimer?.cancel();
    await visualizer?.dispose();
    await _disposeOutputPlayer(player);
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

Future<void> _disposeTestTrack(lk.LocalAudioTrack? track) async {
  if (track == null) return;
  try {
    await track.stop();
  } catch (_) {}
  try {
    await track.dispose();
  } catch (_) {}
}

Future<void> _disposeOutputPlayer(AudioPlayer? player) async {
  if (player == null) return;
  try {
    await player.stop();
  } catch (_) {}
  try {
    await player.dispose();
  } catch (_) {}
}

final Uint8List _outputTestToneWav = _buildOutputTestToneWav();

Uint8List _buildOutputTestToneWav() {
  const sampleRate = 48000;
  const durationMs = 500;
  const frequency = 1000.0;
  const amplitude = 0.22;
  final samples = sampleRate * durationMs ~/ 1000;
  final dataByteCount = samples * 2;
  final bytes = Uint8List(44 + dataByteCount);
  final data = ByteData.sublistView(bytes);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i += 1) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + dataByteCount, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataByteCount, Endian.little);

  for (var i = 0; i < samples; i += 1) {
    final sample =
        math.sin(2 * math.pi * frequency * i / sampleRate) * amplitude;
    data.setInt16(44 + i * 2, (sample * 32767).round(), Endian.little);
  }

  return bytes;
}
