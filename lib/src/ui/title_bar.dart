import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Height of the window-controls buttons, and the height of the notch the live
/// header cuts so the buttons nest into it.
const double titleBarHeight = 32;

/// Height of the draggable band at the very top of the window. This is also the
/// amount the live header drops, so dragging is confined to the gap above it
/// and never steals clicks from the header button.
const double windowDragHeight = 16;

/// Inset of the window controls from the right edge. The live header is inset by
/// the same amount on its right so its right edge shadow is visible and the
/// notch stays aligned under the buttons.
const double windowControlsInset = 8;

/// Combined width of the three window-control buttons. The live header notches
/// a [windowControlsWidth] × [titleBarHeight] rectangle so they nest in.
const double windowControlsWidth = _winButtonWidth * 3;

const double _winButtonWidth = 46;

const _textMuted = Color(0xFF6F7785);
const _hoverNeutral = Color(0xFF1F232C);
const _hoverDanger = Color(0xFFE58383);

bool get _supportsCustomControls => !kIsWeb;

/// When true, [WindowControls] paints nothing. The immersive full-screen
/// screen-share view flips this so the min/maximize/close buttons (which are
/// layered above the page) don't paint over the video.
final ValueNotifier<bool> windowControlsHidden = ValueNotifier<bool>(false);

Future<void> _toggleMaximize() async {
  try {
    if (!await windowManager.isResizable()) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  } catch (_) {}
}

/// A transparent overlay pinned to the top of the window: the whole strip drags
/// the window (double-click maximizes), with the min/maximize/close buttons
/// tucked into the top-right. Designed to sit in a [Stack] above app content so
/// it can nest into the live header's notch. macOS keeps its native controls.
class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    if (!_supportsCustomControls) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: windowControlsHidden,
      builder: (context, hidden, _) {
        if (hidden) return const SizedBox.shrink();
        return SizedBox(
          height: titleBarHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              // Only the gap band drags; below it stays clickable (the header).
              Expanded(
                child: SizedBox(height: windowDragHeight, child: _DragRegion()),
              ),
              _WindowButtons(),
              // Inset from the right edge so the controls line up with the header
              // notch (which is inset by the same amount).
              SizedBox(width: windowControlsInset),
            ],
          ),
        );
      },
    );
  }
}

class _DragRegion extends StatelessWidget {
  const _DragRegion();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: _toggleMaximize,
      child: const SizedBox.expand(),
    );
  }
}

class _WindowButtons extends StatelessWidget {
  const _WindowButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WinButton(
          icon: Icons.remove,
          onPressed: () => windowManager.minimize(),
        ),
        _WinButton(
          icon: Icons.crop_square,
          iconSize: 11,
          onPressed: _toggleMaximize,
        ),
        _WinButton(
          icon: Icons.close,
          danger: true,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.iconSize = 14,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;
  final double iconSize;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hoverBg = widget.danger ? _hoverDanger : _hoverNeutral;
    final iconColor = _hover && widget.danger ? Colors.white : _textMuted;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: _winButtonWidth,
          height: titleBarHeight,
          color: _hover ? hoverBg : Colors.transparent,
          alignment: Alignment.center,
          child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
        ),
      ),
    );
  }
}
