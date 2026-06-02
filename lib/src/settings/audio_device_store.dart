import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

class StoredAudioDevices {
  const StoredAudioDevices({
    this.inputDeviceId,
    this.outputDeviceId,
    this.inputVolume = 1.0,
    this.outputVolume = 1.0,
  });

  final String? inputDeviceId;
  final String? outputDeviceId;
  final double inputVolume;
  final double outputVolume;

  bool get isEmpty =>
      (inputDeviceId == null || inputDeviceId!.isEmpty) &&
      (outputDeviceId == null || outputDeviceId!.isEmpty) &&
      inputVolume == 1.0 &&
      outputVolume == 1.0;
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
  static const _inputVolumeKey = 'gang.audioInputVolume';
  static const _outputVolumeKey = 'gang.audioOutputVolume';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  Future<StoredAudioDevices> read() async {
    final values = await Future.wait([
      _storage.read(key: _inputDeviceIdKey),
      _storage.read(key: _outputDeviceIdKey),
      _storage.read(key: _inputVolumeKey),
      _storage.read(key: _outputVolumeKey),
    ]);
    return StoredAudioDevices(
      inputDeviceId: _nonEmpty(values[0]),
      outputDeviceId: _nonEmpty(values[1]),
      inputVolume: _volumeOrDefault(values[2]),
      outputVolume: _volumeOrDefault(values[3]),
    );
  }

  Future<void> writeInputDeviceId(String deviceId) {
    return _storage.write(key: _inputDeviceIdKey, value: deviceId);
  }

  Future<void> writeOutputDeviceId(String deviceId) {
    return _storage.write(key: _outputDeviceIdKey, value: deviceId);
  }

  Future<void> writeInputVolume(double volume) {
    return _storage.write(key: _inputVolumeKey, value: _volumeString(volume));
  }

  Future<void> writeOutputVolume(double volume) {
    return _storage.write(key: _outputVolumeKey, value: _volumeString(volume));
  }
}

Future<RestoredAudioDevices> restoreStoredAudioDevices(
  AudioDeviceStore store, {
  List<lk.MediaDevice>? devices,
}) async {
  final stored = await store.read();
  final availableDevices =
      devices ?? await lk.Hardware.instance.enumerateDevices();
  final input = _preferredAudioDevice(
    availableDevices,
    kind: 'audioinput',
    storedDeviceId: stored.inputDeviceId,
  );
  final output = _preferredAudioDevice(
    availableDevices,
    kind: 'audiooutput',
    storedDeviceId: stored.outputDeviceId,
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

lk.MediaDevice? _preferredAudioDevice(
  List<lk.MediaDevice> devices, {
  required String kind,
  required String? storedDeviceId,
}) {
  final storedDevice = _findDevice(
    devices,
    kind: kind,
    deviceId: storedDeviceId,
  );
  if (storedDevice != null) return storedDevice;

  // WebRTC exposes the OS-selected device as the synthetic "default" device
  // on desktop. Use it whenever there is no local preference yet, or when the
  // saved device is temporarily unavailable.
  return _findDevice(devices, kind: kind, deviceId: 'default');
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

double _volumeOrDefault(String? value) {
  final parsed = double.tryParse(value ?? '');
  if (parsed == null) return 1.0;
  return parsed.clamp(0.0, 1.0).toDouble();
}

String _volumeString(double volume) {
  return volume.clamp(0.0, 1.0).toStringAsFixed(3);
}
