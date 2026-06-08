part of 'home_shell.dart';

extension _HomeShellMessages on _HomeShellState {
  Future<void> _sendText(String value) async {
    final body = value.trimRight();
    await _sendComposed(
      body: body,
      type: 'text',
      attachments: const [],
      clearComposer: true,
    );
  }

  Future<void> _sendSticker(Sticker sticker) async {
    final draft = message_display.stickerMessageDraft(sticker);
    await _sendComposed(
      body: draft.body,
      type: draft.type,
      attachments: draft.attachments,
      clearComposer: false,
    );
  }

  Future<void> _sendComposed({
    required String body,
    required String type,
    required List<MessageAttachment> attachments,
    required bool clearComposer,
  }) async {
    final room = _selectedRoom;
    if (room == null || _sending) return;
    if (!canSendComposedMessage(
      body: body,
      type: type,
      attachments: attachments,
    )) {
      return;
    }

    String? clientMessageId;
    _setHomeState(() {
      _sending = true;
      _sendError = null;
    });

    try {
      final sent = await _messagesController.sendComposedMessage(
        roomId: room.id,
        sender: _currentUser.toSummary(),
        body: body,
        type: type,
        attachments: attachments,
        onPending: (pending) {
          clientMessageId = pending.clientMessageId;
          if (!mounted) return;
          _setHomeState(() {
            _messages = _messagesController.patchPendingMessage(
              messages: _messages,
              pending: pending,
            );
            if (clearComposer) _composerController.clear();
          });
        },
      );
      if (!mounted || _selectedServerId != room.id) return;
      _setHomeState(() {
        _messages = _messagesController.patchSentMessage(
          messages: _messages,
          sent: sent,
        );
      });
      unawaited(_loadServers());
    } catch (error) {
      if (!mounted) return;
      _setHomeState(() {
        _sendError = error.toString();
        if (clientMessageId != null) {
          _messages = _messagesController.patchFailedMessage(
            messages: _messages,
            clientMessageId: clientMessageId!,
          );
        }
      });
    } finally {
      if (mounted) _setHomeState(() => _sending = false);
    }
  }

  /// Load the personal + room sticker packs that back the composer panel.
  /// Personal packs are read from the on-disk cache first for an instant
  /// render, then refreshed from the server alongside the room's packs.
  Future<void> _loadStickerPacks({bool forceReload = false}) async {
    final roomId = _selectedServerId;
    if (roomId == null) return;
    if (!sticker_display.shouldLoadStickerPanel(
      state: _stickerPanelState,
      forceReload: forceReload,
    )) {
      return;
    }

    _setHomeState(
      () => _stickerPanelState = sticker_display.stickerPanelLoadStarted(
        _stickerPanelState,
      ),
    );

    try {
      final cachedPersonal = forceReload
          ? null
          : await _stickerPacksController.readCachedPersonalPacks(
              userId: _currentUser.id,
            );
      if (!mounted || _selectedServerId != roomId) return;
      if (cachedPersonal != null) {
        _setHomeState(
          () => _stickerPanelState = sticker_display
              .stickerPanelCachedPersonalApplied(
                state: _stickerPanelState,
                packs: cachedPersonal,
              ),
        );
      }
      final shouldFetchPersonal = forceReload || cachedPersonal == null;
      final packs = await Future.wait([
        shouldFetchPersonal
            ? _stickerPacksController.loadPersonalPacks(
                userId: _currentUser.id,
                forceReload: true,
              )
            : Future<List<StickerPack>>.value(cachedPersonal),
        _stickerPacksController.loadRoomPacks(roomId),
      ]);
      if (!mounted || _selectedServerId != roomId) return;
      _setHomeState(
        () => _stickerPanelState = sticker_display.stickerPanelLoadSucceeded(
          state: _stickerPanelState,
          personalPacks: packs[0],
          roomPacks: packs[1],
        ),
      );
    } catch (error) {
      if (!mounted || _selectedServerId != roomId) return;
      _setHomeState(
        () => _stickerPanelState = sticker_display.stickerPanelLoadFailed(
          state: _stickerPanelState,
          failure: error,
        ),
      );
    } finally {
      if (mounted && _selectedServerId == roomId) {
        _setHomeState(
          () => _stickerPanelState = sticker_display.stickerPanelLoadFinished(
            _stickerPanelState,
          ),
        );
      }
    }
  }

  void _changeStickerSource(sticker_display.StickerPanelSource source) {
    _setHomeState(
      () => _stickerPanelState = sticker_display.stickerPanelSourceChanged(
        _stickerPanelState,
        source,
      ),
    );
  }
}
