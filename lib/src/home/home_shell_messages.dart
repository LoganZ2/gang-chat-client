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

  // --- Voice messages ---------------------------------------------------

  /// Begin a click-to-record voice clip. Starts the recorder, then drives a
  /// 1s ticker that updates the displayed duration and stops automatically at
  /// the max length.
  Future<void> _startVoiceRecording() async {
    if (!_voiceState.isIdle || _selectedRoom == null) return;
    try {
      await _voiceRecorder.start();
    } catch (error) {
      if (!mounted) return;
      _setHomeState(
        () => _voiceState = const voice_display.VoiceRecorderState().copyWith(
          error: error.toString(),
        ),
      );
      return;
    }
    if (!mounted) {
      unawaited(_voiceRecorder.cancel());
      return;
    }
    _voiceStartedAt = DateTime.now();
    _setHomeState(() => _voiceState = voice_display.voiceRecordingStarted());
    _voiceTicker?.cancel();
    _voiceTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _onVoiceTick();
    });
  }

  void _onVoiceTick() {
    if (!mounted || !_voiceState.isRecording) return;
    final startedAt = _voiceStartedAt;
    if (startedAt == null) return;
    final elapsed = DateTime.now().difference(startedAt);
    _setHomeState(
      () => _voiceState = voice_display.voiceRecordingTicked(
        _voiceState,
        elapsed,
      ),
    );
    if (voice_display.voiceRecordingReachedLimit(elapsed)) {
      unawaited(_stopVoiceRecording());
    }
  }

  /// Stop recording and move to the review state where the user sends or
  /// discards the clip.
  Future<void> _stopVoiceRecording() async {
    if (!_voiceState.isRecording) return;
    _voiceTicker?.cancel();
    _voiceTicker = null;
    final startedAt = _voiceStartedAt;
    final elapsed = startedAt == null
        ? _voiceState.elapsed
        : DateTime.now().difference(startedAt);
    _voiceStartedAt = null;
    String? path;
    try {
      path = await _voiceRecorder.stop();
    } catch (error) {
      if (!mounted) return;
      _setHomeState(
        () => _voiceState = const voice_display.VoiceRecorderState().copyWith(
          error: error.toString(),
        ),
      );
      return;
    }
    if (!mounted) return;
    _setHomeState(
      () => _voiceState = voice_display.voiceRecordingStopped(
        state: _voiceState,
        path: path,
        elapsed: elapsed,
      ),
    );
  }

  /// Discard the current recording or review clip and reset to idle.
  Future<void> _cancelVoiceRecording() async {
    if (_voiceState.isIdle) return;
    _voiceTicker?.cancel();
    _voiceTicker = null;
    _voiceStartedAt = null;
    final wasRecording = _voiceState.isRecording;
    final path = _voiceState.recordingPath;
    _setHomeState(() => _voiceState = voice_display.voiceRecordingCancelled());
    try {
      if (wasRecording) {
        await _voiceRecorder.cancel();
      } else {
        // Reviewed-but-discarded clip: drop the temp file.
        await _voiceRecorder.discardClip(path);
      }
    } catch (_) {
      // Cleanup failures are non-fatal; the state is already reset.
    }
  }

  /// Upload and send the reviewed voice clip as an audio file attachment,
  /// reusing the shared file message pipeline (pending bubble + transfer).
  Future<void> _sendVoiceMessage() async {
    final room = _selectedRoom;
    final path = _voiceState.recordingPath;
    if (room == null || path == null || !_voiceState.canSend) return;

    _setHomeState(
      () => _voiceState = voice_display.voiceSendStarted(_voiceState),
    );

    Uint8List bytes;
    try {
      bytes = await _voiceRecorder.readClip(path);
    } catch (error) {
      if (!mounted) return;
      _setHomeState(
        () => _voiceState = voice_display.voiceSendFailed(
          state: _voiceState,
          failure: error,
        ),
      );
      return;
    }

    final filename = voice_display.voiceMessageFilename(DateTime.now());
    String? clientMessageId;
    try {
      final sent = await _messagesController.sendFileMessage(
        roomId: room.id,
        sender: _currentUser.toSummary(),
        filename: filename,
        sizeBytes: bytes.length,
        mimeType: voice_display.kVoiceMessageMimeType,
        readBytes: () async => bytes,
        onPending: (pending) {
          clientMessageId = pending.clientMessageId;
          if (!mounted) return;
          _setHomeState(
            () => _applyFileMessageStatePatch(
              _messagesController.patchPendingFileMessage(
                messages: _messages,
                fileTransfers: _fileTransfers,
                pending: pending,
              ),
            ),
          );
        },
        onProgress: (pending, {required sentBytes, required totalBytes}) {
          if (!mounted) return;
          final patch = _messagesController.patchFileTransferProgress(
            messages: _messages,
            fileTransfers: _fileTransfers,
            pending: pending,
            sentBytes: sentBytes,
            totalBytes: totalBytes,
          );
          if (patch == null) return;
          _setHomeState(() => _applyFileMessageStatePatch(patch));
        },
        onUploaded: (pending, attachment) {
          if (!mounted) return;
          _setHomeState(
            () => _applyFileMessageStatePatch(
              _messagesController.patchUploadedFileMessage(
                messages: _messages,
                fileTransfers: _fileTransfers,
                pending: pending,
                attachment: attachment,
              ),
            ),
          );
        },
      );
      if (!mounted || _selectedServerId != room.id) return;
      final activeClientMessageId = clientMessageId;
      if (activeClientMessageId != null) {
        _setHomeState(
          () => _applyFileMessageStatePatch(
            _messagesController.patchSentFileMessage(
              messages: _messages,
              fileTransfers: _fileTransfers,
              clientMessageId: activeClientMessageId,
              sent: sent,
            ),
          ),
        );
      }
      _setHomeState(() => _voiceState = voice_display.voiceSendSucceeded());
      unawaited(_voiceRecorder.discardClip(path));
      unawaited(_loadServers());
    } catch (error) {
      if (!mounted) return;
      final activeClientMessageId = clientMessageId;
      if (activeClientMessageId != null) {
        _setHomeState(
          () => _applyFileMessageStatePatch(
            _messagesController.patchFailedFileMessage(
              messages: _messages,
              fileTransfers: _fileTransfers,
              clientMessageId: activeClientMessageId,
              failure: error,
            ),
          ),
        );
      }
      // Keep the clip on disk and stay in review so the user can press send
      // again to retry the upload.
      _setHomeState(
        () => _voiceState = voice_display.voiceSendFailed(
          state: _voiceState,
          failure: error,
        ),
      );
    }
  }

  /// Stop the in-progress recording and immediately send it. Mirrors the
  /// "发送" control shown while recording.
  Future<void> _finishAndSendVoice() async {
    if (_voiceState.isRecording) {
      await _stopVoiceRecording();
      if (!mounted) return;
    }
    if (_voiceState.canSend) {
      await _sendVoiceMessage();
    }
  }

  /// Apply a [FileMessageStatePatch] to the local message + transfer maps.
  void _applyFileMessageStatePatch(FileMessageStatePatch patch) {
    _messages = patch.messages;
    _fileTransfers = patch.fileTransfers;
  }
}
