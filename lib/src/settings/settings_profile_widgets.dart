part of 'settings_page.dart';

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.spec});

  final account_display.AccountDeletionConfirmationSpec spec;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final matches = matchesConfirmationText(
      _controller.text,
      spec.expectedText,
    );
    return Dialog(
      backgroundColor: _primaryDarkLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(UiRadii.lg)),
        side: BorderSide(color: Color(0xFF3A2A2E)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                spec.title,
                style: const TextStyle(
                  color: _danger,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                spec.body,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                cursorColor: _textSecondary,
                contextMenuBuilder: buildTextFieldContextMenu,
                style: const TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: spec.inputHint,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  Button(
                    onPressed: matches
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    tone: ButtonTone.danger,
                    icon: const Icon(Icons.delete_outline),
                    child: Text(spec.confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordVisibilityToggle extends StatelessWidget {
  const _PasswordVisibilityToggle({
    required this.obscure,
    required this.enabled,
    required this.onPressed,
  });

  final bool obscure;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? _textSecondary : _textMuted;
    return Tooltip(
      message: obscure ? '显示密码' : '隐藏密码',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: obscure ? '显示密码' : '隐藏密码',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: 32,
            height: 22,
            child: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 17,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _UsernameValidityIndicator extends StatelessWidget {
  const _UsernameValidityIndicator({
    required this.error,
    required this.checking,
    required this.enabled,
  });

  final String? error;
  final bool checking;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final valid = error == null && !checking;
    final color = !enabled
        ? _textMuted
        : checking
        ? _textSecondary
        : valid
        ? _cyan
        : _danger;
    final label = checking ? '检测中' : (valid ? '合法' : '不合法');
    final message = checking
        ? '正在检测 Username 是否可用'
        : (valid ? 'Username 可用' : error!);
    return Tooltip(
      message: message,
      child: Semantics(
        label: checking
            ? '正在检测 Username 是否可用'
            : (valid ? 'Username 可用' : 'Username 不合法'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              checking
                  ? Icons.hourglass_empty_outlined
                  : valid
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SettingsNotice extends StatelessWidget {
  const _SettingsNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF1F2D27),
        borderRadius: BorderRadius.all(Radius.circular(UiRadii.md)),
        border: Border.fromBorderSide(BorderSide(color: Color(0xFF22332B))),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: _cyan, size: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: _textPrimary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsEmptyState extends StatelessWidget {
  const _SettingsEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _textMuted, fontSize: 13),
        ),
      ),
    );
  }
}
