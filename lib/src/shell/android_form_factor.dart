import 'dart:ui' show Size;

/// Android's standard large-screen boundary. Keeping this in one platform
/// module prevents phone/tablet checks from drifting between features.
const double androidTabletShortestSide = 600;

bool isAndroidTabletLogicalSize(Size logicalSize) {
  return logicalSize.shortestSide >= androidTabletShortestSide;
}
