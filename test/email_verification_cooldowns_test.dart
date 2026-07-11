import 'package:client/src/app/email_verification_cooldowns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('email verification cooldowns are normalized and email-specific', () {
    var now = DateTime(2026, 7, 12, 12);
    final cooldowns = EmailVerificationCooldowns(now: () => now);

    expect(cooldowns.start(' First@Example.Test '), 59);
    now = now.add(const Duration(seconds: 10));
    expect(cooldowns.remainingSeconds('first@example.test'), 49);
    expect(cooldowns.remainingSeconds('second@example.test'), 0);

    expect(cooldowns.start('second@example.test'), 59);
    now = now.add(const Duration(seconds: 49));
    expect(cooldowns.remainingSeconds('FIRST@example.test'), 0);
    expect(cooldowns.remainingSeconds('second@example.test'), 10);

    now = now.add(const Duration(seconds: 10));
    expect(cooldowns.remainingSeconds('second@example.test'), 0);
  });
}
