import 'package:client/src/app/network_latency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies latency into unavailable, good, fair, and poor bands', () {
    expect(networkLatencyQuality(null), NetworkLatencyQuality.unavailable);
    expect(
      networkLatencyQuality(const Duration(milliseconds: 150)),
      NetworkLatencyQuality.good,
    );
    expect(
      networkLatencyQuality(const Duration(milliseconds: 151)),
      NetworkLatencyQuality.fair,
    );
    expect(
      networkLatencyQuality(const Duration(milliseconds: 350)),
      NetworkLatencyQuality.fair,
    );
    expect(
      networkLatencyQuality(const Duration(milliseconds: 351)),
      NetworkLatencyQuality.poor,
    );
  });

  test('maps latency bands to signal bar counts and tooltip text', () {
    expect(networkLatencySignalBars(null), 0);
    expect(networkLatencySignalBars(const Duration(milliseconds: 80)), 3);
    expect(networkLatencySignalBars(const Duration(milliseconds: 220)), 2);
    expect(networkLatencySignalBars(const Duration(milliseconds: 620)), 1);

    expect(networkLatencyTooltip(null), '延迟检测中');
    expect(networkLatencyTooltip(const Duration(milliseconds: 228)), '228 ms');
  });
}
