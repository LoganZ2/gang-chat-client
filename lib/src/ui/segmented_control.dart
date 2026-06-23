import 'package:flutter/material.dart';

import 'badge_dot.dart';
import 'surface.dart';
import 'tokens.dart';

class Segment<T> {
  const Segment({
    required this.value,
    required this.label,
    this.icon,
    this.showBadge = false,
    this.badgeKey,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool showBadge;
  final Key? badgeKey;
}

class SegmentedControl<T> extends StatefulWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expanded = false,
    this.height = 36,
  });

  final List<Segment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expanded;

  /// Height of each segment. Defaults to 36; shrink for denser layouts.
  final double height;

  @override
  State<SegmentedControl<T>> createState() => _SegmentedControlState<T>();
}

class _SegmentedControlState<T> extends State<SegmentedControl<T>> {
  static const double _segmentPadding = 12;
  static const double _segmentGap = 8;
  static const double _iconSize = 15;
  static const double _iconGap = 6;
  static const double _hoverLift = 2;
  static const double _pressDepth = 2;
  static const double _baseDepth = 4;

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
        final preferredGapWidth = _segmentGap * (widget.segments.length - 1);
        final naturalWidth = naturalContentWidth + preferredGapWidth;
        final constrained = constraints.maxWidth.isFinite;
        final width = widget.expanded && constrained
            ? constraints.maxWidth
            : constrained && naturalWidth > constraints.maxWidth
            ? constraints.maxWidth
            : naturalWidth;
        final gapWidth = width < preferredGapWidth ? width : preferredGapWidth;
        final segmentGap = widget.segments.length <= 1
            ? 0.0
            : gapWidth / (widget.segments.length - 1);
        final contentWidth = (width - gapWidth).clamp(0.0, width).toDouble();
        final segmentWidths = _resolvedSegmentWidths(
          naturalWidths: naturalWidths,
          contentWidth: contentWidth,
          expanded: widget.expanded,
        );

        return SizedBox(
          width: widget.expanded ? double.infinity : width,
          height: widget.height + _hoverLift + _baseDepth,
          child: Row(
            children: [
              for (var index = 0; index < widget.segments.length; index++) ...[
                SizedBox(
                  width: segmentWidths[index],
                  child: PressableSurface(
                    onPressed: () =>
                        widget.onChanged(widget.segments[index].value),
                    selected: widget.segments[index].value == widget.value,
                    height: widget.height,
                    padding: const EdgeInsets.symmetric(
                      horizontal: _segmentPadding,
                    ),
                    backgroundColor: UiColors.background,
                    selectedBackgroundColor: UiColors.selected,
                    pressedBackgroundColor: UiColors.surfaceLow,
                    borderColor: UiColors.border,
                    selectedBorderColor: UiColors.selectedBorder,
                    borderRadius: UiRadii.md,
                    hoverLift: _hoverLift,
                    pressDepth: _pressDepth,
                    baseDepth: _baseDepth,
                    child: _SegmentContent(
                      segment: widget.segments[index],
                      selected: widget.segments[index].value == widget.value,
                    ),
                  ),
                ),
                if (index != widget.segments.length - 1)
                  SizedBox(width: segmentGap),
              ],
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
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: scale,
    )..layout();
    final iconWidth = segment.icon == null ? 0.0 : _iconSize + _iconGap;
    final badgeWidth = segment.showBadge ? 8.0 : 0.0;
    return painter.width + iconWidth + badgeWidth + (_segmentPadding * 2);
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

class _SegmentContent<T> extends StatelessWidget {
  const _SegmentContent({required this.segment, required this.selected});

  final Segment<T> segment;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? UiColors.controlAccent
        : UiColors.textSecondary;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Center(
          child: Row(
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (segment.showBadge)
          Positioned(
            key: segment.badgeKey,
            top: 3,
            right: -2,
            child: const BadgeDot(size: 7),
          ),
      ],
    );
  }
}
