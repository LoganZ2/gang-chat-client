import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/account_sessions.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('accountSessionsLoadStarted preserves sessions and clears error', () {
    final existing = [_session(id: 'session_1')];
    final patch = accountSessionsLoadStarted(sessions: existing);

    expect(patch.sessions, existing);
    expect(patch.loading, isTrue);
    expect(patch.securityError, isNull);
  });

  test(
    'accountSessionsLoadSucceeded stores sessions and clears busy state',
    () {
      final sessions = [_session(id: 'session_2')];
      final patch = accountSessionsLoadSucceeded(sessions: sessions);

      expect(patch.sessions, sessions);
      expect(patch.loading, isFalse);
      expect(patch.securityError, isNull);
    },
  );

  test('accountSessionsLoadCancelled preserves existing feedback', () {
    final existing = [_session(id: 'session_1')];
    final patch = accountSessionsLoadCancelled(
      sessions: existing,
      securityError: 'previous error',
    );

    expect(patch.sessions, existing);
    expect(patch.loading, isFalse);
    expect(patch.securityError, 'previous error');
  });

  test('accountSessionsLoadFailed preserves sessions and reports error', () {
    final existing = [_session(id: 'session_1')];
    final patch = accountSessionsLoadFailed(
      sessions: existing,
      failure: 'load failed',
    );

    expect(patch.sessions, existing);
    expect(patch.loading, isFalse);
    expect(patch.securityError, 'load failed');
  });
}

UserSession _session({required String id}) {
  return UserSession(
    id: id,
    userAgent: 'Test Browser',
    ipAddress: '127.0.0.1',
    location: 'Local',
    createdAt: DateTime(2026, 6, 1),
    lastUsedAt: DateTime(2026, 6, 4),
    expiresAt: DateTime(2026, 6, 5),
    revokedAt: null,
    isCurrent: false,
  );
}
