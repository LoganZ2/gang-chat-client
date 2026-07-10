import 'dart:async';

/// Recovers WebRTC audio output after macOS swaps the default output endpoint
/// underneath a live room.
///
/// The prime case is a Bluetooth headset flipping between its A2DP (stereo
/// "music" profile, output only) and HFP (mono "call" profile, with mic). When
/// the mic opens, macOS forces the headset into HFP; when it closes, the
/// headset flips back to A2DP. Each flip tears down the old CoreAudio output
/// endpoint and builds a new one, but WebRTC's CoreAudio audio device module
/// keeps rendering into the dead endpoint — so playback (e.g. the music box)
/// degrades to noise until the playout unit is rebound to the live endpoint.
///
/// macOS posts a device-change event on each flip. On that signal this rebinds
/// the output device (re-selecting forces the ADM to rebuild the playout unit
/// against the current endpoint, even when the device id is unchanged) and
/// re-applies track volumes. Everything is best-effort: a failed rebind leaves
/// the existing routing untouched rather than throwing into the caller.
class AudioOutputRebinder {
  AudioOutputRebinder({
    required Stream<void> deviceChanges,
    required Future<String?> Function() currentOutputDeviceId,
    required Future<void> Function(String deviceId) selectOutput,
    required Future<void> Function() onRebound,
    Duration debounce = const Duration(milliseconds: 300),
  }) : _deviceChanges = deviceChanges,
       _currentOutputDeviceId = currentOutputDeviceId,
       _selectOutput = selectOutput,
       _onRebound = onRebound,
       _debounce = debounce;

  final Stream<void> _deviceChanges;
  final Future<String?> Function() _currentOutputDeviceId;
  final Future<void> Function(String deviceId) _selectOutput;
  final Future<void> Function() _onRebound;
  final Duration _debounce;

  StreamSubscription<void>? _subscription;
  Timer? _debounceTimer;
  bool _rebinding = false;
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
    // Coalesce the burst of events a single profile flip emits, and give the
    // OS a beat to finish building the new endpoint before we bind to it.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      unawaited(_rebind());
    });
  }

  Future<void> _rebind() async {
    if (_stopped || _rebinding) return;
    _rebinding = true;
    try {
      final deviceId = await _currentOutputDeviceId();
      if (_stopped) return;
      if (deviceId != null && deviceId.isNotEmpty) {
        await _selectOutput(deviceId);
      }
      if (_stopped) return;
      await _onRebound();
    } catch (_) {
      // Best-effort recovery: keep the existing routing on any failure.
    } finally {
      _rebinding = false;
    }
  }
}
