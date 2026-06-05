import 'package:flutter/material.dart';

import 'tokens.dart';

enum ButtonTone { neutral, primary, danger }

enum SurfaceCorner { topLeft, topRight, bottomLeft, bottomRight }

class PressableSurface extends StatefulWidget {
  const PressableSurface({
    super.key,
    required this.child,
    required this.height,
    this.width,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.onPressed,
    this.tooltip,
    this.mouseCursor,
    this.enabled = true,
    this.interactive = false,
    this.loading = false,
    this.pressRequiresHover = false,
    this.selected = false,
    this.backgroundColor = UiColors.surface,
    this.selectedBackgroundColor = UiColors.selected,
    this.pressedBackgroundColor = UiColors.surfacePressed,
    this.disabledBackgroundColor = UiColors.disabledSurface,
    this.borderColor = UiColors.border,
    this.selectedBorderColor = UiColors.accentBorder,
    this.disabledBorderColor = UiColors.disabledBorder,
    this.borderRadius = UiRadii.sm,
    this.hoverLift = 3,
    this.pressDepth = double.infinity,
    this.baseDepth = 5,
    this.hoverEffect = true,
    this.pressEffect = true,
    this.defaultRaised = false,
    this.elevateOnHover = false,
    this.cornerCut = Size.zero,
    this.cutCorner,
  });

  final Widget child;
  final double height;
  final double? width;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onPressed;
  final String? tooltip;
  final MouseCursor? mouseCursor;
  final bool enabled;
  final bool interactive;
  final bool loading;
  final bool pressRequiresHover;
  final bool selected;
  final Color backgroundColor;
  final Color selectedBackgroundColor;
  final Color pressedBackgroundColor;
  final Color disabledBackgroundColor;
  final Color borderColor;
  final Color selectedBorderColor;
  final Color disabledBorderColor;
  final double borderRadius;
  final double hoverLift;
  final double pressDepth;
  final double baseDepth;
  final bool hoverEffect;
  final bool pressEffect;
  final bool defaultRaised;
  final bool elevateOnHover;
  final Size cornerCut;
  final SurfaceCorner? cutCorner;

  @override
  State<PressableSurface> createState() => _PressableSurfaceState();
}

class _PressableSurfaceState extends State<PressableSurface> {
  final GlobalKey _hitTargetKey = GlobalKey();

  bool _hovered = false;
  bool _pressed = false;
  int? _pressedPointer;

  bool get _isInteractive =>
      widget.enabled && (widget.interactive || widget.onPressed != null);

  void _setHover(bool hovered) {
    _hovered = hovered;
    if (!hovered && _pressedPointer == null) _pressed = false;
    if (mounted) setState(() {});
  }

  void _setPressed(bool pressed) {
    if (!_isInteractive || !widget.pressEffect) return;
    if (pressed && widget.pressRequiresHover && !_hovered) return;
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  void _handleTap() {
    if (!widget.enabled || widget.loading) return;
    widget.onPressed?.call();
  }

  bool _isInsideHitTarget(Offset position) {
    final renderObject = _hitTargetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return false;
    final size = renderObject.size;
    return position.dx >= 0 &&
        position.dy >= 0 &&
        position.dx <= size.width &&
        position.dy <= size.height;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isInteractive || widget.loading || _pressedPointer != null) return;
    _pressedPointer = event.pointer;
    _setPressed(_isInsideHitTarget(event.localPosition));
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pressedPointer) return;
    _setPressed(_isInsideHitTarget(event.localPosition));
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _pressedPointer) return;
    final shouldPress = _isInsideHitTarget(event.localPosition);
    _pressedPointer = null;
    _setPressed(false);
    if (shouldPress) _handleTap();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pressedPointer) return;
    _pressedPointer = null;
    _setPressed(false);
  }

  @override
  void didUpdateWidget(PressableSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isInteractive && (_hovered || _pressed)) {
      _hovered = false;
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius <= 0
        ? BorderRadius.zero
        : BorderRadius.circular(widget.borderRadius);
    final background = widget.enabled
        ? (widget.selected
              ? widget.selectedBackgroundColor
              : widget.backgroundColor)
        : widget.disabledBackgroundColor;
    final borderColor = widget.enabled
        ? (widget.selected ? widget.selectedBorderColor : widget.borderColor)
        : widget.disabledBorderColor;
    final pressed = widget.loading || (_pressed && widget.pressEffect);
    final effectiveBackground = pressed
        ? Color.lerp(background, widget.pressedBackgroundColor, 0.28)!
        : background;
    final shadowColor = _shadowFor(background);
    final hoverLift = widget.hoverEffect && _hovered && _isInteractive
        ? widget.hoverLift
        : 0.0;
    final maxDepth = widget.baseDepth.clamp(0.0, double.infinity).toDouble();
    final pressDepth = widget.pressDepth.clamp(0.0, maxDepth).toDouble();
    final outerHeight = widget.elevateOnHover
        ? widget.height
        : widget.height + widget.hoverLift + maxDepth;
    final baseTop = widget.elevateOnHover ? 0.0 : widget.hoverLift + maxDepth;
    final restTop = widget.elevateOnHover
        ? 0.0
        : widget.defaultRaised
        ? 0.0
        : widget.hoverLift;
    final bottomTop = widget.elevateOnHover ? 0.0 : widget.hoverLift + maxDepth;
    final capTop = widget.elevateOnHover
        ? (pressed ? 0.0 : -hoverLift)
        : pressed
        ? (restTop + pressDepth).clamp(0.0, bottomTop).toDouble()
        : (restTop - hoverLift).clamp(0.0, bottomTop).toDouble();
    final baseOpacity = widget.enabled ? 1.0 : 0.42;
    final explicitWidth = widget.width != null && widget.width!.isFinite
        ? widget.width
        : null;
    final cap = _SurfaceLayer(
      background: effectiveBackground,
      borderColor: borderColor,
      borderRadius: radius,
      cornerCut: widget.cornerCut,
      cutCorner: widget.cutCorner,
      padding: widget.padding,
      child: widget.child,
    );

    Widget result = Padding(
      padding: widget.margin,
      child: MouseRegion(
        cursor:
            widget.mouseCursor ??
            (_isInteractive
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic),
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: Listener(
          key: _hitTargetKey,
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fillWidth =
                  explicitWidth != null || constraints.hasTightWidth;
              final stack = Stack(
                clipBehavior: widget.elevateOnHover ? Clip.none : Clip.hardEdge,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: baseTop,
                    height: widget.height,
                    child: Opacity(
                      opacity: baseOpacity,
                      child: _SurfaceLayer(
                        background: shadowColor,
                        borderColor: borderColor,
                        borderRadius: radius,
                        cornerCut: widget.cornerCut,
                        cutCorner: widget.cutCorner,
                      ),
                    ),
                  ),
                  if (fillWidth)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 95),
                      curve: Curves.easeOutCubic,
                      left: 0,
                      right: 0,
                      top: capTop,
                      height: widget.height,
                      child: cap,
                    )
                  else
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 95),
                      curve: Curves.easeOutCubic,
                      transform: Matrix4.translationValues(0, capTop, 0),
                      child: SizedBox(height: widget.height, child: cap),
                    ),
                ],
              );

              return SizedBox(
                width: explicitWidth,
                height: outerHeight,
                child: stack,
              );
            },
          ),
        ),
      ),
    );

    final tooltip = widget.tooltip;
    if (tooltip != null && tooltip.isNotEmpty) {
      result = Tooltip(message: tooltip, child: result);
    }

    return Semantics(
      button: widget.onPressed != null,
      enabled: _isInteractive,
      child: result,
    );
  }
}

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

class _SurfaceLayer extends StatelessWidget {
  const _SurfaceLayer({
    required this.background,
    required this.borderColor,
    required this.borderRadius,
    this.padding = EdgeInsets.zero,
    this.child,
    this.cornerCut = Size.zero,
    this.cutCorner,
  });

  final Color background;
  final Color borderColor;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Widget? child;
  final Size cornerCut;
  final SurfaceCorner? cutCorner;

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius,
        border: _visibleBorder(borderColor)
            ? Border.all(color: borderColor)
            : null,
      ),
      child: Padding(padding: padding, child: child ?? const SizedBox.expand()),
    );

    if (cornerCut.width <= 0 || cornerCut.height <= 0 || cutCorner == null) {
      return ClipRRect(borderRadius: borderRadius, child: content);
    }

    return ClipPath(
      clipper: _SurfaceClipper(
        borderRadius: borderRadius,
        cornerCut: cornerCut,
        cutCorner: cutCorner!,
      ),
      child: content,
    );
  }
}

class _SurfaceClipper extends CustomClipper<Path> {
  const _SurfaceClipper({
    required this.borderRadius,
    required this.cornerCut,
    required this.cutCorner,
  });

  final BorderRadius borderRadius;
  final Size cornerCut;
  final SurfaceCorner cutCorner;

  @override
  Path getClip(Size size) =>
      _surfacePath(Offset.zero & size, borderRadius, cornerCut, cutCorner);

  @override
  bool shouldReclip(_SurfaceClipper oldClipper) =>
      oldClipper.borderRadius != borderRadius ||
      oldClipper.cornerCut != cornerCut ||
      oldClipper.cutCorner != cutCorner;
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

bool _visibleBorder(Color color) => color.a > 0;

Path _surfacePath(
  Rect rect,
  BorderRadius borderRadius,
  Size cornerCut,
  SurfaceCorner cutCorner,
) {
  final cw = cornerCut.width.clamp(0.0, rect.width).toDouble();
  final ch = cornerCut.height.clamp(0.0, rect.height).toDouble();
  if (cw <= 0 || ch <= 0) {
    return Path()..addRRect(borderRadius.toRRect(rect));
  }

  final path = Path();
  final l = rect.left;
  final t = rect.top;
  final r = rect.right;
  final b = rect.bottom;

  if (cutCorner == SurfaceCorner.topLeft) {
    path
      ..moveTo(l + cw, t)
      ..lineTo(r, t)
      ..lineTo(r, b)
      ..lineTo(l, b)
      ..lineTo(l, t + ch)
      ..lineTo(l + cw, t + ch);
  } else if (cutCorner == SurfaceCorner.topRight) {
    path
      ..moveTo(l, t)
      ..lineTo(r - cw, t)
      ..lineTo(r - cw, t + ch)
      ..lineTo(r, t + ch)
      ..lineTo(r, b)
      ..lineTo(l, b);
  } else if (cutCorner == SurfaceCorner.bottomRight) {
    path
      ..moveTo(l, t)
      ..lineTo(r, t)
      ..lineTo(r, b - ch)
      ..lineTo(r - cw, b - ch)
      ..lineTo(r - cw, b)
      ..lineTo(l, b);
  } else {
    path
      ..moveTo(l, t)
      ..lineTo(r, t)
      ..lineTo(r, b)
      ..lineTo(l + cw, b)
      ..lineTo(l + cw, b - ch)
      ..lineTo(l, b - ch);
  }

  path.close();
  return path;
}

Color _shadowFor(Color background) {
  return Color.lerp(background, Colors.black, 0.46)!;
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
