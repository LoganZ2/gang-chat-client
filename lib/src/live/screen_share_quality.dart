/// Pure helpers for the configurable screen-share resolution.
///
/// The target height a user picks (see [screenShareHeightOptions]) controls two
/// independent levers, because no single LiveKit/WebRTC knob covers every
/// platform:
///
///  * On Windows/Linux the desktop capturer honours the capture [dimensions],
///    so [screenShareResolutionForHeight] feeds `VideoParameters.dimensions`
///    and the frames arrive already scaled.
///  * On macOS the ScreenCaptureKit capturer ignores `dimensions` and always
///    grabs the display at its native resolution. The only way to send fewer
///    pixels is to scale the publisher's encoding down, so we apply
///    [screenShareScaleDownBy] to the `RTCRtpSender` after publishing.
///
/// Keeping the maths here (free of any LiveKit/WebRTC types) makes both levers
/// unit-testable without a live session.
library;

/// Selectable target heights, in pixels. [defaultScreenShareMaxHeight] (1080)
/// means "send at native resolution" — it never scales a 1080p-or-smaller
/// display up, and only caps taller (e.g. 1440p/4K/Retina) captures.
const List<int> screenShareHeightOptions = <int>[480, 720, 1080];

/// The default when nothing is stored: native resolution, capped at 1080p.
const int defaultScreenShareMaxHeight = 1080;

/// Coerce an arbitrary stored/in-flight value to one of the supported options,
/// falling back to [defaultScreenShareMaxHeight] for anything unrecognised.
int normalizedScreenShareMaxHeight(int? height) {
  if (height == null) return defaultScreenShareMaxHeight;
  return screenShareHeightOptions.contains(height)
      ? height
      : defaultScreenShareMaxHeight;
}

/// A plain 16:9 capture resolution for [height], with an even width (H.264
/// macroblocks want even dimensions, and odd widths trip some encoders).
class ScreenShareResolution {
  const ScreenShareResolution(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is ScreenShareResolution &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'ScreenShareResolution($width x $height)';
}

/// The 16:9 capture resolution to request for a given target [height]. Used for
/// `VideoParameters.dimensions` (the capture-side cap on Windows/Linux).
ScreenShareResolution screenShareResolutionForHeight(int height) {
  final normalized = normalizedScreenShareMaxHeight(height);
  var width = (normalized * 16 / 9).round();
  if (width.isOdd) width += 1;
  return ScreenShareResolution(width, normalized);
}

/// The `scaleResolutionDownBy` factor for the publisher's encoding so a capture
/// at [sourceHeight] is sent at no more than [targetHeight]. Always >= 1.0
/// (WebRTC only scales down): returns 1.0 when the source already fits, or when
/// either height is unknown/non-positive.
double screenShareScaleDownBy({
  required int sourceHeight,
  required int targetHeight,
}) {
  final target = normalizedScreenShareMaxHeight(targetHeight);
  if (sourceHeight <= 0 || sourceHeight <= target) return 1.0;
  return sourceHeight / target;
}

/// A short human label for the resolution picker.
String screenShareHeightLabel(int height) =>
    '${normalizedScreenShareMaxHeight(height)}p';
