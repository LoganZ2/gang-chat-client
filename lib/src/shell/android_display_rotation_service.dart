import 'package:flutter/services.dart';

typedef AndroidDisplayRotationReader = Future<int> Function();

/// Reads Android's current display rotation as quarter turns from its natural
/// orientation. Callers are responsible for restricting use to Android.
class AndroidDisplayRotationService {
  AndroidDisplayRotationService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('gang_chat/display_orientation');

  final MethodChannel _channel;

  Future<int> currentQuarterTurns() async {
    final value = await _channel.invokeMethod<int>('getDisplayRotation');
    return normalizeDisplayRotationQuarterTurns(value);
  }
}

int normalizeDisplayRotationQuarterTurns(int? value) {
  return switch (value) {
    1 => 1,
    2 => 2,
    3 => 3,
    _ => 0,
  };
}

/// Counter-rotation that keeps a frozen portrait frame fixed while Android's
/// display surface rotates underneath the image-preview route.
int counterDisplayRotationQuarterTurns(int displayQuarterTurns) {
  final normalized = normalizeDisplayRotationQuarterTurns(displayQuarterTurns);
  return (4 - normalized) % 4;
}
