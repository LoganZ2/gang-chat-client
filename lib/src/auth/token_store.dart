import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the auth refresh token and the last-used API base URL.
///
/// The refresh token is sensitive (it grants a logged-in session), so it stays
/// in the OS keychain via flutter_secure_storage. The API base URL is not
/// sensitive and lives in SharedPreferences so reading it never triggers a
/// macOS keychain authorization prompt.
class TokenStore {
  const TokenStore();

  static const _refreshTokenKey = 'gang.refreshToken';
  static const _apiBaseUrlKey = 'gang.apiBaseUrl';

  FlutterSecureStorage get _storage => const FlutterSecureStorage(
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

  Future<String?> readApiBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiBaseUrlKey);
  }

  Future<void> writeApiBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiBaseUrlKey, baseUrl);
  }
}
