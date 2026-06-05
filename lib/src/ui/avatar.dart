import 'package:flutter/material.dart';

import 'tokens.dart';

Color avatarFallbackColor(String key) {
  return switch (key) {
    'blue-3' => const Color(0xFF526C9F),
    'sky-2' => const Color(0xFF4F7F92),
    'cyan-2' => const Color(0xFF47777A),
    'mint-2' => const Color(0xFF4F7A67),
    'green-2' => const Color(0xFF46695B),
    'lime-2' => const Color(0xFF687A47),
    'amber-2' => const Color(0xFF71614E),
    'orange-2' => const Color(0xFF7A6046),
    'coral-2' => const Color(0xFF7A5952),
    'pink-2' => const Color(0xFF75566F),
    'violet-2' => const Color(0xFF665B7D),
    'indigo-2' => const Color(0xFF5B638A),
    'rose-2' => const Color(0xFF7A5961),
    'teal-2' => const Color(0xFF536E73),
    'olive-2' => const Color(0xFF6A704B),
    'slate-2' => const Color(0xFF5E6472),
    'steel-2' => const Color(0xFF4F6672),
    'graphite-2' => const Color(0xFF5B5D63),
    _ => const Color(0xFF526C9F),
  };
}

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.label,
    this.imageUrl,
    this.size = 40,
    this.active = false,
    this.activeBorderWidth = 2,
  });

  final String label;
  final String? imageUrl;
  final double size;
  final bool active;
  final double activeBorderWidth;

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
            width: active ? activeBorderWidth : 1,
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
