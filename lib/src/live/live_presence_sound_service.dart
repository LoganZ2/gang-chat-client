import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LivePresenceSound { joined, left }

abstract interface class LivePresenceSoundPlayer {
  Future<void> play(LivePresenceSound sound, {required double volume});

  Future<void> dispose();
}

/// Plays short, locally generated voice-channel presence cues.
///
/// The tones are synthesized into WAV data so the cue is available on every
/// supported platform without another network request or a binary asset.
class LivePresenceSoundService implements LivePresenceSoundPlayer {
  LivePresenceSoundService({AudioPlayer? joinedPlayer, AudioPlayer? leftPlayer})
    : _joinedPlayer = joinedPlayer ?? AudioPlayer(),
      _leftPlayer = leftPlayer ?? AudioPlayer();

  final AudioPlayer _joinedPlayer;
  final AudioPlayer _leftPlayer;
  bool _disposed = false;
  Future<String>? _joinedFilePath;
  Future<String>? _leftFilePath;

  static final Uint8List _joinedTone = buildLivePresenceTone(
    LivePresenceSound.joined,
  );
  static final Uint8List _leftTone = buildLivePresenceTone(
    LivePresenceSound.left,
  );

  @override
  Future<void> play(LivePresenceSound sound, {required double volume}) async {
    if (_disposed) return;
    final normalizedVolume = volume.clamp(0.0, 1.0).toDouble();
    if (normalizedVolume <= 0) return;
    final player = sound == LivePresenceSound.joined
        ? _joinedPlayer
        : _leftPlayer;
    final bytes = sound == LivePresenceSound.joined ? _joinedTone : _leftTone;
    await player.stop();
    await player.play(
      await _sourceFor(sound, bytes),
      volume: normalizedVolume,
      mode: PlayerMode.lowLatency,
    );
  }

  Future<Source> _sourceFor(LivePresenceSound sound, Uint8List bytes) async {
    if (kIsWeb || !Platform.isWindows) {
      return BytesSource(bytes, mimeType: 'audio/wav');
    }
    final pathFuture = sound == LivePresenceSound.joined
        ? (_joinedFilePath ??= _writeWindowsToneFile(sound, bytes))
        : (_leftFilePath ??= _writeWindowsToneFile(sound, bytes));
    return DeviceFileSource(await pathFuture, mimeType: 'audio/wav');
  }

  Future<String> _writeWindowsToneFile(
    LivePresenceSound sound,
    Uint8List bytes,
  ) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}\\gang_chat_live_${sound.name}_presence.wav',
    );
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait<void>([
      _joinedPlayer.dispose().catchError((_) {}),
      _leftPlayer.dispose().catchError((_) {}),
    ]);
  }
}

List<double> livePresenceSoundNoteFrequencies(LivePresenceSound sound) {
  const rising = <double>[523.25, 783.99];
  return sound == LivePresenceSound.joined
      ? rising
      : rising.reversed.toList(growable: false);
}

Uint8List buildLivePresenceTone(
  LivePresenceSound sound, {
  int sampleRate = 44100,
}) {
  final notes = livePresenceSoundNoteFrequencies(sound);
  const firstNoteDuration = 0.105;
  const gapDuration = 0.022;
  const secondNoteDuration = 0.155;
  const tailDuration = 0.025;
  const totalDuration =
      firstNoteDuration + gapDuration + secondNoteDuration + tailDuration;
  final frameCount = (sampleRate * totalDuration).round();
  final pcmLength = frameCount * 2;
  final bytes = Uint8List(44 + pcmLength);
  final data = ByteData.sublistView(bytes);

  void writeAscii(int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + pcmLength, Endian.little);
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
  data.setUint32(40, pcmLength, Endian.little);

  double noteSample(double localTime, double duration, double frequency) {
    if (localTime < 0 || localTime >= duration) return 0;
    const attackDuration = 0.008;
    const releaseDuration = 0.045;
    final attack = (localTime / attackDuration).clamp(0.0, 1.0);
    final release = ((duration - localTime) / releaseDuration).clamp(0.0, 1.0);
    final envelope = math.sin(math.pi * 0.5 * math.min(attack, release));
    final phase = 2 * math.pi * frequency * localTime;
    return envelope *
        (math.sin(phase) +
            0.16 * math.sin(phase * 2) +
            0.04 * math.sin(phase * 3));
  }

  final secondNoteStart = firstNoteDuration + gapDuration;
  for (var frame = 0; frame < frameCount; frame += 1) {
    final time = frame / sampleRate;
    final sample = time < firstNoteDuration
        ? noteSample(time, firstNoteDuration, notes[0])
        : noteSample(time - secondNoteStart, secondNoteDuration, notes[1]);
    final pcm = (sample * 0.24 * 32767).round().clamp(-32768, 32767);
    data.setInt16(44 + frame * 2, pcm, Endian.little);
  }
  return bytes;
}
