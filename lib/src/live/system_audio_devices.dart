import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../app/audio_device_info.dart';

/// Desktop system audio-device access backed by the native
/// `gang_chat/audio_devices` channel.
///
/// macOS needs CoreAudio enumeration because flutter_webrtc lists no audio
/// devices before a room is joined. Windows already lists devices through
/// WebRTC, but querying the OS default endpoint lets Settings display the real
/// default input/output instead of sticking to a stale selected device.
class SystemAudioDevices {
  SystemAudioDevices({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('gang_chat/audio_devices'),
      _supportedOverride = supported;

  final MethodChannel _channel;
  final bool? _supportedOverride;
  final _inputChanges = StreamController<String?>.broadcast();
  final _outputChanges = StreamController<String?>.broadcast();
  bool _handlerInstalled = false;

  bool get _supported {
    return _supportedOverride ??
        (!kIsWeb && (Platform.isMacOS || Platform.isWindows));
  }

  /// Native input devices, or an empty list when unsupported/unavailable.
  Future<List<AudioDeviceInfo>> enumerateInputs() {
    return _enumerate('enumerateInputs', 'audioinput', '麦克风');
  }

  /// Native output devices, or an empty list when unsupported/unavailable.
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
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        method,
      );
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

  Future<String?> currentInputDeviceId() {
    return _currentDeviceId('getDefaultInputDeviceId');
  }

  Future<String?> currentOutputDeviceId() {
    return _currentDeviceId('getDefaultOutputDeviceId');
  }

  /// Backwards-compatible alias for the default input device id.
  Future<String?> currentDeviceId() => currentInputDeviceId();

  Future<String?> _currentDeviceId(String method) async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>(method);
    } catch (_) {
      // The picker degrades to the enumerated/WebRTC list when the native
      // default is unavailable; surfacing the failure would not help the user.
      return null;
    }
  }

  Stream<String?> get inputChanges {
    _ensureListening();
    return _inputChanges.stream;
  }

  Stream<String?> get outputChanges {
    _ensureListening();
    return _outputChanges.stream;
  }

  /// Backwards-compatible alias for default input changes.
  Stream<String?> get changes => inputChanges;

  void _ensureListening() {
    if (!_supported || _handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler(_handleCall);
    unawaited(_channel.invokeMethod<void>('startListening').catchError((_) {}));
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    final deviceId = call.arguments;
    switch (call.method) {
      case 'defaultInputDeviceChanged':
        _inputChanges.add(deviceId is String ? deviceId : null);
        break;
      case 'defaultOutputDeviceChanged':
        _outputChanges.add(deviceId is String ? deviceId : null);
        break;
    }
    return null;
  }

  Future<void> dispose() async {
    if (_handlerInstalled) {
      _channel.setMethodCallHandler(null);
      _handlerInstalled = false;
    }
    await _inputChanges.close();
    await _outputChanges.close();
  }
}
