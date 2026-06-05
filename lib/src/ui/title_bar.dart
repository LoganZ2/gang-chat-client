import 'package:flutter/material.dart';

/// Legacy layout offsets from the old in-app custom title bar.
///
/// The native title bar is hidden while native window buttons stay visible, so
/// app content should not reserve an extra in-content strip for window controls.
const double titleBarHeight = 0;

const double windowDragHeight = 0;

const double windowControlsInset = 0;

const double windowControlsWidth = 0;

/// Kept for the existing full-screen screen-share state path. Native system
/// controls are no longer painted by Flutter, so toggling this is a no-op.
final ValueNotifier<bool> windowControlsHidden = ValueNotifier<bool>(false);

@Deprecated('Native system title bars are used instead.')
class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
