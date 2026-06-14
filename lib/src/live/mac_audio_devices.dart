import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../app/audio_device_info.dart';

/// macOS audio-input device access backed by the native `gang_chat/audio_devices`
/// CoreAudio channel.
///
/// flutter_webrtc's CoreAudio audio device module lists zero input devices until
/// WebRTC is actually recording (i.e. after audio is published in a room), so
/// its `enumerateDevices()` returns no microphones in Settings before a room is
/// joined, and it never surfaces a synthetic "default" entry the way Windows
/// does. This service reads CoreAudio directly so the picker can list inputs and
/// follow the system default without a live room.
///
/// The deviceIds returned here are the stringified CoreAudio AudioDeviceID
/// integers — byte-for-byte what WebRTC's macOS `RTCIODevice.deviceId` resolves
/// to — so they stay compatible with flutter_webrtc's `selectAudioInput` and the
/// stored-preference matching.
///
/// On every other platform this is a no-op: Windows already exposes a dynamic
/// `'default'` device that follows the system selection, and mobile/web route
/// audio through the OS without a device picker.
class MacAudioDevices {
  MacAudioDevices({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('gang_chat/audio_devices');

  final MethodChannel _channel;
  final _changes = StreamController<String?>.broadcast();
  bool _handlerInstalled = false;

  bool get _supported => !kIsWeb && Platform.isMacOS;

  /// All CoreAudio input devices, or an empty list on unsupported platforms or
  /// when the native side fails. Used to fill the picker on macOS where
  /// flutter_webrtc returns no inputs outside a room.
  Future<List<AudioDeviceInfo>> enumerateInputs() {
    return _enumerate('enumerateInputs', 'audioinput', '麦克风');
  }

  /// All CoreAudio output devices, or an empty list on unsupported platforms or
  /// when the native side fails. flutter_webrtc reports no outputs outside a
  /// room on macOS either, so the picker merges these in the same way as inputs.
  Future<List<AudioDeviceInfo>> enumerateOutputs() {
    return _enumerate('enumerateOutputs', 'audiooutput', '扬声器');
  }

  Future<List<AudioDeviceInfo>> _enumerate(
    String method,
    String kind,
    String fallbackLabel,
  ) async {
    if (!_supported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(method);
      if (raw == null) return const [];
      return [
        for (final entry in raw)
          AudioDeviceInfo(
            deviceId: (entry['deviceId'] as String?) ?? '',
            label: (entry['label'] as String?) ?? fallbackLabel,
            kind: kind,
          ),
      ].where((device) => device.deviceId.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// The deviceId the OS currently uses as the default input, or null when the
  /// platform has no concept of a queryable system default (everything except
  /// macOS) or no input device exists.
  Future<String?> currentDeviceId() async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('getDefaultInputDeviceId');
    } catch (_) {
      // The picker degrades to the enumerated list when the native default is
      // unavailable; surfacing the failure would not help the user.
      return null;
    }
  }

  /// Emits the new default-input deviceId whenever the user changes the system
  /// default microphone (e.g. in System Settings). Never emits on unsupported
  /// platforms.
  Stream<String?> get changes {
    _ensureListening();
    return _changes.stream;
  }

  void _ensureListening() {
    if (!_supported || _handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler(_handleCall);
    // Ask the native side to start observing CoreAudio's default-device
    // property. Safe to call repeatedly; the handler installs the listener once.
    unawaited(_channel.invokeMethod<void>('startListening').catchError((_) {}));
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method == 'defaultInputDeviceChanged') {
      final deviceId = call.arguments;
      _changes.add(deviceId is String ? deviceId : null);
    }
    return null;
  }

  Future<void> dispose() async {
    if (_handlerInstalled) {
      _channel.setMethodCallHandler(null);
      _handlerInstalled = false;
    }
    await _changes.close();
  }
}
