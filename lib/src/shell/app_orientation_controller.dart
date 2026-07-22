import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef PreferredOrientationsSetter =
    Future<void> Function(List<DeviceOrientation> orientations);

/// Owns the platform boundary for Gang Chat's Android orientation policy.
///
/// Other platforms are deliberately ignored. Android stays portrait-only
/// unless a full-screen camera or screen-share viewer is active.
class AppOrientationController {
  AppOrientationController({
    TargetPlatform? platform,
    PreferredOrientationsSetter? setPreferredOrientations,
  }) : _platform = platform ?? defaultTargetPlatform,
       _setPreferredOrientations =
           setPreferredOrientations ?? SystemChrome.setPreferredOrientations;

  static const List<DeviceOrientation> portraitOnly = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];

  static const List<DeviceOrientation> fullScreenMedia = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  final TargetPlatform _platform;
  final PreferredOrientationsSetter _setPreferredOrientations;
  Future<void> _pending = Future<void>.value();

  Future<void> lockPortrait() => _enqueue(portraitOnly);

  Future<void> allowFullScreenMediaLandscape() => _enqueue(fullScreenMedia);

  Future<void> _enqueue(List<DeviceOrientation> orientations) {
    if (_platform != TargetPlatform.android) return Future<void>.value();
    final operation = _pending.then<void>(
      (_) => _setPreferredOrientations(orientations),
    );
    // Keep later restoration requests running even if a platform call fails.
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
