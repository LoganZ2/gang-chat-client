typedef EmailVerificationClock = DateTime Function();

class EmailVerificationCooldowns {
  EmailVerificationCooldowns({
    this.duration = const Duration(seconds: 59),
    EmailVerificationClock? now,
  }) : _now = now ?? DateTime.now;

  final Duration duration;
  final EmailVerificationClock _now;
  final Map<String, DateTime> _expiresAtByEmail = {};

  int start(String email) {
    final key = _normalizeEmail(email);
    if (key.isEmpty) return 0;
    _expiresAtByEmail[key] = _now().add(duration);
    return remainingSeconds(email);
  }

  int remainingSeconds(String email) {
    final key = _normalizeEmail(email);
    final expiresAt = _expiresAtByEmail[key];
    if (expiresAt == null) return 0;
    final remaining = expiresAt.difference(_now());
    if (remaining <= Duration.zero) {
      _expiresAtByEmail.remove(key);
      return 0;
    }
    return (remaining.inMilliseconds / Duration.millisecondsPerSecond).ceil();
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();
}
