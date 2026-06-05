import 'audio_device_display.dart';
import 'audio_levels.dart';

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

class RestoredAudioDevices<T> {
  const RestoredAudioDevices({this.input, this.output});

  final T? input;
  final T? output;
}

T? preferredStoredAudioDeviceFrom<T>(
  List<T> devices, {
  required String kind,
  required String? storedDeviceId,
  required AudioDeviceKindOf<T> kindOf,
  required AudioDeviceIdOf<T> deviceIdOf,
}) {
  final storedDevice = storedAudioDeviceFrom(
    devices,
    kind: kind,
    deviceId: storedDeviceId,
    kindOf: kindOf,
    deviceIdOf: deviceIdOf,
  );
  if (storedDevice != null) return storedDevice;

  // WebRTC exposes the OS-selected device as the synthetic "default" device
  // on desktop. Use it whenever there is no local preference yet, or when the
  // saved device is temporarily unavailable.
  return storedAudioDeviceFrom(
    devices,
    kind: kind,
    deviceId: 'default',
    kindOf: kindOf,
    deviceIdOf: deviceIdOf,
  );
}

T? storedAudioDeviceFrom<T>(
  List<T> devices, {
  required String kind,
  required String? deviceId,
  required AudioDeviceKindOf<T> kindOf,
  required AudioDeviceIdOf<T> deviceIdOf,
}) {
  if (deviceId == null || deviceId.isEmpty) return null;
  for (final device in devices) {
    if (kindOf(device) == kind && deviceIdOf(device) == deviceId) {
      return device;
    }
  }
  return null;
}

Future<T?> selectStoredAudioDeviceIfChanged<T>({
  required T? selected,
  required T device,
  required Future<void> Function(T device) select,
  required AudioDeviceKindOf<T> kindOf,
  required AudioDeviceIdOf<T> deviceIdOf,
}) async {
  if (isSameAudioDevice(
    selected,
    device,
    kindOf: kindOf,
    deviceIdOf: deviceIdOf,
  )) {
    return device;
  }
  try {
    await select(device);
    return device;
  } catch (_) {
    return null;
  }
}

String? storedAudioDeviceIdFromStorageValue(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

double storedAudioVolumeFromStorageValue(String? value) {
  final parsed = double.tryParse(value ?? '');
  if (parsed == null) return 1.0;
  return normalizedAudioVolume(parsed);
}

String audioVolumeStorageString(double volume) {
  return normalizedAudioVolume(volume).toStringAsFixed(3);
}
