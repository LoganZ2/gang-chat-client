part of 'chat_pane.dart';

class _MessageStage extends StatelessWidget {
  const _MessageStage({
    required this.currentUserId,
    required this.roomReady,
    required this.loading,
    required this.error,
    required this.messages,
    required this.fileTransfers,
    required this.onRetry,
  });

  final String currentUserId;
  final bool roomReady;
  final bool loading;
  final String? error;
  final List<Message> messages;
  final Map<String, FileTransferState> fileTransfers;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null && !roomReady) {
      return _CenteredState(
        icon: Icons.error_outline,
        title: '无法加载聊天',
        detail: error!,
        action: Button(
          icon: const Icon(Icons.refresh),
          onPressed: onRetry,
          child: const Text('重试'),
        ),
      );
    }

    if (loading && messages.isEmpty) {
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

    if (messages.isEmpty) {
      return const _CenteredState(
        icon: Icons.forum_outlined,
        title: '还没有消息',
        detail: '在下方开始对话吧',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        _chatHorizontalPadding,
        18,
        _chatHorizontalPadding,
        _composerOverlayInset,
      ),
      itemCount: messages.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final message = messages[index];
        return _MessageRow(
          message: message,
          outgoing: message.sender.id == currentUserId,
          transfer: fileTransfers[message.clientMessageId],
        );
      },
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.outgoing,
    required this.transfer,
  });

  final Message message;
  final bool outgoing;
  final FileTransferState? transfer;

  @override
  Widget build(BuildContext context) {
    final bubble = Flexible(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _messageMaxWidth),
        child: _MessageBubble(
          message: message,
          outgoing: outgoing,
          transfer: transfer,
        ),
      ),
    );

    return Row(
      mainAxisAlignment: outgoing
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!outgoing) ...[
          Avatar(
            label: _senderName(message.sender),
            imageUrl: AppConfigScope.of(
              context,
            ).resolveAssetUrl(message.sender.avatarUrl),
            defaultAvatarKey: message.sender.defaultAvatarKey,
            size: 32,
            active: message.sender.isOnline ?? false,
            activeBorderWidth: 1,
          ),
          const SizedBox(width: 10),
        ],
        bubble,
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.outgoing,
    required this.transfer,
  });

  final Message message;
  final bool outgoing;
  final FileTransferState? transfer;

  @override
  Widget build(BuildContext context) {
    final contentKind = message_display.messageContentKind(message);
    final status = message_display.messageDeliveryStatusText(message);
    final sender = _senderName(message.sender);

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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    sender,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UiTypography.label.copyWith(
                      color: outgoing
                          ? UiColors.accent
                          : UiColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  message_display.formatMessageTime(message.createdAt),
                  style: UiTypography.label.copyWith(color: UiColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 7),
            switch (contentKind) {
              message_display.MessageContentKind.sticker => _StickerBody(
                attachment: message.stickerAttachment!,
              ),
              message_display.MessageContentKind.files => _FileBody(
                message: message,
                transfer: transfer,
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
    return Text(body, style: UiTypography.body);
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
    final name = attachment.name ?? '表情';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageUrl != null && imageUrl.isNotEmpty)
          ClipRRect(
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
        else
          _StickerFallback(name: name),
        const SizedBox(height: 7),
        Text(name, style: UiTypography.label),
      ],
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

class _FileBody extends StatelessWidget {
  const _FileBody({required this.message, required this.transfer});

  final Message message;
  final FileTransferState? transfer;

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
            attachment: attachments[index],
            transfer: index == 0 ? transfer : null,
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
  const _FileAttachmentTile({required this.attachment, required this.transfer});

  final MessageAttachment attachment;
  final FileTransferState? transfer;

  @override
  Widget build(BuildContext context) {
    final asset = attachment.asset;
    final title = file_display.fileAttachmentTitle(attachment);
    final meta = transfer == null
        ? file_display.fileAttachmentMeta(asset)
        : file_display.fileTransferProgressState(transfer!).label;
    final progress = transfer == null
        ? null
        : file_display.fileTransferProgressState(transfer!);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surfaceLow,
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(color: UiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
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
                      fontWeight: FontWeight.w800,
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
          ],
        ),
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
