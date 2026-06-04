import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

class PopoverSurface extends StatelessWidget {
  const PopoverSurface({
    super.key,
    required this.child,
    this.width = 360,
    this.arrowRight = 30,
    this.backgroundColor = UiColors.surfaceLow,
  });

  final Widget child;
  final double width;
  final double arrowRight;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(UiRadii.lg),
                border: Border.all(color: UiColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.34),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: child,
            ),
            Positioned(
              right: arrowRight,
              bottom: -9,
              child: CustomPaint(
                size: const Size(18, 10),
                painter: _PopoverArrowPainter(
                  fillColor: backgroundColor,
                  borderColor: UiColors.border,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PopoverAnchor extends StatefulWidget {
  const PopoverAnchor({
    super.key,
    required this.anchor,
    required this.popover,
    this.width = 360,
    this.arrowRight = 30,
    this.gap = 8,
  });

  final Widget Function(BuildContext context, bool open, VoidCallback toggle)
  anchor;
  final Widget popover;
  final double width;
  final double arrowRight;
  final double gap;

  @override
  State<PopoverAnchor> createState() => _PopoverAnchorState();
}

class _PopoverAnchorState extends State<PopoverAnchor> {
  final GlobalKey _anchorKey = GlobalKey();
  final Object _tapRegionGroup = Object();
  final OverlayPortalController _portal = OverlayPortalController();

  bool get _open => _portal.isShowing;

  void _toggle() => _open ? _close() : _openPopover();

  void _openPopover() {
    if (_portal.isShowing) return;
    _portal.show();
    setState(() {});
  }

  void _close() {
    if (!_portal.isShowing) return;
    _portal.hide();
    if (mounted) setState(() {});
  }

  Rect? _anchorRectInOverlay() {
    final anchorContext = _anchorKey.currentContext;
    final overlay = Overlay.maybeOf(context);
    final anchorBox = anchorContext?.findRenderObject();
    final overlayBox = overlay?.context.findRenderObject();
    if (anchorBox is! RenderBox ||
        overlayBox is! RenderBox ||
        !anchorBox.hasSize ||
        !overlayBox.hasSize) {
      return null;
    }

    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    return topLeft & anchorBox.size;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        return Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final anchorRect = _anchorRectInOverlay();
              if (anchorRect == null) return const SizedBox.shrink();

              final overlayWidth = constraints.maxWidth;
              final overlayHeight = constraints.maxHeight;
              final maxRight = overlayWidth.isFinite
                  ? math.max(0.0, overlayWidth - widget.width)
                  : double.infinity;
              final right = overlayWidth.isFinite
                  ? (overlayWidth - anchorRect.right)
                        .clamp(0.0, maxRight)
                        .toDouble()
                  : 0.0;
              final bottom = overlayHeight.isFinite
                  ? math.max(0.0, overlayHeight - anchorRect.top + widget.gap)
                  : 0.0;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    right: right,
                    bottom: bottom,
                    width: widget.width,
                    child: TapRegion(
                      groupId: _tapRegionGroup,
                      child: PopoverSurface(
                        width: widget.width,
                        arrowRight: widget.arrowRight,
                        child: widget.popover,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
      child: TapRegion(
        groupId: _tapRegionGroup,
        onTapOutside: (_) => _close(),
        child: KeyedSubtree(
          key: _anchorKey,
          child: widget.anchor(context, _open, _toggle),
        ),
      ),
    );
  }
}

class _PopoverArrowPainter extends CustomPainter {
  const _PopoverArrowPainter({
    required this.fillColor,
    required this.borderColor,
  });

  final Color fillColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_PopoverArrowPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor;
  }
}
