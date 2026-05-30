import 'package:flutter/material.dart';

const _keyBackground = Color(0xFF1F232C);
const _keySelectedBackground = Color(0xFF1F2D27);
const _keyPressedBackground = Color(0xFF0F1115);
const _keyDisabledBackground = Color(0xFF1A1D23);
const _keyBorder = Color(0xFF2A2F38);
const _keyAccentBorder = Color(0xFF22332B);
const _keyDangerBorder = Color(0xFF3A2A2E);
const _keyDisabledBorder = Color(0xFF22262E);
const _keyText = Color(0xFFECEFF1);
const _keyMutedText = Color(0xFF6F7785);
const _keyAccent = Color(0xFF6FCFA6);
const _keyDanger = Color(0xFFE58383);

enum KeyButtonTone { neutral, primary, danger }

/// Which corner of a [KeySurface] to chamfer (cut off diagonally).
enum KeyCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Builds the outline for a key surface: a rounded rect, or — when [cornerCut]
/// is a non-empty size — the same rect with a rectangular notch (width ×
/// height) stepped out of one corner.
Path _keyShapePath(
  Rect rect,
  BorderRadius borderRadius,
  Size cornerCut,
  KeyCorner? cutCorner,
) {
  if (cornerCut.width <= 0 || cornerCut.height <= 0 || cutCorner == null) {
    return Path()..addRRect(borderRadius.toRRect(rect));
  }
  final cw = cornerCut.width > rect.width ? rect.width : cornerCut.width;
  final ch = cornerCut.height > rect.height ? rect.height : cornerCut.height;
  final l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
  final path = Path();
  // Top-left corner.
  if (cutCorner == KeyCorner.topLeft) {
    path.moveTo(l + cw, t);
  } else {
    path.moveTo(l, t);
  }
  // Top edge into top-right corner.
  if (cutCorner == KeyCorner.topRight) {
    path.lineTo(r - cw, t);
    path.lineTo(r - cw, t + ch);
    path.lineTo(r, t + ch);
  } else {
    path.lineTo(r, t);
  }
  // Right edge into bottom-right corner.
  if (cutCorner == KeyCorner.bottomRight) {
    path.lineTo(r, b - ch);
    path.lineTo(r - cw, b - ch);
    path.lineTo(r - cw, b);
  } else {
    path.lineTo(r, b);
  }
  // Bottom edge into bottom-left corner.
  if (cutCorner == KeyCorner.bottomLeft) {
    path.lineTo(l + cw, b);
    path.lineTo(l + cw, b - ch);
    path.lineTo(l, b - ch);
  } else {
    path.lineTo(l, b);
  }
  // Left edge back to start, finishing the top-left notch if needed.
  if (cutCorner == KeyCorner.topLeft) {
    path.lineTo(l, t + ch);
    path.lineTo(l + cw, t + ch);
  }
  path.close();
  return path;
}

class _KeyShapeClipper extends CustomClipper<Path> {
  const _KeyShapeClipper({
    required this.borderRadius,
    required this.cornerCut,
    required this.cutCorner,
  });

  final BorderRadius borderRadius;
  final Size cornerCut;
  final KeyCorner? cutCorner;

  @override
  Path getClip(Size size) =>
      _keyShapePath(Offset.zero & size, borderRadius, cornerCut, cutCorner);

  @override
  bool shouldReclip(_KeyShapeClipper oldClipper) =>
      oldClipper.borderRadius != borderRadius ||
      oldClipper.cornerCut != cornerCut ||
      oldClipper.cutCorner != cutCorner;
}

class KeySurface extends StatefulWidget {
  const KeySurface({
    super.key,
    required this.child,
    required this.height,
    this.width,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.onPressed,
    this.tooltip,
    this.enabled = true,
    this.interactive = false,
    this.loading = false,
    this.pressRequiresHover = false,
    this.selected = false,
    this.backgroundColor = _keyBackground,
    this.selectedBackgroundColor = _keySelectedBackground,
    this.pressedBackgroundColor = _keyPressedBackground,
    this.disabledBackgroundColor = _keyDisabledBackground,
    this.borderColor = _keyBorder,
    this.selectedBorderColor = _keyAccentBorder,
    this.disabledBorderColor = _keyDisabledBorder,
    this.borderRadius = 0,
    this.hoverLift = 3,
    this.pressDepth = 3,
    this.baseDepth = 5,
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
  final bool defaultRaised;

  /// Flat mode: the surface is flush with no resting shadow and only lifts
  /// (with a drop shadow) while hovered. Use for docked surfaces such as
  /// headers where the 3D keycap base would otherwise show a permanent gap.
  final bool elevateOnHover;

  /// Size (width × height) of the rectangular notch stepped out of [cutCorner].
  /// [Size.zero] leaves all corners square.
  final Size cornerCut;

  /// Which corner to notch when [cornerCut] is non-empty.
  final KeyCorner? cutCorner;

  @override
  State<KeySurface> createState() => _KeySurfaceState();
}

class _KeySurfaceState extends State<KeySurface> with TickerProviderStateMixin {
  late final AnimationController _hoverController;
  late final AnimationController _pressController;
  bool _hovered = false;

  bool get _isInteractive =>
      widget.enabled && (widget.interactive || widget.onPressed != null);

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 135),
      reverseDuration: const Duration(milliseconds: 115),
    );
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 85),
      reverseDuration: const Duration(milliseconds: 130),
    );
  }

  @override
  void didUpdateWidget(KeySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isInteractive) {
      _hoverController.reverse();
      _pressController.reverse();
    } else if (_hovered) {
      // Re-enabled while the pointer is still over it (e.g. after a loading or
      // busy cycle): resume the hover lift instead of waiting for the pointer
      // to leave and re-enter.
      _hoverController.forward();
    }
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _handleHover(bool hovering) {
    // Always track the real pointer state, even while disabled, so the lift can
    // resume correctly once the surface becomes interactive again.
    _hovered = hovering;
    if (!_isInteractive) return;
    if (hovering) {
      _hoverController.forward();
      return;
    }
    _hoverController.reverse();
    _pressController.reverse();
  }

  void _handlePointerDown() {
    if (!_isInteractive) return;
    if (widget.pressRequiresHover && !_hovered) return;
    _pressController.forward();
  }

  void _handlePointerUp() {
    _pressController.reverse();
    if (_hovered && _isInteractive) {
      _hoverController.forward();
    } else {
      _hoverController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius <= 0
        ? BorderRadius.zero
        : BorderRadius.circular(widget.borderRadius);
    final explicitWidth = widget.width != null && widget.width!.isFinite
        ? widget.width
        : null;
    // In elevate-on-hover mode the surface is flush with no reserved gap: it
    // sits at the top at rest (so no resting shadow) and the cap lifts upward
    // (overflowing its box) on hover, revealing the same keycap base below.
    final topReserve = (widget.defaultRaised || widget.elevateOnHover)
        ? 0.0
        : widget.hoverLift;
    final outerHeight = widget.elevateOnHover
        ? widget.height
        : topReserve + widget.height + widget.baseDepth;
    Widget result = Padding(
      padding: widget.margin,
      child: MouseRegion(
        cursor: _isInteractive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => _handleHover(true),
        onExit: (_) => _handleHover(false),
        child: Listener(
          onPointerDown: (_) => _handlePointerDown(),
          onPointerUp: (_) => _handlePointerUp(),
          onPointerCancel: (_) => _handlePointerUp(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? widget.onPressed : null,
            child: AnimatedBuilder(
              animation: Listenable.merge([_hoverController, _pressController]),
              builder: (context, child) {
                final capChild = child ?? widget.child;
                final hover = Curves.easeOutCubic.transform(
                  _hoverController.value,
                );
                final press = widget.loading
                    ? 1.0
                    : Curves.easeOutCubic.transform(_pressController.value);
                final pressDepth = widget.pressDepth
                    .clamp(0.0, widget.baseDepth)
                    .toDouble();
                final surfaceTop = widget.defaultRaised
                    ? pressDepth * press
                    : topReserve - (widget.hoverLift * hover) * (1 - press);
                final visibleDepth = widget.defaultRaised
                    ? (widget.baseDepth - surfaceTop)
                          .clamp(0.0, widget.baseDepth)
                          .toDouble()
                    : (topReserve - surfaceTop)
                          .clamp(0.0, widget.hoverLift)
                          .toDouble();
                final maxVisibleDepth = widget.defaultRaised
                    ? widget.baseDepth
                    : widget.hoverLift;
                final baseTop = surfaceTop + visibleDepth;
                final baseOpacity = maxVisibleDepth <= 0
                    ? 0.0
                    : (visibleDepth / maxVisibleDepth).clamp(0.0, 1.0);
                final capBackground = widget.enabled
                    ? (widget.selected
                          ? widget.selectedBackgroundColor
                          : widget.backgroundColor)
                    : widget.disabledBackgroundColor;
                final borderColor = widget.enabled
                    ? (widget.selected
                          ? widget.selectedBorderColor
                          : widget.borderColor)
                    : widget.disabledBorderColor;
                final pressedMix = widget.enabled ? 0.42 * press : 0.0;
                final effectiveBackground = Color.lerp(
                  capBackground,
                  widget.pressedBackgroundColor,
                  pressedMix,
                )!;
                final shadowColor = _shadowForBackground(capBackground);
                final seamColor = Color.lerp(
                  shadowColor,
                  borderColor,
                  widget.selected ? 0.26 : 0.16,
                )!;
                final insetOpacity = press;

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final fillWidth =
                        explicitWidth != null || constraints.hasTightWidth;
                    return SizedBox(
                      width: explicitWidth,
                      height: outerHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: baseTop,
                            height: widget.height,
                            child: _KeyBase(
                              opacity: baseOpacity,
                              color: shadowColor,
                              seamColor: seamColor,
                              borderRadius: radius,
                              cornerCut: widget.cornerCut,
                              cutCorner: widget.cutCorner,
                            ),
                          ),
                          if (fillWidth)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: surfaceTop,
                              height: widget.height,
                              child: _KeyCap(
                                padding: widget.padding,
                                background: effectiveBackground,
                                seamColor: seamColor,
                                shadowColor: shadowColor,
                                borderRadius: radius,
                                cornerCut: widget.cornerCut,
                                cutCorner: widget.cutCorner,
                                press: press,
                                insetOpacity: insetOpacity,
                                child: capChild,
                              ),
                            )
                          else
                            Transform.translate(
                              offset: Offset(0, surfaceTop),
                              child: _KeyCap(
                                height: widget.height,
                                padding: widget.padding,
                                background: effectiveBackground,
                                seamColor: seamColor,
                                shadowColor: shadowColor,
                                borderRadius: radius,
                                cornerCut: widget.cornerCut,
                                cutCorner: widget.cutCorner,
                                press: press,
                                insetOpacity: insetOpacity,
                                child: capChild,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }

    return Semantics(
      button: widget.onPressed != null,
      enabled: _isInteractive,
      child: result,
    );
  }
}

class KeyButton extends StatelessWidget {
  const KeyButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.tooltip,
    this.tone = KeyButtonTone.neutral,
    this.selected = false,
    this.width,
    this.height = 42,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.mainAxisSize = MainAxisSize.min,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final String? tooltip;
  final KeyButtonTone tone;
  final bool selected;
  final double? width;
  final double height;
  final EdgeInsetsGeometry padding;
  final MainAxisSize mainAxisSize;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final visuallyEnabled = onPressed != null || loading;
    final effectiveOnPressed = loading ? null : onPressed;
    final colors = _colorsFor(tone, visuallyEnabled);
    final surface = KeySurface(
      onPressed: effectiveOnPressed,
      tooltip: tooltip,
      enabled: visuallyEnabled,
      loading: loading,
      selected: selected || tone == KeyButtonTone.primary,
      height: height,
      padding: padding,
      backgroundColor: colors.background,
      selectedBackgroundColor: colors.background,
      pressedBackgroundColor: colors.pressedBackground,
      borderColor: colors.border,
      selectedBorderColor: colors.border,
      child: IconTheme.merge(
        data: IconThemeData(color: colors.foreground, size: 18),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: colors.foreground,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
          child: Center(
            child: Row(
              mainAxisSize: mainAxisSize,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 8)],
                child,
              ],
            ),
          ),
        ),
      ),
    );
    if (width != null) {
      if (!width!.isFinite) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              width: constraints.maxWidth,
              child: KeySurface(
                onPressed: effectiveOnPressed,
                tooltip: tooltip,
                enabled: visuallyEnabled,
                loading: loading,
                selected: selected || tone == KeyButtonTone.primary,
                width: constraints.maxWidth,
                height: height,
                padding: padding,
                backgroundColor: colors.background,
                selectedBackgroundColor: colors.background,
                pressedBackgroundColor: colors.pressedBackground,
                borderColor: colors.border,
                selectedBorderColor: colors.border,
                child: IconTheme.merge(
                  data: IconThemeData(color: colors.foreground, size: 18),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: colors.foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: mainAxisSize,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            icon!,
                            const SizedBox(width: 8),
                          ],
                          child,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }
      return SizedBox(width: width, child: surface);
    }
    return surface;
  }
}

class KeyIconButton extends StatelessWidget {
  const KeyIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    this.tone = KeyButtonTone.neutral,
    this.selected = false,
    this.size = 40,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String tooltip;
  final KeyButtonTone tone;
  final bool selected;
  final double size;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final visuallyEnabled = onPressed != null || loading;
    final effectiveOnPressed = loading ? null : onPressed;
    final colors = _colorsFor(tone, visuallyEnabled);
    return SizedBox(
      width: size,
      child: KeySurface(
        onPressed: effectiveOnPressed,
        tooltip: tooltip,
        enabled: visuallyEnabled,
        loading: loading,
        selected: selected || tone == KeyButtonTone.primary,
        height: size,
        padding: EdgeInsets.zero,
        backgroundColor: colors.background,
        selectedBackgroundColor: colors.background,
        pressedBackgroundColor: colors.pressedBackground,
        borderColor: colors.border,
        selectedBorderColor: colors.border,
        child: IconTheme.merge(
          data: IconThemeData(color: colors.foreground, size: size * 0.46),
          child: Center(child: icon),
        ),
      ),
    );
  }
}

class _KeyBase extends StatelessWidget {
  const _KeyBase({
    required this.opacity,
    required this.color,
    required this.seamColor,
    required this.borderRadius,
    this.cornerCut = Size.zero,
    this.cutCorner,
  });

  final double opacity;
  final Color color;
  final Color seamColor;
  final BorderRadius borderRadius;
  final Size cornerCut;
  final KeyCorner? cutCorner;

  @override
  Widget build(BuildContext context) {
    Widget fill = DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: borderRadius),
    );
    if (cornerCut.width > 0 && cornerCut.height > 0 && cutCorner != null) {
      fill = ClipPath(
        clipper: _KeyShapeClipper(
          borderRadius: borderRadius,
          cornerCut: cornerCut,
          cutCorner: cutCorner,
        ),
        child: ColoredBox(color: color),
      );
    }
    return Opacity(opacity: opacity, child: fill);
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({
    required this.padding,
    required this.background,
    required this.seamColor,
    required this.shadowColor,
    required this.borderRadius,
    required this.press,
    required this.insetOpacity,
    required this.child,
    this.cornerCut = Size.zero,
    this.cutCorner,
    this.height,
  });

  final EdgeInsetsGeometry padding;
  final Color background;
  final Color seamColor;
  final Color shadowColor;
  final BorderRadius borderRadius;
  final double press;
  final double insetOpacity;
  final Widget child;
  final Size cornerCut;
  final KeyCorner? cutCorner;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: _KeyCapDecoration(
        background: background,
        seamColor: seamColor,
        borderRadius: borderRadius,
        press: press,
        cornerCut: cornerCut,
        cutCorner: cutCorner,
      ),
      foregroundDecoration: _KeyInsetDecoration(
        opacity: insetOpacity,
        borderRadius: borderRadius,
        shadowColor: shadowColor,
        cornerCut: cornerCut,
        cutCorner: cutCorner,
      ),
      child: child,
    );
  }
}

class _KeyCapDecoration extends Decoration {
  const _KeyCapDecoration({
    required this.background,
    required this.seamColor,
    required this.borderRadius,
    required this.press,
    required this.cornerCut,
    required this.cutCorner,
  });

  final Color background;
  final Color seamColor;
  final BorderRadius borderRadius;
  final double press;
  final Size cornerCut;
  final KeyCorner? cutCorner;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _KeyCapPainter(this);
  }

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) {
    return _keyShapePath(rect, borderRadius, cornerCut, cutCorner);
  }
}

class _KeyCapPainter extends BoxPainter {
  const _KeyCapPainter(this.decoration);

  final _KeyCapDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;

    final rect = (offset & size).deflate(0.5);
    final path = _keyShapePath(
      rect,
      decoration.borderRadius,
      decoration.cornerCut,
      decoration.cutCorner,
    );
    canvas.drawPath(path, Paint()..color = decoration.background);
  }
}

class _KeyInsetDecoration extends Decoration {
  const _KeyInsetDecoration({
    required this.opacity,
    required this.borderRadius,
    required this.shadowColor,
    required this.cornerCut,
    required this.cutCorner,
  });

  final double opacity;
  final BorderRadius borderRadius;
  final Color shadowColor;
  final Size cornerCut;
  final KeyCorner? cutCorner;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _KeyInsetPainter(this);
  }
}

class _KeyInsetPainter extends BoxPainter {
  const _KeyInsetPainter(this.decoration);

  final _KeyInsetDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    final opacity = decoration.opacity.clamp(0.0, 1.0);
    if (size == null || opacity == 0) return;

    final rect = offset & size;
    final clipPath = _keyShapePath(
      rect,
      decoration.borderRadius,
      decoration.cornerCut,
      decoration.cutCorner,
    );
    final shadow = Color.lerp(
      Colors.transparent,
      decoration.shadowColor,
      opacity,
    )!;
    final topShadow = Color.lerp(Colors.transparent, shadow, 0.76)!;
    final sideShadow = Color.lerp(Colors.transparent, shadow, 0.7)!;
    final bottomShadow = Color.lerp(Colors.transparent, shadow, 0.28)!;

    final cutCorner = decoration.cutCorner;
    final cut = decoration.cornerCut;
    final hasCut = cutCorner != null && cut.width > 0 && cut.height > 0;
    final cw = hasCut
        ? (cut.width > rect.width ? rect.width : cut.width)
        : 0.0;
    final ch = hasCut
        ? (cut.height > rect.height ? rect.height : cut.height)
        : 0.0;

    // Top edge runs exactly to a top-corner notch wall — far enough to shade
    // the convex corner, but not past the wall into the cut.
    final topLeftX = (hasCut && cutCorner == KeyCorner.topLeft)
        ? rect.left + cw
        : rect.left + 1;
    final topRightX = (hasCut && cutCorner == KeyCorner.topRight)
        ? rect.right - cw
        : rect.right - 1;

    canvas.save();
    canvas.clipPath(clipPath);
    canvas.drawLine(
      Offset(topLeftX, rect.top + 1.75),
      Offset(topRightX, rect.top + 1.75),
      Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.butt
        ..color = topShadow,
    );
    canvas.drawLine(
      rect.topLeft.translate(0.9, 0.5),
      rect.bottomLeft.translate(0.9, 0.5),
      Paint()
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.butt
        ..color = sideShadow,
    );
    canvas.drawLine(
      rect.topRight.translate(-0.9, 0.5),
      rect.bottomRight.translate(-0.9, 0.5),
      Paint()
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.butt
        ..color = sideShadow,
    );
    canvas.drawLine(
      rect.bottomLeft.translate(1, -0.6),
      rect.bottomRight.translate(-1, -0.6),
      Paint()
        ..strokeWidth = 0.6
        ..strokeCap = StrokeCap.butt
        ..color = bottomShadow,
    );
    // The notch's inner angle reuses the same edge shadows as the outer rect:
    // its vertical wall gets the side-edge shadow, its horizontal floor gets
    // the top- (or bottom-) edge shadow.
    if (hasCut) {
      final capOnLeft =
          cutCorner == KeyCorner.topRight || cutCorner == KeyCorner.bottomRight;
      final atTop =
          cutCorner == KeyCorner.topLeft || cutCorner == KeyCorner.topRight;
      final wallX = capOnLeft ? rect.right - cw : rect.left + cw;
      final edgeY = atTop ? rect.top + ch : rect.bottom - ch;
      final wallLineX = capOnLeft ? wallX - 0.9 : wallX + 0.9;
      final floorY = atTop ? edgeY + 1.75 : edgeY - 0.6;

      // Vertical wall (side-edge shadow). Runs all the way to the floor shadow
      // so the concave inner corner is filled.
      final wallOuterY = atTop ? rect.top + 0.5 : rect.bottom - 0.5;
      canvas.drawLine(
        Offset(wallLineX, wallOuterY),
        Offset(wallLineX, floorY),
        Paint()
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.butt
          ..color = sideShadow,
      );

      // Horizontal floor (top-edge, or bottom-edge if the cut is at the
      // bottom). Runs to the wall shadow so they cross at the inner corner.
      final floorX0 = capOnLeft ? wallLineX : rect.left + 1;
      final floorX1 = capOnLeft ? rect.right - 1 : wallLineX;
      canvas.drawLine(
        Offset(floorX0, floorY),
        Offset(floorX1, floorY),
        Paint()
          ..strokeWidth = atTop ? 3 : 0.6
          ..strokeCap = StrokeCap.butt
          ..color = atTop ? topShadow : bottomShadow,
      );
    }
    canvas.restore();
  }
}

class _KeyButtonColors {
  const _KeyButtonColors({
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

Color _shadowForBackground(Color background) {
  final hsl = HSLColor.fromColor(background);
  final saturation = (hsl.saturation * 1.35).clamp(0.0, 1.0).toDouble();
  final lightness = (hsl.lightness * 0.49).clamp(0.06, 0.12).toDouble();
  return hsl.withSaturation(saturation).withLightness(lightness).toColor();
}

_KeyButtonColors _colorsFor(KeyButtonTone tone, bool enabled) {
  if (!enabled) {
    return const _KeyButtonColors(
      background: _keyDisabledBackground,
      pressedBackground: _keyDisabledBackground,
      border: _keyDisabledBorder,
      foreground: _keyMutedText,
    );
  }

  switch (tone) {
    case KeyButtonTone.neutral:
      return const _KeyButtonColors(
        background: _keyBackground,
        pressedBackground: _keyPressedBackground,
        border: _keyBorder,
        foreground: _keyText,
      );
    case KeyButtonTone.primary:
      return const _KeyButtonColors(
        background: _keySelectedBackground,
        pressedBackground: Color(0xFF14211B),
        border: _keyAccentBorder,
        foreground: _keyAccent,
      );
    case KeyButtonTone.danger:
      return const _KeyButtonColors(
        background: Color(0xFF2E1F22),
        pressedBackground: Color(0xFF1A1214),
        border: _keyDangerBorder,
        foreground: _keyDanger,
      );
  }
}
