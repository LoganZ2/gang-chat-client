import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Reports the OS-selected default microphone on macOS.
///
/// flutter_webrtc's CoreAudio device module never surfaces a synthetic
/// "default" entry on macOS the way it does on Windows, so the enumerated
/// device list gives no hint about which microphone the system currently treats
/// as the default. The native `gang_chat/audio_devices` channel answers that
/// using WebRTC's own device list, so the returned [deviceId] always matches one
/// of the ids from `enumerateDevices`.
///
/// On every other platform this is a no-op: Windows already exposes a dynamic
/// `'default'` device that follows the system selection, and mobile/web route
/// audio through the OS without a device picker.
class SystemDefaultAudioInput {
  SystemDefaultAudioInput({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('gang_chat/audio_devices');

  final MethodChannel _channel;
  final _changes = StreamController<String?>.broadcast();
  bool _handlerInstalled = false;

  bool get _supported => !kIsWeb && Platform.isMacOS;

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
