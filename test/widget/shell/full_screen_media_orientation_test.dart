import 'package:client/src/shell/app_orientation_controller.dart';
import 'package:client/src/shell/full_screen_media_orientation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('full-screen media enables landscape and restores portrait', (
    tester,
  ) async {
    final requests = <List<DeviceOrientation>>[];
    final controller = AppOrientationController(
      platform: TargetPlatform.android,
      logicalViewSize: () => const Size(400, 800),
      setPreferredOrientations: (orientations) async {
        requests.add(List<DeviceOrientation>.of(orientations));
      },
    );

    await tester.pumpWidget(
      FullScreenMediaOrientation(
        controller: controller,
        child: const SizedBox(key: ValueKey<String>('full-screen-media')),
      ),
    );
    await tester.pump();

    expect(requests, <List<DeviceOrientation>>[
      AppOrientationController.fullScreenMedia,
    ]);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(requests, <List<DeviceOrientation>>[
      AppOrientationController.fullScreenMedia,
      AppOrientationController.portraitOnly,
    ]);
  });

  testWidgets('Android tablet keeps unrestricted rotation after media exits', (
    tester,
  ) async {
    final requests = <List<DeviceOrientation>>[];
    final controller = AppOrientationController(
      platform: TargetPlatform.android,
      logicalViewSize: () => const Size(1280, 800),
      setPreferredOrientations: (orientations) async {
        requests.add(List<DeviceOrientation>.of(orientations));
      },
    );

    await tester.pumpWidget(
      FullScreenMediaOrientation(
        controller: controller,
        child: const SizedBox(),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(requests, <List<DeviceOrientation>>[
      AppOrientationController.unrestricted,
      AppOrientationController.unrestricted,
    ]);
  });

  testWidgets('scope does not request orientation outside Android', (
    tester,
  ) async {
    var calls = 0;
    final controller = AppOrientationController(
      platform: TargetPlatform.windows,
      setPreferredOrientations: (_) async => calls += 1,
    );

    await tester.pumpWidget(
      FullScreenMediaOrientation(
        controller: controller,
        child: const SizedBox(),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(calls, 0);
  });
}
