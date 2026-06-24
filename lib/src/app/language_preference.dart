import '../protocol/models.dart';

const defaultLanguagePreference = defaultUserLanguage;

String normalizeLanguagePreference(String? language) {
  return switch (language?.trim()) {
    'zh-Hans' => 'zh-Hans',
    'zh-Hant' => 'zh-Hant',
    'en' => 'en',
    _ => defaultLanguagePreference,
  };
}

class LanguagePreferenceStore {
  const LanguagePreferenceStore();

  Future<String> read() {
    throw UnimplementedError(
      'LanguagePreferenceStore.read must be implemented.',
    );
  }

  Future<void> write(String language) {
    throw UnimplementedError(
      'LanguagePreferenceStore.write must be implemented.',
    );
  }
}
