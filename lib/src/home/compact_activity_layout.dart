class CompactActivityLayout {
  const CompactActivityLayout._();

  static const avatarSize = 18.0;
  static const timestampColumnWidth = 82.0;
  static const androidTimestampColumnWidth = 68.0;
  static const androidTimestampContentGap = 4.0;

  static String splitTimestamp(String timestamp) {
    final splitAt = timestamp.indexOf(' ');
    if (splitAt < 0) return timestamp;
    return '${timestamp.substring(0, splitAt)}\n'
        '${timestamp.substring(splitAt + 1)}';
  }
}
