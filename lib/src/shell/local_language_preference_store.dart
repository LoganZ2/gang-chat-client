import 'package:shared_preferences/shared_preferences.dart';

import '../app/language_preference.dart';

class LocalLanguagePreferenceStore extends LanguagePreferenceStore {
  const LocalLanguagePreferenceStore();

  static const _languageKey = 'gang.language';

  @override
  Future<String> read() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizeLanguagePreference(prefs.getString(_languageKey));
  }

  @override
  Future<void> write(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, normalizeLanguagePreference(language));
  }
}
