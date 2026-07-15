/// Returns Simplified-Chinese copy suitable for a floating notice or error
/// panel without exposing platform exception class names and English details.
String userFacingErrorMessage(
  Object failure, {
  String fallback = '操作失败，请稍后重试',
}) {
  final raw = failure.toString().trim();
  if (_containsChinese(raw)) return raw;

  final normalized = raw.toLowerCase();
  if (normalized.contains('cancelled') || normalized.contains('canceled')) {
    return '操作已取消';
  }
  if (normalized.contains('timeout') || normalized.contains('timed out')) {
    return '操作超时，请稍后重试';
  }
  if (normalized.contains('socket') ||
      normalized.contains('connection') ||
      normalized.contains('network') ||
      normalized.contains('handshake')) {
    return '网络连接失败，请检查网络后重试';
  }
  if (normalized.contains('permission') ||
      normalized.contains('access denied')) {
    return '没有权限完成此操作';
  }
  if (normalized.contains('not found') || normalized.contains('missing')) {
    return '所需内容不存在';
  }
  if (normalized.contains('unsupported') ||
      normalized.contains('not supported')) {
    return '当前平台不支持此操作';
  }
  return fallback;
}

bool _containsChinese(String value) {
  return RegExp(r'[\u3400-\u9fff]').hasMatch(value);
}
