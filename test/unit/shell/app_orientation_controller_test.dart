import 'package:client/src/shell/android_form_factor.dart';
import 'package:client/src/shell/app_orientation_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android defaults to portrait-only', () async {
    final requests = <List<DeviceOrientation>>[];
    final controller = AppOrientationController(
      platform: TargetPlatform.android,
      logicalViewSize: () => const Size(400, 800),
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
      logicalViewSize: () => const Size(400, 800),
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

  test('Android tablet keeps unrestricted default orientation', () async {
    final requests = <List<DeviceOrientation>>[];
    final controller = AppOrientationController(
      platform: TargetPlatform.android,
      logicalViewSize: () => const Size(1280, 800),
      setPreferredOrientations: (orientations) async {
        requests.add(List<DeviceOrientation>.of(orientations));
      },
    );

    await controller.restoreDefaultOrientation();
    await controller.allowFullScreenMediaLandscape();

    expect(controller.restoresPortraitByDefault, isFalse);
    expect(requests, <List<DeviceOrientation>>[
      AppOrientationController.unrestricted,
      AppOrientationController.unrestricted,
    ]);
  });

  test('Android tablet boundary uses the standard 600dp shortest side', () {
    expect(isAndroidTabletLogicalSize(const Size(599, 1024)), isFalse);
    expect(isAndroidTabletLogicalSize(const Size(600, 960)), isTrue);
    expect(isAndroidTabletLogicalSize(const Size(1280, 800)), isTrue);
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
        logicalViewSize: () => const Size(400, 800),
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
