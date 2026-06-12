part of 'chat_pane.dart';

/// Callbacks for file-attachment downloads, bundled so they can travel from
/// [ChatPane] down to each [_FileAttachmentTile] without threading five
/// separate parameters through every intermediate widget.
class ChatFileDownloadActions {
  const ChatFileDownloadActions({
    required this.onDownload,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onDismiss,
  });

  /// Start downloading [attachment] (the [index]th attachment of [message]).
  /// [resolvedUrl] is the absolute asset URL, already resolved by the widget
  /// layer against [AppConfig].
  final void Function(
    Message message,
    MessageAttachment attachment,
    int index,
    String resolvedUrl,
  )
  onDownload;
  final ValueChanged<String> onPause;
  final ValueChanged<String> onResume;
  final ValueChanged<String> onCancel;
  final ValueChanged<String> onDismiss;
}

class ChatVoicePlaybackActions {
  const ChatVoicePlaybackActions({
    required this.activeMessageId,
    required this.onToggle,
    this.activePosition = Duration.zero,
    this.activeDuration = Duration.zero,
  });

  const ChatVoicePlaybackActions.disabled()
    : activeMessageId = null,
      onToggle = null,
      activePosition = Duration.zero,
      activeDuration = Duration.zero;

  final String? activeMessageId;
  final Duration activePosition;
  final Duration activeDuration;
  final void Function(String messageId, String resolvedUrl)? onToggle;

  bool isPlaying(String messageId) {
    return activeMessageId == messageId;
  }

  double progressFor(String messageId, {Duration? fallbackDuration}) {
    if (!isPlaying(messageId)) return 0;
    final duration = activeDuration > Duration.zero
        ? activeDuration
        : fallbackDuration;
    return voice_display.voicePlaybackProgress(
      position: activePosition,
      duration: duration,
    );
  }
}

class _MessageStage extends StatefulWidget {
  const _MessageStage({
    required this.roomId,
    required this.currentUserId,
    required this.roomReady,
    required this.loading,
    required this.error,
    required this.messages,
    required this.fileTransfers,
    required this.fileDownloads,
    required this.downloadActions,
    required this.voicePlaybackActions,
    required this.onRetry,
    required this.bottomInset,
    this.onResolveSenderProfile,
  });

  final String? roomId;
  final String currentUserId;
  final bool roomReady;
  final bool loading;
  final String? error;
  final List<Message> messages;
  final Map<String, FileTransferState> fileTransfers;
  final Map<String, FileTransferState> fileDownloads;
  final ChatFileDownloadActions downloadActions;
  final ChatVoicePlaybackActions voicePlaybackActions;
  final VoidCallback onRetry;
  // Space reserved at the bottom of the list so the floating composer (which
  // grows with staged files and open panels) never traps the last messages.
  final double bottomInset;
  final Future<UserSummary> Function(UserSummary sender)?
  onResolveSenderProfile;

  @override
  State<_MessageStage> createState() => _MessageStageState();
}

class _MessageStageState extends State<_MessageStage> {
  bool _showDetailedTimestamps = false;

  @override
  void didUpdateWidget(covariant _MessageStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _showDetailedTimestamps = false;
    }
  }

  void _toggleDetailedTimestamps() {
    setState(() {
      _showDetailedTimestamps = !_showDetailedTimestamps;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.error != null && !widget.roomReady) {
      return _CenteredState(
        icon: Icons.error_outline,
        title: '无法加载聊天',
        detail: widget.error!,
        action: Button(
          icon: const Icon(Icons.refresh),
          onPressed: widget.onRetry,
          child: const Text('重试'),
        ),
      );
    }

    if (widget.loading && widget.messages.isEmpty) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: UiColors.accent,
          ),
        ),
      );
    }

    if (widget.messages.isEmpty) {
      return const _CenteredState(
        icon: Icons.forum_outlined,
        title: '还没有消息',
        detail: '在下方开始对话吧',
      );
    }

    final now = DateTime.now();
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        _chatHorizontalPadding,
        18,
        _chatHorizontalPadding,
        widget.bottomInset,
      ),
      itemCount: widget.messages.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final message = widget.messages[index];
        final systemEvent = message_display.systemMessageEvent(message);
        final previous = index == 0 ? null : widget.messages[index - 1];
        final showTimestamp = message_display.shouldShowChatTimestamp(
          current: message.createdAt,
          previous: previous?.createdAt,
          now: now,
        );
        final timestamp = _showDetailedTimestamps
            ? message_display.formatDetailedChatTimestamp(message.createdAt)
            : message_display.formatChatTimestamp(message.createdAt, now: now);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTimestamp && systemEvent == null) ...[
              _MessageTimeDivider(
                label: timestamp,
                onTap: _toggleDetailedTimestamps,
              ),
              const SizedBox(height: 10),
            ],
            if (systemEvent != null)
              _SystemMessageRow(
                event: systemEvent,
                timestamp: timestamp,
                onTapTimestamp: _toggleDetailedTimestamps,
              )
            else
              _MessageRow(
                message: message,
                outgoing: message.sender.id == widget.currentUserId,
                transfer: widget.fileTransfers[message.clientMessageId],
                fileDownloads: widget.fileDownloads,
                downloadActions: widget.downloadActions,
                voicePlaybackActions: widget.voicePlaybackActions,
                onResolveSenderProfile: widget.onResolveSenderProfile,
              ),
          ],
        );
      },
    );
  }
}

class _MessageTimeDivider extends StatelessWidget {
  const _MessageTimeDivider({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: UiColors.surfacePressed,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: UiColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UiTypography.label.copyWith(
                  color: UiColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemMessageRow extends StatelessWidget {
  const _SystemMessageRow({
    required this.event,
    required this.timestamp,
    required this.onTapTimestamp,
  });

  final message_display.SystemMessageEvent event;
  final String timestamp;
  final VoidCallback onTapTimestamp;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _messageMaxWidth + 96),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: UiColors.surfacePressed.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: UiColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 5,
              runSpacing: 5,
              children: [
                _SystemTimestamp(label: timestamp, onTap: onTapTimestamp),
                ..._SystemMessageParts(event: event).build(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemTimestamp extends StatelessWidget {
  const _SystemTimestamp({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiTypography.label.copyWith(
            color: UiColors.textMuted,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _SystemMessageParts {
  const _SystemMessageParts({required this.event});

  final message_display.SystemMessageEvent event;

  List<Widget> build(BuildContext context) {
    final subject = event.subject;
    switch (event.event) {
      case message_display.kSystemEventRoomMemberJoined:
        return [_SystemUserChip(user: subject), _text('加入了房间')];
      case message_display.kSystemEventRoomMemberLeft:
        return [_SystemUserChip(user: subject), _text('离开了房间')];
      case message_display.kSystemEventRoomMemberRemoved:
        final actor = event.actor;
        return [
          _SystemUserChip(user: subject),
          if (actor == null)
            _text('被踢出了房间')
          else ...[
            _text('被'),
            _SystemUserChip(user: actor),
            _text('踢出了房间'),
          ],
        ];
      case message_display.kSystemEventLiveJoined:
        return [_SystemUserChip(user: subject), _text('进入了直播间')];
      case message_display.kSystemEventLiveLeft:
        return [_SystemUserChip(user: subject), _text('退出了直播间')];
      case message_display.kSystemEventRoomRoleChanged:
        final actor = event.actor;
        final roleLabel = message_display.systemMessageRoleLabel(event.toRole);
        final verb = message_display.systemMessageRoleVerb(event);
        final omitActor = message_display.systemMessageRoleChangeOmitsActor(
          event,
        );
        return [
          _SystemUserChip(user: subject),
          if (!omitActor && actor != null) ...[
            _text('被'),
            _SystemUserChip(user: actor),
          ],
          _text(verb),
          _SystemRoleTag(label: roleLabel),
        ];
      default:
        final fallback = event.message.body.trim();
        return [
          _SystemUserChip(user: subject),
          if (fallback.isNotEmpty) _text(fallback),
        ];
    }
  }

  Widget _text(String value) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: UiTypography.label.copyWith(
        color: UiColors.textSecondary,
        fontSize: 12,
      ),
    );
  }
}

class _SystemUserChip extends StatelessWidget {
  const _SystemUserChip({required this.user});

  final UserSummary user;

  @override
  Widget build(BuildContext context) {
    final name = _senderName(user);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Avatar(
          label: name,
          imageUrl: AppConfigScope.of(context).resolveAssetUrl(user.avatarUrl),
          defaultAvatarKey: user.defaultAvatarKey,
          size: 16,
          activeBorderWidth: 1,
        ),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 128),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.label.copyWith(
              color: UiColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SystemRoleTag extends StatelessWidget {
  const _SystemRoleTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.selected,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: UiColors.selectedBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiTypography.label.copyWith(
            color: UiColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.outgoing,
    required this.transfer,
    required this.fileDownloads,
    required this.downloadActions,
    required this.voicePlaybackActions,
    this.onResolveSenderProfile,
  });

  final Message message;
  final bool outgoing;
  final FileTransferState? transfer;
  final Map<String, FileTransferState> fileDownloads;
  final ChatFileDownloadActions downloadActions;
  final ChatVoicePlaybackActions voicePlaybackActions;
  final Future<UserSummary> Function(UserSummary sender)?
  onResolveSenderProfile;

  @override
  Widget build(BuildContext context) {
    final sender = _senderName(message.sender);
    final bubble = Flexible(
      child: Column(
        crossAxisAlignment: outgoing
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _messageMaxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                sender,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: outgoing ? TextAlign.right : TextAlign.left,
                style: UiTypography.label.copyWith(
                  color: outgoing ? UiColors.accent : UiColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _messageMaxWidth),
            child: _MessageBubble(
              message: message,
              outgoing: outgoing,
              transfer: transfer,
              fileDownloads: fileDownloads,
              downloadActions: downloadActions,
              voicePlaybackActions: voicePlaybackActions,
            ),
          ),
        ],
      ),
    );

    final avatar = Avatar(
      label: sender,
      imageUrl: AppConfigScope.of(
        context,
      ).resolveAssetUrl(message.sender.avatarUrl),
      defaultAvatarKey: message.sender.defaultAvatarKey,
      size: 32,
      active: message.sender.isOnline ?? false,
      activeBorderWidth: 1,
    );

    final avatarHoverCard = _AvatarHoverCard(
      user: message.sender,
      onResolveProfile: onResolveSenderProfile,
      child: avatar,
    );

    return Row(
      mainAxisAlignment: outgoing
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!outgoing) ...[avatarHoverCard, const SizedBox(width: 10)],
        bubble,
        if (outgoing) ...[const SizedBox(width: 10), avatarHoverCard],
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.outgoing,
    required this.transfer,
    required this.fileDownloads,
    required this.downloadActions,
    required this.voicePlaybackActions,
  });

  final Message message;
  final bool outgoing;
  final FileTransferState? transfer;
  final Map<String, FileTransferState> fileDownloads;
  final ChatFileDownloadActions downloadActions;
  final ChatVoicePlaybackActions voicePlaybackActions;

  @override
  Widget build(BuildContext context) {
    final contentKind = message_display.messageContentKind(message);
    final status = message_display.messageDeliveryStatusText(message);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: outgoing ? _outgoingBubble : _incomingBubble,
        borderRadius: BorderRadius.circular(UiRadii.lg),
        border: Border.all(
          color: outgoing ? UiColors.accentBorder : UiColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            switch (contentKind) {
              message_display.MessageContentKind.sticker => _StickerBody(
                attachment: message.stickerAttachment!,
              ),
              message_display.MessageContentKind.voice => _VoiceBody(
                message: message,
                attachment: voice_display.voiceMessageAttachment(message)!,
                playbackActions: voicePlaybackActions,
              ),
              message_display.MessageContentKind.files => _FileBody(
                message: message,
                outgoing: outgoing,
                transfer: transfer,
                fileDownloads: fileDownloads,
                downloadActions: downloadActions,
              ),
              message_display.MessageContentKind.text => _TextBody(
                body: message.body,
              ),
            },
            if (status != null) ...[
              const SizedBox(height: 7),
              Text(
                status,
                style: UiTypography.label.copyWith(
                  color: message.failed ? UiColors.danger : UiColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TextBody extends StatelessWidget {
  const _TextBody({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      body,
      style: UiTypography.body,
      cursorColor: UiColors.accent,
    );
  }
}

class _StickerBody extends StatelessWidget {
  const _StickerBody({required this.attachment});

  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final asset = attachment.asset;
    final imageUrl = asset == null
        ? null
        : AppConfigScope.of(
            context,
          ).resolveAssetUrl(asset.thumbnailUrl ?? asset.url);
    final name = message_display.stickerAttachmentTitle(attachment);
    final image = imageUrl != null && imageUrl.isNotEmpty
        ? ClipRRect(
            borderRadius: BorderRadius.circular(UiRadii.md),
            child: Image.network(
              imageUrl,
              width: 132,
              height: 132,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  _StickerFallback(name: name),
            ),
          )
        : _StickerFallback(name: name);

    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 350),
      child: image,
    );
  }
}

class _StickerFallback extends StatelessWidget {
  const _StickerFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surfaceLow,
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(color: UiColors.border),
      ),
      child: SizedBox(
        width: 132,
        height: 96,
        child: Center(
          child: Text(
            name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.label,
          ),
        ),
      ),
    );
  }
}

const _voiceAccent = Color(0xFF2EA7F2);

class _VoiceBody extends StatelessWidget {
  const _VoiceBody({
    required this.message,
    required this.attachment,
    required this.playbackActions,
  });

  final Message message;
  final MessageAttachment attachment;
  final ChatVoicePlaybackActions playbackActions;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = AppConfigScope.of(
      context,
    ).resolveAssetUrl(attachment.asset?.url);
    final playbackKey = message.clientMessageId;
    final playing = playbackActions.isPlaying(playbackKey);
    final canPlay =
        resolvedUrl != null &&
        resolvedUrl.isNotEmpty &&
        playbackActions.onToggle != null;
    final duration = voice_display.voiceAttachmentDuration(attachment);
    final durationText = voice_display.formatVoiceBubbleDuration(duration);
    final waveformWidth = voice_display.voiceWaveformWidth(duration);
    final playbackProgress = playbackActions.progressFor(
      playbackKey,
      fallbackDuration: duration,
    );

    void togglePlayback() {
      final url = resolvedUrl;
      final onToggle = playbackActions.onToggle;
      if (url == null || url.isEmpty || onToggle == null) return;
      onToggle(playbackKey, url);
    }

    return Semantics(
      button: canPlay,
      label: playing ? '停止播放录音' : '播放录音',
      child: MouseRegion(
        cursor: canPlay ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          onTap: canPlay ? togglePlayback : null,
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150, maxWidth: 280),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 22,
                  child: Icon(
                    playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: canPlay ? _voiceAccent : UiColors.textMuted,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 8),
                _VoiceWaveform(
                  key: const ValueKey('voice-waveform'),
                  width: waveformWidth,
                  progress: playbackProgress,
                ),
                if (durationText.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Text(
                    durationText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UiTypography.body.copyWith(
                      color: _voiceAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceWaveform extends StatelessWidget {
  const _VoiceWaveform({
    super.key,
    required this.width,
    required this.progress,
  });

  final double width;
  final double progress;

  static const _heights = <double>[
    8,
    16,
    22,
    13,
    18,
    10,
    24,
    15,
    9,
    19,
    12,
    21,
    7,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 28,
      child: Stack(
        children: [
          _VoiceWaveformBars(
            color: _voiceAccent.withValues(alpha: 0.28),
            width: width,
          ),
          Positioned.fill(
            child: ClipRect(
              clipper: _VoiceProgressClipper(progress),
              child: _VoiceWaveformBars(color: _voiceAccent, width: width),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceWaveformBars extends StatelessWidget {
  const _VoiceWaveformBars({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final height in _waveformHeightsForWidth(width))
            DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
              child: SizedBox(width: 3, height: height),
            ),
        ],
      ),
    );
  }
}

List<double> _waveformHeightsForWidth(double width) {
  final count = (width / 6).round().clamp(12, 28);
  return [
    for (var i = 0; i < count; i++)
      _VoiceWaveform._heights[i % _VoiceWaveform._heights.length],
  ];
}

class _VoiceProgressClipper extends CustomClipper<Rect> {
  const _VoiceProgressClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) {
    final clamped = progress.clamp(0, 1).toDouble();
    return Rect.fromLTWH(0, 0, size.width * clamped, size.height);
  }

  @override
  bool shouldReclip(covariant _VoiceProgressClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}

class _FileBody extends StatelessWidget {
  const _FileBody({
    required this.message,
    required this.outgoing,
    required this.transfer,
    required this.fileDownloads,
    required this.downloadActions,
  });

  final Message message;
  final bool outgoing;
  final FileTransferState? transfer;
  final Map<String, FileTransferState> fileDownloads;
  final ChatFileDownloadActions downloadActions;

  @override
  Widget build(BuildContext context) {
    final attachments = message.fileAttachments.toList(growable: false);
    final showBody = message_display.shouldShowFileAttachmentBody(
      body: message.body,
      attachments: attachments,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < attachments.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _FileAttachmentTile(
            message: message,
            outgoing: outgoing,
            attachment: attachments[index],
            index: index,
            // The outgoing upload transfer only ever applies to the first
            // attachment; the slot helper resolves upload vs. download for us.
            slot: file_display.fileAttachmentTransferSlot(
              message: message,
              attachment: attachments[index],
              index: index,
              uploadTransfer: transfer,
              downloads: fileDownloads,
            ),
            downloadActions: downloadActions,
          ),
        ],
        if (showBody) ...[
          const SizedBox(height: 8),
          Text(message.body, style: UiTypography.body),
        ],
      ],
    );
  }
}

class _FileAttachmentTile extends StatelessWidget {
  const _FileAttachmentTile({
    required this.message,
    required this.outgoing,
    required this.attachment,
    required this.index,
    required this.slot,
    required this.downloadActions,
  });

  final Message message;
  final bool outgoing;
  final MessageAttachment attachment;
  final int index;
  final file_display.FileAttachmentTransferSlot slot;
  final ChatFileDownloadActions downloadActions;

  @override
  Widget build(BuildContext context) {
    final asset = attachment.asset;
    final transfer = slot.transfer;
    final title = file_display.fileAttachmentTitle(attachment);
    final meta = transfer == null
        ? file_display.fileAttachmentMeta(asset)
        : file_display.fileTransferProgressState(transfer).label;
    final progress = transfer == null
        ? null
        : file_display.fileTransferProgressState(transfer);
    final previewPath = file_display.fileAttachmentPreviewPath(asset);

    // Resolve the asset URL here, at the widget layer, so the download
    // orchestration stays free of [AppConfig].
    final config = AppConfigScope.of(context);
    final resolvedUrl = config.resolveAssetUrl(asset?.url);
    final previewUrl = config.resolveAssetUrl(previewPath);
    final previewSize = file_display.fileAttachmentPreviewSize(asset);
    final interaction = file_display.fileAttachmentInteractionState(
      title: title,
      url: resolvedUrl,
      transfer: transfer,
    );
    final trailing = file_display.fileAttachmentTrailingState(
      transfer: transfer,
      canDownload: interaction.canDownload,
    );

    void startDownload() {
      final url = resolvedUrl;
      if (url == null) return;
      downloadActions.onDownload(message, attachment, index, url);
    }

    final tile = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(UiRadii.md),
        // No fill; the outline matches the surrounding bubble so it reads on
        // both the green outgoing bubble and the darker incoming one.
        border: Border.all(
          color: outgoing ? UiColors.accentBorder : UiColors.borderStrong,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (previewUrl != null && previewUrl.isNotEmpty) ...[
              _FileImagePreview(
                url: previewUrl,
                title: title,
                width: previewSize.width,
                height: previewSize.height,
              ),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  fileIconForMime(asset?.mimeType),
                  color: UiColors.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UiTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: UiTypography.label.copyWith(
                            color: progress?.failed == true
                                ? UiColors.danger
                                : UiColors.textMuted,
                          ),
                        ),
                      ],
                      if (progress != null) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 180,
                          child: LinearProgressIndicator(
                            value: progress.value,
                            minHeight: 3,
                            color: progress.failed
                                ? UiColors.danger
                                : UiColors.accent,
                            backgroundColor: UiColors.border,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _FileAttachmentTrailing(
                  state: trailing,
                  downloadKey: slot.downloadKey,
                  actions: downloadActions,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // Tapping an idle, downloadable tile starts the download. While a transfer
    // is in flight the trailing controls own the interaction instead.
    if (trailing.kind != file_display.FileAttachmentTrailingKind.download) {
      return tile;
    }
    return Tooltip(
      message: title,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: startDownload, child: tile),
      ),
    );
  }
}

class _FileImagePreview extends StatelessWidget {
  const _FileImagePreview({
    required this.url,
    required this.title,
    required this.width,
    required this.height,
  });

  final String url;
  final String title;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(UiRadii.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: UiColors.surfaceLow,
          border: Border.all(color: UiColors.border),
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: UiTypography.label.copyWith(
                      color: UiColors.textMuted,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Trailing controls for a file tile. Renders purely from
/// [file_display.FileAttachmentTrailingState]; the decision of which controls
/// to show lives in `file_display.dart`, so this widget only paints them.
class _FileAttachmentTrailing extends StatelessWidget {
  const _FileAttachmentTrailing({
    required this.state,
    required this.downloadKey,
    required this.actions,
  });

  final file_display.FileAttachmentTrailingState state;
  final String downloadKey;
  final ChatFileDownloadActions actions;

  @override
  Widget build(BuildContext context) {
    switch (state.kind) {
      // Idle/downloadable tiles carry no trailing control: tapping the tile
      // itself starts the download.
      case file_display.FileAttachmentTrailingKind.download:
        return const SizedBox.shrink();
      case file_display.FileAttachmentTrailingKind.activeTransfer:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ButtonIcon(
              icon: Icon(
                state.pauseResumeIsResume
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
              ),
              tooltip: state.pauseResumeTooltip ?? '',
              size: 32,
              onPressed: () => state.pauseResumeIsResume
                  ? actions.onResume(downloadKey)
                  : actions.onPause(downloadKey),
            ),
            const SizedBox(width: 4),
            ButtonIcon(
              icon: const Icon(Icons.close_rounded),
              tooltip: state.cancelTooltip ?? '',
              size: 32,
              onPressed: () => actions.onCancel(downloadKey),
            ),
          ],
        );
      case file_display.FileAttachmentTrailingKind.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.showDismiss)
              ButtonIcon(
                icon: const Icon(Icons.close_rounded),
                tooltip: '清除',
                size: 32,
                onPressed: () => actions.onDismiss(downloadKey),
              ),
          ],
        );
      case file_display.FileAttachmentTrailingKind.sending:
        return const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: UiColors.accent,
          ),
        );
      case file_display.FileAttachmentTrailingKind.placeholder:
        return const SizedBox.shrink();
    }
  }
}

/// Test-only entry point for a single private message bubble.
@visibleForTesting
class MessageBubbleForTest extends StatelessWidget {
  const MessageBubbleForTest({
    super.key,
    required this.message,
    required this.downloadActions,
    this.outgoing = false,
    this.transfer,
    this.fileDownloads = const {},
    this.voicePlaybackActions = const ChatVoicePlaybackActions.disabled(),
  });

  final Message message;
  final ChatFileDownloadActions downloadActions;
  final bool outgoing;
  final FileTransferState? transfer;
  final Map<String, FileTransferState> fileDownloads;
  final ChatVoicePlaybackActions voicePlaybackActions;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _messageMaxWidth),
      child: _MessageBubble(
        message: message,
        outgoing: outgoing,
        transfer: transfer,
        fileDownloads: fileDownloads,
        downloadActions: downloadActions,
        voicePlaybackActions: voicePlaybackActions,
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: UiColors.textMuted, size: 30),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: UiTypography.title,
              ),
              const SizedBox(height: 7),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: UiTypography.body.copyWith(color: UiColors.textMuted),
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

String _senderName(UserSummary user) {
  final roomName = user.roomDisplayName?.trim();
  if (roomName != null && roomName.isNotEmpty) return roomName;
  return user.displayName;
}
