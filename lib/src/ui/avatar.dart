import 'package:flutter/material.dart';

import 'tokens.dart';

/// Fallback initials shown when an avatar has no image. Takes the first two
/// characters of the label so list avatars, the settings preview, and every
/// other fallback stay identical. Returns '?' for an empty label.
String avatarInitials(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.take(2).toString().toUpperCase();
}

const String kDefaultAvatarPresetKey = 'blue-3';

const Map<String, String> kLegacyAvatarPresetAliases = {
  'room-1': kDefaultAvatarPresetKey,
};

String normalizeAvatarPresetKey(String key) {
  final trimmed = key.trim();
  if (trimmed.isEmpty) return kDefaultAvatarPresetKey;
  return kLegacyAvatarPresetAliases[trimmed] ?? trimmed;
}

Color avatarFallbackColor(String key) {
  return switch (normalizeAvatarPresetKey(key)) {
    kDefaultAvatarPresetKey => const Color(0xFF526C9F),
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
    this.defaultAvatarKey,
    this.size = 40,
    this.active = false,
    this.activeBorderWidth = 2,
    this.activeBorderColor,
    this.paintBorderOnForeground = false,
    this.showBorder = true,
    this.showFallbackText = true,
  });

  final String label;
  final String? imageUrl;

  /// Preset color key driving the fallback fill. When null, the neutral
  /// surface color is used. Matches the swatch colors offered by the avatar
  /// picker (see [avatarFallbackColor]) so list avatars and the settings
  /// preview stay in sync.
  final String? defaultAvatarKey;
  final double size;
  final bool active;
  final double activeBorderWidth;
  final Color? activeBorderColor;
  final bool paintBorderOnForeground;
  final bool showBorder;
  final bool showFallbackText;

  @override
  Widget build(BuildContext context) {
    final initials = avatarInitials(label);
    final key = defaultAvatarKey == null
        ? null
        : normalizeAvatarPresetKey(defaultAvatarKey!);
    final fillColor = key == null ? UiColors.surface : avatarFallbackColor(key);
    final activeColor = activeBorderColor ?? UiColors.accent;
    final borderActive = showBorder && active;
    final border = showBorder
        ? Border.all(
            color: borderActive ? activeColor : UiColors.border,
            width: borderActive ? activeBorderWidth : 1,
          )
        : null;
    return SizedBox.square(
      dimension: size,
      child: Container(
        decoration: BoxDecoration(
          color: fillColor,
          shape: BoxShape.circle,
          border: paintBorderOnForeground ? null : border,
        ),
        foregroundDecoration: paintBorderOnForeground && border != null
            ? BoxDecoration(shape: BoxShape.circle, border: border)
            : null,
        child: ClipOval(
          child: imageUrl == null
              ? showFallbackText
                    ? Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            color: key == null && borderActive
                                ? activeColor
                                : UiColors.text,
                            fontSize: size * 0.34,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : const SizedBox.expand()
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
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
