import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

/// Static, build-time URL configuration for the Gang Chat client.
///
/// Values come from three sources, in priority order:
///   1. `--dart-define` flags (e.g. `--dart-define=GANG_API_BASE_URL=...`).
///   2. `assets/config/app_config.json`, the committed default.
///   3. The hard-coded fallbacks in this file (last-resort dev defaults).
///
/// The asset is loaded once at app startup via [AppConfig.load].
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.assetBaseUrl,
  });

  /// Compile-time fallback config. Useful for tests and as a last-resort
  /// default when [load] cannot be awaited (e.g. synchronous widget creation).
  const AppConfig.defaults()
    : apiBaseUrl = _fallbackApiBaseUrl,
      assetBaseUrl = _fallbackAssetBaseUrl;

  /// Base URL of the REST API, including the `/api/v1` prefix.
  final String apiBaseUrl;

  /// Origin used to resolve relative asset URLs (avatars, attachments, ...).
  /// Should not contain a trailing slash.
  final String assetBaseUrl;

  static const _fallbackApiBaseUrl = 'http://127.0.0.1:21116/api/v1';
  static const _fallbackAssetBaseUrl = 'http://127.0.0.1:21116';

  static const _defineApiBaseUrl = String.fromEnvironment('GANG_API_BASE_URL');
  static const _defineAssetBaseUrl = String.fromEnvironment(
    'GANG_ASSET_BASE_URL',
  );

  static const _assetPath = 'assets/config/app_config.json';

  /// Resolve [path] (which may be relative or absolute) against [assetBaseUrl].
  /// Returns `null` if [path] is null or empty.
  String? resolveAssetUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    final lower = path.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('data:')) {
      return path;
    }
    final normalizedBase = assetBaseUrl.endsWith('/')
        ? assetBaseUrl.substring(0, assetBaseUrl.length - 1)
        : assetBaseUrl;
    final suffix = path.startsWith('/') ? path : '/$path';
    return '$normalizedBase$suffix';
  }

  /// Load the configuration. Failures are tolerated; the loader falls back to
  /// `--dart-define` values, then to the hard-coded defaults.
  static Future<AppConfig> load() async {
    Map<String, Object?> assetValues = const {};
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        assetValues = decoded;
      }
    } catch (_) {
      // The asset is optional. Fall back to defines + defaults.
    }

    String pick(String key, String fallback, String defineValue) {
      if (defineValue.isNotEmpty) return defineValue;
      final value = assetValues[key];
      if (value is String && value.isNotEmpty) return value;
      return fallback;
    }

    return AppConfig(
      apiBaseUrl: pick(
        'api_base_url',
        _fallbackApiBaseUrl,
        _defineApiBaseUrl,
      ),
      assetBaseUrl: pick(
        'asset_base_url',
        _fallbackAssetBaseUrl,
        _defineAssetBaseUrl,
      ),
    );
  }
}

/// Inherited widget that exposes the active [AppConfig] to descendants.
class AppConfigScope extends InheritedWidget {
  const AppConfigScope({
    super.key,
    required this.config,
    required super.child,
  });

  final AppConfig config;

  static AppConfig of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppConfigScope>();
    return scope?.config ?? const AppConfig.defaults();
  }

  @override
  bool updateShouldNotify(AppConfigScope oldWidget) =>
      oldWidget.config.apiBaseUrl != config.apiBaseUrl ||
      oldWidget.config.assetBaseUrl != config.assetBaseUrl;
}
