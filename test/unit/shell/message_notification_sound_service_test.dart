import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/shell/message_notification_sound_service.dart';

void main() {
  test('message notification cue uses a short rising phrase', () {
    final frequencies = messageNotificationSoundFrequencies();

    expect(frequencies, hasLength(2));
    expect(frequencies.first, lessThan(frequencies.last));
  });

  test('message notification cue is valid mono PCM WAV data', () {
    final bytes = buildMessageNotificationTone();
    final data = ByteData.sublistView(bytes);

    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(20, Endian.little), 1);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 44100);
    expect(data.getUint16(34, Endian.little), 16);
    expect(data.getUint32(40, Endian.little), bytes.length - 44);
    expect(bytes.length, greaterThan(15000));
  });
}
