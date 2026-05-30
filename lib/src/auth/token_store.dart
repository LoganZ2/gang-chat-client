import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  const TokenStore();

  static const _refreshTokenKey = 'gang.refreshToken';
  static const _apiBaseUrlKey = 'gang.apiBaseUrl';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  Future<String?> readRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> writeRefreshToken(String refreshToken) {
    return _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<void> clearRefreshToken() {
    return _storage.delete(key: _refreshTokenKey);
  }

  Future<String?> readApiBaseUrl() {
    return _storage.read(key: _apiBaseUrlKey);
  }

  Future<void> writeApiBaseUrl(String baseUrl) {
    return _storage.write(key: _apiBaseUrlKey, value: baseUrl);
  }
}
