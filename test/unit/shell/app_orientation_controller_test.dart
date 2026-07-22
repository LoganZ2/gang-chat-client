import 'package:client/src/shell/app_orientation_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android defaults to portrait-only', () async {
    final requests = <List<DeviceOrientation>>[];
    final controller = AppOrientationController(
      platform: TargetPlatform.android,
      setPreferredOrientations: (orientations) async {
        requests.add(List<DeviceOrientation>.of(orientations));
      },
    );

    await controller.lockPortrait();

    expect(requests, <List<DeviceOrientation>>[
      AppOrientationController.portraitOnly,
    ]);
  });

  test('Android full-screen media allows both landscape directions', () async {
    final requests = <List<DeviceOrientation>>[];
    final controller = AppOrientationController(
      platform: TargetPlatform.android,
      setPreferredOrientations: (orientations) async {
        requests.add(List<DeviceOrientation>.of(orientations));
      },
    );

    await controller.allowFullScreenMediaLandscape();

    expect(requests, <List<DeviceOrientation>>[
      <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    ]);
  });

  test('orientation requests never reach non-Android platforms', () async {
    var calls = 0;
    final controller = AppOrientationController(
      platform: TargetPlatform.windows,
      setPreferredOrientations: (_) async => calls += 1,
    );

    await controller.allowFullScreenMediaLandscape();
    await controller.lockPortrait();

    expect(calls, 0);
  });

  test(
    'portrait restoration still runs after an earlier request fails',
    () async {
      final requests = <List<DeviceOrientation>>[];
      var calls = 0;
      final controller = AppOrientationController(
        platform: TargetPlatform.android,
        setPreferredOrientations: (orientations) async {
          calls += 1;
          requests.add(List<DeviceOrientation>.of(orientations));
          if (calls == 1) throw PlatformException(code: 'unsupported');
        },
      );

      await expectLater(
        controller.allowFullScreenMediaLandscape(),
        throwsA(isA<PlatformException>()),
      );
      await controller.lockPortrait();

      expect(requests.last, AppOrientationController.portraitOnly);
    },
  );
}
