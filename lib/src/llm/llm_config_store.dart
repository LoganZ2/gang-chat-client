import 'package:shared_preferences/shared_preferences.dart';

/// Global LLM provider configuration, persisted locally via SharedPreferences.
///
/// This is a local-only, per-machine config (not synced to the server). The
/// API key is stored in plain SharedPreferences because the app is a local
/// desktop tool, not a hosted service — same rationale as audio device prefs.
class LlmConfig {
  const LlmConfig({
    this.providerUrl = '',
    this.apiKey = '',
    this.modelName = '',
    this.contextLength = 8192,
  });

  /// OpenAI-compatible base URL, e.g. `https://api.openai.com/v1` or
  /// `http://localhost:11434/v1`. Must include the `/v1` suffix (or
  /// equivalent) so `/chat/completions` can be appended.
  final String providerUrl;

  final String apiKey;

  /// Model identifier passed to the API, e.g. `gpt-4o` or `llama3.1:8b`.
  final String modelName;

  /// Maximum context window in tokens. Auto-compaction triggers when the
  /// estimated token count approaches this value.
  final int contextLength;

  LlmConfig copyWith({
    String? providerUrl,
    String? apiKey,
    String? modelName,
    int? contextLength,
  }) {
    return LlmConfig(
      providerUrl: providerUrl ?? this.providerUrl,
      apiKey: apiKey ?? this.apiKey,
      modelName: modelName ?? this.modelName,
      contextLength: contextLength ?? this.contextLength,
    );
  }

  bool get isConfigured =>
      providerUrl.isNotEmpty && modelName.isNotEmpty;
}

const _keyProviderUrl = 'llm_provider_url';
const _keyApiKey = 'llm_api_key';
const _keyModelName = 'llm_model_name';
const _keyContextLength = 'llm_context_length';

class LlmConfigStore {
  const LlmConfigStore();

  Future<LlmConfig> read() async {
    final prefs = await SharedPreferences.getInstance();
    return LlmConfig(
      providerUrl: prefs.getString(_keyProviderUrl) ?? '',
      apiKey: prefs.getString(_keyApiKey) ?? '',
      modelName: prefs.getString(_keyModelName) ?? '',
      contextLength: prefs.getInt(_keyContextLength) ?? 8192,
    );
  }

  Future<void> write(LlmConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProviderUrl, config.providerUrl);
    await prefs.setString(_keyApiKey, config.apiKey);
    await prefs.setString(_keyModelName, config.modelName);
    await prefs.setInt(_keyContextLength, config.contextLength);
  }
}
