import 'package:client/src/shell/android_display_rotation_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('normalizes Android display rotation values', () {
    expect(normalizeDisplayRotationQuarterTurns(null), 0);
    expect(normalizeDisplayRotationQuarterTurns(-1), 0);
    expect(normalizeDisplayRotationQuarterTurns(0), 0);
    expect(normalizeDisplayRotationQuarterTurns(1), 1);
    expect(normalizeDisplayRotationQuarterTurns(2), 2);
    expect(normalizeDisplayRotationQuarterTurns(3), 3);
    expect(normalizeDisplayRotationQuarterTurns(4), 0);
  });

  test('counter rotation handles both Android landscape directions', () {
    expect(counterDisplayRotationQuarterTurns(0), 0);
    expect(counterDisplayRotationQuarterTurns(1), 3);
    expect(counterDisplayRotationQuarterTurns(2), 2);
    expect(counterDisplayRotationQuarterTurns(3), 1);
  });

  test('service reads display rotation from the Android channel', () async {
    const channel = MethodChannel('test/display_orientation');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getDisplayRotation');
      return 3;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final service = AndroidDisplayRotationService(channel: channel);

    expect(await service.currentQuarterTurns(), 3);
  });
}
