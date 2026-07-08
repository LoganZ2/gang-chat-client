import 'package:flutter/material.dart';

class LatencySignalBadge extends StatelessWidget {
  const LatencySignalBadge({
    super.key,
    required this.activeBars,
    required this.activeColor,
    required this.tooltip,
    this.size = 18,
  });

  final int activeBars;
  final Color activeColor;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bars = activeBars.clamp(0, 3);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(
        label: tooltip,
        child: SizedBox(
          key: const ValueKey('latency-signal-badge'),
          width: size,
          height: size - 2,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(3.5, 3, 3.5, 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 1; index <= 3; index++) ...[
                  _SignalBar(
                    index: index,
                    active: bars >= index,
                    color: activeColor,
                  ),
                  if (index != 3) const SizedBox(width: 1),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalBar extends StatelessWidget {
  const _SignalBar({
    required this.index,
    required this.active,
    required this.color,
  });

  final int index;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fill = active ? color : const Color(0xFF8A93A3);
    return DecoratedBox(
      key: ValueKey('latency-signal-bar-$index'),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(width: 3, height: 3.0 + index * 2.0),
    );
  }
}
