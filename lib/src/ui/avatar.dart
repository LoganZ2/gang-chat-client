import 'package:flutter/material.dart';

import 'cached_asset_image.dart';
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
    'navy-2' => const Color(0xFF465B7D),
    'azure-2' => const Color(0xFF4A7194),
    'sky-2' => const Color(0xFF4F7F92),
    'cyan-2' => const Color(0xFF47777A),
    'turquoise-2' => const Color(0xFF467B73),
    'mint-2' => const Color(0xFF4F7A67),
    'emerald-2' => const Color(0xFF3F725C),
    'green-2' => const Color(0xFF46695B),
    'forest-2' => const Color(0xFF496449),
    'lime-2' => const Color(0xFF687A47),
    'yellow-2' => const Color(0xFF7B7048),
    'amber-2' => const Color(0xFF71614E),
    'gold-2' => const Color(0xFF7A6744),
    'orange-2' => const Color(0xFF7A6046),
    'coral-2' => const Color(0xFF7A5952),
    'red-2' => const Color(0xFF7B4F52),
    'crimson-2' => const Color(0xFF74495A),
    'pink-2' => const Color(0xFF75566F),
    'magenta-2' => const Color(0xFF704D70),
    'violet-2' => const Color(0xFF665B7D),
    'purple-2' => const Color(0xFF62537C),
    'lavender-2' => const Color(0xFF70688B),
    'indigo-2' => const Color(0xFF5B638A),
    'rose-2' => const Color(0xFF7A5961),
    'teal-2' => const Color(0xFF536E73),
    'olive-2' => const Color(0xFF6A704B),
    'brown-2' => const Color(0xFF6D594C),
    'sand-2' => const Color(0xFF746954),
    'slate-2' => const Color(0xFF5E6472),
    'steel-2' => const Color(0xFF4F6672),
    'gray-2' => const Color(0xFF62666C),
    'graphite-2' => const Color(0xFF5B5D63),
    'black-2' => const Color(0xFF44474D),
    _ => const Color(0xFF526C9F),
  };
}

/// Simplified-Chinese display name for a persisted avatar color key.
///
/// The key remains stable in API payloads and snapshots. Only the picker copy
/// is localized so older accounts and room records remain compatible.
String avatarPresetLabel(String key) {
  return switch (normalizeAvatarPresetKey(key)) {
    kDefaultAvatarPresetKey => '蓝色',
    'navy-2' => '深海蓝',
    'azure-2' => '蔚蓝',
    'sky-2' => '天蓝色',
    'cyan-2' => '青色',
    'turquoise-2' => '绿松石色',
    'mint-2' => '薄荷绿',
    'emerald-2' => '翡翠绿',
    'green-2' => '绿色',
    'forest-2' => '森林绿',
    'lime-2' => '青柠绿',
    'yellow-2' => '黄色',
    'amber-2' => '琥珀色',
    'gold-2' => '金色',
    'orange-2' => '橙色',
    'coral-2' => '珊瑚色',
    'red-2' => '红色',
    'crimson-2' => '绯红色',
    'pink-2' => '粉色',
    'magenta-2' => '品红色',
    'violet-2' => '紫罗兰色',
    'purple-2' => '紫色',
    'lavender-2' => '薰衣草色',
    'indigo-2' => '靛蓝色',
    'rose-2' => '玫瑰色',
    'teal-2' => '蓝绿色',
    'olive-2' => '橄榄绿',
    'brown-2' => '棕色',
    'sand-2' => '沙色',
    'slate-2' => '石板灰',
    'steel-2' => '钢蓝色',
    'gray-2' => '灰色',
    'graphite-2' => '石墨灰',
    'black-2' => '墨黑色',
    _ => '蓝色',
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
    final useAndroidFallbackText =
        Theme.of(context).platform == TargetPlatform.android;
    final key = defaultAvatarKey == null
        ? null
        : normalizeAvatarPresetKey(defaultAvatarKey!);
    final fallbackColor = key == null
        ? UiColors.surface
        : avatarFallbackColor(key);
    final fillColor = imageUrl == null ? fallbackColor : Colors.transparent;
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
                          textAlign: TextAlign.center,
                          textScaler: useAndroidFallbackText
                              ? TextScaler.noScaling
                              : null,
                          style: TextStyle(
                            color: key == null && borderActive
                                ? activeColor
                                : UiColors.text,
                            fontSize: size * 0.34,
                            fontWeight: FontWeight.w600,
                            // The desktop font family is unavailable on
                            // Android. Keep the native font's own ascent and
                            // descent so Center can align its complete line box
                            // without a size- or density-specific offset.
                            fontFamily: useAndroidFallbackText
                                ? 'sans-serif'
                                : null,
                          ),
                        ),
                      )
                    : const SizedBox.expand()
              : CachedAssetImage(url: imageUrl!, fit: BoxFit.cover),
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
