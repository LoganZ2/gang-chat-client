import 'package:shared_preferences/shared_preferences.dart';

import '../app/settings_about.dart';

class LocalAutoUpdatePromptStore extends AutoUpdatePromptStore {
  const LocalAutoUpdatePromptStore();

  static const _autoUpdatePromptKey = 'gang.autoUpdatePrompt';

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
}
