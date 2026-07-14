import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/live/live_presence_sound_service.dart';

void main() {
  test('join cue rises and leave cue falls', () {
    final joined = livePresenceSoundNoteFrequencies(LivePresenceSound.joined);
    final left = livePresenceSoundNoteFrequencies(LivePresenceSound.left);

    expect(joined.first, lessThan(joined.last));
    expect(left.first, greaterThan(left.last));
    expect(left, joined.reversed);
  });

  test('presence cues are valid mono PCM WAV data', () {
    for (final sound in LivePresenceSound.values) {
      final bytes = buildLivePresenceTone(sound);
      final data = ByteData.sublistView(bytes);

      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(data.getUint16(20, Endian.little), 1);
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), 44100);
      expect(data.getUint16(34, Endian.little), 16);
      expect(data.getUint32(40, Endian.little), bytes.length - 44);
      expect(bytes.length, greaterThan(20000));
    }
  });
}
