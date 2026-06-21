import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import '../app/audio_levels.dart';

class AudioTestService {
  Future<AudioTestHandle> startInputTest({
    required String? inputDeviceId,
    required double volume,
    required void Function(double level) onLevel,
  }) async {
    lk.LocalAudioTrack? track;
    _StartedInputLevelSampler? levelSampler;
    try {
      track = await _createTestAudioTrack(inputDeviceId);
      levelSampler = await _startInputLevelSampler(track, onLevel);
      return AudioTestHandle._(track: track, inputLevelSampler: levelSampler);
    } catch (_) {
      await levelSampler?.dispose();
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
    _StartedInputLevelSampler? inputLevelSampler,
    AudioPlayer? outputPlayer,
    Timer? levelTimer,
  }) : _track = track,
       _inputLevelSampler = inputLevelSampler,
       _outputPlayer = outputPlayer,
       _levelTimer = levelTimer;

  lk.LocalAudioTrack? _track;
  _StartedInputLevelSampler? _inputLevelSampler;
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
    final inputLevelSampler = _inputLevelSampler;
    final player = _outputPlayer;
    final levelTimer = _levelTimer;
    final track = _track;
    _inputLevelSampler = null;
    _outputPlayer = null;
    _levelTimer = null;
    _track = null;
    levelTimer?.cancel();
    await inputLevelSampler?.dispose();
    await _disposeOutputPlayer(player);
    await _disposeTestTrack(track);
  }
}

class _StartedInputLevelSampler {
  _StartedInputLevelSampler({
    required this.senderPeerConnection,
    required this.receiverPeerConnection,
    required this.sender,
    required this.timer,
    required this.onLevel,
  });

  final rtc.RTCPeerConnection senderPeerConnection;
  final rtc.RTCPeerConnection receiverPeerConnection;
  final rtc.RTCRtpSender sender;
  final Timer timer;
  final void Function(double level) onLevel;

  double? _previousEnergy;
  double? _previousDuration;
  bool _sampling = false;

  Future<void> sample() async {
    if (_sampling) return;
    _sampling = true;
    try {
      final reports = await sender.getStats();
      final level = _audioLevelFromStats(reports);
      if (level != null) {
        onLevel(level);
      }
    } catch (_) {
      // Keep the mic test alive even if a stats poll fails once.
    } finally {
      _sampling = false;
    }
  }

  Future<void> dispose() async {
    timer.cancel();
    try {
      await senderPeerConnection.removeTrack(sender);
    } catch (_) {}
    await _disposePeerConnection(senderPeerConnection);
    await _disposePeerConnection(receiverPeerConnection);
  }

  double? _audioLevelFromStats(List<rtc.StatsReport> reports) {
    double? directLevel;
    double? totalEnergy;
    double? totalDuration;

    for (final report in reports) {
      final values = report.values;
      final rawLevel = values['audioLevel'];
      if (rawLevel is num && rawLevel.isFinite) {
        directLevel = math.max(directLevel ?? 0, rawLevel.toDouble());
      }

      final rawEnergy = values['totalAudioEnergy'];
      final rawDuration = values['totalSamplesDuration'];
      if (rawEnergy is num && rawDuration is num) {
        final energy = rawEnergy.toDouble();
        final duration = rawDuration.toDouble();
        if (energy.isFinite && duration.isFinite) {
          totalEnergy = energy;
          totalDuration = duration;
        }
      }
    }

    double? energyLevel;
    final previousEnergy = _previousEnergy;
    final previousDuration = _previousDuration;
    if (totalEnergy != null && totalDuration != null) {
      _previousEnergy = totalEnergy;
      _previousDuration = totalDuration;

      if (previousEnergy != null && previousDuration != null) {
        final energyDelta = totalEnergy - previousEnergy;
        final durationDelta = totalDuration - previousDuration;
        if (!energyDelta.isFinite ||
            !durationDelta.isFinite ||
            energyDelta <= 0 ||
            durationDelta <= 0) {
          energyLevel = 0;
        } else {
          energyLevel = math.sqrt(energyDelta / durationDelta);
        }
      }
    }

    if (directLevel == null && energyLevel == null) return null;
    return _displayAudioLevel(math.max(directLevel ?? 0, energyLevel ?? 0));
  }
}

Future<_StartedInputLevelSampler> _startInputLevelSampler(
  lk.LocalAudioTrack track,
  void Function(double level) onLevel,
) async {
  rtc.RTCPeerConnection? senderPeerConnection;
  rtc.RTCPeerConnection? receiverPeerConnection;
  rtc.RTCRtpSender? sender;
  Timer? timer;
  try {
    senderPeerConnection = await rtc.createPeerConnection(
      _inputLevelPeerConnectionConfiguration,
    );
    receiverPeerConnection = await rtc.createPeerConnection(
      _inputLevelPeerConnectionConfiguration,
    );

    final loopbackIce = _InputLevelLoopbackIce(
      senderPeerConnection: senderPeerConnection,
      receiverPeerConnection: receiverPeerConnection,
    );

    sender = await senderPeerConnection.addTrack(
      track.mediaStreamTrack,
      track.mediaStream,
    );
    await _negotiateInputLevelLoopback(
      senderPeerConnection: senderPeerConnection,
      receiverPeerConnection: receiverPeerConnection,
      loopbackIce: loopbackIce,
    );

    late final _StartedInputLevelSampler sampler;
    timer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => unawaited(sampler.sample()),
    );
    sampler = _StartedInputLevelSampler(
      senderPeerConnection: senderPeerConnection,
      receiverPeerConnection: receiverPeerConnection,
      sender: sender,
      timer: timer,
      onLevel: onLevel,
    );
    onLevel(0);
    unawaited(sampler.sample());
    return sampler;
  } catch (_) {
    timer?.cancel();
    if (sender != null && senderPeerConnection != null) {
      try {
        await senderPeerConnection.removeTrack(sender);
      } catch (_) {}
    }
    await _disposePeerConnection(senderPeerConnection);
    await _disposePeerConnection(receiverPeerConnection);
    rethrow;
  }
}

const _inputLevelPeerConnectionConfiguration = {
  'iceServers': <Object>[],
  'sdpSemantics': 'unified-plan',
};

class _InputLevelLoopbackIce {
  _InputLevelLoopbackIce({
    required this.senderPeerConnection,
    required this.receiverPeerConnection,
  }) {
    senderPeerConnection.onIceCandidate = (candidate) {
      if (_receiverCanAcceptCandidates) {
        unawaited(_addIceCandidate(receiverPeerConnection, candidate));
      } else {
        _pendingSenderCandidates.add(candidate);
      }
    };
    receiverPeerConnection.onIceCandidate = (candidate) {
      if (_senderCanAcceptCandidates) {
        unawaited(_addIceCandidate(senderPeerConnection, candidate));
      } else {
        _pendingReceiverCandidates.add(candidate);
      }
    };
    receiverPeerConnection.onAddTrack = (_, track) {
      track.enabled = false;
    };
    receiverPeerConnection.onTrack = (event) {
      event.track.enabled = false;
    };
  }

  final rtc.RTCPeerConnection senderPeerConnection;
  final rtc.RTCPeerConnection receiverPeerConnection;
  final _pendingSenderCandidates = <rtc.RTCIceCandidate>[];
  final _pendingReceiverCandidates = <rtc.RTCIceCandidate>[];
  bool _receiverCanAcceptCandidates = false;
  bool _senderCanAcceptCandidates = false;

  void markReceiverCanAcceptCandidates() {
    _receiverCanAcceptCandidates = true;
    unawaited(
      _flushIceCandidates(receiverPeerConnection, _pendingSenderCandidates),
    );
  }

  void markSenderCanAcceptCandidates() {
    _senderCanAcceptCandidates = true;
    unawaited(
      _flushIceCandidates(senderPeerConnection, _pendingReceiverCandidates),
    );
  }
}

Future<void> _negotiateInputLevelLoopback({
  required rtc.RTCPeerConnection senderPeerConnection,
  required rtc.RTCPeerConnection receiverPeerConnection,
  required _InputLevelLoopbackIce loopbackIce,
}) async {
  final offer = await senderPeerConnection.createOffer({});
  await senderPeerConnection.setLocalDescription(offer);
  await receiverPeerConnection.setRemoteDescription(offer);
  loopbackIce.markReceiverCanAcceptCandidates();

  final answer = await receiverPeerConnection.createAnswer({});
  await receiverPeerConnection.setLocalDescription(answer);
  await senderPeerConnection.setRemoteDescription(answer);
  loopbackIce.markSenderCanAcceptCandidates();
}

Future<void> _flushIceCandidates(
  rtc.RTCPeerConnection peerConnection,
  List<rtc.RTCIceCandidate> candidates,
) async {
  final pending = List<rtc.RTCIceCandidate>.of(candidates);
  candidates.clear();
  for (final candidate in pending) {
    await _addIceCandidate(peerConnection, candidate);
  }
}

Future<void> _addIceCandidate(
  rtc.RTCPeerConnection peerConnection,
  rtc.RTCIceCandidate candidate,
) async {
  try {
    await peerConnection.addCandidate(candidate);
  } catch (_) {}
}

Future<void> _disposePeerConnection(
  rtc.RTCPeerConnection? peerConnection,
) async {
  if (peerConnection == null) return;
  peerConnection.onIceCandidate = null;
  peerConnection.onAddTrack = null;
  peerConnection.onTrack = null;
  try {
    await peerConnection.close();
  } catch (_) {}
  try {
    await peerConnection.dispose();
  } catch (_) {}
}

double _displayAudioLevel(double rawLevel) {
  const noiseFloor = 0.015;
  const displayGain = 2.2;
  if (!rawLevel.isFinite || rawLevel <= noiseFloor) return 0;
  final normalized = (rawLevel - noiseFloor) / (1 - noiseFloor);
  return (normalized * displayGain).clamp(0.0, 1.0).toDouble();
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
