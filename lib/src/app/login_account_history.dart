const loginAccountHistoryLimit = 8;

String normalizeLoginAccount(String login) => login.trim();

String loginAccountKey(String login) =>
    normalizeLoginAccount(login).toLowerCase();

bool loginAccountsMatch(String first, String second) {
  final firstKey = loginAccountKey(first);
  return firstKey.isNotEmpty && firstKey == loginAccountKey(second);
}

class LoginAccountRecord {
  LoginAccountRecord({
    required this.login,
    this.password,
    this.avatarUrl,
    this.defaultAvatarKey,
    int useCount = 1,
    DateTime? updatedAt,
  }) : useCount = useCount < 1 ? 1 : useCount,
       updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String login;
  final String? password;
  final String? avatarUrl;
  final String? defaultAvatarKey;
  final int useCount;
  final DateTime updatedAt;

  bool get remembersPassword => password != null && password!.isNotEmpty;

  LoginAccountRecord copyWith({
    String? login,
    String? password,
    String? avatarUrl,
    String? defaultAvatarKey,
    int? useCount,
    bool clearPassword = false,
    bool clearAvatarUrl = false,
    bool clearDefaultAvatarKey = false,
    DateTime? updatedAt,
  }) {
    return LoginAccountRecord(
      login: login ?? this.login,
      password: clearPassword ? null : password ?? this.password,
      avatarUrl: clearAvatarUrl ? null : avatarUrl ?? this.avatarUrl,
      defaultAvatarKey: clearDefaultAvatarKey
          ? null
          : defaultAvatarKey ?? this.defaultAvatarKey,
      useCount: useCount ?? this.useCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

abstract class LoginAccountHistoryStore {
  const LoginAccountHistoryStore();

  Future<List<LoginAccountRecord>> read();

  Future<void> write(List<LoginAccountRecord> records);
}

class NoopLoginAccountHistoryStore extends LoginAccountHistoryStore {
  const NoopLoginAccountHistoryStore();

  @override
  Future<List<LoginAccountRecord>> read() async => const [];

  @override
  Future<void> write(List<LoginAccountRecord> records) async {}
}

List<LoginAccountRecord> normalizeLoginAccountHistory(
  Iterable<LoginAccountRecord> records, {
  int limit = loginAccountHistoryLimit,
}) {
  final byLogin = <String, LoginAccountRecord>{};
  for (final record in records) {
    final login = normalizeLoginAccount(record.login);
    final key = loginAccountKey(login);
    if (key.isEmpty) continue;
    final normalized = record.copyWith(
      login: login,
      clearPassword: !record.remembersPassword,
    );
    final existing = byLogin[key];
    if (existing == null || _compareLoginRecords(normalized, existing) < 0) {
      byLogin[key] = normalized;
    }
  }

  final result = byLogin.values.toList()..sort(_compareLoginRecords);
  if (result.length > limit) {
    result.removeRange(limit, result.length);
  }
  return List<LoginAccountRecord>.unmodifiable(result);
}

LoginAccountRecord? findLoginAccountRecord(
  Iterable<LoginAccountRecord> records,
  String login,
) {
  for (final record in records) {
    if (loginAccountsMatch(record.login, login)) return record;
  }
  return null;
}

LoginAccountRecord? lastLoginAccountRecord(
  Iterable<LoginAccountRecord> records,
) {
  LoginAccountRecord? latest;
  for (final record in records) {
    if (normalizeLoginAccount(record.login).isEmpty) continue;
    if (latest == null ||
        record.updatedAt.isAfter(latest.updatedAt) ||
        (record.updatedAt == latest.updatedAt &&
            record.useCount > latest.useCount)) {
      latest = record;
    }
  }
  return latest;
}

List<LoginAccountRecord> rememberLoginAccount({
  required Iterable<LoginAccountRecord> records,
  required String login,
  required String password,
  required bool rememberPassword,
  String? avatarUrl,
  String? defaultAvatarKey,
  bool updateAvatarMetadata = false,
  DateTime? now,
  int limit = loginAccountHistoryLimit,
}) {
  final normalizedLogin = normalizeLoginAccount(login);
  if (normalizedLogin.isEmpty) {
    return normalizeLoginAccountHistory(records, limit: limit);
  }

  final existing = findLoginAccountRecord(records, normalizedLogin);
  final applyAvatarMetadata =
      updateAvatarMetadata || avatarUrl != null || defaultAvatarKey != null;
  final updated = LoginAccountRecord(
    login: normalizedLogin,
    password: rememberPassword && password.isNotEmpty ? password : null,
    avatarUrl: applyAvatarMetadata
        ? _nonEmptyString(avatarUrl)
        : existing?.avatarUrl,
    defaultAvatarKey: applyAvatarMetadata
        ? _nonEmptyString(defaultAvatarKey)
        : existing?.defaultAvatarKey,
    useCount: (existing?.useCount ?? 0) + 1,
    updatedAt: now ?? DateTime.now(),
  );

  return normalizeLoginAccountHistory([
    updated,
    ...records.where(
      (record) => !loginAccountsMatch(record.login, normalizedLogin),
    ),
  ], limit: limit);
}

List<LoginAccountRecord> updateLoginAccountAvatarMetadata({
  required Iterable<LoginAccountRecord> records,
  required Iterable<String> accountAliases,
  required String? avatarUrl,
  required String? defaultAvatarKey,
  int limit = loginAccountHistoryLimit,
}) {
  final aliasKeys = accountAliases
      .map(loginAccountKey)
      .where((key) => key.isNotEmpty)
      .toSet();
  if (aliasKeys.isEmpty) {
    return normalizeLoginAccountHistory(records, limit: limit);
  }

  final normalizedAvatarUrl = _nonEmptyString(avatarUrl);
  final normalizedDefaultAvatarKey = _nonEmptyString(defaultAvatarKey);
  return normalizeLoginAccountHistory(
    records.map((record) {
      if (!aliasKeys.contains(loginAccountKey(record.login))) return record;
      return record.copyWith(
        avatarUrl: normalizedAvatarUrl,
        defaultAvatarKey: normalizedDefaultAvatarKey,
        clearAvatarUrl: normalizedAvatarUrl == null,
        clearDefaultAvatarKey: normalizedDefaultAvatarKey == null,
      );
    }),
    limit: limit,
  );
}

List<LoginAccountRecord> deleteLoginAccountRecord({
  required Iterable<LoginAccountRecord> records,
  required String login,
  int limit = loginAccountHistoryLimit,
}) {
  return normalizeLoginAccountHistory(
    records.where((record) => !loginAccountsMatch(record.login, login)),
    limit: limit,
  );
}

int _compareLoginRecords(LoginAccountRecord first, LoginAccountRecord second) {
  final useCount = second.useCount.compareTo(first.useCount);
  if (useCount != 0) return useCount;
  final updatedAt = second.updatedAt.compareTo(first.updatedAt);
  if (updatedAt != 0) return updatedAt;
  return loginAccountKey(first.login).compareTo(loginAccountKey(second.login));
}

String? _nonEmptyString(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
