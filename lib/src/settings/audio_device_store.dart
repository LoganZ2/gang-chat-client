import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

class StoredAudioDevices {
  const StoredAudioDevices({this.inputDeviceId, this.outputDeviceId});

  final String? inputDeviceId;
  final String? outputDeviceId;

  bool get isEmpty =>
      (inputDeviceId == null || inputDeviceId!.isEmpty) &&
      (outputDeviceId == null || outputDeviceId!.isEmpty);
}

class RestoredAudioDevices {
  const RestoredAudioDevices({this.input, this.output});

  final lk.MediaDevice? input;
  final lk.MediaDevice? output;
}

class AudioDeviceStore {
  const AudioDeviceStore();

  static const _inputDeviceIdKey = 'gang.audioInputDeviceId';
  static const _outputDeviceIdKey = 'gang.audioOutputDeviceId';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  Future<StoredAudioDevices> read() async {
    final values = await Future.wait([
      _storage.read(key: _inputDeviceIdKey),
      _storage.read(key: _outputDeviceIdKey),
    ]);
    return StoredAudioDevices(
      inputDeviceId: _nonEmpty(values[0]),
      outputDeviceId: _nonEmpty(values[1]),
    );
  }

  Future<void> writeInputDeviceId(String deviceId) {
    return _storage.write(key: _inputDeviceIdKey, value: deviceId);
  }

  Future<void> writeOutputDeviceId(String deviceId) {
    return _storage.write(key: _outputDeviceIdKey, value: deviceId);
  }
}

Future<RestoredAudioDevices> restoreStoredAudioDevices(
  AudioDeviceStore store, {
  List<lk.MediaDevice>? devices,
}) async {
  final stored = await store.read();
  if (stored.isEmpty) return const RestoredAudioDevices();

  final availableDevices =
      devices ?? await lk.Hardware.instance.enumerateDevices();
  final input = _findDevice(
    availableDevices,
    kind: 'audioinput',
    deviceId: stored.inputDeviceId,
  );
  final output = _findDevice(
    availableDevices,
    kind: 'audiooutput',
    deviceId: stored.outputDeviceId,
  );

  final restoredInput = input == null
      ? null
      : await _trySelectIfChanged(
          selected: lk.Hardware.instance.selectedAudioInput,
          device: input,
          select: lk.Hardware.instance.selectAudioInput,
        );
  final restoredOutput = output == null
      ? null
      : await _trySelectIfChanged(
          selected: lk.Hardware.instance.selectedAudioOutput,
          device: output,
          select: lk.Hardware.instance.selectAudioOutput,
        );

  return RestoredAudioDevices(input: restoredInput, output: restoredOutput);
}

lk.MediaDevice? storedAudioDeviceFrom(
  List<lk.MediaDevice> devices, {
  required String kind,
  required String? deviceId,
}) {
  return _findDevice(devices, kind: kind, deviceId: deviceId);
}

Future<lk.MediaDevice?> _trySelectIfChanged({
  required lk.MediaDevice? selected,
  required lk.MediaDevice device,
  required Future<void> Function(lk.MediaDevice device) select,
}) async {
  if (selected?.kind == device.kind && selected?.deviceId == device.deviceId) {
    return device;
  }
  try {
    await select(device);
    return device;
  } catch (_) {
    return null;
  }
}

lk.MediaDevice? _findDevice(
  List<lk.MediaDevice> devices, {
  required String kind,
  required String? deviceId,
}) {
  if (deviceId == null || deviceId.isEmpty) return null;
  for (final device in devices) {
    if (device.kind == kind && device.deviceId == deviceId) return device;
  }
  return null;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
