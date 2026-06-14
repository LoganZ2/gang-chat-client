import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

// Ground-truth probe for the macOS "no microphone in Settings" bug. Runs the
// real flutter_webrtc/livekit plugins on the host so we can see what
// enumerateDevices() actually returns *before* any room/track exists, and
// whether creating a probe track changes that. Run with:
//   flutter test integration_test/audio_enumeration_probe_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<List<lk.MediaDevice>> enumerate() =>
      lk.Hardware.instance.enumerateDevices();

  testWidgets('enumerateDevices before any track', (tester) async {
    final devices = await enumerate();
    final inputs = devices.where((d) => d.kind == 'audioinput').toList();
    final outputs = devices.where((d) => d.kind == 'audiooutput').toList();
    debugPrint('PROBE cold all=${devices.length} '
        'inputs=${inputs.length} outputs=${outputs.length}');
    for (final d in devices) {
      debugPrint('PROBE cold device kind=${d.kind} id=${d.deviceId} '
          'label=${d.label}');
    }
  });

  testWidgets('enumerateDevices while a probe mic track is live',
      (tester) async {
    lk.LocalAudioTrack? track;
    try {
      track = await lk.LocalAudioTrack.create();
      await track.start();
      debugPrint('PROBE track created+started ok');
    } catch (e) {
      debugPrint('PROBE track create FAILED: $e');
    }
    final devices = await enumerate();
    final inputs = devices.where((d) => d.kind == 'audioinput').toList();
    debugPrint('PROBE warm all=${devices.length} inputs=${inputs.length}');
    for (final d in devices) {
      debugPrint('PROBE warm device kind=${d.kind} id=${d.deviceId} '
          'label=${d.label}');
    }
    await track?.stop();
    await track?.dispose();
  });

  testWidgets('native default-input channel responds', (tester) async {
    const channel = MethodChannel('gang_chat/audio_devices');
    try {
      final id = await channel.invokeMethod<String>('getDefaultInputDeviceId');
      debugPrint('PROBE native defaultInputDeviceId=$id');
    } catch (e) {
      debugPrint('PROBE native channel FAILED: $e');
    }
  });
}
