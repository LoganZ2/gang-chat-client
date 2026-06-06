import 'package:flutter/material.dart';

import 'surface.dart';
import 'tokens.dart';

enum ButtonTone { neutral, primary, danger }

class Button extends StatelessWidget {
  const Button({
    super.key,
    required this.child,
    this.onPressed,
    this.icon,
    this.tooltip,
    this.tone = ButtonTone.neutral,
    this.selected = false,
    this.toggleValue,
    this.onToggleChanged,
    this.width,
    this.height = 40,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.mainAxisSize = MainAxisSize.min,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final ValueChanged<bool>? onToggleChanged;
  final Widget child;
  final Widget? icon;
  final String? tooltip;
  final ButtonTone tone;
  final bool selected;
  final bool? toggleValue;
  final double? width;
  final double height;
  final EdgeInsetsGeometry padding;
  final MainAxisSize mainAxisSize;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final toggleMode = toggleValue != null || onToggleChanged != null;
    final toggled = toggleValue ?? false;
    final visuallyEnabled =
        onPressed != null || onToggleChanged != null || loading;
    final effectiveOnPressed = loading
        ? null
        : toggleMode && onToggleChanged != null
        ? () => onToggleChanged!(!toggled)
        : onPressed;
    final active = selected || toggled || tone == ButtonTone.primary;
    final colors = _colorsFor(tone, visuallyEnabled, active: active);
    final content = _ButtonContent(
      colors: colors,
      icon: icon,
      mainAxisSize: mainAxisSize,
      child: child,
    );

    Widget surfaceFor({double? surfaceWidth}) {
      return PressableSurface(
        onPressed: effectiveOnPressed,
        tooltip: tooltip,
        enabled: visuallyEnabled,
        loading: loading,
        selected: active,
        width: surfaceWidth,
        height: height,
        padding: padding,
        backgroundColor: colors.background,
        selectedBackgroundColor: colors.background,
        pressedBackgroundColor: colors.pressedBackground,
        borderColor: colors.border,
        selectedBorderColor: colors.border,
        child: content,
      );
    }

    final requestedWidth = width;
    if (requestedWidth == null) return surfaceFor();
    if (!requestedWidth.isFinite) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return surfaceFor(surfaceWidth: constraints.maxWidth);
        },
      );
    }
    return surfaceFor(surfaceWidth: requestedWidth);
  }
}

class ButtonIcon extends StatelessWidget {
  const ButtonIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.tone = ButtonTone.neutral,
    this.selected = false,
    this.toggleValue,
    this.onToggleChanged,
    this.size = 40,
    this.loading = false,
    this.backgroundColor,
    this.borderColor,
  });

  final VoidCallback? onPressed;
  final ValueChanged<bool>? onToggleChanged;
  final Widget icon;
  final String tooltip;
  final ButtonTone tone;
  final bool selected;
  final bool? toggleValue;
  final double size;
  final bool loading;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final toggleMode = toggleValue != null || onToggleChanged != null;
    final toggled = toggleValue ?? false;
    final visuallyEnabled =
        onPressed != null || onToggleChanged != null || loading;
    final effectiveOnPressed = loading
        ? null
        : toggleMode && onToggleChanged != null
        ? () => onToggleChanged!(!toggled)
        : onPressed;
    final active = selected || toggled || tone == ButtonTone.primary;
    final colors = _colorsFor(tone, visuallyEnabled, active: active);
    final background = backgroundColor ?? colors.background;
    final border = borderColor ?? colors.border;

    return PressableSurface(
      onPressed: effectiveOnPressed,
      tooltip: tooltip,
      enabled: visuallyEnabled,
      loading: loading,
      selected: active,
      width: size,
      height: size,
      padding: EdgeInsets.zero,
      backgroundColor: background,
      selectedBackgroundColor: background,
      pressedBackgroundColor: colors.pressedBackground,
      borderColor: border,
      selectedBorderColor: border,
      child: IconTheme.merge(
        data: IconThemeData(color: colors.foreground, size: size * 0.46),
        child: Center(child: icon),
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.colors,
    required this.child,
    required this.mainAxisSize,
    this.icon,
  });

  final _ButtonColors colors;
  final Widget child;
  final Widget? icon;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    final label = DefaultTextStyle.merge(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.foreground,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      child: ClipRect(child: child),
    );

    return IconTheme.merge(
      data: IconThemeData(color: colors.foreground, size: 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bounded = constraints.maxWidth.isFinite;
          return Center(
            child: Row(
              mainAxisSize: bounded ? MainAxisSize.max : mainAxisSize,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 8)],
                if (bounded) Flexible(child: label) else label,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ButtonColors {
  const _ButtonColors({
    required this.background,
    required this.pressedBackground,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color pressedBackground;
  final Color border;
  final Color foreground;
}

_ButtonColors _colorsFor(ButtonTone tone, bool enabled, {bool active = false}) {
  if (!enabled) {
    return const _ButtonColors(
      background: UiColors.disabledSurface,
      pressedBackground: UiColors.disabledSurface,
      border: UiColors.disabledBorder,
      foreground: UiColors.textMuted,
    );
  }

  switch (tone) {
    case ButtonTone.neutral:
      if (active) {
        return const _ButtonColors(
          background: UiColors.selected,
          pressedBackground: Color(0xFF14211B),
          border: UiColors.accentBorder,
          foreground: UiColors.accent,
        );
      }
      return const _ButtonColors(
        background: UiColors.surface,
        pressedBackground: UiColors.surfacePressed,
        border: UiColors.border,
        foreground: UiColors.text,
      );
    case ButtonTone.primary:
      return const _ButtonColors(
        background: UiColors.selected,
        pressedBackground: Color(0xFF14211B),
        border: UiColors.accentBorder,
        foreground: UiColors.accent,
      );
    case ButtonTone.danger:
      return const _ButtonColors(
        background: Color(0xFF2E1F22),
        pressedBackground: Color(0xFF1A1214),
        border: UiColors.dangerBorder,
        foreground: UiColors.danger,
      );
  }
}
