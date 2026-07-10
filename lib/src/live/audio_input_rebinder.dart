import 'dart:async';

import '../app/audio_device_info.dart';
import '../app/audio_device_store.dart';
import 'audio_device_service.dart';
import 'system_audio_devices.dart';

/// Recovers the local microphone publisher after desktop audio input hotplug.
///
/// Bluetooth headsets can remove and recreate their input endpoint when the
/// battery dies, reconnects, or flips between output-only and call profiles.
/// WebRTC may keep the old capture endpoint attached to the published mic
/// track, which then surfaces as publisher reconnect failures. This helper is
/// deliberately best-effort: it coalesces the burst of device-change events,
/// resolves the preferred live input device, and asks the session to restart
/// the local mic capture without reconnecting to the room.
class AudioInputRebinder {
  AudioInputRebinder({
    required Stream<void> deviceChanges,
    required Future<String?> Function() currentInputDeviceId,
    required Future<void> Function(String? deviceId) rebindInput,
    Duration debounce = const Duration(milliseconds: 300),
  }) : _deviceChanges = deviceChanges,
       _currentInputDeviceId = currentInputDeviceId,
       _rebindInput = rebindInput,
       _debounce = debounce;

  final Stream<void> _deviceChanges;
  final Future<String?> Function() _currentInputDeviceId;
  final Future<void> Function(String? deviceId) _rebindInput;
  final Duration _debounce;

  StreamSubscription<void>? _subscription;
  Timer? _debounceTimer;
  bool _rebinding = false;
  bool _rebindQueued = false;
  bool _stopped = false;

  /// Begins observing device changes. Safe to call once; a second call is a
  /// no-op while already started.
  void start() {
    if (_subscription != null || _stopped) return;
    _subscription = _deviceChanges.listen(
      (_) => _scheduleRebind(),
      onError: (_, _) {},
    );
  }

  /// Stops observing and cancels any pending rebind. After this the rebinder is
  /// inert and cannot be restarted.
  Future<void> stop() async {
    _stopped = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final sub = _subscription;
    _subscription = null;
    await sub?.cancel();
  }

  void _scheduleRebind() {
    if (_stopped) return;
    // A single Bluetooth reconnect can emit several add/remove/default-change
    // events. Wait for the device list to settle before restarting capture.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      unawaited(_rebind());
    });
  }

  Future<void> _rebind() async {
    if (_stopped) return;
    if (_rebinding) {
      _rebindQueued = true;
      return;
    }
    _rebinding = true;
    try {
      final deviceId = await _currentInputDeviceId();
      if (_stopped) return;
      await _rebindInput(deviceId);
    } catch (_) {
      // Best-effort recovery: the next hardware event gets another attempt.
    } finally {
      _rebinding = false;
      if (_rebindQueued && !_stopped) {
        _rebindQueued = false;
        _scheduleRebind();
      }
    }
  }
}

Future<String?> preferredLiveInputDeviceId({
  required AudioDeviceStore? audioDeviceStore,
  required LiveAudioDeviceService audioDevices,
  required SystemAudioDevices systemAudio,
}) async {
  final systemDefaultInputId = await systemAudio.currentInputDeviceId();
  if (audioDeviceStore == null) return systemDefaultInputId;
  try {
    final stored = await audioDeviceStore.read();
    final devices = await audioDevices.enumerateDevices();
    final storedInput = preferredStoredAudioDeviceFrom<AudioDeviceInfo>(
      devices,
      kind: 'audioinput',
      storedDeviceId: stored.inputDeviceId,
      storedDeviceLabel: stored.inputDeviceLabel,
      storedDeviceGroupId: stored.inputDeviceGroupId,
      kindOf: audioDeviceInfoKind,
      deviceIdOf: audioDeviceInfoId,
      labelOf: audioDeviceInfoLabel,
      groupIdOf: audioDeviceInfoGroupId,
      systemDefaultDeviceId: systemDefaultInputId,
    );
    return storedInput?.deviceId ?? systemDefaultInputId;
  } catch (_) {
    return systemDefaultInputId;
  }
}
