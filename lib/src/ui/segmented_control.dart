import 'package:flutter/material.dart';

import 'tokens.dart';

class Segment<T> {
  const Segment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

class SegmentedControl<T> extends StatefulWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expanded = false,
  });

  final List<Segment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expanded;

  @override
  State<SegmentedControl<T>> createState() => _SegmentedControlState<T>();
}

class _SegmentedControlState<T> extends State<SegmentedControl<T>> {
  static const double _segmentHeight = 36;
  static const double _segmentPadding = 12;
  static const double _iconSize = 15;
  static const double _iconGap = 6;
  static const double _hoverLift = 0;
  static const double _baseDepth = 5;
  static const double _contentLift = 2;
  static const double _trackHeight = _segmentHeight;
  static const Duration _duration = Duration(milliseconds: 180);

  int? _hoveredIndex;
  int? _pressedIndex;

  int get _selectedIndex {
    final index = widget.segments.indexWhere(
      (segment) => segment.value == widget.value,
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.segments.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final naturalWidths = [
          for (final segment in widget.segments)
            _measureSegmentWidth(context, segment),
        ];
        final naturalContentWidth = naturalWidths.fold<double>(
          0,
          (sum, width) => sum + width,
        );
        final naturalWidth = naturalContentWidth;
        final constrained = constraints.maxWidth.isFinite;
        final width = widget.expanded && constrained
            ? constraints.maxWidth
            : constrained && naturalWidth > constraints.maxWidth
            ? constraints.maxWidth
            : naturalWidth;
        final contentWidth = width;
        final segmentWidths = _resolvedSegmentWidths(
          naturalWidths: naturalWidths,
          contentWidth: contentWidth,
          expanded: widget.expanded,
        );
        final selectedIndex = _selectedIndex.clamp(
          0,
          widget.segments.length - 1,
        );
        final selectedLeft = segmentWidths
            .take(selectedIndex)
            .fold<double>(0, (sum, width) => sum + width);
        final selectedPressed = _pressedIndex == selectedIndex;
        final capTop = selectedPressed ? _baseDepth : 0.0;

        return SizedBox(
          width: widget.expanded ? double.infinity : width,
          height: _segmentHeight + _hoverLift + _baseDepth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _trackHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: UiColors.surfacePressed,
                    borderRadius: BorderRadius.circular(UiRadii.md),
                    border: Border.all(color: UiColors.border),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: _duration,
                curve: Curves.easeOutCubic,
                left: selectedLeft,
                top: 0,
                width: segmentWidths[selectedIndex],
                height: _segmentHeight + _hoverLift + _baseDepth,
                child: _SegmentThumb(capTop: capTop),
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    for (var index = 0; index < widget.segments.length; index++)
                      SizedBox(
                        width: segmentWidths[index],
                        height: _segmentHeight + _baseDepth,
                        child: _SegmentHitTarget(
                          segment: widget.segments[index],
                          selected: index == selectedIndex,
                          hovered: index == _hoveredIndex,
                          capTop: index == selectedIndex
                              ? capTop - _contentLift
                              : _baseDepth - _contentLift,
                          onHoverChanged: (hovered) {
                            setState(() {
                              _hoveredIndex = hovered ? index : null;
                              if (!hovered && _pressedIndex == index) {
                                _pressedIndex = null;
                              }
                            });
                          },
                          onPressedChanged: (pressed) {
                            setState(
                              () => _pressedIndex = pressed ? index : null,
                            );
                          },
                          onTap: () =>
                              widget.onChanged(widget.segments[index].value),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _measureSegmentWidth(BuildContext context, Segment<T> segment) {
    final scale = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(
        text: segment.label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: scale,
    )..layout();
    final iconWidth = segment.icon == null ? 0.0 : _iconSize + _iconGap;
    return painter.width + iconWidth + (_segmentPadding * 2);
  }

  List<double> _resolvedSegmentWidths({
    required List<double> naturalWidths,
    required double contentWidth,
    required bool expanded,
  }) {
    final naturalContentWidth = naturalWidths.fold<double>(
      0,
      (sum, width) => sum + width,
    );
    if (naturalContentWidth <= 0) return naturalWidths;
    if (expanded && contentWidth > naturalContentWidth) {
      final extra = (contentWidth - naturalContentWidth) / naturalWidths.length;
      return [for (final width in naturalWidths) width + extra];
    }
    if (contentWidth >= naturalContentWidth) return naturalWidths;
    final scale = contentWidth / naturalContentWidth;
    return [for (final width in naturalWidths) width * scale];
  }
}

class _SegmentThumb extends StatelessWidget {
  const _SegmentThumb({required this.capTop});

  final double capTop;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(UiRadii.md);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: _SegmentedControlState._baseDepth,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: UiColors.surfacePressed,
              borderRadius: radius,
              border: Border.all(color: UiColors.accentBorder),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          left: 0,
          right: 0,
          top: capTop,
          height: _SegmentedControlState._segmentHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: UiColors.selected,
              borderRadius: radius,
              border: Border.all(color: UiColors.accentBorder),
            ),
          ),
        ),
      ],
    );
  }
}

class _SegmentHitTarget<T> extends StatelessWidget {
  const _SegmentHitTarget({
    required this.segment,
    required this.selected,
    required this.hovered,
    required this.capTop,
    required this.onHoverChanged,
    required this.onPressedChanged,
    required this.onTap,
  });

  final Segment<T> segment;
  final bool selected;
  final bool hovered;
  final double capTop;
  final ValueChanged<bool> onHoverChanged;
  final ValueChanged<bool> onPressedChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? UiColors.accent
        : hovered
        ? UiColors.text
        : UiColors.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onPressedChanged(true),
        onTapUp: (_) => onPressedChanged(false),
        onTapCancel: () => onPressedChanged(false),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, capTop, 0),
          height: _SegmentedControlState._segmentHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: _SegmentedControlState._segmentPadding,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (segment.icon != null) ...[
                Icon(
                  segment.icon,
                  size: _SegmentedControlState._iconSize,
                  color: foreground,
                ),
                const SizedBox(width: _SegmentedControlState._iconGap),
              ],
              Flexible(
                child: Text(
                  segment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
