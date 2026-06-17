import 'audio_device_display.dart';
import 'audio_levels.dart';
import '../live/screen_share_quality.dart';

class StoredAudioDevices {
  const StoredAudioDevices({
    this.inputDeviceId,
    this.outputDeviceId,
    this.inputVolume = 1.0,
    this.outputVolume = 1.0,
    this.musicBoxVolume = 1.0,
    this.screenShareVolume = 1.0,
    this.screenShareMaxHeight = defaultScreenShareMaxHeight,
  });

  final String? inputDeviceId;
  final String? outputDeviceId;
  final double inputVolume;
  final double outputVolume;

  /// Local listening volume for the music box bot's audio track. Independent of
  /// [outputVolume] — it scales only the `__musicbox__` participant.
  final double musicBoxVolume;

  /// Local listening volume for remote screen-share audio. Independent of
  /// [outputVolume], which scales ordinary voice tracks.
  final double screenShareVolume;

  /// Target max height (px) for the local screen share — one of
  /// [screenShareHeightOptions]. [defaultScreenShareMaxHeight] sends at native
  /// resolution; lower values cap what we publish to save bandwidth.
  final int screenShareMaxHeight;

  bool get isEmpty =>
      (inputDeviceId == null || inputDeviceId!.isEmpty) &&
      (outputDeviceId == null || outputDeviceId!.isEmpty) &&
      inputVolume == 1.0 &&
      outputVolume == 1.0 &&
      musicBoxVolume == 1.0 &&
      screenShareVolume == 1.0 &&
      screenShareMaxHeight == defaultScreenShareMaxHeight;
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
  String? systemDefaultDeviceId,
}) {
  final storedDevice = storedAudioDeviceFrom(
    devices,
    kind: kind,
    deviceId: storedDeviceId,
    kindOf: kindOf,
    deviceIdOf: deviceIdOf,
  );
  if (storedDevice != null) return storedDevice;

  // macOS never enumerates a synthetic "default" device, so the OS-selected
  // device is identified by an explicit id from the native channel. Prefer it
  // when there is no local preference yet so the picker follows the system.
  final systemDefault = storedAudioDeviceFrom(
    devices,
    kind: kind,
    deviceId: systemDefaultDeviceId,
    kindOf: kindOf,
    deviceIdOf: deviceIdOf,
  );
  if (systemDefault != null) return systemDefault;

  // WebRTC exposes the OS-selected device as the synthetic "default" device
  // on Windows. Use it whenever there is no local preference yet, or when the
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
