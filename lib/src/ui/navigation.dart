import 'package:flutter/material.dart';

import 'segmented_control.dart';

class NavigationItem<T> {
  const NavigationItem({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

class NavigationTabs<T> extends StatelessWidget {
  const NavigationTabs({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.expanded = false,
  });

  final List<NavigationItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return SegmentedControl<T>(
      value: value,
      onChanged: onChanged,
      expanded: expanded,
      segments: [
        for (final item in items)
          Segment<T>(value: item.value, label: item.label, icon: item.icon),
      ],
    );
  }
}
