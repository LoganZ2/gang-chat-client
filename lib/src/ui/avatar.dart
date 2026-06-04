import 'package:flutter/material.dart';

import 'tokens.dart';

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.label,
    this.imageUrl,
    this.size = 40,
    this.active = false,
  });

  final String label;
  final String? imageUrl;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final initials = label.trim().isEmpty
        ? '?'
        : label.trim().characters.take(2).toString().toUpperCase();
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: UiColors.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? UiColors.accent : UiColors.border,
            width: active ? 2 : 1,
          ),
        ),
        child: ClipOval(
          child: imageUrl == null
              ? Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: active ? UiColors.accent : UiColors.text,
                      fontSize: size * 0.34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              : Image.network(imageUrl!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.active = false,
    this.danger = false,
  });

  final String label;
  final IconData? icon;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? UiColors.danger
        : active
        ? UiColors.accent
        : UiColors.textMuted;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
