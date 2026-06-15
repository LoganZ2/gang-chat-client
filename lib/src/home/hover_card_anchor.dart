import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/ui.dart';

const double hoverCardDefaultWidth = 248;
const double hoverCardDefaultGap = 10;

typedef HoverCardBuilder = Widget Function(BuildContext context);

/// Shared hover/tap shell for small profile cards anchored to an avatar.
class HoverCardAnchor extends StatefulWidget {
  const HoverCardAnchor({
    super.key,
    required this.child,
    required this.cardBuilder,
    this.onBeforeOpen,
    this.resetKey,
    this.cardWidth = hoverCardDefaultWidth,
    this.gap = hoverCardDefaultGap,
    this.closeDelay = const Duration(milliseconds: 120),
  });

  final Widget child;
  final HoverCardBuilder cardBuilder;
  final Future<void> Function()? onBeforeOpen;
  final Object? resetKey;
  final double cardWidth;
  final double gap;
  final Duration closeDelay;

  @override
  State<HoverCardAnchor> createState() => _HoverCardAnchorState();
}

class _HoverCardAnchorState extends State<HoverCardAnchor> {
  final GlobalKey _anchorKey = GlobalKey();
  final OverlayPortalController _portal = OverlayPortalController();
  final Object _tapRegionGroup = Object();

  bool _overAnchor = false;
  bool _overCard = false;
  bool _pinned = false;
  Timer? _closeTimer;
  Future<void>? _openFuture;

  bool get _wantsOpen => _pinned || _overAnchor || _overCard;

  @override
  void didUpdateWidget(covariant HoverCardAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey == widget.resetKey) return;
    _dismiss();
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _enterAnchor() {
    _overAnchor = true;
    _open();
  }

  void _exitAnchor() {
    _overAnchor = false;
    _scheduleClose();
  }

  void _enterCard() {
    _overCard = true;
    _closeTimer?.cancel();
  }

  void _exitCard() {
    _overCard = false;
    _scheduleClose();
  }

  void _open() {
    _closeTimer?.cancel();
    final beforeOpen = widget.onBeforeOpen;
    if (beforeOpen == null) {
      _showPortal();
      return;
    }
    final existing = _openFuture;
    if (existing != null) return;

    final future = Future<void>.sync(beforeOpen);
    _openFuture = future;
    unawaited(
      future.catchError((_) {}).whenComplete(() {
        if (!mounted || _openFuture != future) return;
        _openFuture = null;
        if (_wantsOpen) _showPortal();
      }),
    );
  }

  void _showPortal() {
    if (_portal.isShowing) return;
    _portal.show();
  }

  void _pinOpen() {
    _pinned = true;
    _open();
  }

  void _dismiss() {
    _pinned = false;
    _overAnchor = false;
    _overCard = false;
    _closeTimer?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  void _scheduleClose() {
    if (_pinned) return;
    _closeTimer?.cancel();
    _closeTimer = Timer(widget.closeDelay, () {
      if (!mounted || _pinned || _overAnchor || _overCard) return;
      if (_portal.isShowing) _portal.hide();
    });
  }

  Rect? _anchorRectInOverlay() {
    final anchorBox = _anchorKey.currentContext?.findRenderObject();
    final overlayBox = Overlay.maybeOf(context)?.context.findRenderObject();
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
              return CustomSingleChildLayout(
                delegate: _HoverCardLayoutDelegate(
                  anchorRect: anchorRect,
                  gap: widget.gap,
                  cardWidth: widget.cardWidth,
                ),
                child: TapRegion(
                  groupId: _tapRegionGroup,
                  onTapOutside: (_) => _dismiss(),
                  child: MouseRegion(
                    onEnter: (_) => _enterCard(),
                    onExit: (_) => _exitCard(),
                    child: AnchoredPanel(
                      width: widget.cardWidth,
                      child: widget.cardBuilder(context),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      child: TapRegion(
        groupId: _tapRegionGroup,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _pinOpen,
          child: MouseRegion(
            onEnter: (_) => _enterAnchor(),
            onExit: (_) => _exitAnchor(),
            child: KeyedSubtree(key: _anchorKey, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _HoverCardLayoutDelegate extends SingleChildLayoutDelegate {
  const _HoverCardLayoutDelegate({
    required this.anchorRect,
    required this.gap,
    required this.cardWidth,
  });

  final Rect anchorRect;
  final double gap;
  final double cardWidth;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      constraints.biggest,
    ).copyWith(minWidth: cardWidth, maxWidth: cardWidth);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final spaceRight = size.width - anchorRect.right - gap;
    final placeRight = spaceRight >= childSize.width;
    final rawLeft = placeRight
        ? anchorRect.right + gap
        : anchorRect.left - gap - childSize.width;
    final maxLeft = math.max(0.0, size.width - childSize.width);
    final left = rawLeft.clamp(0.0, maxLeft).toDouble();

    final maxTop = math.max(0.0, size.height - childSize.height);
    final top = anchorRect.top.clamp(0.0, maxTop).toDouble();
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_HoverCardLayoutDelegate oldDelegate) {
    return oldDelegate.anchorRect != anchorRect ||
        oldDelegate.gap != gap ||
        oldDelegate.cardWidth != cardWidth;
  }
}
