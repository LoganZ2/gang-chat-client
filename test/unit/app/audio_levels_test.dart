import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/audio_levels.dart';

void main() {
  test('normalizedAudioVolume clamps volume to audio range', () {
    expect(normalizedAudioVolume(-0.2), 0);
    expect(normalizedAudioVolume(0.45), 0.45);
    expect(normalizedAudioVolume(1.7), 1);
  });

  test('audioVolumePercentText formats clamped volume', () {
    expect(audioVolumePercentText(-0.2), '0%');
    expect(audioVolumePercentText(0.455), '46%');
    expect(audioVolumePercentText(1.7), '100%');
  });

  test('participant voice volume supports 200 percent boosts', () {
    expect(normalizedParticipantVoiceVolume(-0.2), 0);
    expect(normalizedParticipantVoiceVolume(1.25), 1.25);
    expect(normalizedParticipantVoiceVolume(3), 2);
    expect(participantVoiceVolumePercentText(1.25), '125%');
    expect(participantVoiceVolumePercentText(3), '200%');
  });

  test('level meter helpers calculate segment counts and active bars', () {
    expect(audioLevelSegmentCount(120), 24);
    expect(audioLevelSegmentCount(420), 35);
    expect(audioLevelSegmentCount(900), 56);

    expect(
      activeAudioLevelSegmentCount(level: 0.31, active: true, segmentCount: 10),
      4,
    );
    expect(
      activeAudioLevelSegmentCount(
        level: 0.31,
        active: false,
        segmentCount: 10,
      ),
      0,
    );
    expect(
      activeAudioLevelSegmentCount(level: 2, active: true, segmentCount: 10),
      10,
    );
  });

  test('audioLevelFromVisualizerBands uses overall audio energy', () {
    expect(audioLevelFromVisualizerBands([0.0, 0.03, null, double.nan]), 0);

    final singleSpike = audioLevelFromVisualizerBands(<Object?>[
      1.0,
      ...List<double>.filled(13, 0.0),
    ]);
    final broadVoice = audioLevelFromVisualizerBands(
      List<double>.filled(14, 0.5),
    );

    expect(singleSpike, greaterThan(0));
    expect(singleSpike, lessThan(0.7));
    expect(broadVoice, greaterThan(singleSpike));
    expect(audioLevelFromVisualizerBands(List<double>.filled(14, 1.0)), 1);
  });
}
