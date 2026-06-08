part of 'home_shell.dart';

const _homeTitleBarHeight = 44.0;
const _homeTitleBarSearchMaxWidth = 520.0;
const _homeTitleBarMinSearchWidth = 122.0;
const _homeTitleBarControlsWidth = 134.0;
const _homeTitleBarControlWidth = 34.0;
const _homeTitleBarControlHeight = 28.0;
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
            // mac 使用系统原生红绿灯,其它平台用自定义窗口按钮。
            final nativeMacControls =
                Theme.of(context).platform == TargetPlatform.macOS;
            final wide = constraints.maxWidth >= narrowBreakpoint;
            final compactBrandWidth =
                (constraints.maxWidth -
                        (nativeMacControls ? 0 : _homeTitleBarControlsWidth) -
                        _homeTitleBarMinSearchWidth)
                    .clamp(118.0, 168.0)
                    .toDouble();
            final brandWidth = wide ? sidebarWidth : compactBrandWidth;

            // 搜索框相对整个标题栏居中。为了不压到左侧品牌区或右侧窗口控制,
            // 用两侧较宽者来对称收窄可用宽度,再夹到上限。mac 右侧没有自定义
            // 按钮,但左侧品牌区已包含红绿灯让位,仍按品牌区宽度对称即可。
            final rightReserved = nativeMacControls
                ? 0.0
                : _homeTitleBarControlsWidth;
            final reserved = brandWidth > rightReserved
                ? brandWidth
                : rightReserved;
            final searchWidth = (constraints.maxWidth - reserved * 2 - 24)
                .clamp(0.0, _homeTitleBarSearchMaxWidth)
                .toDouble();

            return Stack(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: brandWidth,
                      child: _WindowDragRegion(
                        windowController: widget.windowController,
                        onDoubleTap: _toggleMaximize,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: _WindowDragRegion(
                        windowController: widget.windowController,
                        onDoubleTap: _toggleMaximize,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    if (!nativeMacControls)
                      SelectionContainer.disabled(
                        child: _WindowControls(
                          maximized: _maximized,
                          onMinimize: _minimize,
                          onToggleMaximize: _toggleMaximize,
                          onClose: _close,
                        ),
                      ),
                  ],
                ),
                if (searchWidth >= 96)
                  Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      key: const ValueKey('home-title-search'),
                      width: searchWidth,
                      child: const _TitleSearchField(),
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

/// 标题栏中央的搜索框。不复用通用 [Input] 封装,而是一个普通的圆角矩形,
/// 获得焦点时会像按钮一样显示绿色边框与底色。
class _TitleSearchField extends StatefulWidget {
  const _TitleSearchField();

  @override
  State<_TitleSearchField> createState() => _TitleSearchFieldState();
}

class _TitleSearchFieldState extends State<_TitleSearchField> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _focused ? UiColors.accent : UiColors.textMuted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _focused ? UiColors.selected : UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(
          color: _focused ? UiColors.selectedBorder : UiColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              focusNode: _focusNode,
              maxLines: 1,
              cursorColor: UiColors.accent,
              cursorWidth: 1.5,
              style: UiTypography.body.copyWith(fontSize: 13, height: 1.2),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '搜索',
                hintStyle: UiTypography.body.copyWith(
                  fontSize: 13,
                  height: 1.2,
                  color: UiColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
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
