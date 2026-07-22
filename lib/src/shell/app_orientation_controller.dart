import 'dart:ui' show PlatformDispatcher, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'android_form_factor.dart';

typedef PreferredOrientationsSetter =
    Future<void> Function(List<DeviceOrientation> orientations);
typedef LogicalViewSizeReader = Size Function();

/// Owns the platform boundary for Gang Chat's Android orientation policy.
///
/// Other platforms are deliberately ignored. Android phones stay portrait-only
/// unless full-screen media is active, while Android tablets use the platform's
/// unrestricted orientation behavior.
class AppOrientationController {
  AppOrientationController({
    TargetPlatform? platform,
    PreferredOrientationsSetter? setPreferredOrientations,
    LogicalViewSizeReader? logicalViewSize,
  }) : _platform = platform ?? defaultTargetPlatform,
       _setPreferredOrientations =
           setPreferredOrientations ?? SystemChrome.setPreferredOrientations,
       _logicalViewSize = logicalViewSize ?? _primaryLogicalViewSize;

  static const List<DeviceOrientation> portraitOnly = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];

  static const List<DeviceOrientation> fullScreenMedia = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
  static const List<DeviceOrientation> unrestricted = <DeviceOrientation>[];

  final TargetPlatform _platform;
  final PreferredOrientationsSetter _setPreferredOrientations;
  final LogicalViewSizeReader _logicalViewSize;
  Future<void> _pending = Future<void>.value();

  bool get restoresPortraitByDefault =>
      _platform == TargetPlatform.android &&
      !isAndroidTabletLogicalSize(_logicalViewSize());

  Future<void> lockPortrait() => _enqueue(portraitOnly);

  Future<void> restoreDefaultOrientation() =>
      _enqueue(restoresPortraitByDefault ? portraitOnly : unrestricted);

  Future<void> allowFullScreenMediaLandscape() =>
      _enqueue(restoresPortraitByDefault ? fullScreenMedia : unrestricted);

  Future<void> _enqueue(List<DeviceOrientation> orientations) {
    if (_platform != TargetPlatform.android) return Future<void>.value();
    final operation = _pending.then<void>(
      (_) => _setPreferredOrientations(orientations),
    );
    // Keep later restoration requests running even if a platform call fails.
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  static Size _primaryLogicalViewSize() {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return Size.zero;
    final view = views.first;
    final ratio = view.devicePixelRatio <= 0 ? 1.0 : view.devicePixelRatio;
    return Size(
      view.physicalSize.width / ratio,
      view.physicalSize.height / ratio,
    );
  }
}
