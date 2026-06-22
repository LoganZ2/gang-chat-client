import 'package:shared_preferences/shared_preferences.dart';

import '../app/audio_device_store.dart';
import '../app/audio_levels.dart';
import '../live/screen_share_quality.dart';

/// Persists audio device + volume preferences in [SharedPreferences].
///
/// These values (which mic/speaker, what volumes) are not sensitive, so they
/// live in plain local preferences rather than the keychain. On macOS reading
/// the keychain pops an authorization prompt every launch under a debug/unstable
/// code signature; SharedPreferences (a plist on macOS) never does. The refresh
/// token stays in flutter_secure_storage — see TokenStore.
class LocalAudioDeviceStore extends AudioDeviceStore {
  const LocalAudioDeviceStore();

  static const _inputDeviceIdKey = 'gang.audioInputDeviceId';
  static const _outputDeviceIdKey = 'gang.audioOutputDeviceId';
  static const _inputVolumeKey = 'gang.audioInputVolume';
  static const _outputVolumeKey = 'gang.audioOutputVolume';
  static const _musicBoxVolumeKey = 'gang.musicBoxVolume';
  static const _screenShareVolumeKey = 'gang.screenShareVolume';
  static const _screenShareMaxHeightKey = 'gang.screenShareMaxHeight';
  static const _participantVoiceVolumePrefix = 'gang.participantVoiceVolume.';

  @override
  Future<StoredAudioDevices> read() async {
    final prefs = await SharedPreferences.getInstance();
    return StoredAudioDevices(
      inputDeviceId: storedAudioDeviceIdFromStorageValue(
        prefs.getString(_inputDeviceIdKey),
      ),
      outputDeviceId: storedAudioDeviceIdFromStorageValue(
        prefs.getString(_outputDeviceIdKey),
      ),
      inputVolume: _readVolume(prefs, _inputVolumeKey),
      outputVolume: _readVolume(prefs, _outputVolumeKey),
      musicBoxVolume: _readVolume(prefs, _musicBoxVolumeKey),
      screenShareVolume: _readVolume(prefs, _screenShareVolumeKey),
      screenShareMaxHeight: normalizedScreenShareMaxHeight(
        prefs.getInt(_screenShareMaxHeightKey),
      ),
    );
  }

  @override
  Future<void> writeInputDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_inputDeviceIdKey, deviceId);
  }

  @override
  Future<void> writeOutputDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_outputDeviceIdKey, deviceId);
  }

  @override
  Future<void> writeInputVolume(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_inputVolumeKey, normalizedAudioVolume(volume));
  }

  @override
  Future<void> writeOutputVolume(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_outputVolumeKey, normalizedAudioVolume(volume));
  }

  @override
  Future<void> writeMusicBoxVolume(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_musicBoxVolumeKey, normalizedAudioVolume(volume));
  }

  @override
  Future<void> writeScreenShareVolume(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_screenShareVolumeKey, normalizedAudioVolume(volume));
  }

  @override
  Future<void> writeScreenShareMaxHeight(int height) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _screenShareMaxHeightKey,
      normalizedScreenShareMaxHeight(height),
    );
  }

  @override
  Future<double> readParticipantVoiceVolume(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_participantVoiceVolumeKey(userId));
    if (value == null) return defaultParticipantVoiceVolume;
    return normalizedParticipantVoiceVolume(value);
  }

  @override
  Future<void> writeParticipantVoiceVolume(String userId, double volume) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizedParticipantVoiceVolume(volume);
    final key = _participantVoiceVolumeKey(userId);
    if (normalized == defaultParticipantVoiceVolume) {
      await prefs.remove(key);
      return;
    }
    await prefs.setDouble(key, normalized);
  }

  double _readVolume(SharedPreferences prefs, String key) {
    final value = prefs.getDouble(key);
    return value == null ? defaultAudioVolume : normalizedAudioVolume(value);
  }

  String _participantVoiceVolumeKey(String userId) {
    return '$_participantVoiceVolumePrefix${Uri.encodeComponent(userId)}';
  }
}
