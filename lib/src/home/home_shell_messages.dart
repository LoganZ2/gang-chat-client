part of 'home_shell.dart';

extension _HomeShellMessages on _HomeShellState {
  Future<void> _sendText(String value) async {
    final body = value.trimRight();
    // When files are staged, the message goes out as a file message carrying
    // them as attachments (the body rides along). Otherwise it's plain text.
    if (_stagedAttachments.isNotEmpty) {
      await _sendStagedAttachments(body);
      return;
    }
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

  // --- Composer attachments ---------------------------------------------
  //
  // Files picked here upload immediately (eagerly), so by send time the assets
  // are usually already in hand and the message goes out in one round trip. The
  // message itself still rides the shared composed-send path as a `file` message
  // carrying the assets as attachments — a workaround until the backend offers a
  // single multipart "send message with files" call. Eager upload can leave an
  // orphan asset behind if the user removes a chip or never sends; that cleanup
  // is the backend's responsibility (asset TTL / unreferenced sweep).

  /// View models for the chips shown above the composer input.
  List<composer_attachment.ComposerAttachmentView> get _stagedAttachmentViews {
    return [
      for (final entry in _stagedAttachments)
        composer_attachment.ComposerAttachmentView(
          id: entry.id,
          filename: entry.file.name,
          status: entry.status,
          sizeBytes: entry.sizeBytes,
          mimeType: entry.file.mimeType,
          progress: entry.progress,
        ),
    ];
  }

  /// Open the system file picker (multi-select), stage the chosen files on the
  /// composer, and start uploading each one right away. Does not send anything;
  /// the finished assets go out with the next message.
  Future<void> _pickAttachments() async {
    if (_selectedRoom == null) return;
    List<SelectedFile> files;
    try {
      files = await _fileSelectionService.openFiles();
    } catch (error) {
      if (!mounted) return;
      _setHomeState(() => _sendError = error.toString());
      return;
    }
    if (!mounted || files.isEmpty) return;

    final fresh = <_StagedAttachment>[];
    _setHomeState(() {
      for (final file in files) {
        final entry = _StagedAttachment(
          id: _messagesController.mintClientId('att'),
          file: file,
        );
        _stagedAttachments.add(entry);
        fresh.add(entry);
      }
      _sendError = null;
    });

    for (final entry in fresh) {
      unawaited(_uploadStagedAttachment(entry));
    }
  }

  /// Upload (or re-upload) a single staged file, streaming progress into its
  /// chip. Safe to call again after a failure to retry.
  Future<void> _uploadStagedAttachment(_StagedAttachment entry) async {
    if (!_stagedAttachments.contains(entry)) return;
    _setHomeState(() {
      entry.status = composer_attachment.ComposerAttachmentStatus.uploading;
      entry.progress = null;
      entry.error = null;
    });

    try {
      final bytes = await entry.file.readAsBytes();
      // Drop out if the chip was removed (or the room switched) while reading.
      if (!_stagedAttachments.contains(entry)) return;
      final asset = await _messagesController.uploadFileAsset(
        bytes: bytes,
        filename: entry.file.name,
        controller: entry.uploadController,
        onProgress: ({required sentBytes, required totalBytes}) {
          if (!mounted || !_stagedAttachments.contains(entry)) return;
          _setHomeState(() {
            entry.sizeBytes = totalBytes;
            entry.progress = totalBytes > 0 ? sentBytes / totalBytes : null;
          });
        },
      );
      if (!_stagedAttachments.contains(entry)) return;
      _setHomeState(() {
        entry.asset = asset;
        entry.sizeBytes = asset.sizeBytes;
        entry.progress = 1;
        entry.status = composer_attachment.ComposerAttachmentStatus.uploaded;
      });
    } on UploadCancelledException {
      // Cancellation means the chip was removed; nothing left to update.
    } catch (error) {
      if (!mounted || !_stagedAttachments.contains(entry)) return;
      _setHomeState(() {
        entry.error = error;
        entry.status = composer_attachment.ComposerAttachmentStatus.failed;
      });
    }
  }

  /// Retry a staged upload that previously failed.
  void _retryAttachment(String id) {
    final entry = _stagedAttachmentById(id);
    if (entry == null || entry.isUploaded) return;
    unawaited(_uploadStagedAttachment(entry));
  }

  /// Drop a single staged file, cancelling its upload if still in flight.
  void _removeAttachment(String id) {
    final index = _stagedAttachments.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final entry = _stagedAttachments[index];
    entry.uploadController.cancel();
    _setHomeState(() => _stagedAttachments.removeAt(index));
  }

  _StagedAttachment? _stagedAttachmentById(String id) {
    for (final entry in _stagedAttachments) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Send the staged files as one composed message alongside any typed [body].
  /// Uploads were kicked off at pick time, so this waits for any still in
  /// flight, refuses to send while uploads are failed, then collects the
  /// finished assets.
  Future<void> _sendStagedAttachments(String body) async {
    final room = _selectedRoom;
    if (room == null || _stagedAttachments.isEmpty || _sending) return;

    // Wait for any uploads still in flight before deciding what to send.
    final pending = _stagedAttachments
        .where((entry) => entry.status ==
            composer_attachment.ComposerAttachmentStatus.uploading)
        .toList();
    if (pending.isNotEmpty) {
      _setHomeState(() {
        _sending = true;
        _sendError = null;
      });
      await Future.wait(pending.map(_awaitUpload));
      if (!mounted || _selectedServerId != room.id) {
        if (mounted) _setHomeState(() => _sending = false);
        return;
      }
      _setHomeState(() => _sending = false);
    }

    // Refuse to send a partial batch; surface the failures for retry/removal.
    if (_stagedAttachments.any((entry) => entry.status ==
        composer_attachment.ComposerAttachmentStatus.failed)) {
      _setHomeState(() => _sendError = '部分文件上传失败，请重试或移除后再发送');
      return;
    }

    final attachments = [
      for (final entry in _stagedAttachments)
        if (entry.asset != null)
          _messagesController.fileAttachment(
            name: entry.file.name,
            asset: entry.asset!,
          ),
    ];
    if (attachments.isEmpty) return;

    // Hand off to the shared composed send (which owns the pending/sent/failed
    // bubble and the _sending flag).
    _setHomeState(() => _stagedAttachments.clear());
    await _sendComposed(
      body: body,
      type: 'file',
      attachments: attachments,
      clearComposer: true,
    );
  }

  /// Block until [entry]'s in-flight upload settles (success or failure).
  Future<void> _awaitUpload(_StagedAttachment entry) async {
    while (mounted &&
        _stagedAttachments.contains(entry) &&
        entry.status == composer_attachment.ComposerAttachmentStatus.uploading) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
