import 'dart:math' as math;

double normalizedAudioVolume(double volume) {
  return volume.clamp(0.0, 1.0).toDouble();
}

String audioVolumePercentText(double volume) {
  return '${(normalizedAudioVolume(volume) * 100).round()}%';
}

int audioLevelSegmentCount(
  double availableWidth, {
  double segmentWidth = 12,
  int minSegments = 24,
  int maxSegments = 56,
}) {
  return (availableWidth / segmentWidth)
      .floor()
      .clamp(minSegments, maxSegments)
      .toInt();
}

int activeAudioLevelSegmentCount({
  required double level,
  required bool active,
  required int segmentCount,
}) {
  if (!active) return 0;
  return (normalizedAudioVolume(level) * segmentCount)
      .ceil()
      .clamp(0, segmentCount)
      .toInt();
}

double audioLevelFromVisualizerBands(Iterable<Object?> bands) {
  const noiseFloor = 0.04;
  const displayGain = 1.45;
  var peak = 0.0;
  var squareSum = 0.0;
  var count = 0;

  for (final value in bands) {
    if (value is! num) continue;
    final raw = value.toDouble();
    if (!raw.isFinite) continue;
    final clamped = raw.clamp(0.0, 1.0).toDouble();
    final sample = clamped <= noiseFloor
        ? 0.0
        : (clamped - noiseFloor) / (1 - noiseFloor);
    if (sample > peak) peak = sample;
    squareSum += sample * sample;
    count++;
  }

  if (count == 0 || peak <= 0) return 0;
  final rms = math.sqrt(squareSum / count);
  final energy = (rms * 0.82) + (peak * 0.18);
  return (energy * displayGain).clamp(0.0, 1.0).toDouble();
}
