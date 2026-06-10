part of 'home_shell.dart';

class _JoinApplicationDialog extends StatefulWidget {
  const _JoinApplicationDialog({required this.room});

  final PublicRoom room;

  @override
  State<_JoinApplicationDialog> createState() => _JoinApplicationDialogState();
}

class _JoinApplicationDialogState extends State<_JoinApplicationDialog> {
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  void _send() {
    Navigator.of(context).pop(_reasonController.text);
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: UiColors.surfaceLow,
            borderRadius: BorderRadius.circular(UiRadii.lg),
            border: Border.all(color: UiColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.how_to_reg_outlined,
                      color: UiColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '申请加入',
                        style: UiTypography.title.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    ButtonIcon(
                      tooltip: '关闭',
                      icon: const Icon(Icons.close),
                      onPressed: _cancel,
                      size: 34,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 6,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '您需要等待',
                      style: UiTypography.body.copyWith(
                        color: UiColors.textSecondary,
                      ),
                    ),
                    Avatar(
                      label: room.name,
                      imageUrl: AppConfigScope.of(
                        context,
                      ).resolveAssetUrl(room.avatarUrl),
                      defaultAvatarKey: room.defaultAvatarKey,
                      size: 28,
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 230),
                      child: Text(
                        room.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UiTypography.body.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '的管理员批准',
                      style: UiTypography.body.copyWith(
                        color: UiColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Input(
                  controller: _reasonController,
                  hintText: '申请说明',
                  minLines: 3,
                  maxLines: 4,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Button(onPressed: _cancel, child: const Text('取消')),
                    const SizedBox(width: 8),
                    Button(
                      tone: ButtonTone.primary,
                      onPressed: _send,
                      child: const Text('发送申请'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
