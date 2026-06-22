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

  void _setMicMutedLocally(bool muted, {bool syncVolume = true}) {
    if (syncVolume) {
      final volume = muted ? 0.0 : _restoredInputVolume();
      if (muted) {
        _rememberInputVolume(_liveSessionController.inputVolume);
      }
      unawaited(_liveSessionController.setInputVolume(volume));
    }
    unawaited(_liveSessionController.setMicMuted(muted));
    if (_micMuted != muted) {
      _setHomeState(() => _micMuted = muted);
    }
  }

  void _toggleMicMute() {
    final muted = !_micMuted;
    final unmuteHeadphones = !muted && _headphonesMuted;
    _setMicMutedLocally(muted);
    if (unmuteHeadphones) {
      _setHeadphonesMuted(false, patchState: false);
    }
    unawaited(
      _patchLiveState(
        micMuted: muted,
        headphonesMuted: unmuteHeadphones ? false : null,
        syncLiveKitMic: false,
      ),
    );
  }

  void _toggleHeadphonesMute() {
    final patch = liveOutputMuteToggled(headphonesMuted: _headphonesMuted);
    _setHeadphonesMuted(patch.headphonesMuted);
  }

  void _setHeadphonesMuted(
    bool muted, {
    bool syncVolume = true,
    bool patchState = true,
  }) {
    final headphonesChanged = _headphonesMuted != muted;
    final muteMic = muted && !_micMuted;
    if (!headphonesChanged && !muteMic) return;

    if (headphonesChanged && syncVolume) {
      final volume = muted ? 0.0 : _restoredOutputVolume();
      if (muted) {
        _rememberOutputVolume(_liveSessionController.outputVolume);
      }
      unawaited(_liveSessionController.setOutputVolume(volume));
    }
    if (muteMic) {
      _setMicMutedLocally(true);
    }
    if (headphonesChanged) {
      _setHomeState(() => _headphonesMuted = muted);
      unawaited(_liveSessionController.setOutputMuted(muted));
    }
    // Report the headphone state to the server so other participants see it on
    // the live snapshot. Best-effort: a failure here doesn't undo the local
    // mute, which already took effect on the LiveKit session above.
    if (patchState) {
      final micMutedPatch = muteMic || (!muted && _micMuted) ? true : null;
      unawaited(
        _patchLiveState(
          micMuted: micMutedPatch,
          headphonesMuted: headphonesChanged ? muted : null,
          syncLiveKitMic: micMutedPatch == null,
        ),
      );
    }
  }

  void _changeInputVolume(double volume) {
    final normalized = normalizedAudioVolume(volume);
    if (normalized == 0) {
      _rememberInputVolume(_liveSessionController.inputVolume);
    } else {
      _rememberInputVolume(normalized);
    }
    unawaited(_liveSessionController.setInputVolume(normalized));
    final muted = normalized == 0;
    if (!muted && _voiceBlocked) return;
    final micChanged = muted != _micMuted;
    if (micChanged) {
      _setMicMutedLocally(muted, syncVolume: false);
    }
    final unmuteHeadphones = !muted && _headphonesMuted;
    if (unmuteHeadphones) {
      _setHeadphonesMuted(false, patchState: false);
    }
    if (!micChanged && !unmuteHeadphones) return;
    unawaited(
      _patchLiveState(
        micMuted: micChanged ? muted : null,
        headphonesMuted: unmuteHeadphones ? false : null,
        syncLiveKitMic: false,
      ),
    );
  }

  void _changeOutputVolume(double volume) {
    final normalized = normalizedAudioVolume(volume);
    if (normalized == 0) {
      _rememberOutputVolume(_liveSessionController.outputVolume);
    } else {
      _rememberOutputVolume(normalized);
    }
    unawaited(_liveSessionController.setOutputVolume(normalized));
    _setHeadphonesMuted(normalized == 0, syncVolume: false);
  }

  void _changeScreenShareVolume(double volume) {
    unawaited(_liveSessionController.setScreenShareVolume(volume));
  }

  double _participantVoiceVolume(String userId) {
    unawaited(_restoreParticipantVoiceVolume(userId));
    return _liveSessionController.participantVoiceVolume(userId);
  }

  void _changeParticipantVoiceVolume(String userId, double volume) {
    unawaited(_setParticipantVoiceVolume(userId, volume));
  }

  void _toggleParticipantVoiceMute(String userId) {
    unawaited(_toggleParticipantVoiceMuted(userId));
  }

  Future<void> _restoreParticipantVoiceVolume(String userId) async {
    final changed = await _liveSessionController.restoreParticipantVoiceVolume(
      userId,
    );
    if (!changed || !mounted) return;
    _setHomeState(() {});
  }

  Future<void> _setParticipantVoiceVolume(String userId, double volume) async {
    await _liveSessionController.setParticipantVoiceVolume(userId, volume);
    if (!mounted) return;
    _setHomeState(() {});
  }

  Future<void> _toggleParticipantVoiceMuted(String userId) async {
    await _liveSessionController.toggleParticipantVoiceMuted(userId);
    if (!mounted) return;
    _setHomeState(() {});
  }

  bool _canRemoveLiveParticipant(LiveParticipant participant) {
    final room = _selectedRoom;
    if (room == null ||
        _busyLiveMemberRemovalIds.contains(participant.user.id)) {
      return false;
    }
    final managementPermission = room_display.roomManagementPermissionState(
      room: room,
      currentUser: _currentUser,
    );
    final permission = member_filter.roomMemberPermissionState(
      member: _roomMemberFromLiveParticipant(participant, room),
      currentUser: _currentUser,
      canEditCreatorOnly: managementPermission.canEditCreatorOnly,
      canManageMembers: room.isAdmin || _currentUser.isSuperuser,
      ownerUserId: room.createdBy?.id,
    );
    return permission.canRemoveMember;
  }

  Future<void> _removeLiveParticipant(LiveParticipant participant) async {
    final room = _selectedRoom;
    if (room == null || !_canRemoveLiveParticipant(participant)) return;
    final member = _roomMemberFromLiveParticipant(participant, room);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _LiveMemberRemoveConfirmDialog(member: member),
    );
    if (confirmed != true || !mounted) return;
    final userId = participant.user.id;
    if (_busyLiveMemberRemovalIds.contains(userId)) return;
    _setHomeState(() {
      _busyLiveMemberRemovalIds.add(userId);
      _roomError = null;
    });
    try {
      await _liveController.kickParticipant(roomId: room.id, userId: userId);
      if (!mounted) return;
      final patch = _liveController.removeUserFromLive(
        live: _live,
        rooms: _servers,
        roomId: room.id,
        userId: userId,
      );
      _setHomeState(() {
        _busyLiveMemberRemovalIds.remove(userId);
        _live = patch.live;
        _servers = patch.rooms;
        _roomError = null;
      });
    } catch (error) {
      if (!mounted) return;
      _setHomeState(() {
        _busyLiveMemberRemovalIds.remove(userId);
        _roomError = error.toString();
      });
    }
  }

  RoomMember _roomMemberFromLiveParticipant(
    LiveParticipant participant,
    RoomDetail room,
  ) {
    final role =
        participant.user.roomRole ??
        (participant.user.id == room.createdBy?.id ? 'owner' : 'member');
    return RoomMember(
      user: participant.user,
      role: role,
      joinedAt: participant.joinedAt,
      roomDisplayName: participant.user.roomDisplayName,
    );
  }

  void _syncSettingsAudioVolumeToLive(String kind, double volume) {
    if (kind == 'audioinput') {
      _changeInputVolume(volume);
      return;
    }
    if (kind == 'audiooutput') {
      _changeOutputVolume(volume);
    }
  }

  void _rememberInputVolume(double volume) {
    _lastInputVolumeBeforeMute = rememberedAudioVolume(volume);
  }

  void _rememberOutputVolume(double volume) {
    _lastOutputVolumeBeforeMute = rememberedAudioVolume(volume);
  }

  double _restoredInputVolume() {
    return restoredAudioVolume(_lastInputVolumeBeforeMute);
  }

  double _restoredOutputVolume() {
    return restoredAudioVolume(_lastOutputVolumeBeforeMute);
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

  Future<void> _restoreLiveAfterRealtimeReconnect(String roomId) async {
    if (_joiningLive || _joinedLiveRoomId != roomId) return;

    final previousMicMuted = _micMuted;
    final previousHeadphonesMuted = _headphonesMuted;
    final previousCameraOn = _cameraOn;
    final previousScreenSharing = _screenSharing;
    _setHomeState(() {
      _joiningLive = true;
      _roomError = null;
    });

    try {
      final result = await _liveController.joinLive(
        roomId: roomId,
        source: 'reconnect',
      );
      if (!mounted || _joinedLiveRoomId != roomId) return;

      final joinPatch = _liveController.patchJoinResult(
        rooms: _servers,
        result: result,
      );
      _setHomeState(() {
        _micMuted = joinPatch.micMuted;
        _cameraOn = joinPatch.cameraOn;
        _screenSharing = joinPatch.screenSharing;
        _voiceBlocked = joinPatch.voiceBlocked;
        _servers = joinPatch.rooms;
        if (_selectedServerId == result.live.roomId) {
          _live = joinPatch.live;
        }
      });

      try {
        await _liveSessionController.connectWithRetry(
          result,
          isCancelled: () => !mounted || _joinedLiveRoomId != roomId,
        );
      } catch (error) {
        if (mounted) _setHomeState(() => _roomError = error.toString());
        return;
      }
      if (!mounted || _joinedLiveRoomId != roomId) return;

      final canPublish = !joinPatch.voiceBlocked;
      await _restoreLiveParticipantState(
        roomId: roomId,
        micMuted: canPublish ? previousMicMuted : true,
        headphonesMuted: previousHeadphonesMuted,
        cameraOn: canPublish && previousCameraOn,
        screenSharing:
            canPublish &&
            previousScreenSharing &&
            _liveSessionController.isScreenSharing,
      );
    } catch (error) {
      if (mounted) _setHomeState(() => _roomError = error.toString());
    } finally {
      if (mounted) _setHomeState(() => _joiningLive = false);
    }
  }

  Future<void> _restoreLiveParticipantState({
    required String roomId,
    required bool micMuted,
    required bool headphonesMuted,
    required bool cameraOn,
    required bool screenSharing,
  }) async {
    var restoredCameraOn = cameraOn;
    try {
      await _liveSessionController.setOutputMuted(headphonesMuted);
    } catch (_) {}
    try {
      await _liveSessionController.setCameraEnabled(restoredCameraOn);
    } catch (error) {
      restoredCameraOn = false;
      if (mounted) _setHomeState(() => _roomError = error.toString());
    }
    if (!screenSharing && _liveSessionController.isScreenSharing) {
      try {
        await _liveSessionController.setScreenShareEnabled(false);
      } catch (_) {}
    }

    final liveKitMicFuture = _liveSessionController
        .setMicMuted(micMuted)
        .catchError((_) {});
    try {
      final participant = await _liveController.updateMyState(
        roomId: roomId,
        micMuted: micMuted,
        headphonesMuted: headphonesMuted,
        cameraOn: restoredCameraOn,
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
      if (!mounted || _joinedLiveRoomId != roomId) return;
      final updateSelectedLive = _selectedServerId == roomId;
      final patch = _liveController.patchStateUpdate(
        live: updateSelectedLive ? _live : null,
        participant: participant,
      );
      _setHomeState(() {
        _micMuted = patch.micMuted;
        _headphonesMuted = participant.headphonesMuted;
        _cameraOn = patch.cameraOn;
        _screenSharing = patch.screenSharing;
        _voiceBlocked = patch.voiceBlocked;
        if (updateSelectedLive) _live = patch.live;
      });
    } catch (error) {
      await liveKitMicFuture;
      if (!mounted || isBenignGoneLiveStatePatch(error)) return;
      _setHomeState(() => _roomError = error.toString());
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
    bool syncLiveKitMic = true,
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
      final liveKitMicFuture = !syncLiveKitMic || micMuted == null
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

class _LiveMemberRemoveConfirmDialog extends StatelessWidget {
  const _LiveMemberRemoveConfirmDialog({required this.member});

  final RoomMember member;

  @override
  Widget build(BuildContext context) {
    return DialogFrame(
      title: '踢出语音频道',
      icon: Icons.warning_amber_outlined,
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        Button(
          tone: ButtonTone.danger,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('踢出'),
        ),
      ],
      child: Text(
        '确定要将 ${member_filter.roomMemberDisplayName(member)} 踢出语音频道吗？',
        style: UiTypography.body,
      ),
    );
  }
}
