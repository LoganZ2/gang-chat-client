import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/live/system_default_audio_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'gang_chat/audio_devices';
  final messenger = TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(channelName),
      null,
    );
  });

  test('currentDeviceId returns the native default input id', () async {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (
      call,
    ) async {
      if (call.method == 'getDefaultInputDeviceId') return 'mic_2';
      return null;
    });

    final service = SystemDefaultAudioInput();
    addTearDown(service.dispose);

    expect(await service.currentDeviceId(), 'mic_2');
  });

  test('currentDeviceId swallows native failures', () async {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (
      call,
    ) async {
      throw PlatformException(code: 'unavailable');
    });

    final service = SystemDefaultAudioInput();
    addTearDown(service.dispose);

    expect(await service.currentDeviceId(), isNull);
  });

  test('changes emits the new default when the native side notifies', () async {
    final startCalls = <String>[];
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (
      call,
    ) async {
      startCalls.add(call.method);
      return null;
    });

    final service = SystemDefaultAudioInput();
    addTearDown(service.dispose);

    final emissions = <String?>[];
    final sub = service.changes.listen(emissions.add);
    addTearDown(sub.cancel);

    // Subscribing asks the native side to start observing.
    await Future<void>.delayed(Duration.zero);
    expect(startCalls, contains('startListening'));

    // Simulate the native channel pushing a default-device change.
    await messenger.handlePlatformMessage(
      channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('defaultInputDeviceChanged', 'mic_3'),
      ),
      (_) {},
    );

    expect(emissions, ['mic_3']);
  });
}
