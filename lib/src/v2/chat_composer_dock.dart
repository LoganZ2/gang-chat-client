part of 'chat_pane.dart';

class _ComposerDock extends StatelessWidget {
  const _ComposerDock({
    required this.controller,
    required this.sending,
    required this.sendError,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool sending;
  final String? sendError;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sendError != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                sendError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: UiTypography.label.copyWith(color: UiColors.danger),
              ),
            ),
          ],
          Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: controller,
              hintText: 'Write a message',
              maxLines: 5,
              onSubmitted: onSubmit,
              actions: [
                ComposerAction(
                  id: 'stickers',
                  icon: Icons.emoji_emotions_outlined,
                  label: 'Stickers',
                  panel: ComposerPanel.list(
                    itemCount: _composerStickerIcons.length,
                    itemBuilder: (context, index) {
                      return _StickerPanelItem(
                        icon: _composerStickerIcons[index],
                        label: _composerStickerLabels[index],
                        color:
                            _composerStickerColors[index %
                                _composerStickerColors.length],
                      );
                    },
                  ),
                ),
                const ComposerAction(
                  id: 'voice',
                  icon: Icons.mic_none,
                  label: 'Voice',
                  panel: ComposerPanel.static(child: _VoicePanelPreview()),
                ),
                ComposerAction(
                  id: 'send',
                  icon: Icons.send_rounded,
                  label: 'Send',
                  tooltip: sending ? 'Sending' : 'Send',
                  tone: ButtonTone.primary,
                  onPressed: () => onSubmit(controller.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StickerPanelItem extends StatelessWidget {
  const _StickerPanelItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: PressableSurface(
        height: 76,
        onPressed: () {},
        padding: const EdgeInsets.all(10),
        backgroundColor: UiColors.surfaceLow,
        borderColor: UiColors.border,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: UiColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoicePanelPreview extends StatelessWidget {
  const _VoicePanelPreview();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PressableSurface(
          width: 86,
          height: 76,
          selected: true,
          padding: EdgeInsets.zero,
          child: const Center(
            child: Icon(Icons.mic_none, color: UiColors.accent, size: 30),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: _VoiceMeter()),
        const SizedBox(width: 12),
        Button(
          icon: const Icon(Icons.fiber_manual_record),
          tone: ButtonTone.primary,
          onPressed: () {},
          child: const Text('Record'),
        ),
      ],
    );
  }
}

class _VoiceMeter extends StatelessWidget {
  const _VoiceMeter();

  static const _levels = [0.34, 0.58, 0.82, 0.46, 0.72, 0.38, 0.62, 0.9];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: UiColors.surfaceLow,
          borderRadius: BorderRadius.circular(UiRadii.md),
          border: Border.all(color: UiColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Voice note',
                style: TextStyle(
                  color: UiColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (final level in _levels)
                      FractionallySizedBox(
                        heightFactor: level,
                        child: const SizedBox(
                          width: 7,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: UiColors.accent,
                              borderRadius: BorderRadius.all(
                                Radius.circular(99),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
