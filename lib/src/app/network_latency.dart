enum NetworkLatencyQuality { unavailable, poor, fair, good }

const lowNetworkLatencyThreshold = Duration(milliseconds: 150);
const fairNetworkLatencyThreshold = Duration(milliseconds: 350);

NetworkLatencyQuality networkLatencyQuality(Duration? latency) {
  if (latency == null) return NetworkLatencyQuality.unavailable;
  if (latency <= lowNetworkLatencyThreshold) return NetworkLatencyQuality.good;
  if (latency <= fairNetworkLatencyThreshold) return NetworkLatencyQuality.fair;
  return NetworkLatencyQuality.poor;
}

int networkLatencySignalBars(Duration? latency) {
  return switch (networkLatencyQuality(latency)) {
    NetworkLatencyQuality.good => 3,
    NetworkLatencyQuality.fair => 2,
    NetworkLatencyQuality.poor => 1,
    NetworkLatencyQuality.unavailable => 0,
  };
}

String networkLatencyTooltip(Duration? latency) {
  if (latency == null) return '延迟检测中';
  return '${latency.inMilliseconds} ms';
}
