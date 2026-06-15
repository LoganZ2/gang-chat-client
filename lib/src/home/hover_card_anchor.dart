import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/ui.dart';

const double hoverCardDefaultWidth = 248;
const double hoverCardDefaultGap = 10;

typedef HoverCardBuilder = Widget Function(BuildContext context);

class HoverCardTapRegionScope extends InheritedWidget {
  const HoverCardTapRegionScope({
    super.key,
    required this.tapRegionGroup,
    required super.child,
  });

  final Object tapRegionGroup;

  static HoverCardTapRegionScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<HoverCardTapRegionScope>();
  }

  @override
  bool updateShouldNotify(HoverCardTapRegionScope oldWidget) {
    return tapRegionGroup != oldWidget.tapRegionGroup;
  }
}

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
  final Object _rootTapRegionGroup = Object();

  late final _HoverCardCoordinator _coordinator;
  _HoverCardCoordinator? _parentCoordinator;
  Object? _inheritedTapRegionGroup;
  bool _overAnchor = false;
  bool _overCard = false;
  bool _pinned = false;
  bool _portalVisible = false;
  bool _advertisedActiveToParent = false;
  Timer? _closeTimer;
  Future<void>? _openFuture;

  Object get _tapRegionGroup => _inheritedTapRegionGroup ?? _rootTapRegionGroup;

  bool get _wantsOpen =>
      _pinned || _overAnchor || _overCard || _coordinator.hasActiveDescendants;

  bool get _keepsParentOpen =>
      _wantsOpen || _portalVisible || _openFuture != null;

  @override
  void initState() {
    super.initState();
    _coordinator = _HoverCardCoordinator(_handleDescendantActivityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chainScope = _HoverCardChainScope.maybeOf(context);
    final nextParent = chainScope?.coordinator;
    if (nextParent != _parentCoordinator) {
      if (_advertisedActiveToParent) {
        _parentCoordinator?.setDescendantActive(this, false);
        _advertisedActiveToParent = false;
      }
      _parentCoordinator?.releaseOpenChild(this);
      _parentCoordinator = nextParent;
    }
    final tapRegionScope = HoverCardTapRegionScope.maybeOf(context);
    _inheritedTapRegionGroup =
        chainScope?.tapRegionGroup ?? tapRegionScope?.tapRegionGroup;
    _syncParentActivity();
  }

  @override
  void didUpdateWidget(covariant HoverCardAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey == widget.resetKey) return;
    _dismiss();
  }

  @override
  void dispose() {
    if (_advertisedActiveToParent) {
      _parentCoordinator?.setDescendantActive(this, false);
      _advertisedActiveToParent = false;
    }
    _parentCoordinator?.releaseOpenChild(this);
    _closeTimer?.cancel();
    super.dispose();
  }

  void _enterAnchor() {
    _overAnchor = true;
    _open();
    _syncParentActivity();
  }

  void _exitAnchor() {
    _overAnchor = false;
    _syncParentActivity();
    _scheduleClose();
  }

  void _enterCard() {
    _overCard = true;
    _closeTimer?.cancel();
    _syncParentActivity();
  }

  void _exitCard() {
    _overCard = false;
    _syncParentActivity();
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
    _syncParentActivity();
    unawaited(
      future.catchError((_) {}).whenComplete(() {
        if (!mounted || _openFuture != future) return;
        _openFuture = null;
        if (_wantsOpen) _showPortal();
        _syncParentActivity();
      }),
    );
  }

  void _showPortal() {
    _parentCoordinator?.showOnlyChild(this);
    if (_portalVisible && _portal.isShowing) return;
    _portalVisible = true;
    _portal.show();
    _syncParentActivity();
  }

  void _pinOpen() {
    _pinned = true;
    _open();
    _syncParentActivity();
  }

  void _dismiss() {
    _pinned = false;
    _overAnchor = false;
    _overCard = false;
    _closeTimer?.cancel();
    _portalVisible = false;
    _parentCoordinator?.releaseOpenChild(this);
    if (_portal.isShowing) _portal.hide();
    _syncParentActivity();
  }

  void _dismissFromPeer() {
    _pinned = false;
    _overAnchor = false;
    _overCard = false;
    _closeTimer?.cancel();
    _portalVisible = false;
    if (_portal.isShowing) _portal.hide();
    _syncParentActivity();
  }

  void _scheduleClose() {
    if (_pinned) return;
    _closeTimer?.cancel();
    _closeTimer = Timer(widget.closeDelay, () {
      if (!mounted || _wantsOpen) return;
      _portalVisible = false;
      if (_portal.isShowing) _portal.hide();
      _syncParentActivity();
    });
  }

  void _handleDescendantActivityChanged() {
    if (!mounted) return;
    if (_coordinator.hasActiveDescendants) {
      _closeTimer?.cancel();
    } else {
      _scheduleClose();
    }
    _syncParentActivity();
  }

  void _syncParentActivity() {
    final parent = _parentCoordinator;
    if (parent == null) return;
    final active = _keepsParentOpen;
    if (active == _advertisedActiveToParent) return;
    parent.setDescendantActive(this, active);
    _advertisedActiveToParent = active;
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
                      child: _HoverCardChainScope(
                        coordinator: _coordinator,
                        tapRegionGroup: _tapRegionGroup,
                        child: Builder(builder: widget.cardBuilder),
                      ),
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

class _HoverCardCoordinator {
  _HoverCardCoordinator(this.onChanged);

  final VoidCallback onChanged;
  final Set<Object> _activeDescendants = <Object>{};
  _HoverCardAnchorState? _openChild;

  bool get hasActiveDescendants => _activeDescendants.isNotEmpty;

  void setDescendantActive(Object token, bool active) {
    final changed = active
        ? _activeDescendants.add(token)
        : _activeDescendants.remove(token);
    if (changed) onChanged();
  }

  void showOnlyChild(_HoverCardAnchorState child) {
    final previous = _openChild;
    if (previous != null && previous != child) {
      previous._dismissFromPeer();
    }
    _openChild = child;
  }

  void releaseOpenChild(_HoverCardAnchorState child) {
    if (_openChild == child) _openChild = null;
  }
}

class _HoverCardChainScope extends InheritedWidget {
  const _HoverCardChainScope({
    required this.coordinator,
    required this.tapRegionGroup,
    required super.child,
  });

  final _HoverCardCoordinator coordinator;
  final Object tapRegionGroup;

  static _HoverCardChainScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_HoverCardChainScope>();
  }

  @override
  bool updateShouldNotify(_HoverCardChainScope oldWidget) {
    return coordinator != oldWidget.coordinator ||
        tapRegionGroup != oldWidget.tapRegionGroup;
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
