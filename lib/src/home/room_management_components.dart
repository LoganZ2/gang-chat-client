part of 'room_management.dart';

class _RoomDialogShell extends StatelessWidget {
  const _RoomDialogShell({
    required this.title,
    required this.icon,
    required this.child,
    required this.onClose,
    required this.maxWidth,
    required this.maxHeight,
    this.headerAction,
    this.pinned,
    this.embedded = false,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final VoidCallback onClose;
  final double maxWidth;
  final double maxHeight;
  final Widget? headerAction;
  final Widget? pinned;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      return SettingsScaffold(
        icon: icon,
        title: title,
        headerAction: headerAction,
        onBack: onClose,
        pinned: pinned,
        body: child,
      );
    }

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: UiColors.accent, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: UiColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?headerAction,
              if (headerAction != null) const SizedBox(width: 4),
              ButtonIcon(
                tooltip: '关闭',
                icon: const Icon(Icons.close),
                onPressed: onClose,
                size: 38,
              ),
            ],
          ),
          if (pinned != null) ...[const SizedBox(height: 14), pinned!],
          const SizedBox(height: 14),
          Expanded(child: child),
        ],
      ),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: UiColors.surfaceLow,
            borderRadius: BorderRadius.circular(_panelRadius),
            border: Border.all(color: UiColors.border),
          ),
          child: body,
        ),
      ),
    );
  }
}

class _RowSurface extends StatelessWidget {
  const _RowSurface({required this.child, this.compact = false});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surfaceLow,
        borderRadius: BorderRadius.circular(_rowRadius),
        border: Border.all(color: UiColors.border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 10,
          vertical: compact ? 7 : 9,
        ),
        child: child,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? UiColors.selected : UiColors.surfacePressed,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? UiColors.accentBorder : UiColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiTypography.label.copyWith(
            color: active ? UiColors.accent : UiColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _NoticeStrip extends StatelessWidget {
  const _NoticeStrip({required this.message, this.icon, this.danger = false});

  final String message;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: danger ? const Color(0xFF2E1F22) : UiColors.selected,
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(
          color: danger ? UiColors.dangerBorder : UiColors.accentBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(
              icon ?? Icons.error_outline,
              color: danger ? UiColors.danger : UiColors.accent,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: UiTypography.label.copyWith(color: UiColors.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: UiColors.textMuted, size: 30),
          const SizedBox(height: 8),
          Text(
            title,
            style: UiTypography.body.copyWith(color: UiColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _LabeledSegmented<T> extends StatelessWidget {
  const _LabeledSegmented({
    required this.label,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final T value;
  final List<Segment<T>> segments;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: UiTypography.label.copyWith(color: UiColors.textMuted),
          ),
        ),
        Expanded(
          child: IgnorePointer(
            ignoring: !enabled,
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: SegmentedControl<T>(
                expanded: true,
                value: value,
                segments: segments,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: UiTypography.label.copyWith(color: UiColors.textMuted),
          ),
        ),
        UiSwitch(
          value: value,
          onChanged: enabled ? onChanged : null,
          tooltip: label,
        ),
      ],
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.danger = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return DialogFrame(
      title: title,
      icon: danger ? Icons.warning_amber_outlined : Icons.info_outline,
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        Button(
          tone: danger ? ButtonTone.danger : ButtonTone.primary,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
      child: Text(message, style: UiTypography.body),
    );
  }
}

class _StrongConfirmDialog extends StatefulWidget {
  const _StrongConfirmDialog({
    required this.title,
    required this.message,
    required this.expectedText,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String expectedText;
  final String confirmLabel;

  @override
  State<_StrongConfirmDialog> createState() => _StrongConfirmDialogState();
}

class _StrongConfirmDialogState extends State<_StrongConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _controller.text.trim() == widget.expectedText;
    return DialogFrame(
      title: widget.title,
      icon: Icons.warning_amber_outlined,
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        Button(
          tone: ButtonTone.danger,
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message, style: UiTypography.body),
          const SizedBox(height: 12),
          Input(controller: _controller, hintText: widget.expectedText),
        ],
      ),
    );
  }
}

class _CroppedRoomAvatar {
  const _CroppedRoomAvatar({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

/// Open a file picker, read the bytes, and run them through the shared
/// [AvatarCropDialog]. Returns null if the user cancels at any step.
Future<_CroppedRoomAvatar?> _pickAndCropRoomAvatar(BuildContext context) async {
  const fileSelectionService = FileSelectionService();
  SelectedFile? file;
  try {
    file = await fileSelectionService.openFile(
      acceptedTypeGroups: const [
        FileTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp']),
      ],
    );
  } catch (error) {
    throw Exception('无法打开文件选择器：$error');
  }
  if (file == null) return null;

  Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (error) {
    throw Exception('无法读取图片：$error');
  }
  if (bytes.isEmpty) {
    throw Exception('图片文件为空');
  }
  if (!context.mounted) return null;

  final cropped = await showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AvatarCropDialog(bytes: bytes, title: '裁剪房间图标'),
  );
  if (cropped == null) return null;
  return _CroppedRoomAvatar(
    bytes: cropped,
    filename: account_display.avatarUploadFilename(file.name),
  );
}
