part of 'home_shell.dart';

const _homeTitleBarHeight = 56.0;
const _homeTitleBarSearchMaxWidth = 520.0;
const _homeTitleBarMinSearchWidth = 122.0;
const _homeTitleBarControlsWidth = 134.0;
const _homeTitleBarControlWidth = 34.0;
const _homeTitleBarControlHeight = 32.0;
const _homeTitleBarControlGap = 6.0;

class _HomeTitleBar extends StatefulWidget {
  const _HomeTitleBar({required this.windowController});

  final DesktopWindowController windowController;

  @override
  State<_HomeTitleBar> createState() => _HomeTitleBarState();
}

class _HomeTitleBarState extends State<_HomeTitleBar> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    unawaited(_syncMaximized());
  }

  @override
  void didUpdateWidget(_HomeTitleBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowController != widget.windowController) {
      unawaited(_syncMaximized());
    }
  }

  Future<void> _syncMaximized() async {
    final maximized = await widget.windowController.isMaximizedWindow();
    if (!mounted) return;
    setState(() => _maximized = maximized);
  }

  void _minimize() {
    unawaited(widget.windowController.minimizeWindow());
  }

  void _toggleMaximize() {
    unawaited(() async {
      await widget.windowController.toggleMaximizeWindow();
      await _syncMaximized();
    }());
  }

  void _close() {
    unawaited(widget.windowController.closeWindow());
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _homeTitleBarHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: UiColors.surfaceLow,
          border: Border(bottom: BorderSide(color: UiColors.border)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= narrowBreakpoint;
            final compactBrandWidth =
                (constraints.maxWidth -
                        _homeTitleBarControlsWidth -
                        _homeTitleBarMinSearchWidth)
                    .clamp(118.0, 168.0)
                    .toDouble();
            final brandWidth = wide ? sidebarWidth : compactBrandWidth;

            return Row(
              children: [
                SizedBox(
                  width: brandWidth,
                  child: SelectionContainer.disabled(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: UiColors.border),
                        ),
                      ),
                      child: _WindowDragRegion(
                        windowController: widget.windowController,
                        onDoubleTap: _toggleMaximize,
                        child: const _BrandLockup(),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _TitleSearchLane(
                    windowController: widget.windowController,
                    onDoubleTap: _toggleMaximize,
                  ),
                ),
                SelectionContainer.disabled(
                  child: _WindowControls(
                    maximized: _maximized,
                    onMinimize: _minimize,
                    onToggleMaximize: _toggleMaximize,
                    onClose: _close,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: UiColors.selected,
              borderRadius: BorderRadius.circular(UiRadii.md),
              border: Border.all(color: UiColors.accentBorder),
            ),
            child: const SizedBox.square(
              dimension: 28,
              child: Center(
                child: Icon(
                  Icons.forum_outlined,
                  size: 17,
                  color: UiColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Gang Chat',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: UiColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleSearchLane extends StatelessWidget {
  const _TitleSearchLane({
    required this.windowController,
    required this.onDoubleTap,
  });

  final DesktopWindowController windowController;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _WindowDragRegion(
          windowController: windowController,
          onDoubleTap: onDoubleTap,
          child: const SizedBox.expand(),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth
                  .clamp(0.0, _homeTitleBarSearchMaxWidth)
                  .toDouble();
              if (width < 96) return const SizedBox.shrink();
              return SizedBox(
                key: const ValueKey('home-title-search'),
                width: width,
                child: Input(
                  hintText: 'Search',
                  prefixIcon: Icons.search,
                  maxLines: 1,
                  style: UiTypography.body.copyWith(fontSize: 13, height: 1.2),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WindowDragRegion extends StatelessWidget {
  const _WindowDragRegion({
    required this.windowController,
    required this.child,
    required this.onDoubleTap,
  });

  final DesktopWindowController windowController;
  final Widget child;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => unawaited(windowController.startDragging()),
      onDoubleTap: onDoubleTap,
      child: child,
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls({
    required this.maximized,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final bool maximized;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _homeTitleBarControlsWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _WindowControlButton(
              tooltip: 'Minimize',
              icon: Icons.remove,
              onPressed: onMinimize,
            ),
            const SizedBox(width: _homeTitleBarControlGap),
            _WindowControlButton(
              tooltip: maximized ? 'Restore' : 'Maximize',
              icon: maximized ? Icons.filter_none : Icons.crop_square,
              onPressed: onToggleMaximize,
            ),
            const SizedBox(width: _homeTitleBarControlGap),
            _WindowControlButton(
              tooltip: 'Close',
              icon: Icons.close,
              danger: true,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  const _WindowControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;
    final background = active
        ? widget.danger
              ? const Color(0xFF332126)
              : UiColors.surface
        : Colors.transparent;
    final border = active
        ? widget.danger
              ? UiColors.dangerBorder
              : UiColors.border
        : Colors.transparent;
    final foreground = active && widget.danger
        ? UiColors.danger
        : UiColors.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) {
          _setHovered(false);
          _setPressed(false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOutCubic,
            width: _homeTitleBarControlWidth,
            height: _homeTitleBarControlHeight,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(UiRadii.sm),
              border: Border.all(color: border),
            ),
            child: Center(
              child: Icon(widget.icon, size: 16, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
