import 'dart:async';

import '../live/audio_device_service.dart';
import '../protocol/api_client.dart';
import '../protocol/models.dart';
import 'audio_device_info.dart';
import 'audio_device_store.dart';
import 'audio_levels.dart';

/// Adapts the server-backed audio defaults of a managed account to the same
/// volume controls used by the ordinary settings page. Hardware device ids and
/// screen-share resolution remain device-local and are deliberately not
/// represented here.
class ManagedUserAudioSettingsStore extends AudioDeviceStore {
  ManagedUserAudioSettingsStore({required this.api, required this.userId});

  final GangApi api;
  final String userId;

  UserAudioSettings? _settings;
  Future<void> _writes = Future<void>.value();

  @override
  Future<StoredAudioDevices> read() async {
    await _writes;
    final settings = await _load();
    return StoredAudioDevices(
      inputVolume: normalizedAudioVolume(
        settings.defaultAudioInputVolume / 100,
      ),
      outputVolume: normalizedAudioVolume(
        settings.defaultAudioOutputVolume / 100,
      ),
      musicBoxVolume: normalizedAudioVolume(
        settings.liveMusicOutputVolume / 100,
      ),
      screenShareVolume: normalizedAudioVolume(
        settings.liveScreenShareOutputVolume / 100,
      ),
    );
  }

  @override
  Future<void> writeInputVolume(double volume) {
    return _update(defaultInput: _percent(volume));
  }

  @override
  Future<void> writeOutputVolume(double volume) {
    return _update(defaultOutput: _percent(volume));
  }

  @override
  Future<void> writeMusicBoxVolume(double volume) {
    return _update(music: _percent(volume));
  }

  @override
  Future<void> writeScreenShareVolume(double volume) {
    return _update(screenShare: _percent(volume));
  }

  @override
  Future<void> writeInputDeviceId(String deviceId) async {}

  @override
  Future<void> writeOutputDeviceId(String deviceId) async {}

  @override
  Future<void> writeScreenShareMaxHeight(int height) async {}

  int _percent(double volume) {
    return (normalizedAudioVolume(volume) * 100).round();
  }

  Future<UserAudioSettings> _load() async {
    return _settings ??= await api.getForcedUserAudioSettings(userId);
  }

  Future<void> _update({
    int? defaultInput,
    int? defaultOutput,
    int? screenShare,
    int? music,
  }) {
    final operation = _writes.then((_) async {
      final current = await _load();
      _settings = await api.updateForcedUserAudioSettings(
        userId: userId,
        settings: UserAudioSettings(
          defaultAudioInputVolume:
              defaultInput ?? current.defaultAudioInputVolume,
          defaultAudioOutputVolume:
              defaultOutput ?? current.defaultAudioOutputVolume,
          liveMicInputVolume: current.liveMicInputVolume,
          liveVoiceOutputVolume: current.liveVoiceOutputVolume,
          liveScreenShareOutputVolume:
              screenShare ?? current.liveScreenShareOutputVolume,
          liveMusicOutputVolume: music ?? current.liveMusicOutputVolume,
          updatedAt: current.updatedAt,
        ),
      );
    });
    _writes = operation.catchError((_) {});
    return operation;
  }
}

/// Prevents a managed account page from enumerating or selecting hardware on
/// the administrator's computer.
class ManagedUserAudioDeviceService extends LiveAudioDeviceService {
  const ManagedUserAudioDeviceService();

  @override
  Stream<List<AudioDeviceInfo>> get devicesChanged => const Stream.empty();

  @override
  Future<List<AudioDeviceInfo>> enumerateDevices() async => const [];

  @override
  AudioDeviceInfo? get selectedAudioInput => null;

  @override
  AudioDeviceInfo? get selectedAudioOutput => null;

  @override
  Future<void> selectAudioInput(AudioDeviceInfo device) async {}

  @override
  Future<void> selectAudioOutput(AudioDeviceInfo device) async {}
}
