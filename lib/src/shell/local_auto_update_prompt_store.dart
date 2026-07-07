import 'package:shared_preferences/shared_preferences.dart';

import '../app/settings_about.dart';

class LocalAutoUpdatePromptStore extends AutoUpdatePromptStore {
  const LocalAutoUpdatePromptStore();

  static const _autoUpdatePromptKey = 'gang.autoUpdatePrompt';
  static const _ignoredVersionKey = 'gang.autoUpdateIgnoredVersion';

  @override
  Future<bool> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoUpdatePromptKey) ??
        defaultAutoUpdatePromptEnabled;
  }

  @override
  Future<void> write(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoUpdatePromptKey, enabled);
  }

  @override
  Future<String?> readIgnoredVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString(_ignoredVersionKey)?.trim();
    if (version == null || version.isEmpty) return null;
    return version;
  }

  @override
  Future<void> writeIgnoredVersion(String? version) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = version?.trim();
    if (normalized == null || normalized.isEmpty) {
      await prefs.remove(_ignoredVersionKey);
      return;
    }
    await prefs.setString(_ignoredVersionKey, normalized);
  }
}
