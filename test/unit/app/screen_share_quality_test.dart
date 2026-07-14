import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/live/screen_share_quality.dart';

void main() {
  group('normalizedScreenShareMaxHeight', () {
    test('passes through supported options', () {
      for (final option in screenShareHeightOptions) {
        expect(normalizedScreenShareMaxHeight(option), option);
      }
    });

    test('falls back to default for null/unsupported values', () {
      expect(normalizedScreenShareMaxHeight(null), defaultScreenShareMaxHeight);
      expect(normalizedScreenShareMaxHeight(0), defaultScreenShareMaxHeight);
      expect(normalizedScreenShareMaxHeight(900), defaultScreenShareMaxHeight);
      expect(normalizedScreenShareMaxHeight(2160), defaultScreenShareMaxHeight);
    });

    test('default is 1080', () {
      expect(defaultScreenShareMaxHeight, 1080);
    });
  });

  group('screenShareResolutionForHeight', () {
    test('returns 16:9 dimensions with an even width', () {
      expect(
        screenShareResolutionForHeight(480),
        const ScreenShareResolution(854, 480),
      );
      expect(
        screenShareResolutionForHeight(720),
        const ScreenShareResolution(1280, 720),
      );
      expect(
        screenShareResolutionForHeight(1080),
        const ScreenShareResolution(1920, 1080),
      );
    });

    test('width is always even', () {
      for (final option in screenShareHeightOptions) {
        expect(screenShareResolutionForHeight(option).width.isEven, isTrue);
      }
    });

    test('coerces unsupported heights to the default resolution', () {
      expect(
        screenShareResolutionForHeight(999),
        const ScreenShareResolution(1920, 1080),
      );
    });
  });

  group('screenShareScaleDownBy', () {
    test('downscales a taller source to the target', () {
      // 4K display capped at 720p.
      expect(
        screenShareScaleDownBy(sourceHeight: 2160, targetHeight: 720),
        closeTo(3.0, 1e-9),
      );
      // 1440p capped at 480p.
      expect(
        screenShareScaleDownBy(sourceHeight: 1440, targetHeight: 480),
        closeTo(3.0, 1e-9),
      );
    });

    test('never scales up when the source already fits', () {
      expect(
        screenShareScaleDownBy(sourceHeight: 720, targetHeight: 1080),
        1.0,
      );
      expect(
        screenShareScaleDownBy(sourceHeight: 1080, targetHeight: 1080),
        1.0,
      );
    });

    test('returns 1.0 for unknown/non-positive source heights', () {
      expect(screenShareScaleDownBy(sourceHeight: 0, targetHeight: 720), 1.0);
      expect(screenShareScaleDownBy(sourceHeight: -5, targetHeight: 720), 1.0);
    });

    test('coerces an unsupported target to the default before scaling', () {
      // target 999 -> 1080; a 1080p source then needs no scaling.
      expect(
        screenShareScaleDownBy(sourceHeight: 1080, targetHeight: 999),
        1.0,
      );
    });
  });

  group('screenShareHeightLabel', () {
    test('formats supported heights', () {
      expect(screenShareHeightLabel(480), '480p');
      expect(screenShareHeightLabel(720), '720p');
      expect(screenShareHeightLabel(1080), '1080p');
    });

    test('coerces unsupported heights to the default label', () {
      expect(screenShareHeightLabel(999), '1080p');
    });
  });
}
