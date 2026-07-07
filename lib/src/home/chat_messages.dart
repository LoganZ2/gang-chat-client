part of 'chat_pane.dart';

/// How close (in logical pixels) to the newest message counts as "at bottom"
/// for saved scroll anchors and the jump-to-latest affordance.
const double _autoScrollFollowThreshold = 120;
const double _chatMessageListTopPadding = 18;
const _messageListCacheExtent = ScrollCacheExtent.pixels(1200);

/// A remembered scroll position for one room's message list. The list widget is
/// torn down and rebuilt whenever the pane swaps (e.g. opening the live
/// channel and coming back), so we stash the last position here keyed by room
/// id and restore it on the next mount instead of snapping to the bottom.
class _ScrollAnchor {
  const _ScrollAnchor({required this.offset, required this.atBottom});

  final double offset;
  final bool atBottom;
}

class _ViewportAnchor {
  const _ViewportAnchor({required this.clientMessageId, required this.top});

  final String clientMessageId;
  final double top;
}

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

class ChatMessageActions {
  const ChatMessageActions({
    required this.onCopy,
    required this.onDeleteForMe,
    required this.onRecall,
    required this.canRecall,
    this.onReeditRecalledText = _syncNoop,
    this.canReeditRecalledText = _neverCanRecall,
    this.canInspectRecalledText = _neverCanRecall,
  });

  const ChatMessageActions.disabled()
    : onCopy = _noop,
      onDeleteForMe = _noop,
      onRecall = _noop,
      canRecall = _neverCanRecall,
      onReeditRecalledText = _syncNoop,
      canReeditRecalledText = _neverCanRecall,
      canInspectRecalledText = _neverCanRecall;

  final Future<void> Function(BuildContext context, Message message) onCopy;
  final Future<void> Function(BuildContext context, Message message)
  onDeleteForMe;
  final Future<void> Function(BuildContext context, Message message) onRecall;
  final bool Function(Message message) canRecall;
  final void Function(Message message) onReeditRecalledText;
  final bool Function(Message message) canReeditRecalledText;
  final bool Function(Message message) canInspectRecalledText;

  static Future<void> _noop(BuildContext context, Message message) async {}
  static void _syncNoop(Message message) {}

  static bool _neverCanRecall(Message message) => false;
}

class _MessageStage extends StatefulWidget {
  const _MessageStage({
    super.key,
    required this.roomId,
    required this.currentUser,
    required this.ownerUserId,
    required this.roomReady,
    required this.loading,
    required this.error,
    required this.messages,
    required this.newMessageCount,
    required this.fileTransfers,
    required this.fileDownloads,
    required this.live,
    required this.downloadActions,
    required this.voicePlaybackActions,
    required this.imagePreviewActions,
    required this.messageActions,
    required this.onRetry,
    required this.onViewedNewMessages,
    required this.bottomInset,
    this.onResolveSenderProfile,
    this.onResolveRoomProfile,
    this.onEnterProfileRoom,
    this.senderProfileActionBuilder,
  });

  final String? roomId;
  final CurrentUser currentUser;
  final String? ownerUserId;
  final bool roomReady;
  final bool loading;
  final String? error;
  final List<Message> messages;
  final int newMessageCount;
  final Map<String, FileTransferState> fileTransfers;
  final Map<String, FileTransferState> fileDownloads;
  final LiveState? live;
  final ChatFileDownloadActions downloadActions;
  final ChatVoicePlaybackActions voicePlaybackActions;
  final ChatImagePreviewActions imagePreviewActions;
  final ChatMessageActions messageActions;
  final VoidCallback onRetry;
  final VoidCallback onViewedNewMessages;
  // Breathing room at the bottom of the list, between the last message and the
  // composer row that now sits below it.
  final double bottomInset;
  final Future<UserSummary> Function(UserSummary sender)?
  onResolveSenderProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterProfileRoom;
  final UserProfileActionBuilder? senderProfileActionBuilder;

  @override
  State<_MessageStage> createState() => _MessageStageState();
}

class _MessageStageState extends State<_MessageStage> {
  // Last known scroll position per room, surviving widget teardown when the
  // pane swaps (live channel, settings, etc.). Static so it outlives the State.
  static final Map<String, _ScrollAnchor> _scrollAnchors = {};

  bool _showDetailedTimestamps = false;
  bool _showLatestButton = false;
  bool _showNewMessageJumpButton = false;
  bool _newMessageJumpDismissed = false;
  String? _retainedNewMessageClientId;
  int _retainedNewMessageLabelCount = 0;
  late final ScrollController _scrollController;
  final GlobalKey _messageListKey = GlobalKey();
  final GlobalKey _oldestMessageKey = GlobalKey();
  final GlobalKey _firstNewMessageKey = GlobalKey();
  final Map<String, GlobalKey> _messageRowKeys = {};
  double _underflowBottomSpacer = 0;
  bool _underflowAlignmentScheduled = false;
  bool _newMessageJumpVisibilityScheduled = false;
  bool _messageListReady = false;
  bool _incomingUnreadWaitingForUserScroll = false;
  bool _restoringIncomingViewport = false;
  // Guards queued scroll requests so overlapping requests don't stack up; the newest
  // request wins by bumping this token.
  int _scrollToBottomToken = 0;

  @override
  void initState() {
    super.initState();
    _captureNewMessageAnchorFromWidget();
    // Seed the controller with the remembered offset so the very first layout
    // lands in place — restoring via a post-frame jump would render one frame
    // pinned to the latest message first, which reads as a flash.
    final anchor = _anchorForRoom(widget.roomId);
    final restoring = anchor != null && !anchor.atBottom;
    _scrollController = ScrollController(
      initialScrollOffset: restoring ? anchor.offset : 0,
    );
    _scrollController.addListener(_handleScrollChanged);
    // If we're not restoring a browsed-history position, land at the newest
    // message when the room first opens.
    if (!restoring) {
      _scrollToBottom(animated: false);
    }
  }

  @override
  void didUpdateWidget(covariant _MessageStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _showDetailedTimestamps = false;
      _showLatestButton = false;
      _showNewMessageJumpButton = false;
      _newMessageJumpDismissed = false;
      _incomingUnreadWaitingForUserScroll = false;
      _restoringIncomingViewport = false;
      _clearRetainedNewMessageAnchor();
      _captureNewMessageAnchorFromWidget();
      _messageRowKeys.clear();
      _underflowBottomSpacer = 0;
      _messageListReady = false;
      // New room: restore its remembered position, or snap to latest.
      final anchor = _anchorForRoom(widget.roomId);
      if (anchor != null && !anchor.atBottom) {
        _restoreScroll(anchor.offset);
      } else {
        _scrollToBottom(animated: false);
      }
      return;
    }
    final addedMessages = _addedMessagesSince(oldWidget);
    final preserveIncomingViewport = _shouldPreserveViewportForIncoming(
      addedMessages,
    );
    final viewportAnchor = preserveIncomingViewport
        ? _captureViewportAnchorFrom(oldWidget.messages)
        : null;

    if (oldWidget.newMessageCount != widget.newMessageCount) {
      _showNewMessageJumpButton = false;
      if (widget.newMessageCount > 0) {
        _newMessageJumpDismissed = false;
        _captureNewMessageAnchorFromWidget();
      } else {
        _incomingUnreadWaitingForUserScroll = false;
      }
    }
    if (oldWidget.messages.length != widget.messages.length ||
        (oldWidget.messages.isNotEmpty &&
            widget.messages.isNotEmpty &&
            oldWidget.messages.last.clientMessageId !=
                widget.messages.last.clientMessageId)) {
      _underflowBottomSpacer = 0;
      _showNewMessageJumpButton = false;
      if (widget.newMessageCount > 0) {
        _newMessageJumpDismissed = false;
        _captureNewMessageAnchorFromWidget();
      }
    }
    if (_shouldFollowToBottom(oldWidget, addedMessages)) {
      _scrollToBottom(animated: true);
    } else if (viewportAnchor != null) {
      _incomingUnreadWaitingForUserScroll =
          _scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0;
      _restoreViewportAnchorAfterIncoming(viewportAnchor);
    }
  }

  @override
  void dispose() {
    _rememberScrollPosition();
    _scrollController.removeListener(_handleScrollChanged);
    _scrollController.dispose();
    super.dispose();
  }

  _ScrollAnchor? _anchorForRoom(String? roomId) {
    if (roomId == null) return null;
    return _scrollAnchors[roomId];
  }

  // Records the live scroll offset (and whether it's pinned to the latest
  // message) so a later remount can restore it. The list is reversed, so the
  // newest message sits at the minimum scroll extent — "at bottom" means the
  // offset is within the follow threshold of it. Called on every scroll and on
  // dispose.
  void _rememberScrollPosition() {
    final roomId = widget.roomId;
    if (roomId == null || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    _scrollAnchors[roomId] = _ScrollAnchor(
      offset: position.pixels,
      atBottom: _distanceFromBottom() <= _autoScrollFollowThreshold,
    );
  }

  // Restores a remembered offset once the list has laid out, clamped to the
  // current scroll extent in case the content shrank while we were away.
  void _restoreScroll(double offset) {
    final token = ++_scrollToBottomToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _scrollToBottomToken ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      _scrollController.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
    });
  }

  List<Message> _addedMessagesSince(_MessageStage oldWidget) {
    if (widget.messages.isEmpty) return const [];
    final grew = widget.messages.length > oldWidget.messages.length;
    final lastChanged =
        oldWidget.messages.isNotEmpty &&
        widget.messages.isNotEmpty &&
        oldWidget.messages.last.clientMessageId !=
            widget.messages.last.clientMessageId;
    if (!grew && !lastChanged) return const [];
    final oldClientMessageIds = {
      for (final message in oldWidget.messages) message.clientMessageId,
    };
    return [
      for (final message in widget.messages)
        if (!oldClientMessageIds.contains(message.clientMessageId)) message,
    ];
  }

  bool _shouldPreserveViewportForIncoming(List<Message> addedMessages) {
    if (widget.newMessageCount <= 0 || addedMessages.isEmpty) return false;
    return addedMessages.any(
      (message) => message.sender.id != widget.currentUser.id,
    );
  }

  // Decides whether an update introduced a new message worth following. We
  // always chase our own outgoing messages; messages from others remain unread
  // until the divider actually enters the viewport.
  bool _shouldFollowToBottom(
    _MessageStage oldWidget,
    List<Message> addedMessages,
  ) {
    final messages = widget.messages;
    if (messages.isEmpty) return false;
    if (addedMessages.isNotEmpty) {
      return addedMessages.last.sender.id == widget.currentUser.id;
    }
    final lastChanged =
        oldWidget.messages.isNotEmpty &&
        messages.last.clientMessageId !=
            oldWidget.messages.last.clientMessageId;
    if (!lastChanged) return false;
    if (messages.last.sender.id == widget.currentUser.id) return true;
    return false;
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _distanceFromBottom() <= _autoScrollFollowThreshold;
  }

  double _distanceFromBottom() {
    final position = _scrollController.position;
    return math.max(0, position.pixels - position.minScrollExtent);
  }

  bool _userInLive(String userId) {
    return live_display.liveParticipantByUserId(widget.live, userId) != null;
  }

  void _handleScrollChanged() {
    if (_incomingUnreadWaitingForUserScroll && !_restoringIncomingViewport) {
      _incomingUnreadWaitingForUserScroll = false;
    }
    _rememberScrollPosition();
    _syncLatestButtonVisibility();
    _scheduleNewMessageJumpVisibilitySync();
  }

  void _syncLatestButtonVisibility() {
    if (!_scrollController.hasClients) return;
    final next = !_isNearBottom();
    if (next == _showLatestButton) return;
    setState(() => _showLatestButton = next);
  }

  void _captureNewMessageAnchorFromWidget() {
    final count = _effectiveWidgetNewMessageCount;
    if (count <= 0) return;
    final index = widget.messages.length - count;
    if (index < 0 || index >= widget.messages.length) return;
    _retainedNewMessageClientId = widget.messages[index].clientMessageId;
    _retainedNewMessageLabelCount = _newMessageLabelCountFromWidget;
  }

  void _clearRetainedNewMessageAnchor() {
    _retainedNewMessageClientId = null;
    _retainedNewMessageLabelCount = 0;
  }

  void _scheduleUnderflowAlignment() {
    if (_underflowAlignmentScheduled) return;
    _underflowAlignmentScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _underflowAlignmentScheduled = false;
      if (!mounted) return;
      final listBox =
          _messageListKey.currentContext?.findRenderObject() as RenderBox?;
      final oldestBox =
          _oldestMessageKey.currentContext?.findRenderObject() as RenderBox?;
      if (listBox == null) return;
      if (oldestBox == null) {
        if (_underflowBottomSpacer > 0 || !_messageListReady) {
          setState(() {
            _underflowBottomSpacer = 0;
            _messageListReady = true;
          });
        }
        return;
      }

      final listTop = listBox.localToGlobal(Offset.zero).dy;
      final oldestTop = oldestBox.localToGlobal(Offset.zero).dy;
      final targetTop = listTop + _chatMessageListTopPadding;
      final delta = oldestTop - targetTop;
      final nextSpacer = math.max(0.0, _underflowBottomSpacer + delta);
      final spacerChanged = (nextSpacer - _underflowBottomSpacer).abs() >= 0.5;
      if (!spacerChanged && _messageListReady) return;
      setState(() {
        if (spacerChanged) _underflowBottomSpacer = nextSpacer;
        _messageListReady = true;
      });
    });
  }

  void _scheduleNewMessageJumpVisibilitySync() {
    if (_newMessageJumpVisibilityScheduled) return;
    _newMessageJumpVisibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _newMessageJumpVisibilityScheduled = false;
      if (!mounted) return;
      if (_firstNewMessageIsVisible() && !_newMessageJumpDismissed) {
        if (!_incomingUnreadWaitingForUserScroll) {
          _markNewMessagesViewed();
        }
        return;
      }
      final next = _shouldShowNewMessageJumpButton();
      if (next == _showNewMessageJumpButton) return;
      setState(() => _showNewMessageJumpButton = next);
    });
  }

  bool _shouldShowNewMessageJumpButton() {
    if (_firstNewMessageIndex == null || _newMessageJumpDismissed) {
      return false;
    }
    if (!_messageListReady || !_scrollController.hasClients) return false;
    final listBox =
        _messageListKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null || !listBox.hasSize) return false;
    final anchorBox =
        _firstNewMessageKey.currentContext?.findRenderObject() as RenderBox?;
    if (anchorBox == null || !anchorBox.hasSize) {
      // If the first-new anchor is not in the sliver cache, it is above the
      // visible window and needs the one-shot jump affordance.
      return true;
    }
    final listTop = listBox.localToGlobal(Offset.zero).dy;
    final anchorTop = anchorBox.localToGlobal(Offset.zero).dy;
    return anchorTop < listTop + 1;
  }

  bool _firstNewMessageAnchorIsVisible() {
    if (_firstNewMessageIndex == null) return false;
    final anchorBox =
        _firstNewMessageKey.currentContext?.findRenderObject() as RenderBox?;
    return _renderBoxIntersectsMessageList(anchorBox);
  }

  bool _firstNewMessageIsVisible() {
    if (_firstNewMessageAnchorIsVisible()) return true;
    final firstIndex = _firstNewMessageIndex;
    if (firstIndex == null ||
        firstIndex < 0 ||
        firstIndex >= widget.messages.length) {
      return false;
    }
    final message = widget.messages[firstIndex];
    final rowBox =
        _messageRowKeys[message.clientMessageId]?.currentContext
                ?.findRenderObject()
            as RenderBox?;
    return _renderBoxIntersectsMessageList(rowBox);
  }

  bool _renderBoxIntersectsMessageList(RenderBox? box) {
    final listBox =
        _messageListKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null || box == null || !listBox.hasSize || !box.hasSize) {
      return false;
    }
    final listTop = listBox.localToGlobal(Offset.zero).dy;
    final listBottom = listTop + listBox.size.height;
    final boxTop = box.localToGlobal(Offset.zero).dy;
    final boxBottom = boxTop + box.size.height;
    return boxBottom >= listTop && boxTop <= listBottom;
  }

  // The list is reversed, so the latest message lives at the minimum scroll
  // extent. New rooms can render directly at the final bottom position instead
  // of painting history first and jumping on the next frame.
  void _scrollToBottom({required bool animated}) {
    final token = ++_scrollToBottomToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _scrollToBottomToken ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final target = position.minScrollExtent;
      if ((position.pixels - target).abs() < 1) {
        _syncLatestButtonVisibility();
        return;
      }
      if (animated) {
        unawaited(
          _scrollController
              .animateTo(
                target,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
              )
              .whenComplete(() {
                if (mounted) _syncLatestButtonVisibility();
              }),
        );
        return;
      }
      _scrollController.jumpTo(target);
      _syncLatestButtonVisibility();
    });
  }

  GlobalKey _messageRowKey(String clientMessageId) {
    return _messageRowKeys.putIfAbsent(clientMessageId, GlobalKey.new);
  }

  void _trimMessageRowKeys() {
    final activeIds = {
      for (final message in widget.messages) message.clientMessageId,
    };
    _messageRowKeys.removeWhere(
      (id, key) => !activeIds.contains(id) || key.currentContext == null,
    );
  }

  _ViewportAnchor? _captureViewportAnchorFrom(List<Message> messages) {
    final listBox =
        _messageListKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null || !listBox.hasSize) return null;
    final listTop = listBox.localToGlobal(Offset.zero).dy;
    final listBottom = listTop + listBox.size.height;
    for (final message in messages.reversed) {
      final box =
          _messageRowKeys[message.clientMessageId]?.currentContext
                  ?.findRenderObject()
              as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom >= listTop && top <= listBottom) {
        return _ViewportAnchor(
          clientMessageId: message.clientMessageId,
          top: top,
        );
      }
    }
    return null;
  }

  void _restoreViewportAnchorAfterIncoming(_ViewportAnchor anchor) {
    final token = ++_scrollToBottomToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _scrollToBottomToken ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final anchorBox =
          _messageRowKeys[anchor.clientMessageId]?.currentContext
                  ?.findRenderObject()
              as RenderBox?;
      final listBox =
          _messageListKey.currentContext?.findRenderObject() as RenderBox?;
      if (anchorBox != null &&
          anchorBox.hasSize &&
          listBox != null &&
          listBox.hasSize) {
        final viewport = RenderAbstractViewport.of(anchorBox);
        final listTop = listBox.localToGlobal(Offset.zero).dy;
        final desiredTopInList = (anchor.top - listTop).clamp(
          0.0,
          listBox.size.height,
        );
        final alignment = listBox.size.height <= 0
            ? 0.0
            : desiredTopInList / listBox.size.height;
        final target = viewport
            .getOffsetToReveal(anchorBox, alignment)
            .offset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if ((position.pixels - target).abs() > 0.5) {
          _jumpToDuringIncomingViewportRestore(target);
        }
        _correctViewportAnchorAfterIncoming(anchor, token, remainingPasses: 2);
        return;
      }
      _finishViewportAnchorRestore();
    });
  }

  void _correctViewportAnchorAfterIncoming(
    _ViewportAnchor anchor,
    int token, {
    required int remainingPasses,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _scrollToBottomToken ||
          !_scrollController.hasClients) {
        return;
      }
      final anchorBox =
          _messageRowKeys[anchor.clientMessageId]?.currentContext
                  ?.findRenderObject()
              as RenderBox?;
      if (anchorBox == null || !anchorBox.hasSize) {
        _finishViewportAnchorRestore();
        return;
      }
      final top = anchorBox.localToGlobal(Offset.zero).dy;
      final delta = top - anchor.top;
      if (delta.abs() > 0.5) {
        final position = _scrollController.position;
        final target = (position.pixels - delta)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if ((position.pixels - target).abs() > 0.5) {
          _jumpToDuringIncomingViewportRestore(target);
        }
        if (remainingPasses > 0) {
          _correctViewportAnchorAfterIncoming(
            anchor,
            token,
            remainingPasses: remainingPasses - 1,
          );
          return;
        }
      }
      _finishViewportAnchorRestore();
    });
  }

  void _finishViewportAnchorRestore() {
    _rememberScrollPosition();
    _syncLatestButtonVisibility();
    _scheduleNewMessageJumpVisibilitySync();
  }

  void _jumpToDuringIncomingViewportRestore(double target) {
    _restoringIncomingViewport = true;
    try {
      _scrollController.jumpTo(target);
    } finally {
      _restoringIncomingViewport = false;
    }
  }

  int get _effectiveWidgetNewMessageCount {
    if (widget.messages.isEmpty || widget.newMessageCount <= 0) return 0;
    return widget.newMessageCount.clamp(0, widget.messages.length).toInt();
  }

  int get _newMessageLabelCountFromWidget {
    return widget.newMessageCount < 0 ? 0 : widget.newMessageCount;
  }

  int get _activeNewMessageCount {
    final widgetCount = _effectiveWidgetNewMessageCount;
    if (widgetCount > 0) return widgetCount;
    if (_retainedNewMessageIndex == null) return 0;
    return _retainedNewMessageLabelCount
        .clamp(0, widget.messages.length)
        .toInt();
  }

  int get _newMessageLabelCount {
    final widgetCount = _effectiveWidgetNewMessageCount;
    if (widgetCount > 0) return _newMessageLabelCountFromWidget;
    return _retainedNewMessageLabelCount;
  }

  int? get _retainedNewMessageIndex {
    final retainedId = _retainedNewMessageClientId;
    if (retainedId == null) return null;
    final index = widget.messages.indexWhere(
      (message) => message.clientMessageId == retainedId,
    );
    return index == -1 ? null : index;
  }

  int? get _firstNewMessageIndex {
    final widgetCount = _effectiveWidgetNewMessageCount;
    if (widgetCount > 0) return widget.messages.length - widgetCount;
    return _retainedNewMessageIndex;
  }

  void _markNewMessagesViewed() {
    if (_newMessageJumpDismissed) return;
    setState(() {
      _newMessageJumpDismissed = true;
      _showNewMessageJumpButton = false;
      _incomingUnreadWaitingForUserScroll = false;
    });
    widget.onViewedNewMessages();
  }

  void _scrollToFirstNewMessage() {
    _markNewMessagesViewed();
    if (_ensureFirstNewMessageVisible()) {
      return;
    }
    if (!_scrollController.hasClients) return;
    final count = _activeNewMessageCount;
    if (count <= 0) return;
    final position = _scrollController.position;
    final averageExtent = widget.messages.length <= 1
        ? position.maxScrollExtent
        : position.maxScrollExtent / (widget.messages.length - 1);
    final firstIndex = _firstNewMessageIndex;
    final distanceFromBottom = firstIndex == null
        ? count - 1
        : widget.messages.length - 1 - firstIndex;
    final target =
        (position.minScrollExtent + averageExtent * distanceFromBottom)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    unawaited(
      _scrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted) _ensureFirstNewMessageVisible();
          }),
    );
  }

  bool _ensureFirstNewMessageVisible() {
    final context = _firstNewMessageKey.currentContext;
    if (context == null) return false;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
    );
    return true;
  }

  void _toggleDetailedTimestamps() {
    setState(() {
      _showDetailedTimestamps = !_showDetailedTimestamps;
      _underflowBottomSpacer = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    _trimMessageRowKeys();
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

    _scheduleUnderflowAlignment();

    final now = DateTime.now();
    final firstNewMessageIndex = _firstNewMessageIndex;
    final showNewMessageJump =
        firstNewMessageIndex != null &&
        !_newMessageJumpDismissed &&
        _showNewMessageJumpButton;
    _scheduleNewMessageJumpVisibilitySync();
    final list = ListView.separated(
      key: _messageListKey,
      controller: _scrollController,
      reverse: true,
      physics: const ClampingScrollPhysics(),
      scrollCacheExtent: _messageListCacheExtent,
      padding: EdgeInsets.fromLTRB(
        _chatHorizontalPadding,
        _chatMessageListTopPadding,
        _chatHorizontalPadding,
        widget.bottomInset,
      ),
      itemCount: widget.messages.length + 1,
      separatorBuilder: (context, index) =>
          index == 0 ? const SizedBox.shrink() : const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) return SizedBox(height: _underflowBottomSpacer);

        final messageIndex = index - 1;
        final chronologicalIndex = widget.messages.length - 1 - messageIndex;
        final message = widget.messages[chronologicalIndex];
        final systemEvent = message_display.systemMessageEvent(message);
        final previous = chronologicalIndex == 0
            ? null
            : widget.messages[chronologicalIndex - 1];
        final showTimestamp = message_display.shouldShowChatTimestamp(
          current: message.createdAt,
          previous: previous?.createdAt,
          now: now,
        );
        final timestamp = _showDetailedTimestamps
            ? message_display.formatDetailedChatTimestamp(message.createdAt)
            : message_display.formatChatTimestamp(message.createdAt, now: now);
        final showNewMessageDivider =
            chronologicalIndex == firstNewMessageIndex;
        final row = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showNewMessageDivider) ...[
              KeyedSubtree(
                key: _firstNewMessageKey,
                child: const _NewMessagesDivider(),
              ),
              const SizedBox(height: 10),
            ],
            if (showTimestamp) ...[
              _MessageTimeDivider(
                label: timestamp,
                onTap: _toggleDetailedTimestamps,
              ),
              const SizedBox(height: 10),
            ],
            if (systemEvent != null)
              _SystemMessageRow(
                message: message,
                event: systemEvent,
                currentUser: widget.currentUser,
                ownerUserId: widget.ownerUserId,
                live: widget.live,
                messageActions: widget.messageActions,
                onResolveSenderProfile: widget.onResolveSenderProfile,
                onResolveRoomProfile: widget.onResolveRoomProfile,
                onEnterProfileRoom: widget.onEnterProfileRoom,
                profileActionBuilder: widget.senderProfileActionBuilder,
              )
            else if (message.isRemoved)
              _RemovedMessageRow(
                message: message,
                currentUser: widget.currentUser,
                ownerUserId: widget.ownerUserId,
                live: widget.live,
                messageActions: widget.messageActions,
                onResolveSenderProfile: widget.onResolveSenderProfile,
                onResolveRoomProfile: widget.onResolveRoomProfile,
                onEnterProfileRoom: widget.onEnterProfileRoom,
                profileActionBuilder: widget.senderProfileActionBuilder,
              )
            else
              _MessageRow(
                message: message,
                outgoing: message.sender.id == widget.currentUser.id,
                currentUser: widget.currentUser,
                ownerUserId: widget.ownerUserId,
                transfer: widget.fileTransfers[message.clientMessageId],
                fileDownloads: widget.fileDownloads,
                downloadActions: widget.downloadActions,
                voicePlaybackActions: widget.voicePlaybackActions,
                imagePreviewActions: widget.imagePreviewActions,
                messageActions: widget.messageActions,
                inLive: _userInLive(message.sender.id),
                onResolveSenderProfile: widget.onResolveSenderProfile,
                onResolveRoomProfile: widget.onResolveRoomProfile,
                onEnterProfileRoom: widget.onEnterProfileRoom,
                profileActionBuilder: widget.senderProfileActionBuilder,
              ),
          ],
        );
        final keyedRow = KeyedSubtree(
          key: _messageRowKey(message.clientMessageId),
          child: row,
        );
        if (chronologicalIndex == 0) {
          return KeyedSubtree(key: _oldestMessageKey, child: keyedRow);
        }
        return keyedRow;
      },
    );

    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: _messageListReady ? 1 : 0,
            child: KeyedSubtree(
              key: const ValueKey('chat-message-list'),
              child: list,
            ),
          ),
        ),
        Positioned(
          right: _chatFloatingEdgeInset,
          bottom: 12,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _showLatestButton
                ? PressableSurface(
                    key: const ValueKey('chat-jump-to-latest'),
                    width: 34,
                    height: 34,
                    hoverLift: 0,
                    baseDepth: 0,
                    backgroundColor: UiColors.selected,
                    selectedBackgroundColor: UiColors.selected,
                    pressedBackgroundColor: const Color(0xFF14211B),
                    borderColor: UiColors.selectedBorder,
                    selectedBorderColor: UiColors.selectedBorder,
                    tooltip: '跳到最新消息',
                    onPressed: () => _scrollToBottom(animated: true),
                    child: const Center(
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: UiColors.accent,
                        size: 18,
                      ),
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey('chat-jump-to-latest-hidden'),
                  ),
          ),
        ),
        Positioned(
          top: 12,
          right: _chatFloatingEdgeInset,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: showNewMessageJump
                ? PressableSurface(
                    key: const ValueKey('chat-jump-to-first-new'),
                    width: 34,
                    height: 34,
                    hoverLift: 0,
                    baseDepth: 0,
                    backgroundColor: UiColors.selected,
                    selectedBackgroundColor: UiColors.selected,
                    pressedBackgroundColor: const Color(0xFF14211B),
                    borderColor: UiColors.selectedBorder,
                    selectedBorderColor: UiColors.selectedBorder,
                    tooltip: '查看 $_newMessageLabelCount 条未读消息',
                    onPressed: _scrollToFirstNewMessage,
                    child: const Center(
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: UiColors.accent,
                        size: 18,
                      ),
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey('chat-jump-to-first-new-hidden'),
                  ),
          ),
        ),
      ],
    );
  }
}

class _NewMessagesDivider extends StatelessWidget {
  const _NewMessagesDivider();

  @override
  Widget build(BuildContext context) {
    final lineColor = UiColors.accent.withValues(alpha: 0.58);
    return Row(
      children: [
        Expanded(child: Divider(height: 1, thickness: 1, color: lineColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '未读消息',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.label.copyWith(
              color: UiColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(height: 1, thickness: 1, color: lineColor)),
      ],
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
    required this.message,
    required this.event,
    required this.currentUser,
    required this.ownerUserId,
    required this.live,
    required this.messageActions,
    this.onResolveSenderProfile,
    this.onResolveRoomProfile,
    this.onEnterProfileRoom,
    this.profileActionBuilder,
  });

  final Message message;
  final message_display.SystemMessageEvent event;
  final CurrentUser currentUser;
  final String? ownerUserId;
  final LiveState? live;
  final ChatMessageActions messageActions;
  final Future<UserSummary> Function(UserSummary sender)?
  onResolveSenderProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterProfileRoom;
  final UserProfileActionBuilder? profileActionBuilder;

  @override
  Widget build(BuildContext context) {
    return _SystemMessageContainer(
      message: message,
      actions: messageActions,
      children: _SystemMessageParts(
        event: event,
        currentUser: currentUser,
        ownerUserId: ownerUserId,
        live: live,
        onResolveSenderProfile: onResolveSenderProfile,
        onResolveRoomProfile: onResolveRoomProfile,
        onEnterProfileRoom: onEnterProfileRoom,
        profileActionBuilder: profileActionBuilder,
      ).build(context),
    );
  }
}

class _SystemMessageContainer extends StatefulWidget {
  const _SystemMessageContainer({
    required this.children,
    this.message,
    this.actions,
  });

  final List<Widget> children;
  final Message? message;
  final ChatMessageActions? actions;

  @override
  State<_SystemMessageContainer> createState() =>
      _SystemMessageContainerState();
}

class _SystemMessageContainerState extends State<_SystemMessageContainer> {
  bool _contextMenuActive = false;

  @override
  Widget build(BuildContext context) {
    final active = _contextMenuActive;
    final contentColor = UiColors.surfacePressed.withValues(alpha: 0.82);
    final highlightColor = active ? UiColors.selected : contentColor;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: highlightColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? UiColors.selectedBorder : UiColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: highlightColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 5,
            runSpacing: 5,
            children: widget.children,
          ),
        ),
      ),
    );
    final menuMessage = widget.message;
    final menuActions = widget.actions;
    final wrappedContent = menuMessage == null || menuActions == null
        ? content
        : _MessageContextMenuRegion(
            message: menuMessage,
            actions: menuActions,
            onContextMenuActiveChanged: _setContextMenuActive,
            child: content,
          );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _messageMaxWidth + 96),
        child: wrappedContent,
      ),
    );
  }

  void _setContextMenuActive(bool active) {
    if (!mounted || _contextMenuActive == active) return;
    setState(() => _contextMenuActive = active);
  }
}

class _RemovedMessageRow extends StatelessWidget {
  const _RemovedMessageRow({
    required this.message,
    required this.currentUser,
    required this.ownerUserId,
    required this.live,
    required this.messageActions,
    this.onResolveSenderProfile,
    this.onResolveRoomProfile,
    this.onEnterProfileRoom,
    this.profileActionBuilder,
  });

  final Message message;
  final CurrentUser currentUser;
  final String? ownerUserId;
  final LiveState? live;
  final ChatMessageActions messageActions;
  final Future<UserSummary> Function(UserSummary sender)?
  onResolveSenderProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterProfileRoom;
  final UserProfileActionBuilder? profileActionBuilder;

  @override
  Widget build(BuildContext context) {
    return _SystemMessageContainer(
      message: message,
      actions: messageActions,
      children: _buildParts(),
    );
  }

  List<Widget> _buildParts() {
    if (message.isForceDeleted) {
      final actor = message.forceDeletedBy;
      return [
        if (actor != null) _userChip(actor),
        _systemText(actor == null ? '消息已被删除' : '删除了一条消息'),
      ];
    }

    final actor = message.recalledBy ?? message.sender;
    final recalledOwnMessage = actor.id == message.sender.id;
    final action = _removedTextAction();
    return [
      _userChip(actor),
      if (recalledOwnMessage)
        _systemTextWithTrailingAction('撤回了一条消息', action)
      else ...[
        _systemText('撤回了一条来自'),
        _userChip(message.sender),
        _systemTextWithTrailingAction('的消息', action),
      ],
    ];
  }

  Widget _userChip(UserSummary user) {
    return _SystemUserChip(
      user: user,
      currentUser: currentUser,
      ownerUserId: ownerUserId,
      onResolveProfile: onResolveSenderProfile,
      onResolveRoomProfile: onResolveRoomProfile,
      onEnterProfileRoom: onEnterProfileRoom,
      profileActionBuilder: profileActionBuilder,
      inLive: live_display.liveParticipantByUserId(live, user.id) != null,
    );
  }

  Widget? _removedTextAction() {
    if (!message.isRecalled || message.type != 'text') return null;
    if (message.body.isEmpty) return null;
    if (messageActions.canReeditRecalledText(message)) {
      return _RemovedMessageInlineButton(
        key: ValueKey('message-reedit-${message.id}'),
        icon: Icons.edit_outlined,
        tooltip: '重新编辑',
        onPressed: () => messageActions.onReeditRecalledText(message),
      );
    }
    if (messageActions.canInspectRecalledText(message)) {
      return _SystemInfoButton(
        key: ValueKey('message-info-${message.id}'),
        message: message.body,
      );
    }
    return null;
  }
}

class _RemovedMessageInlineButton extends StatelessWidget {
  const _RemovedMessageInlineButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 16,
            child: Icon(icon, size: 14, color: UiColors.accent),
          ),
        ),
      ),
    );
  }
}

class _SystemInfoButton extends StatelessWidget {
  const _SystemInfoButton({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return HoverCardAnchor(
      resetKey: message,
      cardWidth: _systemInfoCardWidth(context, message),
      gap: 8,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox.square(
          dimension: 16,
          child: Icon(Icons.info_outline, size: 14, color: UiColors.accent),
        ),
      ),
      cardBuilder: (context) => _SystemInfoCard(message: message),
    );
  }
}

double _systemInfoCardWidth(BuildContext context, String message) {
  const horizontalPadding = 24.0;
  const minWidth = 112.0;
  const maxWidth = 360.0;
  final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
  final style = UiTypography.body.copyWith(fontSize: 12, height: 1.38);
  final lines = message.trimRight().split('\n');
  var longestLineWidth = 0.0;
  for (final line in lines) {
    final painter = TextPainter(
      text: TextSpan(text: line.isEmpty ? ' ' : line, style: style),
      textDirection: direction,
      maxLines: 1,
    )..layout();
    longestLineWidth = math.max(longestLineWidth, painter.width);
  }
  return (longestLineWidth + horizontalPadding).clamp(minWidth, maxWidth);
}

class _SystemInfoCard extends StatelessWidget {
  const _SystemInfoCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final hoverScope = HoverCardTapRegionScope.maybeOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: ReadOnlySelectableText(
        value: message,
        maxLines: 8,
        style: UiTypography.body.copyWith(
          color: UiColors.text,
          fontSize: 12,
          height: 1.38,
        ),
        contextMenuTapRegionGroupId: hoverScope?.tapRegionGroup,
        onContextMenuOpenChanged: hoverScope?.onOverlayActivityChanged,
      ),
    );
  }
}

class _MessageContextMenuRegion extends StatelessWidget {
  const _MessageContextMenuRegion({
    required this.message,
    required this.actions,
    required this.child,
    this.onContextMenuActiveChanged,
  });

  final Message message;
  final ChatMessageActions actions;
  final Widget child;
  final ValueChanged<bool>? onContextMenuActiveChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) {
        onContextMenuActiveChanged?.call(true);
        unawaited(
          _showChatMessageContextMenu(
            context: context,
            position: details.globalPosition,
            message: message,
            actions: actions,
          ).whenComplete(() => onContextMenuActiveChanged?.call(false)),
        );
      },
      child: child,
    );
  }
}

Future<void> _showChatMessageContextMenu({
  required BuildContext context,
  required Offset position,
  required Message message,
  required ChatMessageActions actions,
}) {
  final sections = _messageContextMenuSections(
    context: context,
    message: message,
    actions: actions,
    includeCopy: true,
    includeDelete: true,
    includeRecall: !message.isRemoved,
  );
  return showUiContextMenu(context, position: position, sections: sections);
}

List<UiContextMenuSection> _messageContextMenuSections({
  required BuildContext context,
  required Message message,
  required ChatMessageActions actions,
  bool includeCopy = true,
  bool includeDelete = true,
  bool includeRecall = true,
}) {
  return [
    if (includeCopy)
      UiContextMenuSection([
        UiContextMenuItem(
          label: '复制',
          shortcut: 'Ctrl+C',
          onPressed: () => unawaited(actions.onCopy(context, message)),
        ),
      ]),
    if (includeRecall && actions.canRecall(message))
      UiContextMenuSection([
        UiContextMenuItem(
          label: '撤回',
          onPressed: () => unawaited(actions.onRecall(context, message)),
        ),
      ]),
    if (includeDelete)
      UiContextMenuSection([
        UiContextMenuItem(
          label: '删除',
          onPressed: () => unawaited(actions.onDeleteForMe(context, message)),
        ),
      ]),
  ];
}

Widget _systemText(String value) {
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

Widget _systemTextWithTrailingAction(String value, Widget? action) {
  if (action == null) return _systemText(value);
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [_systemText(value), action],
  );
}

class _SystemMessageParts {
  const _SystemMessageParts({
    required this.event,
    required this.currentUser,
    required this.ownerUserId,
    required this.live,
    this.onResolveSenderProfile,
    this.onResolveRoomProfile,
    this.onEnterProfileRoom,
    this.profileActionBuilder,
  });

  final message_display.SystemMessageEvent event;
  final CurrentUser currentUser;
  final String? ownerUserId;
  final LiveState? live;
  final Future<UserSummary> Function(UserSummary sender)?
  onResolveSenderProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterProfileRoom;
  final UserProfileActionBuilder? profileActionBuilder;

  List<Widget> build(BuildContext context) {
    final subject = event.subject;
    switch (event.event) {
      case message_display.kSystemEventRoomMemberJoined:
        return [_userChip(subject), _text('加入了房间')];
      case message_display.kSystemEventRoomMemberLeft:
        return [_userChip(subject), _text('离开了房间')];
      case message_display.kSystemEventRoomMemberRemoved:
        final actor = event.actor;
        return [
          _userChip(subject),
          if (actor == null)
            _text('被踢出了房间')
          else ...[
            _text('被'),
            _userChip(actor),
            _text('踢出了房间'),
          ],
        ];
      case message_display.kSystemEventLiveJoined:
        return [_userChip(subject), _text('进入了语音频道')];
      case message_display.kSystemEventLiveLeft:
        return [_userChip(subject), _text('退出了语音频道')];
      case message_display.kSystemEventRoomRoleChanged:
        final actor = event.actor;
        final roleLabel = message_display.systemMessageRoleLabel(event.toRole);
        final verb = message_display.systemMessageRoleVerb(event);
        final omitActor = message_display.systemMessageRoleChangeOmitsActor(
          event,
        );
        return [
          _userChip(subject, roleOverride: event.toRole),
          if (!omitActor && actor != null) ...[_text('被'), _userChip(actor)],
          _text(verb),
          RoleBadge(
            label: roleLabel,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ];
      case message_display.kSystemEventRoomNameChanged:
        final actor = event.actor ?? event.user;
        return [
          _textWithInfoButton('房间名称', '原房间名称：${event.oldValue ?? ''}'),
          if (actor == null) ...[
            _text('修改为'),
          ] else ...[
            _text('被'),
            _userChip(actor),
            _text('修改为'),
          ],
          _highlightText(_systemChangedValueLabel(event.newValue)),
        ];
      case message_display.kSystemEventRoomDescriptionChanged:
        final actor = event.actor ?? event.user;
        return [
          _textWithInfoButton('房间简介', '原房间简介：${event.oldValue ?? ''}'),
          if (actor == null) ...[
            _text('修改为'),
          ] else ...[
            _text('被'),
            _userChip(actor),
            _text('修改为'),
          ],
          _lineBreak(),
          _highlightText(_systemChangedValueLabel(event.newValue), maxLines: 4),
        ];
      default:
        final fallback = event.message.body.trim();
        return [_userChip(subject), if (fallback.isNotEmpty) _text(fallback)];
    }
  }

  Widget _userChip(UserSummary user, {String? roleOverride}) {
    return _SystemUserChip(
      user: user,
      roleOverride: roleOverride,
      currentUser: currentUser,
      ownerUserId: ownerUserId,
      onResolveProfile: onResolveSenderProfile,
      onResolveRoomProfile: onResolveRoomProfile,
      onEnterProfileRoom: onEnterProfileRoom,
      profileActionBuilder: profileActionBuilder,
      inLive: live_display.liveParticipantByUserId(live, user.id) != null,
    );
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

  Widget _textWithInfoButton(String value, String info) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [_text(value), _infoButton(info)],
    );
  }

  Widget _infoButton(String value) {
    return _SystemInfoButton(
      key: ValueKey(
        'system-info-${event.message.clientMessageId}-${event.event}',
      ),
      message: value,
    );
  }

  Widget _highlightText(String value, {int maxLines = 1}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _messageMaxWidth),
      child: Text(
        value,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: UiTypography.label.copyWith(
          color: UiColors.accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _lineBreak() {
    return const SizedBox(width: _messageMaxWidth + 96, height: 0);
  }

  String _systemChangedValueLabel(String? value) {
    final normalized = value ?? '';
    if (normalized.isEmpty) return '（空）';
    return normalized;
  }
}

class _SystemUserChip extends StatelessWidget {
  const _SystemUserChip({
    required this.user,
    this.roleOverride,
    required this.currentUser,
    required this.ownerUserId,
    required this.inLive,
    this.onResolveProfile,
    this.onResolveRoomProfile,
    this.onEnterProfileRoom,
    this.profileActionBuilder,
  });

  final UserSummary user;
  final String? roleOverride;
  final CurrentUser currentUser;
  final String? ownerUserId;
  final bool inLive;
  final Future<UserSummary> Function(UserSummary sender)? onResolveProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterProfileRoom;
  final UserProfileActionBuilder? profileActionBuilder;

  @override
  Widget build(BuildContext context) {
    final name = _senderName(user);
    final colorUser = roleOverride == null
        ? user
        : user.copyWith(roomRole: roleOverride);
    final avatar = Avatar(
      label: room_display.userAvatarLabel(user),
      imageUrl: AppConfigScope.of(context).resolveAssetUrl(user.avatarUrl),
      defaultAvatarKey: user.defaultAvatarKey,
      size: 16,
      activeBorderWidth: 1,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AvatarHoverCard(
          user: user,
          currentUser: currentUser,
          onResolveProfile: onResolveProfile,
          onResolveRoomProfile: onResolveRoomProfile,
          onEnterCommonRoom: onEnterProfileRoom,
          profileActionBuilder: profileActionBuilder,
          inLive: inLive,
          child: avatar,
        ),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 128),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.label.copyWith(
              color: _roomUsernameColor(
                user: colorUser,
                currentUser: currentUser,
                ownerUserId: ownerUserId,
              ),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.outgoing,
    required this.currentUser,
    required this.ownerUserId,
    required this.transfer,
    required this.fileDownloads,
    required this.downloadActions,
    required this.voicePlaybackActions,
    required this.imagePreviewActions,
    required this.messageActions,
    required this.inLive,
    this.onResolveSenderProfile,
    this.onResolveRoomProfile,
    this.onEnterProfileRoom,
    this.profileActionBuilder,
  });

  final Message message;
  final bool outgoing;
  final CurrentUser currentUser;
  final String? ownerUserId;
  final FileTransferState? transfer;
  final Map<String, FileTransferState> fileDownloads;
  final ChatFileDownloadActions downloadActions;
  final ChatVoicePlaybackActions voicePlaybackActions;
  final ChatImagePreviewActions imagePreviewActions;
  final ChatMessageActions messageActions;
  final bool inLive;
  final Future<UserSummary> Function(UserSummary sender)?
  onResolveSenderProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterProfileRoom;
  final UserProfileActionBuilder? profileActionBuilder;

  @override
  Widget build(BuildContext context) {
    final sender = _senderName(message.sender);
    final senderColor = _roomUsernameColor(
      user: message.sender,
      currentUser: currentUser,
      ownerUserId: ownerUserId,
    );
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
                  color: senderColor,
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
              imagePreviewActions: imagePreviewActions,
              messageActions: messageActions,
            ),
          ),
        ],
      ),
    );

    final avatar = Avatar(
      label: room_display.userAvatarLabel(message.sender),
      imageUrl: AppConfigScope.of(
        context,
      ).resolveAssetUrl(message.sender.avatarUrl),
      defaultAvatarKey: message.sender.defaultAvatarKey,
      size: 32,
      showBorder: false,
    );

    final avatarHoverCard = _AvatarHoverCard(
      user: message.sender,
      currentUser: currentUser,
      onResolveProfile: onResolveSenderProfile,
      onResolveRoomProfile: onResolveRoomProfile,
      onEnterCommonRoom: onEnterProfileRoom,
      profileActionBuilder: profileActionBuilder,
      inLive: inLive,
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

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.outgoing,
    required this.transfer,
    required this.fileDownloads,
    required this.downloadActions,
    required this.voicePlaybackActions,
    required this.imagePreviewActions,
    required this.messageActions,
  });

  final Message message;
  final bool outgoing;
  final FileTransferState? transfer;
  final Map<String, FileTransferState> fileDownloads;
  final ChatFileDownloadActions downloadActions;
  final ChatVoicePlaybackActions voicePlaybackActions;
  final ChatImagePreviewActions imagePreviewActions;
  final ChatMessageActions messageActions;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _textSelectionActive = false;
  bool _contextMenuActive = false;

  @override
  Widget build(BuildContext context) {
    final contentKind = message_display.messageContentKind(widget.message);
    final status = message_display.messageDeliveryStatusText(widget.message);
    final contextMenuActive = _contextMenuActive;
    final backgroundColor = widget.outgoing ? _outgoingBubble : _incomingBubble;
    final highlightColor = contextMenuActive
        ? UiColors.selected
        : backgroundColor;
    final borderColor = contextMenuActive
        ? UiColors.selectedBorder
        : widget.outgoing
        ? UiColors.accentBorder
        : UiColors.border;

    return Listener(
      onPointerDown: (event) => _handleBubblePointerDown(event, contentKind),
      child: AnimatedContainer(
        key: ValueKey('message-bubble-surface-${widget.message.id}'),
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: highlightColor,
          borderRadius: BorderRadius.circular(UiRadii.lg),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: DecoratedBox(
            key: ValueKey('message-bubble-content-${widget.message.id}'),
            decoration: BoxDecoration(
              color: highlightColor,
              borderRadius: BorderRadius.circular(math.max(0, UiRadii.lg - 5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                switch (contentKind) {
                  message_display.MessageContentKind.sticker => _StickerBody(
                    message: widget.message,
                    attachment: widget.message.stickerAttachment!,
                    imagePreviewActions: widget.imagePreviewActions,
                  ),
                  message_display.MessageContentKind.voice => _VoiceBody(
                    message: widget.message,
                    attachment: voice_display.voiceMessageAttachment(
                      widget.message,
                    )!,
                    playbackActions: widget.voicePlaybackActions,
                  ),
                  message_display.MessageContentKind.files => _FileBody(
                    message: widget.message,
                    outgoing: widget.outgoing,
                    transfer: widget.transfer,
                    fileDownloads: widget.fileDownloads,
                    downloadActions: widget.downloadActions,
                    imagePreviewActions: widget.imagePreviewActions,
                  ),
                  message_display.MessageContentKind.text => _TextBody(
                    message: widget.message,
                    onSelectionActiveChanged: _handleTextSelectionActiveChanged,
                  ),
                },
                if (status != null) ...[
                  const SizedBox(height: 7),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.message.pending && !widget.message.failed) ...[
                        const SizedBox.square(
                          dimension: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: UiColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        status,
                        style: UiTypography.label.copyWith(
                          color: widget.message.failed
                              ? UiColors.danger
                              : UiColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleBubblePointerDown(
    PointerDownEvent event,
    message_display.MessageContentKind contentKind,
  ) {
    if ((event.buttons & kSecondaryMouseButton) == 0) return;
    if (contentKind == message_display.MessageContentKind.text &&
        _textSelectionActive) {
      return;
    }
    if (contentKind == message_display.MessageContentKind.sticker) {
      _showContextMenuWithHighlight(
        () => _showStickerContextMenu(
          context: context,
          position: event.position,
          message: widget.message,
          attachment: widget.message.stickerAttachment!,
          imagePreviewActions: widget.imagePreviewActions,
          messageActions: widget.messageActions,
        ),
      );
      return;
    }
    _showContextMenuWithHighlight(
      () => _showChatMessageContextMenu(
        context: context,
        position: event.position,
        message: widget.message,
        actions: widget.messageActions,
      ),
    );
  }

  void _handleTextSelectionActiveChanged(bool active) {
    if (_textSelectionActive == active) return;
    setState(() => _textSelectionActive = active);
  }

  void _showContextMenuWithHighlight(Future<void> Function() showMenu) {
    _setContextMenuActive(true);
    unawaited(
      showMenu().whenComplete(() {
        if (mounted) _setContextMenuActive(false);
      }),
    );
  }

  void _setContextMenuActive(bool active) {
    if (!mounted || _contextMenuActive == active) return;
    setState(() => _contextMenuActive = active);
  }
}

class _TextBody extends StatefulWidget {
  const _TextBody({
    required this.message,
    required this.onSelectionActiveChanged,
  });

  final Message message;
  final ValueChanged<bool> onSelectionActiveChanged;

  @override
  State<_TextBody> createState() => _TextBodyState();
}

class _TextBodyState extends State<_TextBody> {
  late final _MessageTextController _controller;
  final FocusNode _focusNode = FocusNode();
  final UndoHistoryController _undoController = UndoHistoryController();
  final Object _tapRegionGroup = Object();
  EditableTextState? _activeTextContextMenuState;
  bool _textContextMenuOpen = false;
  bool _textContextMenuActionPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = _MessageTextController(
      text: widget.message.body,
      onOpenLink: _handleOpenLink,
    );
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(_TextBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.body == widget.message.body) return;
    final selection = _controller.selection;
    _controller.value = TextEditingValue(
      text: widget.message.body,
      selection: _clampMessageTextSelection(
        selection,
        widget.message.body.length,
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    widget.onSelectionActiveChanged(false);
    _controller.dispose();
    _focusNode.dispose();
    _undoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: _tapRegionGroup,
      onTapOutside: _handleTapOutside,
      child: TextFieldEditingShortcuts(
        controller: _controller,
        focusNode: _focusNode,
        undoController: _undoController,
        onGlobalPrimaryPointerDownDuringSecondaryClickProtection:
            _handleGlobalPrimaryPointerDownDuringTextSelectionProtection,
        child: IntrinsicWidth(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            readOnly: true,
            showCursor: false,
            enableInteractiveSelection: true,
            minLines: 1,
            maxLines: null,
            mouseCursor: SystemMouseCursors.text,
            style: UiTypography.body,
            cursorColor: UiColors.accent,
            undoController: _undoController,
            contextMenuBuilder: (context, editableTextState) {
              _activeTextContextMenuState = editableTextState;
              return buildTextFieldContextMenu(
                context,
                editableTextState,
                readOnly: true,
                showReadOnlySelectAll: false,
                tapRegionGroupId: _tapRegionGroup,
                onOpenChanged: _handleTextContextMenuOpenChanged,
                onActionPressed: _handleTextContextMenuActionPressed,
              );
            },
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }

  void _handleControllerChanged() {
    widget.onSelectionActiveChanged(_hasSelection);
  }

  void _handleTextContextMenuActionPressed() {
    _textContextMenuActionPressed = true;
  }

  void _handleTextContextMenuOpenChanged(bool open) {
    if (!mounted) return;
    if (open) {
      _textContextMenuOpen = true;
      _textContextMenuActionPressed = false;
      return;
    }

    final closedByOutsideClick =
        _textContextMenuOpen && !_textContextMenuActionPressed;
    _textContextMenuOpen = false;
    _textContextMenuActionPressed = false;
    _activeTextContextMenuState = null;
    if (closedByOutsideClick) _collapseSelection();
  }

  bool get _hasSelection {
    final selection = _controller.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  void _handleTapOutside(PointerDownEvent event) {
    if ((event.buttons & kPrimaryMouseButton) == 0) return;
    _collapseSelection(hideToolbar: true);
  }

  void _handleGlobalPrimaryPointerDownDuringTextSelectionProtection(
    PointerDownEvent event,
  ) {
    if (isTextContextMenuPanelHit(event.position)) return;
    _collapseSelection(hideToolbar: true);
  }

  void _collapseSelection({bool hideToolbar = false}) {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final offset = selection.extentOffset.clamp(0, _controller.text.length);
    _controller.selection = TextSelection.collapsed(offset: offset);
    widget.onSelectionActiveChanged(false);
    if (hideToolbar) _activeTextContextMenuState?.hideToolbar();
  }

  void _handleOpenLink(Uri uri) {
    unawaited(_openLink(uri));
  }

  Future<void> _openLink(Uri uri) async {
    try {
      await const ExternalUriLauncher().open(uri);
    } catch (_) {
      if (!mounted) return;
      _showMessageContextNotice(context, '无法打开链接');
    }
  }
}

class _MessageTextController extends TextEditingController {
  _MessageTextController({required String text, required this.onOpenLink})
    : super(text: text);

  final ValueChanged<Uri> onOpenLink;
  Map<String, TapGestureRecognizer> _linkRecognizers = {};

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final matches = _messageLinkMatches(text).toList(growable: false);
    if (matches.isEmpty) {
      _disposeStaleLinkRecognizers(_linkRecognizers);
      _linkRecognizers = {};
      return TextSpan(text: text, style: style);
    }

    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final linkStyle = baseStyle.copyWith(
      color: UiColors.accent,
      decoration: TextDecoration.underline,
      decorationColor: UiColors.accent,
    );
    final children = <InlineSpan>[];
    final staleRecognizers = Map<String, TapGestureRecognizer>.of(
      _linkRecognizers,
    );
    final nextRecognizers = <String, TapGestureRecognizer>{};
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final key = '${match.start}:${match.end}:${match.uri}';
      final recognizer = staleRecognizers.remove(key) ?? TapGestureRecognizer();
      recognizer.onTap = () => onOpenLink(match.uri);
      nextRecognizers[key] = recognizer;
      children.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: linkStyle,
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    _disposeStaleLinkRecognizers(staleRecognizers);
    _linkRecognizers = nextRecognizers;
    return TextSpan(style: baseStyle, children: children);
  }

  @override
  void dispose() {
    _disposeStaleLinkRecognizers(_linkRecognizers);
    _linkRecognizers = {};
    super.dispose();
  }

  void _disposeStaleLinkRecognizers(
    Map<String, TapGestureRecognizer> recognizers,
  ) {
    for (final recognizer in recognizers.values) {
      recognizer.dispose();
    }
  }
}

class _MessageLinkMatch {
  const _MessageLinkMatch({
    required this.start,
    required this.end,
    required this.uri,
  });

  final int start;
  final int end;
  final Uri uri;
}

final RegExp _messageLinkPattern = RegExp(
  r"""(?:(?:https?:\/\/)|(?:www\.))[^\s<>{}\[\]"']+""",
  caseSensitive: false,
);

const String _messageLinkTrailingPunctuation = '.,!?;:，。！？；：、)]}）】》';

Iterable<_MessageLinkMatch> _messageLinkMatches(String value) sync* {
  for (final match in _messageLinkPattern.allMatches(value)) {
    var end = match.end;
    while (end > match.start &&
        _messageLinkTrailingPunctuation.contains(value[end - 1])) {
      end--;
    }
    if (end <= match.start) continue;
    final raw = value.substring(match.start, end);
    final uri = _messageLinkUri(raw);
    if (uri == null) continue;
    yield _MessageLinkMatch(start: match.start, end: end, uri: uri);
  }
}

Uri? _messageLinkUri(String value) {
  final lower = value.toLowerCase();
  final normalized = lower.startsWith('http://') || lower.startsWith('https://')
      ? value
      : 'https://$value';
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

TextSelection _clampMessageTextSelection(TextSelection selection, int length) {
  if (!selection.isValid) return TextSelection.collapsed(offset: length);
  return TextSelection(
    baseOffset: math.min(selection.baseOffset, length),
    extentOffset: math.min(selection.extentOffset, length),
    affinity: selection.affinity,
    isDirectional: selection.isDirectional,
  );
}

class _StickerBody extends StatelessWidget {
  const _StickerBody({
    required this.message,
    required this.attachment,
    required this.imagePreviewActions,
  });

  final Message message;
  final MessageAttachment attachment;
  final ChatImagePreviewActions imagePreviewActions;

  @override
  Widget build(BuildContext context) {
    final asset = attachment.asset;
    final config = AppConfigScope.of(context);
    final imageUrl = asset == null
        ? null
        : config.resolveAssetUrl(asset.thumbnailUrl ?? asset.url);
    // The preview shows the full-resolution sticker, not the thumbnail.
    final previewUrl = asset == null ? null : config.resolveAssetUrl(asset.url);
    final name = message_display.stickerAttachmentTitle(attachment);
    final image = imageUrl != null && imageUrl.isNotEmpty
        ? ClipRRect(
            borderRadius: BorderRadius.circular(UiRadii.md),
            child: CachedAssetImage(
              url: imageUrl,
              filename: asset?.filename ?? name,
              mimeType: asset?.mimeType,
              expectedBytes: asset?.sizeBytes,
              cache: imagePreviewActions.mediaCache,
              width: 132,
              height: 132,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  _StickerFallback(name: name),
            ),
          )
        : _StickerFallback(name: name);

    final tappablePreviewUrl = previewUrl != null && previewUrl.isNotEmpty
        ? previewUrl
        : (imageUrl != null && imageUrl.isNotEmpty ? imageUrl : null);

    final preview = tappablePreviewUrl == null
        ? image
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => showChatImagePreview(
                context,
                imageUrl: tappablePreviewUrl,
                suggestedName: message_display.stickerPreviewFilename(
                  attachment,
                ),
                actions: imagePreviewActions,
                stickerSource: attachment.stickerId != null
                    ? (message: message, attachment: attachment)
                    : null,
              ),
              child: image,
            ),
          );

    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 350),
      child: preview,
    );
  }
}

Future<void> _showStickerContextMenu({
  required BuildContext context,
  required Offset position,
  required Message message,
  required MessageAttachment attachment,
  required ChatImagePreviewActions imagePreviewActions,
  required ChatMessageActions messageActions,
}) {
  final stickerId = attachment.stickerId;

  final stickerItems = <UiContextMenuItem>[
    if (imagePreviewActions.onSaveSticker != null)
      UiContextMenuItem(
        label: '添加到我的表情包',
        onPressed: () => unawaited(
          _runStickerContextAction(
            context,
            message,
            attachment,
            imagePreviewActions.onSaveSticker!,
            successMessage: '已添加到我的表情包',
          ),
        ),
      ),
    if (imagePreviewActions.onSaveRoomSticker != null)
      UiContextMenuItem(
        label: '添加到房间表情包',
        onPressed: () => unawaited(
          _runStickerContextAction(
            context,
            message,
            attachment,
            imagePreviewActions.onSaveRoomSticker!,
            successMessage: '已添加到房间表情包',
          ),
        ),
      ),
  ];
  final sections = [
    ..._messageContextMenuSections(
      context: context,
      message: message,
      actions: messageActions,
      includeCopy: true,
      includeDelete: false,
      includeRecall: false,
    ),
    if (stickerId != null && stickerId.isNotEmpty && stickerItems.isNotEmpty)
      UiContextMenuSection(stickerItems),
    ..._messageContextMenuSections(
      context: context,
      message: message,
      actions: messageActions,
      includeCopy: false,
      includeDelete: false,
      includeRecall: true,
    ),
    ..._messageContextMenuSections(
      context: context,
      message: message,
      actions: messageActions,
      includeCopy: false,
      includeDelete: true,
      includeRecall: false,
    ),
  ];

  return showUiContextMenu(context, position: position, sections: sections);
}

Future<void> _runStickerContextAction(
  BuildContext context,
  Message message,
  MessageAttachment attachment,
  Future<void> Function(Message message, MessageAttachment attachment) action, {
  required String successMessage,
}) async {
  try {
    await action(message, attachment);
    if (!context.mounted) return;
    _showMessageContextNotice(context, successMessage);
  } catch (error) {
    if (!context.mounted) return;
    _showMessageContextNotice(context, '$error');
  }
}

void _showMessageContextNotice(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
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

const _voiceAccent = Colors.white;

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
            key: const ValueKey('voice-body'),
            constraints: const BoxConstraints(minWidth: 150, maxWidth: 304),
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
    required this.imagePreviewActions,
  });

  final Message message;
  final bool outgoing;
  final FileTransferState? transfer;
  final Map<String, FileTransferState> fileDownloads;
  final ChatFileDownloadActions downloadActions;
  final ChatImagePreviewActions imagePreviewActions;

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
            imagePreviewActions: imagePreviewActions,
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
    required this.imagePreviewActions,
  });

  final Message message;
  final bool outgoing;
  final MessageAttachment attachment;
  final int index;
  final file_display.FileAttachmentTransferSlot slot;
  final ChatFileDownloadActions downloadActions;
  final ChatImagePreviewActions imagePreviewActions;

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
                mediaCache: imagePreviewActions.mediaCache,
                onTap: () {
                  final fullUrl =
                      (resolvedUrl != null && resolvedUrl.isNotEmpty)
                      ? resolvedUrl
                      : previewUrl;
                  showChatImagePreview(
                    context,
                    imageUrl: fullUrl,
                    suggestedName: title,
                    actions: imagePreviewActions,
                  );
                },
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
    this.mediaCache,
    this.onTap,
  });

  final String url;
  final String title;
  final double width;
  final double height;
  final MediaCacheController? mediaCache;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(UiRadii.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: UiColors.surfaceLow,
          border: Border.all(color: UiColors.border),
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: _filePreviewImage(),
        ),
      ),
    );

    if (onTap == null) return preview;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: preview),
    );
  }

  Widget _filePreviewImage() {
    return CachedAssetImage(
      url: url,
      filename: title,
      cache: mediaCache,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _filePreviewFallback(),
    );
  }

  Widget _filePreviewFallback() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          title,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: UiTypography.label.copyWith(color: UiColors.textMuted),
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
    this.imagePreviewActions,
    this.outgoing = false,
    this.transfer,
    this.fileDownloads = const {},
    this.voicePlaybackActions = const ChatVoicePlaybackActions.disabled(),
    this.messageActions = const ChatMessageActions.disabled(),
  });

  final Message message;
  final ChatFileDownloadActions downloadActions;
  final ChatImagePreviewActions? imagePreviewActions;
  final bool outgoing;
  final FileTransferState? transfer;
  final Map<String, FileTransferState> fileDownloads;
  final ChatVoicePlaybackActions voicePlaybackActions;
  final ChatMessageActions messageActions;

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
        imagePreviewActions:
            imagePreviewActions ?? ChatImagePreviewActions.disabled(),
        messageActions: messageActions,
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

Color _roomUsernameColor({
  required UserSummary user,
  required CurrentUser currentUser,
  String? ownerUserId,
}) {
  if (user.id == currentUser.id) return UiColors.accent;
  return roleBadgeForegroundColorForLabel(
    room_display.roomRoleLabel(user, ownerUserId: ownerUserId),
  );
}

String _senderName(UserSummary user) {
  final roomName = user.roomDisplayName?.trim();
  if (roomName != null && roomName.isNotEmpty) return roomName;
  return user.displayName;
}
