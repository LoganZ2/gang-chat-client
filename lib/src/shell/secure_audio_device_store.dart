import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app/audio_device_store.dart';

class SecureAudioDeviceStore extends AudioDeviceStore {
  const SecureAudioDeviceStore();

  static const _inputDeviceIdKey = 'gang.audioInputDeviceId';
  static const _outputDeviceIdKey = 'gang.audioOutputDeviceId';
  static const _inputVolumeKey = 'gang.audioInputVolume';
  static const _outputVolumeKey = 'gang.audioOutputVolume';
  static const _musicBoxVolumeKey = 'gang.musicBoxVolume';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<StoredAudioDevices> read() async {
    final values = await Future.wait([
      _storage.read(key: _inputDeviceIdKey),
      _storage.read(key: _outputDeviceIdKey),
      _storage.read(key: _inputVolumeKey),
      _storage.read(key: _outputVolumeKey),
      _storage.read(key: _musicBoxVolumeKey),
    ]);
    return StoredAudioDevices(
      inputDeviceId: storedAudioDeviceIdFromStorageValue(values[0]),
      outputDeviceId: storedAudioDeviceIdFromStorageValue(values[1]),
      inputVolume: storedAudioVolumeFromStorageValue(values[2]),
      outputVolume: storedAudioVolumeFromStorageValue(values[3]),
      musicBoxVolume: storedAudioVolumeFromStorageValue(values[4]),
    );
  }

  @override
  Future<void> writeInputDeviceId(String deviceId) {
    return _storage.write(key: _inputDeviceIdKey, value: deviceId);
  }

  @override
  Future<void> writeOutputDeviceId(String deviceId) {
    return _storage.write(key: _outputDeviceIdKey, value: deviceId);
  }

  @override
  Future<void> writeInputVolume(double volume) {
    return _storage.write(
      key: _inputVolumeKey,
      value: audioVolumeStorageString(volume),
    );
  }

  @override
  Future<void> writeOutputVolume(double volume) {
    return _storage.write(
      key: _outputVolumeKey,
      value: audioVolumeStorageString(volume),
    );
  }

  @override
  Future<void> writeMusicBoxVolume(double volume) {
    return _storage.write(
      key: _musicBoxVolumeKey,
      value: audioVolumeStorageString(volume),
    );
  }
}
