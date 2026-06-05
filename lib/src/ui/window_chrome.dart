import 'package:flutter/material.dart';

const _macOsSidebarTopOffset = 18.0;

class WindowChromeInsets {
  const WindowChromeInsets({required this.sidebarTopOffset});

  final double sidebarTopOffset;

  static WindowChromeInsets of(BuildContext context) {
    final platform = Theme.of(context).platform;
    final viewPadding =
        MediaQuery.maybeOf(context)?.viewPadding ?? EdgeInsets.zero;

    return WindowChromeInsets(
      sidebarTopOffset: switch (platform) {
        TargetPlatform.macOS => _macOsSidebarTopOffset,
        TargetPlatform.iOS || TargetPlatform.android => viewPadding.top,
        _ => 0,
      },
    );
  }
}
