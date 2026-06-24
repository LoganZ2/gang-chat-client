import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/login_account_history.dart';

class LocalLoginAccountHistoryStore extends LoginAccountHistoryStore {
  const LocalLoginAccountHistoryStore();

  static const _accountsKey = 'gang.loginAccounts';
  static const _passwordKeyPrefix = 'gang.loginAccountPassword.';

  FlutterSecureStorage get _storage => const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  @override
  Future<List<LoginAccountRecord>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final metadata = _readMetadata(prefs);
    final records = <LoginAccountRecord>[];
    for (final item in metadata) {
      final password = item.remembersPassword
          ? await _storage.read(key: _passwordKey(item.login))
          : null;
      records.add(
        LoginAccountRecord(
          login: item.login,
          password: password == null || password.isEmpty ? null : password,
          avatarUrl: item.avatarUrl,
          defaultAvatarKey: item.defaultAvatarKey,
          useCount: item.useCount,
          updatedAt: item.updatedAt,
        ),
      );
    }
    return normalizeLoginAccountHistory(records);
  }

  @override
  Future<void> write(List<LoginAccountRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final oldMetadata = _readMetadata(prefs);
    final normalized = normalizeLoginAccountHistory(records);
    final activePasswordKeys = <String>{};

    for (final record in normalized) {
      final key = _passwordKey(record.login);
      activePasswordKeys.add(key);
      if (record.remembersPassword) {
        await _storage.write(key: key, value: record.password);
      } else {
        await _storage.delete(key: key);
      }
    }

    for (final item in oldMetadata) {
      final key = _passwordKey(item.login);
      if (!activePasswordKeys.contains(key)) {
        await _storage.delete(key: key);
      }
    }

    if (normalized.isEmpty) {
      await prefs.remove(_accountsKey);
      return;
    }
    await prefs.setString(
      _accountsKey,
      jsonEncode(
        normalized
            .map(
              (record) => <String, Object?>{
                'login': record.login,
                'updatedAt': record.updatedAt.toIso8601String(),
                'remembersPassword': record.remembersPassword,
                'avatarUrl': record.avatarUrl,
                'defaultAvatarKey': record.defaultAvatarKey,
                'useCount': record.useCount,
              },
            )
            .toList(),
      ),
    );
  }

  List<_LoginAccountMetadata> _readMetadata(SharedPreferences prefs) {
    final encoded = prefs.getString(_accountsKey);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<Object?>) return const [];
      return decoded
          .whereType<Map<String, Object?>>()
          .map(_LoginAccountMetadata.fromJson)
          .whereType<_LoginAccountMetadata>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _passwordKey(String login) {
    final key = base64Url.encode(utf8.encode(loginAccountKey(login)));
    return '$_passwordKeyPrefix$key';
  }
}

class _LoginAccountMetadata {
  const _LoginAccountMetadata({
    required this.login,
    required this.updatedAt,
    required this.remembersPassword,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    required this.useCount,
  });

  final String login;
  final DateTime updatedAt;
  final bool remembersPassword;
  final String? avatarUrl;
  final String? defaultAvatarKey;
  final int useCount;

  static _LoginAccountMetadata? fromJson(Map<String, Object?> json) {
    final login = json['login'] as String?;
    if (login == null || normalizeLoginAccount(login).isEmpty) return null;
    final updatedAtText = json['updatedAt'] as String?;
    return _LoginAccountMetadata(
      login: normalizeLoginAccount(login),
      updatedAt:
          DateTime.tryParse(updatedAtText ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      remembersPassword: json['remembersPassword'] == true,
      avatarUrl: _nonEmptyString(json['avatarUrl'] as String?),
      defaultAvatarKey: _nonEmptyString(json['defaultAvatarKey'] as String?),
      useCount: _positiveInt(json['useCount']),
    );
  }
}

String? _nonEmptyString(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

int _positiveInt(Object? value) {
  if (value is int && value > 0) return value;
  if (value is num && value > 0) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null && parsed > 0) return parsed;
  }
  return 1;
}
