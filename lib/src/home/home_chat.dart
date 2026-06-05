part of 'home_page.dart';

enum _StickerContextAction { saveToPersonal, saveToRoom, saveAs }

Sticker? _stickerFromAttachment(MessageAttachment attachment, String fallback) {
  final stickerId = attachment.stickerId;
  final asset = attachment.asset;
  if (stickerId == null || asset == null) return null;
  return Sticker(
    id: stickerId,
    name: attachment.name ?? fallback,
    sortOrder: 10,
    asset: asset,
  );
}

class _ChatPane extends StatefulWidget {
  const _ChatPane({
    required this.roomId,
    required this.stickerPacksController,
    required this.messages,
    required this.fileTransfers,
    required this.fileDownloads,
    required this.currentUserId,
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onStickerSend,
    required this.onFileSend,
    required this.onFilePause,
    required this.onFileResume,
    required this.onFileCancel,
    required this.onFileDownload,
    required this.onFileDownloadPause,
    required this.onFileDownloadResume,
    required this.onFileDownloadCancel,
    required this.onOpenUserInfo,
    required this.canManageRoomStickers,
    required this.onStickerSaveToPersonal,
    required this.onStickerSaveToRoom,
    required this.onStickerSaveAs,
  });

  final String roomId;
  final StickerPacksController stickerPacksController;
  final List<Message> messages;
  final Map<String, FileTransferState> fileTransfers;
  final Map<String, FileTransferState> fileDownloads;
  final String currentUserId;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final Future<void> Function(Sticker sticker) onStickerSend;
  final Future<void> Function() onFileSend;
  final ValueChanged<String> onFilePause;
  final ValueChanged<String> onFileResume;
  final ValueChanged<String> onFileCancel;
  final Future<void> Function({
    required String downloadKey,
    required MessageAttachment attachment,
    required String url,
  })
  onFileDownload;
  final ValueChanged<String> onFileDownloadPause;
  final ValueChanged<String> onFileDownloadResume;
  final ValueChanged<String> onFileDownloadCancel;
  final ValueChanged<UserSummary> onOpenUserInfo;
  final bool canManageRoomStickers;
  final Future<void> Function(Sticker sticker) onStickerSaveToPersonal;
  final Future<void> Function(Sticker sticker) onStickerSaveToRoom;
  final Future<void> Function(Sticker sticker) onStickerSaveAs;

  @override
  State<_ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<_ChatPane> {
  final Object _composerTapRegionGroup = Object();
  ChatComposerPanel? _openPanel;
  sticker_display.StickerPanelLoadState _stickerPanelState =
      const sticker_display.StickerPanelLoadState();
  double _composerInputHeight = 76;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(_ChatPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _applyComposerPanelPatch(chatComposerPanelResetForRoomChange());
      _resetStickerPacks();
      if (_openPanel == ChatComposerPanel.stickers) {
        unawaited(_ensureStickerPacksLoaded(forceReload: true));
      }
    } else if (oldWidget.stickerPacksController !=
            widget.stickerPacksController ||
        oldWidget.currentUserId != widget.currentUserId) {
      _resetStickerPacks();
      if (_openPanel == ChatComposerPanel.stickers) {
        unawaited(_ensureStickerPacksLoaded());
      }
    }
  }

  void _resetStickerPacks() {
    _stickerPanelState = sticker_display.stickerPanelReset(
      source: _stickerPanelState.source,
    );
  }

  Future<void> _ensureStickerPacksLoaded({bool forceReload = false}) async {
    if (!sticker_display.shouldLoadStickerPanel(
      state: _stickerPanelState,
      forceReload: forceReload,
    )) {
      return;
    }
    await _loadStickerPacks(forceReload: forceReload);
  }

  Future<void> _loadStickerPacks({bool forceReload = false}) async {
    final roomId = widget.roomId;
    setState(
      () => _stickerPanelState = sticker_display.stickerPanelLoadStarted(
        _stickerPanelState,
      ),
    );
    try {
      final cachedPersonal = forceReload
          ? null
          : await widget.stickerPacksController.readCachedPersonalPacks(
              userId: widget.currentUserId,
            );
      if (!mounted || widget.roomId != roomId) return;
      if (cachedPersonal != null) {
        setState(
          () => _stickerPanelState = sticker_display
              .stickerPanelCachedPersonalApplied(
                state: _stickerPanelState,
                packs: cachedPersonal,
              ),
        );
        _precacheStickerThumbnails(cachedPersonal, limit: 30);
      }
      final shouldFetchPersonal = forceReload || cachedPersonal == null;
      final packs = await Future.wait([
        shouldFetchPersonal
            ? widget.stickerPacksController.loadPersonalPacks(
                userId: widget.currentUserId,
                forceReload: true,
              )
            : Future<List<StickerPack>>.value(cachedPersonal),
        widget.stickerPacksController.loadRoomPacks(roomId),
      ]);
      if (!mounted || widget.roomId != roomId) return;
      setState(
        () => _stickerPanelState = sticker_display.stickerPanelLoadSucceeded(
          state: _stickerPanelState,
          personalPacks: packs[0],
          roomPacks: packs[1],
        ),
      );
      _precacheStickerThumbnails([...packs[0], ...packs[1]]);
    } catch (e) {
      if (!mounted || widget.roomId != roomId) return;
      setState(
        () => _stickerPanelState = sticker_display.stickerPanelLoadFailed(
          state: _stickerPanelState,
          failure: e,
        ),
      );
    } finally {
      if (mounted && widget.roomId == roomId) {
        setState(
          () => _stickerPanelState = sticker_display.stickerPanelLoadFinished(
            _stickerPanelState,
          ),
        );
      }
    }
  }

  void _precacheStickerThumbnails(List<StickerPack> packs, {int limit = 60}) {
    if (!mounted || packs.isEmpty || limit <= 0) return;
    final config = AppConfigScope.of(context);
    final seen = <String>{};
    var count = 0;
    for (final pack in packs) {
      for (final sticker in pack.stickers) {
        final imageUrl = config.resolveAssetUrl(
          sticker.asset.thumbnailUrl ?? sticker.asset.url,
        );
        if (imageUrl == null || !seen.add(imageUrl)) continue;
        unawaited(
          precacheImage(NetworkImage(imageUrl), context).catchError((_) {}),
        );
        count += 1;
        if (count >= limit) return;
      }
    }
  }

  void _closePanel() {
    final patch = chatComposerPanelClosed(currentPanel: _openPanel);
    if (patch == null) return;
    setState(() => _applyComposerPanelPatch(patch));
  }

  void _togglePanel(ChatComposerPanel panel) {
    final patch = chatComposerPanelToggled(
      currentPanel: _openPanel,
      panel: panel,
    );
    setState(() => _applyComposerPanelPatch(patch));
    if (patch.shouldLoadStickers) {
      unawaited(_ensureStickerPacksLoaded());
    }
  }

  void _applyComposerPanelPatch(ChatComposerPanelPatch patch) {
    _openPanel = patch.openPanel;
  }

  void _onComposerInputSize(Size size) {
    final patch = chatComposerInputHeightMeasured(
      currentHeight: _composerInputHeight,
      measuredHeight: size.height,
    );
    if (patch == null) return;
    setState(() => _applyComposerInputHeightPatch(patch));
  }

  void _applyComposerInputHeightPatch(ChatComposerInputHeightPatch patch) {
    _composerInputHeight = patch.inputHeight;
  }

  Future<void> _showStickerContextMenu(
    TapDownDetails details,
    Sticker sticker,
  ) async {
    final action = await showMenu<_StickerContextAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        const PopupMenuItem(
          value: _StickerContextAction.saveToPersonal,
          child: Text('添加到我的表情包'),
        ),
        if (widget.canManageRoomStickers)
          const PopupMenuItem(
            value: _StickerContextAction.saveToRoom,
            child: Text('添加到房间表情包'),
          ),
        const PopupMenuItem(
          value: _StickerContextAction.saveAs,
          child: Text('另存为'),
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _StickerContextAction.saveToPersonal:
        await widget.onStickerSaveToPersonal(sticker);
        if (mounted) await _loadStickerPacks(forceReload: true);
        break;
      case _StickerContextAction.saveToRoom:
        await widget.onStickerSaveToRoom(sticker);
        if (mounted) await _loadStickerPacks(forceReload: true);
        break;
      case _StickerContextAction.saveAs:
        await widget.onStickerSaveAs(sticker);
        break;
    }
  }

  Widget _buildComposerInput() {
    final input = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            '>',
            style: TextStyle(
              color: _textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => widget.onSend(),
            cursorColor: _textSecondary,
            contextMenuBuilder: buildTextFieldContextMenu,
            decoration: const InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );

    final actions = _ComposerActionBar(
      openPanel: _openPanel,
      sending: widget.sending,
      onStickers: () => _togglePanel(ChatComposerPanel.stickers),
      onVoice: () => _togglePanel(ChatComposerPanel.voice),
      onFile: widget.sending
          ? null
          : () {
              _closePanel();
              unawaited(widget.onFileSend());
            },
      onTools: () => _togglePanel(ChatComposerPanel.tools),
      onSend: () {
        _closePanel();
        widget.onSend();
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              input,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: input),
            const SizedBox(width: 10),
            Transform.translate(offset: const Offset(0, 2), child: actions),
          ],
        );
      },
    );
  }

  Widget _buildPanel() {
    final panel = _openPanel;
    if (panel == null) return const SizedBox.shrink();

    return switch (panel) {
      ChatComposerPanel.stickers => _StickerPanel(
        source: _stickerPanelState.source,
        personalPacks: _stickerPanelState.personalPacks,
        roomPacks: _stickerPanelState.roomPacks,
        loading: _stickerPanelState.loading,
        error: _stickerPanelState.error,
        onRefresh: () => _loadStickerPacks(forceReload: true),
        onSourceChanged: (source) => setState(
          () => _stickerPanelState = sticker_display.stickerPanelSourceChanged(
            _stickerPanelState,
            source,
          ),
        ),
        onStickerSelected: (sticker) {
          _closePanel();
          unawaited(widget.onStickerSend(sticker));
        },
        onStickerContextMenu: _showStickerContextMenu,
      ),
      ChatComposerPanel.voice => const _PlaceholderPanel(text: '语音输入开发中'),
      ChatComposerPanel.file => const _PlaceholderPanel(text: '文件上传开发中'),
      ChatComposerPanel.tools => const _ToolboxPanel(),
    };
  }

  Widget _buildPanelOverlay() {
    return Positioned(
      left: 18,
      right: 18,
      bottom: _composerInputHeight + 6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 360.0
              ? constraints.maxWidth
              : 360.0;
          return Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: width,
              child: TapRegion(
                groupId: _composerTapRegionGroup,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.bottomRight,
                      children: [...previousChildren, ?currentChild],
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_openPanel),
                    child: _buildPanel(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDarkLow,
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: widget.messages.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有消息',
                          style: TextStyle(color: _textMuted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                        itemCount: widget.messages.length,
                        itemBuilder: (context, index) {
                          final message = widget.messages[index];
                          return _MessageBubble(
                            message: message,
                            mine: message.sender.id == widget.currentUserId,
                            fileTransfer:
                                widget.fileTransfers[message.clientMessageId],
                            fileDownloads: widget.fileDownloads,
                            onFilePause: () =>
                                widget.onFilePause(message.clientMessageId),
                            onFileResume: () =>
                                widget.onFileResume(message.clientMessageId),
                            onFileCancel: () =>
                                widget.onFileCancel(message.clientMessageId),
                            onFileDownload: widget.onFileDownload,
                            onFileDownloadPause: widget.onFileDownloadPause,
                            onFileDownloadResume: widget.onFileDownloadResume,
                            onFileDownloadCancel: widget.onFileDownloadCancel,
                            onOpenUserInfo: () =>
                                widget.onOpenUserInfo(message.sender),
                            onStickerContextMenu: _showStickerContextMenu,
                          );
                        },
                      ),
              ),
              TapRegion(
                groupId: _composerTapRegionGroup,
                onTapOutside: (_) => _closePanel(),
                child: _SizeReporter(
                  onChange: _onComposerInputSize,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                    color: _primaryDarkLow,
                    child: _buildComposerInput(),
                  ),
                ),
              ),
            ],
          ),
          if (_openPanel != null) _buildPanelOverlay(),
        ],
      ),
    );
  }
}

class _SizeReporter extends StatefulWidget {
  const _SizeReporter({required this.child, required this.onChange});

  final Widget child;
  final ValueChanged<Size> onChange;

  @override
  State<_SizeReporter> createState() => _SizeReporterState();
}

class _SizeReporterState extends State<_SizeReporter> {
  Size? _lastSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportSize());
    return widget.child;
  }

  void _reportSize() {
    if (!mounted) return;
    final size = context.size;
    if (size == null || size == _lastSize) return;
    _lastSize = size;
    widget.onChange(size);
  }
}

class _ComposerActionBar extends StatelessWidget {
  const _ComposerActionBar({
    required this.openPanel,
    required this.sending,
    required this.onStickers,
    required this.onVoice,
    required this.onFile,
    required this.onTools,
    required this.onSend,
  });

  final ChatComposerPanel? openPanel;
  final bool sending;
  final VoidCallback onStickers;
  final VoidCallback? onVoice;
  final VoidCallback? onFile;
  final VoidCallback onTools;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ButtonIcon(
          tooltip: '表情包',
          onPressed: onStickers,
          selected: openPanel == ChatComposerPanel.stickers,
          icon: const Icon(Icons.emoji_emotions_outlined),
        ),
        const SizedBox(width: 8),
        ButtonIcon(
          tooltip: '语音',
          onPressed: onVoice,
          icon: const Icon(Icons.mic_none),
        ),
        const SizedBox(width: 8),
        ButtonIcon(
          tooltip: '文件上传',
          onPressed: onFile,
          icon: const Icon(Icons.attach_file),
        ),
        const SizedBox(width: 8),
        ButtonIcon(
          tooltip: '工具箱',
          onPressed: onTools,
          selected: openPanel == ChatComposerPanel.tools,
          icon: const Icon(Icons.extension_outlined),
        ),
        const SizedBox(width: 8),
        ButtonIcon(
          tooltip: '发送',
          onPressed: sending ? null : onSend,
          loading: sending,
          tone: ButtonTone.primary,
          icon: sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _cyan,
                  ),
                )
              : const Icon(Icons.send_rounded),
          size: 44,
        ),
      ],
    );
  }
}

class _StickerPanel extends StatelessWidget {
  const _StickerPanel({
    required this.source,
    required this.personalPacks,
    required this.roomPacks,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onSourceChanged,
    required this.onStickerSelected,
    required this.onStickerContextMenu,
  });

  final sticker_display.StickerPanelSource source;
  final List<StickerPack> personalPacks;
  final List<StickerPack> roomPacks;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<sticker_display.StickerPanelSource> onSourceChanged;
  final ValueChanged<Sticker> onStickerSelected;
  final Future<void> Function(TapDownDetails details, Sticker sticker)
  onStickerContextMenu;

  @override
  Widget build(BuildContext context) {
    final stickers = sticker_display.stickerPanelStickers(
      source: source,
      personalPacks: personalPacks,
      roomPacks: roomPacks,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: _buildBody(stickers),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: SegmentedControl<sticker_display.StickerPanelSource>(
            value: source,
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
        ),
      ],
    );
  }

  Widget _buildBody(List<Sticker> stickers) {
    final bodyState = sticker_display.stickerPanelBodyState(
      loading: loading,
      error: error,
      stickers: stickers,
    );
    return switch (bodyState) {
      sticker_display.StickerPanelBodyState.loading => const SizedBox(
        height: 78,
        child: Center(child: CircularProgressIndicator(color: _cyan)),
      ),
      sticker_display.StickerPanelBodyState.error => _StickerPanelMessage(
        text: error ?? '',
        icon: Icons.warning_amber,
        onRefresh: onRefresh,
      ),
      sticker_display.StickerPanelBodyState.empty => _StickerPanelMessage(
        text: sticker_display.stickerPanelEmptyText(source),
        icon: Icons.emoji_emotions_outlined,
        onRefresh: onRefresh,
      ),
      sticker_display.StickerPanelBodyState.results => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final sticker in stickers)
            _StickerButton(
              sticker: sticker,
              onPressed: () => onStickerSelected(sticker),
              onSecondaryTapDown: (details) =>
                  onStickerContextMenu(details, sticker),
            ),
        ],
      ),
    };
  }
}

class _ToolboxPanel extends StatelessWidget {
  const _ToolboxPanel();

  static const double buttonSize = 46;
  static const double spacing = 10;

  static const _items = [
    _ToolboxItem(
      icon: Icons.music_note,
      tooltip: '音乐盒',
      backgroundColor: Color(0xFF1F2D27),
      borderColor: Color(0xFF355C49),
      foregroundColor: Color(0xFF6FCFA6),
    ),
    _ToolboxItem(
      icon: Icons.poll_outlined,
      tooltip: '投票',
      backgroundColor: Color(0xFF2B2739),
      borderColor: Color(0xFF594D78),
      foregroundColor: Color(0xFFB8A3FF),
    ),
    _ToolboxItem(
      icon: Icons.bolt_outlined,
      tooltip: '快捷指令',
      backgroundColor: Color(0xFF33291C),
      borderColor: Color(0xFF6D5630),
      foregroundColor: Color(0xFFD4B675),
    ),
    _ToolboxItem(
      icon: Icons.add_box_outlined,
      tooltip: '后续扩展',
      backgroundColor: Color(0xFF2E1F22),
      borderColor: Color(0xFF6B3E45),
      foregroundColor: Color(0xFFE58383),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final item in _items)
            _ToolboxButton(
              icon: item.icon,
              tooltip: item.tooltip,
              backgroundColor: item.backgroundColor,
              borderColor: item.borderColor,
              foregroundColor: item.foregroundColor,
            ),
        ],
      ),
    );
  }
}

class _PlaceholderPanel extends StatelessWidget {
  const _PlaceholderPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: _textMuted, fontSize: 13),
        ),
      ),
    );
  }
}

class _ToolboxItem {
  const _ToolboxItem({
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;
}

class _StickerButton extends StatelessWidget {
  const _StickerButton({
    required this.sticker,
    required this.onPressed,
    required this.onSecondaryTapDown,
  });

  final Sticker sticker;
  final VoidCallback onPressed;
  final GestureTapDownCallback onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final imageUrl = AppConfigScope.of(
      context,
    ).resolveAssetUrl(sticker.asset.thumbnailUrl ?? sticker.asset.url);
    final fallback = Icon(
      Icons.image_not_supported_outlined,
      color: _textMuted,
      size: 22,
    );
    return Tooltip(
      message: sticker.name,
      child: GestureDetector(
        onSecondaryTapDown: onSecondaryTapDown,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 46,
              width: 52,
              child: Center(
                child: SizedBox.square(
                  dimension: 32,
                  child: imageUrl == null
                      ? fallback
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => fallback,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerPanelMessage extends StatelessWidget {
  const _StickerPanelMessage({
    required this.text,
    required this.icon,
    required this.onRefresh,
  });

  final String text;
  final IconData icon;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Row(
        children: [
          Icon(icon, color: _textMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          ButtonIcon(
            tooltip: '刷新表情包',
            onPressed: () => unawaited(onRefresh()),
            icon: const Icon(Icons.refresh),
            size: 32,
            backgroundColor: _primaryDarkRaised,
            borderColor: _primaryDarkRaised,
          ),
        ],
      ),
    );
  }
}

class _BubbleIconAction extends StatelessWidget {
  const _BubbleIconAction({
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
    required this.onPressed,
    this.size = 50,
  });

  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: PressableSurface(
        tooltip: tooltip,
        onPressed: onPressed,
        height: size,
        padding: EdgeInsets.zero,
        backgroundColor: backgroundColor,
        selectedBackgroundColor: backgroundColor,
        pressedBackgroundColor: backgroundColor,
        borderColor: borderColor,
        selectedBorderColor: borderColor,
        child: Center(
          child: Icon(icon, color: foregroundColor, size: size * 0.42),
        ),
      ),
    );
  }
}

class _ToolboxButton extends StatelessWidget {
  const _ToolboxButton({
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return _BubbleIconAction(
      icon: icon,
      tooltip: tooltip,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      foregroundColor: foregroundColor,
      onPressed: () {},
      size: _ToolboxPanel.buttonSize,
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.fileTransfer,
    required this.fileDownloads,
    required this.onFilePause,
    required this.onFileResume,
    required this.onFileCancel,
    required this.onFileDownload,
    required this.onFileDownloadPause,
    required this.onFileDownloadResume,
    required this.onFileDownloadCancel,
    required this.onOpenUserInfo,
    required this.onStickerContextMenu,
  });

  final Message message;
  final bool mine;
  final FileTransferState? fileTransfer;
  final Map<String, FileTransferState> fileDownloads;
  final VoidCallback onFilePause;
  final VoidCallback onFileResume;
  final VoidCallback onFileCancel;
  final Future<void> Function({
    required String downloadKey,
    required MessageAttachment attachment,
    required String url,
  })
  onFileDownload;
  final ValueChanged<String> onFileDownloadPause;
  final ValueChanged<String> onFileDownloadResume;
  final ValueChanged<String> onFileDownloadCancel;
  final VoidCallback onOpenUserInfo;
  final Future<void> Function(TapDownDetails details, Sticker sticker)
  onStickerContextMenu;

  @override
  Widget build(BuildContext context) {
    final sticker = message.stickerAttachment;
    final files = message.fileAttachments.toList();
    final contentKind = message_display.messageContentKind(message);
    final deliveryStatus = fileTransfer == null
        ? message_display.messageDeliveryStatusText(message)
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _borderColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _UserInfoTapTarget(
                tooltip: '查看用户信息',
                onTap: onOpenUserInfo,
                child: _Avatar(
                  label: message.sender.displayName,
                  imageUrl: AppConfigScope.of(
                    context,
                  ).resolveAssetUrl(message.sender.avatarUrl),
                  defaultAvatarKey: message.sender.defaultAvatarKey,
                  size: 32,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _UserInfoTapTarget(
                            tooltip: '查看用户信息',
                            onTap: onOpenUserInfo,
                            child: Text(
                              mine ? 'You' : message.sender.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: message.failed
                                    ? _danger
                                    : mine
                                    ? _cyan
                                    : _textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          message_display.formatMessageTime(message.createdAt),
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (contentKind ==
                        message_display.MessageContentKind.sticker)
                      _StickerMessageImage(
                        message: message,
                        sticker: sticker!,
                        onContextMenu: onStickerContextMenu,
                      ),
                    if (contentKind == message_display.MessageContentKind.files)
                      _FileAttachmentList(
                        message: message,
                        attachments: files,
                        transfer: fileTransfer,
                        downloads: fileDownloads,
                        onPause: onFilePause,
                        onResume: onFileResume,
                        onCancel: onFileCancel,
                        onDownload: onFileDownload,
                        onDownloadPause: onFileDownloadPause,
                        onDownloadResume: onFileDownloadResume,
                        onDownloadCancel: onFileDownloadCancel,
                      ),
                    if (contentKind == message_display.MessageContentKind.text)
                      _MessageText(text: message.body),
                    if (deliveryStatus != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        deliveryStatus,
                        style: TextStyle(
                          color: message.failed ? _danger : _textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
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

class _MessageText extends StatelessWidget {
  const _MessageText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      text,
      cursorColor: _cyan,
      selectionColor: _cyan.withValues(alpha: 0.28),
      style: const TextStyle(color: _textPrimary, fontSize: 15, height: 1.4),
    );
  }
}

class _UserInfoTapTarget extends StatelessWidget {
  const _UserInfoTapTarget({
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

class _FileAttachmentList extends StatelessWidget {
  const _FileAttachmentList({
    required this.message,
    required this.attachments,
    required this.transfer,
    required this.downloads,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onDownload,
    required this.onDownloadPause,
    required this.onDownloadResume,
    required this.onDownloadCancel,
  });

  final Message message;
  final List<MessageAttachment> attachments;
  final FileTransferState? transfer;
  final Map<String, FileTransferState> downloads;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final Future<void> Function({
    required String downloadKey,
    required MessageAttachment attachment,
    required String url,
  })
  onDownload;
  final ValueChanged<String> onDownloadPause;
  final ValueChanged<String> onDownloadResume;
  final ValueChanged<String> onDownloadCancel;

  @override
  Widget build(BuildContext context) {
    final showBody = message_display.shouldShowFileAttachmentBody(
      body: message.body,
      attachments: attachments,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBody) ...[
          _MessageText(text: message.body),
          const SizedBox(height: 8),
        ],
        for (final entry in attachments.asMap().entries) ...[
          if (entry.key > 0) const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final transferSlot = file_display.fileAttachmentTransferSlot(
                message: message,
                attachment: entry.value,
                index: entry.key,
                uploadTransfer: transfer,
                downloads: downloads,
              );

              return _FileAttachmentCard(
                attachment: entry.value,
                transfer: transferSlot.transfer,
                onDownload: ({required attachment, required url}) => onDownload(
                  downloadKey: transferSlot.downloadKey,
                  attachment: attachment,
                  url: url,
                ),
                onPause: transferSlot.usesUploadTransfer
                    ? onPause
                    : () => onDownloadPause(transferSlot.downloadKey),
                onResume: transferSlot.usesUploadTransfer
                    ? onResume
                    : () => onDownloadResume(transferSlot.downloadKey),
                onCancel: transferSlot.usesUploadTransfer
                    ? onCancel
                    : () => onDownloadCancel(transferSlot.downloadKey),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _FileAttachmentCard extends StatelessWidget {
  const _FileAttachmentCard({
    required this.attachment,
    required this.transfer,
    required this.onDownload,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final MessageAttachment attachment;
  final FileTransferState? transfer;
  final Future<void> Function({
    required MessageAttachment attachment,
    required String url,
  })
  onDownload;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final asset = attachment.asset;
    final transfer = this.transfer;
    final config = AppConfigScope.of(context);
    final url = config.resolveAssetUrl(asset?.url);
    final title = file_display.fileAttachmentTitle(attachment);
    final meta = file_display.fileAttachmentMeta(asset);
    final previewUrl = config.resolveAssetUrl(
      file_display.fileAttachmentPreviewPath(asset),
    );
    final interaction = file_display.fileAttachmentInteractionState(
      title: title,
      url: url,
      transfer: transfer,
    );
    final downloadUrl = interaction.canDownload ? url : null;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Tooltip(
        message: interaction.tooltip,
        child: MouseRegion(
          cursor: downloadUrl != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: downloadUrl != null
                ? () => unawaited(
                    onDownload(attachment: attachment, url: downloadUrl),
                  )
                : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _primaryDarkRaised,
                border: Border.all(color: _borderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _FileAttachmentIcon(
                          asset: asset,
                          previewUrl: previewUrl,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                              ),
                              if (meta.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FileAttachmentTrailing(
                          transfer: transfer,
                          canDownload: interaction.canDownload,
                          onPause: onPause,
                          onResume: onResume,
                          onCancel: onCancel,
                        ),
                      ],
                    ),
                    if (transfer != null) ...[
                      const SizedBox(height: 10),
                      _FileTransferProgress(transfer: transfer),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileAttachmentTrailing extends StatelessWidget {
  const _FileAttachmentTrailing({
    required this.transfer,
    required this.canDownload,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final FileTransferState? transfer;
  final bool canDownload;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final transfer = this.transfer;
    final state = file_display.fileAttachmentTrailingState(
      transfer: transfer,
      canDownload: canDownload,
    );
    switch (state.kind) {
      case file_display.FileAttachmentTrailingKind.sending:
        return const SizedBox.square(
          dimension: 30,
          child: Center(
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(color: _cyan, strokeWidth: 2),
            ),
          ),
        );
      case file_display.FileAttachmentTrailingKind.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _danger, size: 20),
            if (state.showDismiss) ...[
              const SizedBox(width: 6),
              _InlineIconButton(
                tooltip: 'Dismiss download',
                icon: Icons.close,
                onPressed: onCancel,
                danger: true,
              ),
            ],
          ],
        );
      case file_display.FileAttachmentTrailingKind.activeTransfer:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _InlineIconButton(
              tooltip: state.pauseResumeTooltip!,
              icon: state.pauseResumeIsResume ? Icons.play_arrow : Icons.pause,
              onPressed: state.pauseResumeIsResume ? onResume : onPause,
            ),
            const SizedBox(width: 6),
            _InlineIconButton(
              tooltip: state.cancelTooltip!,
              icon: Icons.close,
              onPressed: onCancel,
              danger: true,
            ),
          ],
        );
      case file_display.FileAttachmentTrailingKind.placeholder:
        return const Icon(Icons.insert_drive_file_outlined, color: _textMuted);
      case file_display.FileAttachmentTrailingKind.download:
        return const Icon(Icons.download_outlined, color: _textMuted, size: 20);
    }
  }
}

class _FileTransferProgress extends StatelessWidget {
  const _FileTransferProgress({required this.transfer});

  final FileTransferState transfer;

  @override
  Widget build(BuildContext context) {
    final progress = file_display.fileTransferProgressState(transfer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 4,
            value: progress.value,
            backgroundColor: _borderColor,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress.failed ? _danger : _cyan,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          progress.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: progress.failed ? _danger : _textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _InlineIconButton extends StatelessWidget {
  const _InlineIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? _danger : _cyan;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: danger ? const Color(0xFF2E1F22) : const Color(0xFF1F2D27),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: danger ? const Color(0xFF6B3E45) : const Color(0xFF355C49),
            ),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

class _FileAttachmentIcon extends StatelessWidget {
  const _FileAttachmentIcon({required this.asset, required this.previewUrl});

  final UploadedAsset? asset;
  final String? previewUrl;

  @override
  Widget build(BuildContext context) {
    final previewUrl = this.previewUrl;
    if (previewUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox.square(
          dimension: 42,
          child: Image.network(
            previewUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallbackIcon(),
          ),
        ),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: _selectedSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF355C49)),
      ),
      child: Icon(fileIconForMime(asset?.mimeType), color: _cyan, size: 22),
    );
  }
}

class _StickerMessageImage extends StatelessWidget {
  const _StickerMessageImage({
    required this.message,
    required this.sticker,
    required this.onContextMenu,
  });

  final Message message;
  final MessageAttachment sticker;
  final Future<void> Function(TapDownDetails details, Sticker sticker)
  onContextMenu;

  @override
  Widget build(BuildContext context) {
    final asset = sticker.asset;
    final imageUrl = AppConfigScope.of(
      context,
    ).resolveAssetUrl(asset?.url ?? asset?.thumbnailUrl);
    if (imageUrl == null) return _MessageText(text: message.body);

    final label = sticker.name ?? message.body;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          final stickerModel = _stickerFromAttachment(sticker, label);
          if (stickerModel == null) return;
          unawaited(onContextMenu(details, stickerModel));
        },
        child: Semantics(
          image: true,
          label: label,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 168, maxHeight: 168),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const SizedBox.square(
                    dimension: 72,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          color: _cyan,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  );
                },
                errorBuilder: (_, _, _) => _MessageText(text: message.body),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
