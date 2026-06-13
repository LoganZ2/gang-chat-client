import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/live/audio_test_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The probe track can't be created off-device (no platform channel), so
  // withCaptureSession falls straight through to the action. That still lets us
  // exercise the retry loop that covers macOS's lazily-populated device list.
  test('withCaptureSession retries while the result is still empty', () async {
    final service = AudioTestService();
    var calls = 0;

    final result = await service.withCaptureSession<List<String>>(
      () async {
        calls++;
        // Stay "empty" for the first two passes, then report a device.
        return calls < 3 ? const <String>[] : const ['mic_1'];
      },
      retryWhile: (devices) => devices.isEmpty,
      maxAttempts: 5,
      retryDelay: Duration.zero,
    );

    expect(result, ['mic_1']);
    expect(calls, 3);
  });

  test('withCaptureSession stops retrying at maxAttempts', () async {
    final service = AudioTestService();
    var calls = 0;

    final result = await service.withCaptureSession<List<String>>(
      () async {
        calls++;
        return const <String>[];
      },
      retryWhile: (devices) => devices.isEmpty,
      maxAttempts: 4,
      retryDelay: Duration.zero,
    );

    expect(result, isEmpty);
    expect(calls, 4);
  });

  test('withCaptureSession runs the action once without a retry predicate',
      () async {
    final service = AudioTestService();
    var calls = 0;

    await service.withCaptureSession<void>(() async {
      calls++;
    });

    expect(calls, 1);
  });
}
