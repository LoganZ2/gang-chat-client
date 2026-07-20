import 'dart:math' as math;
import 'dart:typed_data';

class SynthesizedToneNote {
  const SynthesizedToneNote({
    required this.frequency,
    required this.duration,
    this.gapAfter = 0,
  });

  final double frequency;
  final double duration;
  final double gapAfter;
}

/// Builds a mono 16-bit PCM WAV cue with the same soft harmonic envelope used
/// by Gang Chat's short local notification sounds.
Uint8List buildSynthesizedToneWav({
  required List<SynthesizedToneNote> notes,
  int sampleRate = 44100,
  double tailDuration = 0.025,
  double amplitude = 0.24,
}) {
  if (notes.isEmpty) throw ArgumentError.value(notes, 'notes');
  if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
  if (tailDuration < 0) {
    throw ArgumentError.value(tailDuration, 'tailDuration');
  }
  for (final note in notes) {
    if (note.frequency <= 0 || note.duration <= 0 || note.gapAfter < 0) {
      throw ArgumentError.value(note, 'notes');
    }
  }

  final totalDuration = notes.fold<double>(
    tailDuration,
    (total, note) => total + note.duration + note.gapAfter,
  );
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

  for (var frame = 0; frame < frameCount; frame += 1) {
    final time = frame / sampleRate;
    var noteStart = 0.0;
    var sample = 0.0;
    for (final note in notes) {
      final noteEnd = noteStart + note.duration;
      if (time >= noteStart && time < noteEnd) {
        sample = noteSample(time - noteStart, note.duration, note.frequency);
        break;
      }
      noteStart = noteEnd + note.gapAfter;
    }
    final pcm = (sample * amplitude * 32767).round().clamp(-32768, 32767);
    data.setInt16(44 + frame * 2, pcm, Endian.little);
  }
  return bytes;
}
