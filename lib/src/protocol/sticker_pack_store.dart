import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class StickerPackStore {
  const StickerPackStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  }) : _storage = storage;

  static const _version = 1;
  static const _keyPrefix = 'gang.stickerPacks.v1';

  final FlutterSecureStorage _storage;

  Future<List<StickerPack>?> readPersonalPacks({
    required String userId,
    required String apiBaseUrl,
  }) async {
    if (userId.isEmpty || apiBaseUrl.isEmpty) return null;
    try {
      final raw = await _storage.read(key: _key(userId, apiBaseUrl));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      if (decoded['version'] != _version) return null;
      final packs = decoded['packs'];
      if (packs is! List<Object?>) return null;
      return packs
          .cast<Map<String, Object?>>()
          .map(StickerPack.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> writePersonalPacks({
    required String userId,
    required String apiBaseUrl,
    required List<StickerPack> packs,
  }) async {
    if (userId.isEmpty || apiBaseUrl.isEmpty) return;
    try {
      await _storage.write(
        key: _key(userId, apiBaseUrl),
        value: jsonEncode({
          'version': _version,
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'packs': packs.map((pack) => pack.toJson()).toList(),
        }),
      );
    } catch (_) {
      // The cache is a convenience path. Network data should remain usable even
      // when the platform storage backend refuses a large value.
    }
  }

  Future<void> clearPersonalPacks({
    required String userId,
    required String apiBaseUrl,
  }) async {
    if (userId.isEmpty || apiBaseUrl.isEmpty) return;
    try {
      await _storage.delete(key: _key(userId, apiBaseUrl));
    } catch (_) {}
  }

  String _key(String userId, String apiBaseUrl) {
    final account = base64Url
        .encode(utf8.encode('$apiBaseUrl\n$userId'))
        .replaceAll('=', '');
    return '$_keyPrefix.$account';
  }
}
