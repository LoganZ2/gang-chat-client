import 'dart:async';

import 'audio_device_preferences.dart';

export 'audio_device_preferences.dart';

class AudioDeviceStore {
  const AudioDeviceStore();

  Future<StoredAudioDevices> read() {
    throw UnimplementedError('AudioDeviceStore.read must be implemented.');
  }

  Future<void> writeInputDeviceId(String deviceId) {
    throw UnimplementedError(
      'AudioDeviceStore.writeInputDeviceId must be implemented.',
    );
  }

  Future<void> writeOutputDeviceId(String deviceId) {
    throw UnimplementedError(
      'AudioDeviceStore.writeOutputDeviceId must be implemented.',
    );
  }

  Future<void> writeInputVolume(double volume) {
    throw UnimplementedError(
      'AudioDeviceStore.writeInputVolume must be implemented.',
    );
  }

  Future<void> writeOutputVolume(double volume) {
    throw UnimplementedError(
      'AudioDeviceStore.writeOutputVolume must be implemented.',
    );
  }

  Future<void> writeMusicBoxVolume(double volume) {
    throw UnimplementedError(
      'AudioDeviceStore.writeMusicBoxVolume must be implemented.',
    );
  }
}
