import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_orientation_controller.dart';

/// Temporarily enables Android landscape rotation for full-screen live media.
///
/// Disposing the scope restores portrait mode, covering explicit exits as well
/// as a camera/share track ending or its parent page being removed.
class FullScreenMediaOrientation extends StatefulWidget {
  const FullScreenMediaOrientation({
    super.key,
    required this.child,
    this.controller,
  });

  final Widget child;
  final AppOrientationController? controller;

  @override
  State<FullScreenMediaOrientation> createState() =>
      _FullScreenMediaOrientationState();
}

class _FullScreenMediaOrientationState
    extends State<FullScreenMediaOrientation> {
  late AppOrientationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AppOrientationController();
    _allowLandscape();
  }

  @override
  void didUpdateWidget(FullScreenMediaOrientation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _restorePortrait(_controller);
    _controller = widget.controller ?? AppOrientationController();
    _allowLandscape();
  }

  @override
  void dispose() {
    _restorePortrait(_controller);
    super.dispose();
  }

  void _allowLandscape() {
    unawaited(_ignoreFailure(_controller.allowFullScreenMediaLandscape()));
  }

  void _restorePortrait(AppOrientationController controller) {
    unawaited(_ignoreFailure(controller.lockPortrait()));
  }

  Future<void> _ignoreFailure(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      // Orientation support is best-effort and must never break navigation.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
