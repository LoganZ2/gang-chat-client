import 'package:flutter/material.dart';

import 'navigation.dart';

/// Shares one width-driven compact/wide decision across the home subtree.
/// Platform-specific controls remain responsible for their own OS behavior.
class HomeAdaptiveLayout extends InheritedWidget {
  const HomeAdaptiveLayout({
    super.key,
    required this.compact,
    required super.child,
  });

  final bool compact;

  static bool usesCompactLayout(BuildContext context) {
    final mode = context
        .dependOnInheritedWidgetOfExactType<HomeAdaptiveLayout>();
    return mode?.compact ?? MediaQuery.sizeOf(context).width < narrowBreakpoint;
  }

  @override
  bool updateShouldNotify(HomeAdaptiveLayout oldWidget) {
    return compact != oldWidget.compact;
  }
}
