part of 'home_shell.dart';

extension _HomeShellLayout on _HomeShellState {
  Widget _buildNarrowLayout(double width) {
    if (!_narrowContentOpen) {
      return _buildSidebar(width: width, openContentOnSelect: true);
    }

    return _buildContentPane();
  }

  Widget _buildContentPane() {
    if (_settingsOpen) {
      return SettingsPage(
        isSubWindow: true,
        api: _services.api,
        apiBaseUrl: widget.app.apiBaseUrl,
        stickerPackStore: widget.app.stickerPackStore,
        currentUser: _currentUser,
        onUserUpdated: _handleUserUpdated,
        onAccountDeleted: _logout,
        onClose: _closeSettings,
      );
    }

    if (_selectedServerId == null) return const HomeContent();
    if (_contentMode == _ContentMode.members && _selectedRoom != null) {
      return RoomMembersDialog(
        controller: _roomsController,
        room: _selectedRoom!,
        currentUser: _currentUser,
        initialLive: _live ?? _selectedRoom!.live,
        embedded: true,
        onClose: _openChat,
        onChanged: () => unawaited(_loadServers()),
      );
    }
    if (_contentMode == _ContentMode.roomSettings && _selectedRoom != null) {
      final room = _selectedRoom!;
      return RoomSettingsDialog(
        controller: _roomsController,
        room: room,
        currentUser: _currentUser,
        isInLive: _joinedLiveRoomId == room.id,
        onRoomUpdated: _applyManagedRoomUpdated,
        onLeaveLive: () async {
          if (_joinedLiveRoomId == room.id) await _leaveLive();
        },
        embedded: true,
        onClose: _openChat,
        onResult: (result) => _handleRoomSettingsResult(room.id, result),
      );
    }
    if (_contentMode == _ContentMode.live) {
      return LiveChannelPane(
        title: _roomTitle(_selectedRoom, _selectedServer),
        avatarUrl: _selectedRoom?.avatarUrl ?? _selectedServer?.avatarUrl,
        live: _live ?? _selectedRoom?.live,
        currentUser: _currentUser,
        loading: _loadingRoom,
        joined: _joinedLiveRoomId == _selectedServerId,
        joining: _joiningLive,
        micMuted: _micMuted,
        headphonesMuted: _headphonesMuted,
        voiceBlocked: _voiceBlocked,
        cameraOn: _cameraOn,
        screenSharing: _screenSharing,
        speakingUserIds: _liveSessionController.speakingIdentities,
        videoTracks: _liveSessionController.videoTracks,
        stageSelection: _liveStageSelections[_selectedServerId],
        onStageSelectionChanged: _setLiveStageSelection,
        onEnterFullScreen: _enterLiveFullScreen,
        onBackToChat: _openChat,
        onJoin: () => unawaited(_joinLive('live_panel')),
        onLeave: () => unawaited(_leaveLive()),
        onToggleMic: _voiceBlocked
            ? null
            : () => unawaited(_patchLiveState(micMuted: !_micMuted)),
        onToggleHeadphones: _toggleHeadphonesMute,
        onToggleCamera: () => unawaited(_toggleCamera()),
        onToggleShare: () => unawaited(_toggleScreenShare()),
      );
    }

    return ChatPane(
      currentUser: _currentUser,
      roomCard: _selectedServer,
      room: _selectedRoom,
      live: _live,
      messages: _messages,
      fileTransfers: _fileTransfers,
      loading: _loadingRoom,
      error: _roomError,
      sending: _sending,
      sendError: _sendError,
      composerController: _composerController,
      onSubmit: (value) => unawaited(_sendText(value)),
      onRetry: () => unawaited(_retryOpenSelectedRoom()),
      onOpenLiveChannel: _openLiveChannel,
      onOpenRoomMembers: () => unawaited(_openRoomMembers()),
      onOpenRoomSettings: () => unawaited(_openRoomSettings()),
    );
  }

  Widget _buildSidebar({
    required double width,
    required bool openContentOnSelect,
  }) {
    return HomeSidebar(
      width: width,
      currentUser: _currentUser,
      servers: _servers,
      selectedServerId: _selectedServerId,
      joinedLiveRoomId: _joinedLiveRoomId,
      loading: _loadingServers,
      error: _serverLoadError,
      settingsActive: _settingsOpen,
      includeWindowChromeOffset: false,
      onServerSelected: (server) =>
          _selectServer(server, openContent: openContentOnSelect),
      onOpenSettings: () => _toggleSettings(openContent: openContentOnSelect),
      onLogout: () => unawaited(_logout()),
    );
  }
}
