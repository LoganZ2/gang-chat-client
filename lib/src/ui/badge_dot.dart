import 'package:flutter/material.dart';

import 'tokens.dart';

class BadgeDot extends StatelessWidget {
  const BadgeDot({
    super.key,
    this.size = 8,
    this.color = UiColors.danger,
    this.borderColor = UiColors.surface,
  });

  final double size;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.4),
        ),
        child: SizedBox.square(dimension: size),
      ),
    );
  }
}
