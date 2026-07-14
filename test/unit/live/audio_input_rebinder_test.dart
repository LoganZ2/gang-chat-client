import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/audio_device_info.dart';
import 'package:client/src/app/audio_device_store.dart';
import 'package:client/src/live/audio_device_service.dart';
import 'package:client/src/live/audio_input_rebinder.dart';
import 'package:client/src/live/system_audio_devices.dart';

void main() {
  test('rebinds input on a device change', () async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    final rebound = <String?>[];

    final rebinder = AudioInputRebinder(
      deviceChanges: changes.stream,
      currentInputDeviceId: () async => 'mic_1',
      rebindInput: (id) async => rebound.add(id),
      debounce: const Duration(milliseconds: 10),
    );
    addTearDown(rebinder.stop);
    rebinder.start();

    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(rebound, ['mic_1']);
  });

  test('coalesces a burst of changes into a single input rebind', () async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    var rebounds = 0;

    final rebinder = AudioInputRebinder(
      deviceChanges: changes.stream,
      currentInputDeviceId: () async => 'headset_mic',
      rebindInput: (_) async => rebounds += 1,
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(rebinder.stop);
    rebinder.start();

    changes
      ..add(null)
      ..add(null)
      ..add(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(rebounds, 1);
  });

  test('treats later same-device changes as fresh input rebinds', () async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    final rebound = <String?>[];

    final rebinder = AudioInputRebinder(
      deviceChanges: changes.stream,
      currentInputDeviceId: () async => 'headset_mic',
      rebindInput: (id) async => rebound.add(id),
      debounce: const Duration(milliseconds: 10),
    );
    addTearDown(rebinder.stop);
    rebinder.start();

    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(rebound, ['headset_mic', 'headset_mic']);
  });

  test('queues changes that arrive while an input rebind is running', () async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    final firstStarted = Completer<void>();
    final finishFirst = Completer<void>();
    var attempts = 0;

    final rebinder = AudioInputRebinder(
      deviceChanges: changes.stream,
      currentInputDeviceId: () async => 'headset_mic',
      rebindInput: (_) async {
        attempts += 1;
        if (attempts == 1) {
          firstStarted.complete();
          await finishFirst.future;
        }
      },
      debounce: const Duration(milliseconds: 10),
    );
    addTearDown(rebinder.stop);
    rebinder.start();

    changes.add(null);
    await firstStarted.future;
    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    finishFirst.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(attempts, 2);
  });

  test(
    'a failed input rebind is swallowed and does not block later ones',
    () async {
      final changes = StreamController<void>.broadcast();
      addTearDown(changes.close);
      var attempts = 0;

      final rebinder = AudioInputRebinder(
        deviceChanges: changes.stream,
        currentInputDeviceId: () async => 'headset_mic',
        rebindInput: (_) async {
          attempts += 1;
          if (attempts == 1) throw StateError('device vanished');
        },
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(rebinder.stop);
      rebinder.start();

      changes.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      changes.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(attempts, 2);
    },
  );

  test('stop cancels a pending input rebind', () async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    var rebounds = 0;

    final rebinder = AudioInputRebinder(
      deviceChanges: changes.stream,
      currentInputDeviceId: () async => 'mic_1',
      rebindInput: (_) async => rebounds += 1,
      debounce: const Duration(milliseconds: 30),
    );
    rebinder.start();

    changes.add(null);
    await rebinder.stop();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(rebounds, 0);
  });

  test('preferredLiveInputDeviceId restores hotplugged input by signature', () {
    const defaultMic = AudioDeviceInfo(
      deviceId: 'default_mic',
      label: 'Default Mic',
      kind: 'audioinput',
      groupId: 'group_default',
    );
    const repluggedHeadset = AudioDeviceInfo(
      deviceId: 'headset_new',
      label: 'Bluetooth Headset',
      kind: 'audioinput',
      groupId: 'group_headset',
    );

    expect(
      preferredLiveInputDeviceId(
        audioDeviceStore: _FakeAudioDeviceStore(
          inputDeviceId: 'headset_old',
          inputDeviceLabel: 'Bluetooth Headset',
          inputDeviceGroupId: 'group_headset',
        ),
        audioDevices: _FakeLiveAudioDeviceService(
          devices: const [defaultMic, repluggedHeadset],
        ),
        systemAudio: _FakeSystemAudioDevices(inputDeviceId: 'default_mic'),
      ),
      completion('headset_new'),
    );
  });

  test('preferredLiveInputDeviceId falls back to system default input', () {
    const defaultMic = AudioDeviceInfo(
      deviceId: 'mic_2',
      label: 'Room Mic',
      kind: 'audioinput',
    );

    expect(
      preferredLiveInputDeviceId(
        audioDeviceStore: _FakeAudioDeviceStore(inputDeviceId: 'missing_mic'),
        audioDevices: _FakeLiveAudioDeviceService(devices: const [defaultMic]),
        systemAudio: _FakeSystemAudioDevices(inputDeviceId: 'mic_2'),
      ),
      completion('mic_2'),
    );
  });

  test('preferredLiveInputDeviceId falls back when enumeration fails', () {
    expect(
      preferredLiveInputDeviceId(
        audioDeviceStore: _FakeAudioDeviceStore(inputDeviceId: 'headset_mic'),
        audioDevices: _FakeLiveAudioDeviceService(
          devices: const [],
          enumerateError: StateError('enumerate failed'),
        ),
        systemAudio: _FakeSystemAudioDevices(inputDeviceId: 'default_mic'),
      ),
      completion('default_mic'),
    );
  });
}

class _FakeAudioDeviceStore extends AudioDeviceStore {
  const _FakeAudioDeviceStore({
    this.inputDeviceId,
    this.inputDeviceLabel,
    this.inputDeviceGroupId,
  });

  final String? inputDeviceId;
  final String? inputDeviceLabel;
  final String? inputDeviceGroupId;

  @override
  Future<StoredAudioDevices> read() async {
    return StoredAudioDevices(
      inputDeviceId: inputDeviceId,
      inputDeviceLabel: inputDeviceLabel,
      inputDeviceGroupId: inputDeviceGroupId,
    );
  }
}

class _FakeLiveAudioDeviceService extends LiveAudioDeviceService {
  const _FakeLiveAudioDeviceService({
    required this.devices,
    this.enumerateError,
  });

  final List<AudioDeviceInfo> devices;
  final Object? enumerateError;

  @override
  Future<List<AudioDeviceInfo>> enumerateDevices() async {
    final error = enumerateError;
    if (error != null) throw error;
    return devices;
  }
}

class _FakeSystemAudioDevices extends SystemAudioDevices {
  _FakeSystemAudioDevices({required this.inputDeviceId})
    : super(supported: false);

  final String? inputDeviceId;

  @override
  Future<String?> currentInputDeviceId() async => inputDeviceId;
}
