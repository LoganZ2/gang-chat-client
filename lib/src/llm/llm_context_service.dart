import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../protocol/models.dart';
import 'llm_config_store.dart';

/// Tracks the LLM context for the current room and handles compaction.
///
/// "Context" = a running summary (produced by compaction) + recent messages.
/// Token count is estimated as ceil(bytes / 4) — a standard heuristic that
/// avoids shipping a tokenizer for every model family. When the estimated
/// token count exceeds the configured context length, [checkAutoCompact]
/// triggers a compaction call to the LLM API.
///
/// Compaction sends the oldest portion of the context to the configured
/// OpenAI-compatible endpoint with a "summarize" system prompt, stores the
/// returned summary, and drops the summarized messages from the active
/// window. The summary persists per-room in memory; it is not sent to the
/// gang-chat server.
class LlmContextService extends ChangeNotifier {
  LlmContextService({LlmConfigStore? configStore})
      : _configStore = configStore ?? const LlmConfigStore();

  final LlmConfigStore _configStore;

  LlmConfig _config = const LlmConfig();
  LlmConfig get config => _config;

  /// Per-room compacted summaries (roomId → summary text).
  final Map<String, String> _summaries = {};

  /// Per-room active message windows (roomId → messages in the context).
  final Map<String, List<Message>> _windows = {};

  bool _compacting = false;
  bool get isCompacting => _compacting;

  String? _lastError;
  String? get lastError => _lastError;

  /// Estimated token count for the given room's context (summary + messages).
  int contextTokens(String roomId) {
    int tokens = 0;
    final summary = _summaries[roomId];
    if (summary != null && summary.isNotEmpty) {
      tokens += _estimateTokens(summary);
    }
    for (final msg in _windows[roomId] ?? const <Message>[]) {
      tokens += _estimateTokens('${msg.sender.displayName}: ${msg.body}');
    }
    return tokens;
  }

  /// Rough token estimate: ~4 bytes per token for most tokenizers.
  int _estimateTokens(String text) {
    return (utf8.encode(text).length / 4).ceil();
  }

  /// Loads config from disk. Call once at startup.
  Future<void> loadConfig() async {
    _config = await _configStore.read();
    notifyListeners();
  }

  Future<void> saveConfig(LlmConfig config) async {
    _config = config;
    await _configStore.write(config);
    notifyListeners();
  }

  /// Sets the active message window for a room (called when messages load/update).
  void setRoomMessages(String roomId, List<Message> messages) {
    _windows[roomId] = List.of(messages);
    notifyListeners();
  }

  /// Clears context for a room (called when leaving/disconnecting).
  void clearRoom(String roomId) {
    _summaries.remove(roomId);
    _windows.remove(roomId);
    notifyListeners();
  }

  /// Returns the summary for a room, if compaction has been performed.
  String? summaryFor(String roomId) => _summaries[roomId];

  /// Checks if auto-compaction should trigger and runs it if so.
  /// Returns true if compaction was triggered.
  Future<bool> checkAutoCompact(String roomId) async {
    if (!_config.isConfigured || _compacting) return false;
    final tokens = contextTokens(roomId);
    // Trigger at 80% of context length — leave room for the response.
    if (tokens < _config.contextLength * 0.8) return false;
    return compact(roomId);
  }

  /// Manually triggers compaction for a room.
  /// Returns true on success, false on failure (sets [lastError]).
  Future<bool> compact(String roomId) async {
    if (!_config.isConfigured) {
      _lastError = 'LLM 未配置';
      notifyListeners();
      return false;
    }
    if (_compacting) return false;

    final messages = _windows[roomId];
    if (messages == null || messages.isEmpty) {
      _lastError = '没有可压缩的上下文';
      notifyListeners();
      return false;
    }

    _compacting = true;
    _lastError = null;
    notifyListeners();

    try {
      // Keep the most recent ~25% of messages; summarize the rest.
      final keepCount = (messages.length * 0.25).ceil().clamp(1, messages.length - 1);
      final toSummarize = messages.sublist(0, messages.length - keepCount);
      final toKeep = messages.sublist(messages.length - keepCount);

      final existingSummary = _summaries[roomId] ?? '';
      final conversationText = _buildConversationText(toSummarize, existingSummary);

      final summary = await _callLlmForSummary(conversationText);
      _summaries[roomId] = summary;
      _windows[roomId] = toKeep;
      _compacting = false;
      notifyListeners();
      return true;
    } catch (e) {
      _compacting = false;
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  String _buildConversationText(List<Message> messages, String existingSummary) {
    final parts = <String>[];
    if (existingSummary.isNotEmpty) {
      parts.add('Previous summary:\n$existingSummary');
    }
    for (final msg in messages) {
      if (msg.isRemoved) continue;
      parts.add('${msg.sender.displayName}: ${msg.body}');
    }
    return parts.join('\n');
  }

  /// Calls the configured OpenAI-compatible endpoint to summarize the text.
  Future<String> _callLlmForSummary(String conversationText) async {
    final url = '${_config.providerUrl}/chat/completions';
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    final requestBody = jsonEncode({
      'model': _config.modelName,
      'messages': [
        {
          'role': 'system',
          'content': 'You are a conversation summarizer. Summarize the '
              'following conversation concisely, preserving key decisions, '
              'action items, and important context. Write in the same language '
              'as the conversation. Respond with only the summary.',
        },
        {
          'role': 'user',
          'content': conversationText,
        },
      ],
      'max_tokens': 1024,
      'temperature': 0.3,
    });

    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    if (_config.apiKey.isNotEmpty) {
      request.headers.set('Authorization', 'Bearer ${_config.apiKey}');
    }
    request.write(requestBody);

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception('LLM API error ${response.statusCode}: $body');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('LLM API returned no choices');
    }
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>;
    final content = message['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw Exception('LLM API returned empty summary');
    }
    return content.trim();
  }
}
