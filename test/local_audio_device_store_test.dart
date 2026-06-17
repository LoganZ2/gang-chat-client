import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/src/app/audio_levels.dart';
import 'package:client/src/shell/local_audio_device_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('read returns defaults when nothing is stored', () async {
    final store = const LocalAudioDeviceStore();

    final stored = await store.read();

    expect(stored.inputDeviceId, isNull);
    expect(stored.outputDeviceId, isNull);
    expect(stored.inputVolume, 0.5);
    expect(stored.outputVolume, 0.5);
    expect(stored.musicBoxVolume, 0.5);
    expect(stored.screenShareVolume, 0.5);
    expect(stored.screenShareMaxHeight, 1080);
  });

  test('writes round-trip through SharedPreferences', () async {
    final store = const LocalAudioDeviceStore();

    await store.writeInputDeviceId('87');
    await store.writeOutputDeviceId('54');
    await store.writeInputVolume(0.4);
    await store.writeOutputVolume(0.6);
    await store.writeMusicBoxVolume(0.2);
    await store.writeScreenShareVolume(0.8);
    await store.writeScreenShareMaxHeight(720);

    final stored = await store.read();
    expect(stored.inputDeviceId, '87');
    expect(stored.outputDeviceId, '54');
    expect(stored.inputVolume, closeTo(0.4, 1e-9));
    expect(stored.outputVolume, closeTo(0.6, 1e-9));
    expect(stored.musicBoxVolume, closeTo(0.2, 1e-9));
    expect(stored.screenShareVolume, closeTo(0.8, 1e-9));
    expect(stored.screenShareMaxHeight, 720);
  });

  test(
    'screen share height is coerced to a supported option on write',
    () async {
      final store = const LocalAudioDeviceStore();

      await store.writeScreenShareMaxHeight(999);
      final stored = await store.read();

      expect(stored.screenShareMaxHeight, 1080);
    },
  );

  test('volumes are clamped to the valid range on write', () async {
    final store = const LocalAudioDeviceStore();

    await store.writeOutputVolume(5.0);
    await store.writeScreenShareVolume(-0.5);
    final stored = await store.read();

    expect(stored.outputVolume, normalizedAudioVolume(5.0));
    expect(stored.outputVolume, 1.0);
    expect(stored.screenShareVolume, 0.0);
  });
}
