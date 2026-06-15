part of 'home_shell.dart';

extension _HomeShellLiveActions on _HomeShellState {
  void _setLiveStageSelection(LiveStageSelection? selection) {
    final roomId = _selectedServerId;
    if (roomId == null) return;
    _setHomeState(() => _liveStageSelections[roomId] = selection);
  }

  void _enterLiveFullScreen(LiveVideoTrack track) {
    _setHomeState(() => _fullScreenLiveTrack = track);
    unawaited(_setSystemFullScreen(true));
  }

  void _exitLiveFullScreen() {
    _setHomeState(() => _fullScreenLiveTrack = null);
    unawaited(_setSystemFullScreen(false));
  }

  Future<void> _setSystemFullScreen(bool fullScreen) async {
    if (!_supportsWindowManagement) return;
    try {
      if (await windowManager.isFullScreen() != fullScreen) {
        await windowManager.setFullScreen(fullScreen);
      }
    } catch (_) {}
  }

  LiveVideoTrack? _resolveFullScreenLiveTrack() {
    final selected = _fullScreenLiveTrack;
    if (selected == null) return null;
    for (final track in _liveSessionController.videoTracks) {
      if (track.identity == selected.identity &&
          track.isScreenShare == selected.isScreenShare) {
        return track;
      }
    }
    return null;
  }

  void _onLiveSessionChanged() {
    if (!mounted) return;
    if (live_display.shouldPatchEndedLocalScreenShare(
      localScreenSharing: _screenSharing,
      sessionScreenSharing: _liveSessionController.isScreenSharing,
      joinedLiveRoomId: _joinedLiveRoomId,
      selectedRoomId: _selectedServerId,
    )) {
      unawaited(_patchLiveState(screenSharing: false));
    }
    if (_fullScreenLiveTrack != null && _resolveFullScreenLiveTrack() == null) {
      _fullScreenLiveTrack = null;
      unawaited(_setSystemFullScreen(false));
    }
    _setHomeState(() {});
  }

  void _onForciblyRemovedFromLive() {
    if (!mounted) return;
    final patch = _liveController.patchLocalDeparture(
      live: _live,
      rooms: _servers,
      joinedLiveRoomId: _joinedLiveRoomId,
      userId: _currentUser.id,
      joiningLive: false,
    );
    _setHomeState(() => _applyLiveLocalDeparturePatch(patch));
    unawaited(_liveSessionController.disconnect());
  }

  void _onPublishPermissionChanged(bool canPublish) {
    if (!mounted) return;
    final patch = _liveController.patchPublishPermission(
      canPublish: canPublish,
      micMuted: _micMuted,
    );
    _setHomeState(() => _applyLivePublishPermissionPatch(patch));
  }

  void _applyLiveJoinStatePatch(LiveJoinStatePatch patch) {
    _joinedLiveRoomId = patch.joinedLiveRoomId;
    _joiningLive = patch.joiningLive;
    _contentMode = patch.livePanelOpen ? _ContentMode.live : _contentMode;
    _roomError = patch.error;
  }

  void _applyLiveJoinPreviousRoomDisconnectedPatch(
    LiveJoinPreviousRoomDisconnectedPatch patch,
  ) {
    _live = patch.live;
    _servers = patch.rooms;
    _joinedLiveRoomId = patch.joinedLiveRoomId;
    _joiningLive = patch.joiningLive;
    _contentMode = patch.livePanelOpen ? _ContentMode.live : _contentMode;
    _roomError = patch.error;
  }

  void _applyLiveLocalDeparturePatch(LiveLocalDeparturePatch patch) {
    _live = patch.live;
    _servers = patch.rooms;
    _joinedLiveRoomId = patch.joinedLiveRoomId;
    _joiningLive = patch.joiningLive;
    _cameraOn = patch.cameraOn;
    _screenSharing = patch.screenSharing;
    _voiceBlocked = patch.voiceBlocked;
  }

  void _applyLivePublishPermissionPatch(LivePublishPermissionPatch patch) {
    _voiceBlocked = patch.voiceBlocked;
    _micMuted = patch.micMuted;
  }

  void _applyLiveJoinResultPatch(LiveJoinResultPatch patch) {
    _micMuted = patch.micMuted;
    _cameraOn = patch.cameraOn;
    _screenSharing = patch.screenSharing;
    _voiceBlocked = patch.voiceBlocked;
    _live = patch.live;
    _servers = patch.rooms;
  }

  void _applyLiveStateUpdatePatch(LiveStateUpdatePatch patch) {
    _micMuted = patch.micMuted;
    _cameraOn = patch.cameraOn;
    _screenSharing = patch.screenSharing;
    _voiceBlocked = patch.voiceBlocked;
    _live = patch.live;
  }

  void _toggleHeadphonesMute() {
    final patch = liveOutputMuteToggled(headphonesMuted: _headphonesMuted);
    _setHomeState(() => _headphonesMuted = patch.headphonesMuted);
    unawaited(_liveSessionController.setOutputMuted(patch.headphonesMuted));
    // Report the headphone state to the server so other participants see it on
    // the live snapshot. Best-effort: a failure here doesn't undo the local
    // mute, which already took effect on the LiveKit session above.
    unawaited(_patchLiveState(headphonesMuted: patch.headphonesMuted));
  }

  Future<void> _joinLive(String source) async {
    final room = _selectedRoom;
    if (room == null || _joiningLive) return;

    _setHomeState(
      () => _applyLiveJoinStatePatch(
        _liveController.patchJoinStarted(joinedLiveRoomId: _joinedLiveRoomId),
      ),
    );

    final previousLiveRoomId = joinedLiveRoomToDisconnectBeforeJoin(
      joinedLiveRoomId: _joinedLiveRoomId,
      targetRoomId: room.id,
    );
    if (previousLiveRoomId != null) {
      await _notifyLiveLeft(previousLiveRoomId);
      await _liveSessionController.disconnect();
      if (mounted) {
        _setHomeState(() {
          _applyLiveJoinPreviousRoomDisconnectedPatch(
            _liveController.patchJoinPreviousRoomDisconnected(
              live: _live,
              rooms: _servers,
              previousRoomId: previousLiveRoomId,
              userId: _currentUser.id,
              livePanelOpen: true,
              error: _roomError,
            ),
          );
        });
      }
    }

    try {
      final result = await _liveController.joinLive(
        roomId: room.id,
        source: source,
      );
      if (!mounted) return;
      _setHomeState(
        () => _applyLiveJoinResultPatch(
          _liveController.patchJoinResult(rooms: _servers, result: result),
        ),
      );
      try {
        await _liveSessionController.connectWithRetry(
          result,
          isCancelled: () => !mounted,
        );
      } catch (error) {
        if (mounted) _setHomeState(() => _roomError = error.toString());
        return;
      }
      if (!mounted) return;
      _setHomeState(
        () => _applyLiveJoinStatePatch(
          _liveController.patchJoinConnected(
            roomId: room.id,
            livePanelOpen: true,
            error: _roomError,
          ),
        ),
      );
      // Join with the microphone live by default. The server seeds new
      // participants as muted, so unmute through the normal patch path (which
      // syncs LiveKit, the server, and the UI) unless the user can't publish.
      if (_micMuted && !_voiceBlocked) {
        await _patchLiveState(micMuted: false);
      }
    } catch (error) {
      if (mounted) _setHomeState(() => _roomError = error.toString());
    } finally {
      if (mounted) {
        _setHomeState(
          () => _applyLiveJoinStatePatch(
            _liveController.patchJoinFinished(
              joinedLiveRoomId: _joinedLiveRoomId,
              livePanelOpen: true,
              error: _roomError,
            ),
          ),
        );
      }
    }
  }

  Future<void> _leaveLive() async {
    final roomId = _joinedLiveRoomId;
    if (roomId == null) return;
    final patch = _liveController.patchLocalDeparture(
      live: _live,
      rooms: _servers,
      joinedLiveRoomId: roomId,
      userId: _currentUser.id,
      joiningLive: true,
    );
    _setHomeState(() => _applyLiveLocalDeparturePatch(patch));
    try {
      await _notifyLiveLeft(roomId);
      await _liveSessionController.disconnect();
    } catch (error) {
      if (mounted) _setHomeState(() => _roomError = error.toString());
    } finally {
      if (mounted) {
        _setHomeState(
          () => _applyLiveJoinStatePatch(
            _liveController.patchJoinFinished(
              joinedLiveRoomId: _joinedLiveRoomId,
              livePanelOpen: true,
              error: _roomError,
            ),
          ),
        );
      }
    }
  }

  Future<void> _notifyLiveLeft(String roomId) async {
    try {
      await _liveController.leaveLive(roomId: roomId);
    } catch (error) {
      if (!mounted || isBenignGoneLiveStatePatch(error)) return;
      _setHomeState(() => _roomError = error.toString());
    }
  }

  Future<void> _patchLiveState({
    bool? micMuted,
    bool? headphonesMuted,
    bool? cameraOn,
    bool? screenSharing,
  }) async {
    final roomId = _joinedLiveRoomId;
    if (roomId == null ||
        !canPatchSelectedLiveState(
          joinedLiveRoomId: roomId,
          selectedRoomId: _selectedServerId,
        )) {
      return;
    }

    try {
      final liveKitMicFuture = micMuted == null
          ? Future<void>.value()
          : _liveSessionController.setMicMuted(micMuted).catchError((_) {});
      final participant = await _liveController.updateMyState(
        roomId: roomId,
        micMuted: micMuted,
        headphonesMuted: headphonesMuted,
        cameraOn: cameraOn,
        screenSharing: screenSharing,
      );
      await liveKitMicFuture;
      if (shouldSyncLiveKitMicAfterServerPatch(
        requestedMicMuted: micMuted,
        serverMicMuted: participant.micMuted,
      )) {
        try {
          await _liveSessionController.setMicMuted(participant.micMuted);
        } catch (_) {}
      }
      if (!mounted) return;
      _setHomeState(
        () => _applyLiveStateUpdatePatch(
          _liveController.patchStateUpdate(
            live: _live,
            participant: participant,
          ),
        ),
      );
    } catch (error) {
      if (!mounted || isBenignGoneLiveStatePatch(error)) return;
      _setHomeState(() => _roomError = error.toString());
    }
  }

  Future<void> _toggleCamera() async {
    final roomId = _joinedLiveRoomId;
    if (roomId == null ||
        !canPatchSelectedLiveState(
          joinedLiveRoomId: roomId,
          selectedRoomId: _selectedServerId,
        )) {
      return;
    }
    final enable = !_cameraOn;
    try {
      await _liveSessionController.setCameraEnabled(enable);
    } catch (error) {
      if (mounted) _setHomeState(() => _roomError = error.toString());
      return;
    }
    await _patchLiveState(cameraOn: enable);
  }

  Future<void> _toggleScreenShare() async {
    final roomId = _joinedLiveRoomId;
    if (roomId == null ||
        !canPatchSelectedLiveState(
          joinedLiveRoomId: roomId,
          selectedRoomId: _selectedServerId,
        )) {
      return;
    }

    if (_screenSharing) {
      try {
        await _liveSessionController.setScreenShareEnabled(false);
      } catch (_) {}
      await _patchLiveState(screenSharing: false);
      return;
    }

    final source = await showDialog<ScreenSource>(
      context: context,
      builder: (context) => LiveScreenSharePicker(
        loadSources: _liveSessionController.listScreenSources,
        refreshThumbnails: _liveSessionController.refreshScreenSourceThumbnails,
      ),
    );
    if (source == null || !mounted) return;
    if (!canApplyPickedScreenShareSource(
      pickedForRoomId: roomId,
      joinedLiveRoomId: _joinedLiveRoomId,
      selectedRoomId: _selectedServerId,
    )) {
      return;
    }

    try {
      await _liveSessionController.setScreenShareEnabled(
        true,
        sourceId: source.id,
      );
    } catch (error) {
      if (mounted) _setHomeState(() => _roomError = error.toString());
      return;
    }
    await _patchLiveState(screenSharing: true);
  }
}
