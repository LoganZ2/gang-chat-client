import 'package:flutter/material.dart';

import '../ui/tokens.dart';
import '../llm/llm_config_store.dart';
import '../llm/llm_context_service.dart';

/// LLM provider/model configuration page. Global (per-user on this machine).
///
/// Fields:
/// - Provider URL (OpenAI-compatible base URL)
/// - API Key (optional for local models)
/// - Model name
/// - Context length (token window size)
class LlmSettingsPage extends StatefulWidget {
  const LlmSettingsPage({
    super.key,
    required this.service,
    required this.onClose,
  });

  final LlmContextService service;
  final VoidCallback onClose;

  @override
  State<LlmSettingsPage> createState() => _LlmSettingsPageState();
}

class _LlmSettingsPageState extends State<LlmSettingsPage> {
  late final TextEditingController _urlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _contextLengthController;
  bool _saving = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final config = widget.service.config;
    _urlController = TextEditingController(text: config.providerUrl);
    _apiKeyController = TextEditingController(text: config.apiKey);
    _modelController = TextEditingController(text: config.modelName);
    _contextLengthController =
        TextEditingController(text: config.contextLength.toString());
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _contextLengthController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _notice = null;
    });
    final contextLength = int.tryParse(_contextLengthController.text.trim()) ??
        widget.service.config.contextLength;
    await widget.service.saveConfig(LlmConfig(
      providerUrl: _urlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      modelName: _modelController.text.trim(),
      contextLength: contextLength,
    ));
    if (!mounted) return;
    setState(() {
      _saving = false;
      _notice = '已保存';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: UiColors.background,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    title: 'Provider',
                    children: [
                      _buildField(
                        label: 'API URL',
                        controller: _urlController,
                        hint: 'https://api.openai.com/v1',
                      ),
                      _buildField(
                        label: 'API Key',
                        controller: _apiKeyController,
                        hint: 'sk-...（本地模型可留空）',
                        obscure: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildSection(
                    title: 'Model',
                    children: [
                      _buildField(
                        label: 'Model Name',
                        controller: _modelController,
                        hint: 'gpt-4o / llama3.1:8b / ...',
                      ),
                      _buildField(
                        label: 'Context Length (tokens)',
                        controller: _contextLengthController,
                        hint: '8192',
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: UiColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(UiRadii.sm),
                          ),
                        ),
                        child: Text(_saving ? '保存中...' : '保存'),
                      ),
                      const SizedBox(width: 12),
                      if (_notice != null)
                        Text(
                          _notice!,
                          style: UiTypography.label
                              .copyWith(color: UiColors.accent),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _buildCompactionCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: UiColors.surfaceLow,
        border: Border(bottom: BorderSide(color: UiColors.border)),
      ),
      child: Row(
        children: [
          const Text(
            'LLM 设置',
            style: TextStyle(
              color: UiColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: widget.onClose,
            child: const Text('关闭', style: TextStyle(color: UiColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            title,
            style: const TextStyle(
              color: UiColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: UiColors.surface,
            borderRadius: BorderRadius.circular(UiRadii.md),
            border: Border.all(color: UiColors.border),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: UiTypography.label.copyWith(color: UiColors.textSecondary),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            style: const TextStyle(color: UiColors.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: UiColors.textMuted.withValues(alpha: 0.5)),
              filled: true,
              fillColor: UiColors.surfaceLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(UiRadii.sm),
                borderSide: BorderSide(color: UiColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(UiRadii.sm),
                borderSide: BorderSide(color: UiColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(UiRadii.sm),
                borderSide: const BorderSide(color: UiColors.accent),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactionCard() {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: UiColors.surface,
            borderRadius: BorderRadius.circular(UiRadii.md),
            border: Border.all(color: UiColors.border),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Compaction',
                style: TextStyle(
                  color: UiColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.service.config.isConfigured
                    ? '上下文达到 ${widget.service.config.contextLength} tokens 的 80% 时自动压缩。'
                    : '请先配置 LLM Provider 和 Model。',
                style: UiTypography.label.copyWith(color: UiColors.textMuted),
              ),
              if (widget.service.isCompacting) ...[
                const SizedBox(height: 10),
                const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('正在压缩...', style: TextStyle(color: UiColors.textMuted, fontSize: 12)),
                  ],
                ),
              ],
              if (widget.service.lastError != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.service.lastError!,
                  style: const TextStyle(color: UiColors.danger, fontSize: 12),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
