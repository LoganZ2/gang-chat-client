import 'package:flutter/material.dart';

class CompactActivityLayout {
  const CompactActivityLayout._();

  static const avatarSize = 18.0;
  static const timestampColumnWidth = 82.0;
  static const compactTimestampColumnWidth = 68.0;
  static const compactTimestampContentGap = 4.0;
  static const compactNotificationListHorizontalPadding = 16.0;

  static String splitTimestamp(String timestamp) {
    final splitAt = timestamp.indexOf(' ');
    if (splitAt < 0) return timestamp;
    return '${timestamp.substring(0, splitAt)}\n'
        '${timestamp.substring(splitAt + 1)}';
  }
}

class CompactActivityTimestamp extends StatelessWidget {
  const CompactActivityTimestamp({
    super.key,
    required this.timestamp,
    required this.style,
  });

  final String timestamp;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final lines = CompactActivityLayout.splitTimestamp(timestamp).split('\n');
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in lines)
            Text(line, maxLines: 1, softWrap: false, style: style),
        ],
      ),
    );
  }
}
