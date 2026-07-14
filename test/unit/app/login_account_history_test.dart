import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/login_account_history.dart';

void main() {
  test(
    'rememberLoginAccount records recent login without password by default',
    () {
      final records = rememberLoginAccount(
        records: const [],
        login: '  Kai@example.com  ',
        password: 'secret',
        rememberPassword: false,
        now: DateTime.utc(2026, 1, 2),
      );

      expect(records, hasLength(1));
      expect(records.single.login, 'Kai@example.com');
      expect(records.single.password, isNull);
      expect(records.single.remembersPassword, isFalse);
      expect(records.single.useCount, 1);
    },
  );

  test('rememberLoginAccount stores password only when enabled', () {
    final records = rememberLoginAccount(
      records: const [],
      login: 'kai',
      password: 'secret',
      rememberPassword: true,
      avatarUrl: '/avatars/kai.png',
      defaultAvatarKey: 'green-2',
      now: DateTime.utc(2026, 1, 2),
    );

    expect(records.single.password, 'secret');
    expect(records.single.remembersPassword, isTrue);
    expect(records.single.avatarUrl, '/avatars/kai.png');
    expect(records.single.defaultAvatarKey, 'green-2');
    expect(records.single.useCount, 1);
  });

  test(
    'rememberLoginAccount moves existing account to top and clears password',
    () {
      final records = rememberLoginAccount(
        records: [
          LoginAccountRecord(
            login: 'kai',
            password: 'old-secret',
            useCount: 2,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
          LoginAccountRecord(
            login: 'morgan',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        login: 'KAI',
        password: 'new-secret',
        rememberPassword: false,
        now: DateTime.utc(2026, 1, 3),
      );

      expect(records.map((record) => record.login), ['KAI', 'morgan']);
      expect(records.first.password, isNull);
      expect(records.first.useCount, 3);
    },
  );

  test('normalizeLoginAccountHistory sorts by use count then latest login', () {
    final records = normalizeLoginAccountHistory([
      LoginAccountRecord(
        login: 'kai',
        useCount: 2,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      LoginAccountRecord(
        login: 'morgan',
        useCount: 2,
        updatedAt: DateTime.utc(2026, 1, 3),
      ),
      LoginAccountRecord(
        login: 'riley',
        useCount: 3,
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    ]);

    expect(records.map((record) => record.login), ['riley', 'morgan', 'kai']);
  });

  test('lastLoginAccountRecord returns the most recent login', () {
    final latest = lastLoginAccountRecord([
      LoginAccountRecord(
        login: 'kai',
        useCount: 5,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      LoginAccountRecord(
        login: 'morgan',
        useCount: 1,
        updatedAt: DateTime.utc(2026, 1, 4),
      ),
    ]);

    expect(latest?.login, 'morgan');
  });

  test('deleteLoginAccountRecord removes records case-insensitively', () {
    final records = deleteLoginAccountRecord(
      records: [
        LoginAccountRecord(login: 'kai'),
        LoginAccountRecord(login: 'morgan'),
      ],
      login: 'KAI',
    );

    expect(records.map((record) => record.login), ['morgan']);
  });
}
