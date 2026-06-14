import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/live/mac_audio_devices.dart';

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

    final service = MacAudioDevices();
    addTearDown(service.dispose);

    expect(await service.currentDeviceId(), 'mic_2');
  });

  test('currentDeviceId swallows native failures', () async {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (
      call,
    ) async {
      throw PlatformException(code: 'unavailable');
    });

    final service = MacAudioDevices();
    addTearDown(service.dispose);

    expect(await service.currentDeviceId(), isNull);
  });

  test('enumerateInputs maps the native list to audioinput devices', () async {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (
      call,
    ) async {
      if (call.method == 'enumerateInputs') {
        return [
          {'deviceId': '87', 'label': '内建麦克风', 'isDefault': true},
          {'deviceId': '92', 'label': 'USB Mic', 'isDefault': false},
          // Entries without a deviceId are dropped.
          {'deviceId': '', 'label': 'broken', 'isDefault': false},
        ];
      }
      return null;
    });

    final service = MacAudioDevices();
    addTearDown(service.dispose);

    final inputs = await service.enumerateInputs();
    expect(inputs.map((d) => d.deviceId), ['87', '92']);
    expect(inputs.map((d) => d.label), ['内建麦克风', 'USB Mic']);
    expect(inputs.every((d) => d.kind == 'audioinput'), isTrue);
  });

  test('enumerateInputs returns empty when the native side fails', () async {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (
      call,
    ) async {
      throw PlatformException(code: 'unavailable');
    });

    final service = MacAudioDevices();
    addTearDown(service.dispose);

    expect(await service.enumerateInputs(), isEmpty);
  });

  test('enumerateOutputs maps the native list to audiooutput devices', () async {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (
      call,
    ) async {
      if (call.method == 'enumerateOutputs') {
        return [
          {'deviceId': '54', 'label': '内建扬声器', 'isDefault': true},
          {'deviceId': '61', 'label': 'USB Speaker', 'isDefault': false},
          // Entries without a deviceId are dropped.
          {'deviceId': '', 'label': 'broken', 'isDefault': false},
        ];
      }
      return null;
    });

    final service = MacAudioDevices();
    addTearDown(service.dispose);

    final outputs = await service.enumerateOutputs();
    expect(outputs.map((d) => d.deviceId), ['54', '61']);
    expect(outputs.map((d) => d.label), ['内建扬声器', 'USB Speaker']);
    expect(outputs.every((d) => d.kind == 'audiooutput'), isTrue);
  });

  test('enumerateOutputs returns empty when the native side fails', () async {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (
      call,
    ) async {
      throw PlatformException(code: 'unavailable');
    });

    final service = MacAudioDevices();
    addTearDown(service.dispose);

    expect(await service.enumerateOutputs(), isEmpty);
  });

  test('changes emits the new default when the native side notifies', () async {
    final startCalls = <String>[];
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), (
      call,
    ) async {
      startCalls.add(call.method);
      return null;
    });

    final service = MacAudioDevices();
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
