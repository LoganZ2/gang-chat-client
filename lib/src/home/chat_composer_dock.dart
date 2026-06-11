part of 'chat_pane.dart';

const _stickerPanelHeight = 268.0;
const _stickerTileSize = 56.0;
const _voicePanelHeight = 150.0;

class _ComposerDock extends StatelessWidget {
  const _ComposerDock({
    required this.controller,
    required this.sending,
    required this.sendError,
    required this.stickerPanel,
    required this.voiceState,
    required this.attachments,
    required this.fileActionHighlighted,
    required this.onSubmit,
    required this.onSendSticker,
    required this.onOpenStickers,
    required this.onRefreshStickers,
    required this.onStickerSourceChanged,
    required this.onStartVoice,
    required this.onSendVoice,
    required this.onCancelVoice,
    required this.onPickFile,
    required this.onPasteFiles,
    required this.onRemoveAttachment,
    required this.onRetryAttachment,
    this.dropKey,
  });

  final TextEditingController controller;
  final bool sending;
  final String? sendError;
  final sticker_display.StickerPanelLoadState stickerPanel;
  final voice_display.VoiceRecorderState voiceState;
  final List<composer_attachment.ComposerAttachmentView> attachments;
  final bool fileActionHighlighted;
  final ValueChanged<String> onSubmit;
  final ValueChanged<Sticker> onSendSticker;
  final VoidCallback onOpenStickers;
  final VoidCallback onRefreshStickers;
  final ValueChanged<sticker_display.StickerPanelSource> onStickerSourceChanged;
  final VoidCallback onStartVoice;
  final VoidCallback onSendVoice;
  final VoidCallback onCancelVoice;
  final VoidCallback onPickFile;
  final VoidCallback onPasteFiles;
  final ValueChanged<String> onRemoveAttachment;
  final ValueChanged<String> onRetryAttachment;
  final Key? dropKey;

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
            child: KeyedSubtree(
              key: dropKey,
              child: ChatComposer(
                controller: controller,
                hintText: '写点什么…',
                maxLines: 5,
                onSubmitted: onSubmit,
                onPasteFiles: onPasteFiles,
                attachments: attachments.isEmpty
                    ? null
                    : _ComposerAttachmentStrip(
                        attachments: attachments,
                        onRemove: onRemoveAttachment,
                        onRetry: onRetryAttachment,
                      ),
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
                  ComposerAction(
                    id: 'voice',
                    icon: Icons.mic_none,
                    label: '语音',
                    onPressed: onCancelVoice,
                    panel: ComposerPanel.static(
                      height: _voicePanelHeight,
                      child: _VoicePanel(
                        state: voiceState,
                        onStart: onStartVoice,
                        onSend: onSendVoice,
                        onCancel: onCancelVoice,
                      ),
                    ),
                  ),
                  ComposerAction(
                    id: 'file',
                    icon: Icons.attach_file,
                    label: '文件',
                    selected: fileActionHighlighted,
                    onPressed: onPickFile,
                  ),
                  ComposerAction(
                    id: 'send',
                    icon: Icons.send_rounded,
                    label: '发送',
                    tooltip: sending ? '发送中' : '发送',
                    tone: ButtonTone.primary,
                    alignment: ComposerActionAlignment.trailing,
                    onPressed: () => onSubmit(controller.text),
                  ),
                ],
              ),
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
            sticker_display.StickerPanelBodyState.results => _StickerList(
              stickers: stickers,
              onSendSticker: onSendSticker,
            ),
          },
        ),
      ],
    );
  }
}

class _StickerList extends StatelessWidget {
  const _StickerList({required this.stickers, required this.onSendSticker});

  final List<Sticker> stickers;
  final ValueChanged<Sticker> onSendSticker;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final sticker in stickers)
              _StickerTile(
                sticker: sticker,
                onPressed: () => onSendSticker(sticker),
              ),
          ],
        ),
      ],
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

/// The strip of staged-file chips shown above the composer input. Each chip
/// names a file queued for the next message and offers a remove button. The
/// files ride out as attachments when the message is sent.
class _ComposerAttachmentStrip extends StatelessWidget {
  const _ComposerAttachmentStrip({
    required this.attachments,
    required this.onRemove,
    required this.onRetry,
  });

  final List<composer_attachment.ComposerAttachmentView> attachments;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final attachment in attachments)
            _ComposerAttachmentChip(
              attachment: attachment,
              onRemove: () => onRemove(attachment.id),
              onRetry: () => onRetry(attachment.id),
            ),
        ],
      ),
    );
  }
}

class _ComposerAttachmentChip extends StatelessWidget {
  const _ComposerAttachmentChip({
    required this.attachment,
    required this.onRemove,
    required this.onRetry,
  });

  final composer_attachment.ComposerAttachmentView attachment;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final size = attachment.sizeLabel;
    final failed = attachment.hasFailed;
    final subtitle = switch (attachment.status) {
      composer_attachment.ComposerAttachmentStatus.failed =>
        attachment.errorMessage ?? '上传失败，点击重试',
      composer_attachment.ComposerAttachmentStatus.uploading =>
        attachment.progress == null
            ? '上传中…'
            : '上传中 ${(attachment.progress! * 100).round()}%',
      composer_attachment.ComposerAttachmentStatus.uploaded => size,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(color: failed ? UiColors.danger : UiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ComposerAttachmentLeading(
              attachment: attachment,
              onRetry: onRetry,
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Tooltip(
                message: attachment.filename,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UiTypography.label.copyWith(color: UiColors.text),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: UiTypography.label.copyWith(
                          color: failed ? UiColors.danger : UiColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              iconSize: 16,
              color: UiColors.textMuted,
              splashRadius: 16,
              tooltip: '移除',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chip's leading slot: a spinner while uploading, a tappable retry icon
/// when the upload failed, and the file-type glyph once it has landed.
class _ComposerAttachmentLeading extends StatelessWidget {
  const _ComposerAttachmentLeading({
    required this.attachment,
    required this.onRetry,
  });

  final composer_attachment.ComposerAttachmentView attachment;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    switch (attachment.status) {
      case composer_attachment.ComposerAttachmentStatus.uploading:
        return SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: attachment.progress,
            color: UiColors.accent,
          ),
        );
      case composer_attachment.ComposerAttachmentStatus.failed:
        return InkResponse(
          onTap: onRetry,
          radius: 16,
          child: const Icon(Icons.refresh, size: 18, color: UiColors.danger),
        );
      case composer_attachment.ComposerAttachmentStatus.uploaded:
        return Icon(
          composer_attachment.composerAttachmentGlyph(
            mimeType: attachment.mimeType,
            filename: attachment.filename,
          ),
          size: 18,
          color: UiColors.textSecondary,
        );
    }
  }
}

class _VoicePanel extends StatelessWidget {
  const _VoicePanel({
    required this.state,
    required this.onStart,
    required this.onSend,
    required this.onCancel,
  });

  final voice_display.VoiceRecorderState state;
  final VoidCallback onStart;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: switch (state.phase) {
        voice_display.VoiceRecorderPhase.idle => _VoiceIdle(
          error: state.error,
          onStart: onStart,
        ),
        voice_display.VoiceRecorderPhase.recording => _VoiceActive(
          elapsed: state.elapsed,
          recording: true,
          busy: false,
          onSend: onSend,
          onCancel: onCancel,
        ),
        voice_display.VoiceRecorderPhase.review => _VoiceActive(
          elapsed: state.elapsed,
          recording: false,
          busy: false,
          error: state.error,
          onSend: onSend,
          onCancel: onCancel,
        ),
        voice_display.VoiceRecorderPhase.sending => _VoiceActive(
          elapsed: state.elapsed,
          recording: false,
          busy: true,
          onSend: onSend,
          onCancel: onCancel,
        ),
      },
    );
  }
}

class _VoiceIdle extends StatelessWidget {
  const _VoiceIdle({required this.onStart, this.error});

  final VoidCallback onStart;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 14),
        // Plain icon trigger — no raised surface or circular background.
        IconButton(
          onPressed: onStart,
          icon: const Icon(Icons.mic_none),
          iconSize: 30,
          color: UiColors.accent,
          tooltip: '点击录音',
          splashRadius: 24,
        ),
        const SizedBox(height: 8),
        Text(
          error ?? '点击录音',
          textAlign: TextAlign.center,
          style: UiTypography.label.copyWith(
            color: error != null ? UiColors.danger : UiColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _VoiceActive extends StatelessWidget {
  const _VoiceActive({
    required this.elapsed,
    required this.recording,
    required this.busy,
    required this.onSend,
    required this.onCancel,
    this.error,
  });

  final Duration elapsed;
  final bool recording;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              recording ? Icons.fiber_manual_record : Icons.mic_none,
              size: 16,
              color: recording ? UiColors.danger : UiColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              voice_display.formatVoiceDuration(elapsed),
              style: UiTypography.body.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          error ?? (recording ? '正在录音…' : '点击发送或取消'),
          textAlign: TextAlign.center,
          style: UiTypography.label.copyWith(
            color: error != null ? UiColors.danger : UiColors.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ButtonIcon(
              onPressed: busy ? null : onCancel,
              icon: const Icon(Icons.delete_outline),
              tooltip: '取消',
              tone: ButtonTone.danger,
              size: 34,
            ),
            const SizedBox(width: 10),
            ButtonIcon(
              onPressed: busy ? null : onSend,
              icon: const Icon(Icons.send_rounded),
              tooltip: recording ? '完成并发送' : '发送',
              tone: ButtonTone.primary,
              loading: busy,
              size: 34,
            ),
          ],
        ),
      ],
    );
  }
}

/// Test-only entry point for the otherwise-private composer attachment strip,
/// so widget tests can pump it directly without standing up the whole dock.
@visibleForTesting
class ComposerAttachmentStripForTest extends StatelessWidget {
  const ComposerAttachmentStripForTest({
    super.key,
    required this.attachments,
    required this.onRemove,
    this.onRetry,
  });

  final List<composer_attachment.ComposerAttachmentView> attachments;
  final ValueChanged<String> onRemove;
  final ValueChanged<String>? onRetry;

  @override
  Widget build(BuildContext context) {
    return _ComposerAttachmentStrip(
      attachments: attachments,
      onRemove: onRemove,
      onRetry: onRetry ?? (_) {},
    );
  }
}

/// Test-only entry point for the otherwise-private voice panel, so widget
/// tests can pump it directly without standing up the whole composer dock.
@visibleForTesting
class VoicePanelForTest extends StatelessWidget {
  const VoicePanelForTest({
    super.key,
    required this.state,
    required this.onStart,
    required this.onSend,
    required this.onCancel,
  });

  final voice_display.VoiceRecorderState state;
  final VoidCallback onStart;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return _VoicePanel(
      state: state,
      onStart: onStart,
      onSend: onSend,
      onCancel: onCancel,
    );
  }
}

/// Test-only entry point for the otherwise-private sticker panel.
@visibleForTesting
class StickerPanelForTest extends StatelessWidget {
  const StickerPanelForTest({
    super.key,
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
    return _StickerPanel(
      state: state,
      onSendSticker: onSendSticker,
      onRefresh: onRefresh,
      onSourceChanged: onSourceChanged,
    );
  }
}
