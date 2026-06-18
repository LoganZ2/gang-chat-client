import 'package:flutter/material.dart';

import 'highlighted_text.dart';
import 'tokens.dart';

enum RoleBadgeTone { member, admin, creator, superuser, neutral }

RoleBadgeTone roleBadgeToneForLabel(String label) {
  return switch (label.trim()) {
    '成员' => RoleBadgeTone.member,
    '管理员' => RoleBadgeTone.admin,
    '创建者' => RoleBadgeTone.creator,
    '超级用户' => RoleBadgeTone.superuser,
    _ => RoleBadgeTone.neutral,
  };
}

Color roleBadgeForegroundColorForLabel(String label) {
  return _roleBadgeStyle(roleBadgeToneForLabel(label)).foreground;
}

class RoleBadge extends StatelessWidget {
  const RoleBadge({
    super.key,
    required this.label,
    this.query = '',
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    this.borderRadius = 999,
    this.fontSize = 12,
    this.fontWeight = FontWeight.w600,
  });

  final String label;
  final String query;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final style = _roleBadgeStyle(roleBadgeToneForLabel(label));
    final textStyle = UiTypography.label.copyWith(
      color: style.foreground,
      fontSize: fontSize,
      fontWeight: fontWeight,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: style.border),
      ),
      child: Padding(
        padding: padding,
        child: query.trim().isEmpty
            ? Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              )
            : HighlightedText(
                text: label,
                query: query,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
      ),
    );
  }
}

class _RoleBadgeStyle {
  const _RoleBadgeStyle({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}

_RoleBadgeStyle _roleBadgeStyle(RoleBadgeTone tone) {
  return switch (tone) {
    RoleBadgeTone.member => const _RoleBadgeStyle(
      foreground: UiColors.roleMember,
      background: UiColors.roleMemberSurface,
      border: UiColors.roleMemberBorder,
    ),
    RoleBadgeTone.admin => const _RoleBadgeStyle(
      foreground: UiColors.roleAdmin,
      background: UiColors.roleAdminSurface,
      border: UiColors.roleAdminBorder,
    ),
    RoleBadgeTone.creator => const _RoleBadgeStyle(
      foreground: UiColors.roleCreator,
      background: UiColors.roleCreatorSurface,
      border: UiColors.roleCreatorBorder,
    ),
    RoleBadgeTone.superuser => const _RoleBadgeStyle(
      foreground: UiColors.roleSuperuser,
      background: UiColors.roleSuperuserSurface,
      border: UiColors.roleSuperuserBorder,
    ),
    RoleBadgeTone.neutral => const _RoleBadgeStyle(
      foreground: UiColors.textSecondary,
      background: UiColors.surfacePressed,
      border: UiColors.border,
    ),
  };
}
