part of 'chat_pane.dart';

const _stickerPanelHeight = 268.0;
const _stickerTileSize = 56.0;

class _ComposerDock extends StatelessWidget {
  const _ComposerDock({
    required this.controller,
    required this.sending,
    required this.sendError,
    required this.stickerPanel,
    required this.onSubmit,
    required this.onSendSticker,
    required this.onOpenStickers,
    required this.onRefreshStickers,
    required this.onStickerSourceChanged,
  });

  final TextEditingController controller;
  final bool sending;
  final String? sendError;
  final sticker_display.StickerPanelLoadState stickerPanel;
  final ValueChanged<String> onSubmit;
  final ValueChanged<Sticker> onSendSticker;
  final VoidCallback onOpenStickers;
  final VoidCallback onRefreshStickers;
  final ValueChanged<sticker_display.StickerPanelSource> onStickerSourceChanged;

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
              hintText: '写点什么…',
              maxLines: 5,
              onSubmitted: onSubmit,
              actions: [
                ComposerAction(
                  id: 'stickers',
                  icon: Icons.emoji_emotions_outlined,
                  label: '表情',
                  onPressed: onOpenStickers,
                  panel: ComposerPanel.static(
                    height: _stickerPanelHeight,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: _StickerPanel(
                      state: stickerPanel,
                      onSendSticker: onSendSticker,
                      onRefresh: onRefreshStickers,
                      onSourceChanged: onStickerSourceChanged,
                    ),
                  ),
                ),
                const ComposerAction(
                  id: 'voice',
                  icon: Icons.mic_none,
                  label: '语音',
                  panel: ComposerPanel.static(child: _VoicePanelPreview()),
                ),
                ComposerAction(
                  id: 'send',
                  icon: Icons.send_rounded,
                  label: '发送',
                  tooltip: sending ? '发送中' : '发送',
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

/// The composer's sticker picker. Shows the user's personal packs and the
/// current room's packs behind a source toggle, sending the real managed
/// sticker (asset + id) rather than a decorative placeholder.
class _StickerPanel extends StatelessWidget {
  const _StickerPanel({
    required this.state,
    required this.onSendSticker,
    required this.onRefresh,
    required this.onSourceChanged,
  });

  final sticker_display.StickerPanelLoadState state;
  final ValueChanged<Sticker> onSendSticker;
  final VoidCallback onRefresh;
  final ValueChanged<sticker_display.StickerPanelSource> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    final packs = state.source == sticker_display.StickerPanelSource.personal
        ? state.personalPacks
        : state.roomPacks;
    final stickers = sticker_display.stickerPanelStickers(
      source: state.source,
      personalPacks: state.personalPacks,
      roomPacks: state.roomPacks,
    );
    final bodyState = sticker_display.stickerPanelBodyState(
      loading: state.loading,
      error: state.error,
      stickers: stickers,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedControl<sticker_display.StickerPanelSource>(
          value: state.source,
          expanded: true,
          onChanged: onSourceChanged,
          segments: const [
            Segment(
              value: sticker_display.StickerPanelSource.personal,
              label: '我的表情包',
            ),
            Segment(
              value: sticker_display.StickerPanelSource.room,
              label: '房间表情包',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: switch (bodyState) {
            sticker_display.StickerPanelBodyState.loading =>
              const _StickerPanelCentered(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: UiColors.accent,
                  ),
                ),
              ),
            sticker_display.StickerPanelBodyState.error => _StickerPanelMessage(
              icon: Icons.warning_amber_rounded,
              text: state.error ?? '加载表情失败',
              onRefresh: onRefresh,
            ),
            sticker_display.StickerPanelBodyState.empty => _StickerPanelMessage(
              icon: Icons.emoji_emotions_outlined,
              text: sticker_display.stickerPanelEmptyText(state.source),
            ),
            sticker_display.StickerPanelBodyState.results => _StickerPackList(
              packs: packs,
              onSendSticker: onSendSticker,
            ),
          },
        ),
      ],
    );
  }
}

class _StickerPackList extends StatelessWidget {
  const _StickerPackList({required this.packs, required this.onSendSticker});

  final List<StickerPack> packs;
  final ValueChanged<Sticker> onSendSticker;

  @override
  Widget build(BuildContext context) {
    // Packs are the unit of layering: a personal pack groups the user's saved
    // stickers, a room pack groups the room's shared ones. Multiple packs in a
    // scope render as separate labelled sections so the grouping stays visible.
    final visiblePacks = [
      for (final pack in packs)
        if (pack.stickers.isNotEmpty) pack,
    ];
    final showHeaders = visiblePacks.length > 1;

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: visiblePacks.length,
      itemBuilder: (context, index) {
        final pack = visiblePacks[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeaders) ...[
              if (index > 0) const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 2),
                child: Text(
                  pack.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: UiTypography.label.copyWith(
                    color: UiColors.textMuted,
                  ),
                ),
              ),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sticker in pack.stickers)
                  _StickerTile(
                    sticker: sticker,
                    onPressed: () => onSendSticker(sticker),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _StickerTile extends StatelessWidget {
  const _StickerTile({required this.sticker, required this.onPressed});

  final Sticker sticker;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final imageUrl = AppConfigScope.of(
      context,
    ).resolveAssetUrl(sticker.asset.thumbnailUrl ?? sticker.asset.url);

    return Tooltip(
      message: sticker.name,
      child: PressableSurface(
        width: _stickerTileSize,
        height: _stickerTileSize,
        onPressed: onPressed,
        padding: const EdgeInsets.all(6),
        backgroundColor: UiColors.surfaceLow,
        borderColor: UiColors.border,
        child: Center(
          child: imageUrl == null
              ? const Icon(
                  Icons.image_not_supported_outlined,
                  color: UiColors.textMuted,
                  size: 20,
                )
              : Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image_outlined,
                    color: UiColors.textMuted,
                    size: 20,
                  ),
                ),
        ),
      ),
    );
  }
}

class _StickerPanelCentered extends StatelessWidget {
  const _StickerPanelCentered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(child: child);
  }
}

class _StickerPanelMessage extends StatelessWidget {
  const _StickerPanelMessage({
    required this.icon,
    required this.text,
    this.onRefresh,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: UiColors.textMuted, size: 26),
          const SizedBox(height: 10),
          Text(
            text,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.label.copyWith(color: UiColors.textMuted),
          ),
          if (onRefresh != null) ...[
            const SizedBox(height: 12),
            Button(
              icon: const Icon(Icons.refresh),
              onPressed: onRefresh,
              child: const Text('刷新'),
            ),
          ],
        ],
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
          child: const Text('录制'),
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
                '语音消息',
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
