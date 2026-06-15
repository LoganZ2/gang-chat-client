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

    if (_contentMode == _ContentMode.createRoom) {
      return RoomSettingsDialog.create(
        controller: _roomsController,
        currentUser: _currentUser,
        embedded: true,
        onClose: _closeCreateRoom,
        onResult: _handleCreateRoomResult,
      );
    }

    if (_contentMode == _ContentMode.notifications) {
      return HomeNotificationsPane(
        invites: _notificationInvites,
        applications: _notificationApplications,
        currentUser: _currentUser,
        loading: _loadingNotifications,
        error: _notificationError,
        busyInviteId: _busyNotificationInviteId,
        busyApplicationId: _busyNotificationApplicationId,
        onClose: _closeNotifications,
        onRefresh: () => unawaited(_loadNotifications()),
        onReviewInvite: _reviewNotificationInvite,
        onWithdrawApplication: _withdrawNotificationApplication,
        onOpenRoom: _openNotificationRoom,
      );
    }

    if (_selectedServerId == null) return const HomeContent();
    if (_contentMode == _ContentMode.members && _selectedRoom != null) {
      return RoomMembersDialog(
        controller: _roomsController,
        room: _selectedRoom!,
        currentUser: _currentUser,
        initialLive: _live ?? _selectedRoom!.live,
        reloadToken: _membersReloadToken,
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
        musicBox: _musicBox,
        musicBoxOpen: _musicBoxOpen,
        musicBoxSearchController: _musicBoxSearchController,
        musicBoxSearchResults: _musicBoxSearchResults,
        musicBoxSearching: _musicBoxSearching,
        musicBoxSearchError: _musicBoxSearchError,
        musicBoxSource: _musicBoxSource,
        onToggleMusicBox: _toggleMusicBoxPanel,
        onMusicBoxTogglePlayback: _toggleMusicBoxPlayback,
        onMusicBoxSkip: () => unawaited(_controlMusicBox('skip')),
        onMusicBoxQueueResult: (result) =>
            unawaited(_queueMusicBoxTrack(result)),
        onMusicBoxRemoveItem: (item) => unawaited(_removeMusicBoxItem(item)),
        onMusicBoxSourceChanged: _changeMusicBoxSource,
        musicBoxVolume: _liveSessionController.musicBoxVolume,
        onMusicBoxVolumeChanged: (volume) =>
            unawaited(_liveSessionController.setMusicBoxVolume(volume)),
      );
    }

    return ChatPane(
      currentUser: _currentUser,
      roomCard: _selectedServer,
      room: _selectedRoom,
      live: _live,
      messages: _messages,
      fileTransfers: _fileTransfers,
      fileDownloads: _fileDownloads,
      downloadActions: ChatFileDownloadActions(
        onDownload: (message, attachment, index, resolvedUrl) => unawaited(
          _downloadAttachment(
            message: message,
            attachment: attachment,
            index: index,
            resolvedUrl: resolvedUrl,
          ),
        ),
        onPause: _pauseDownload,
        onResume: _resumeDownload,
        onCancel: _cancelDownload,
        onDismiss: _dismissDownload,
      ),
      voicePlaybackActions: ChatVoicePlaybackActions(
        activeMessageId: _voicePlayback.playing
            ? _voicePlayback.activeMessageId
            : null,
        activePosition: _voicePlayback.position,
        activeDuration: _voicePlayback.duration,
        onToggle: (messageId, resolvedUrl) => unawaited(
          _toggleVoicePlayback(messageId: messageId, resolvedUrl: resolvedUrl),
        ),
      ),
      loading: _loadingRoom,
      error: _roomError,
      sending: _sending,
      sendError: _sendError,
      composerController: _composerController,
      composerPanelController: _composerPanelController,
      stickerPanel: _stickerPanelState,
      voiceState: _voiceState,
      composerAttachments: _stagedAttachmentViews,
      fileActionHighlighted:
          _pickingAttachments || _stagedAttachments.isNotEmpty,
      onSubmit: (value) => unawaited(_sendText(value)),
      onSendSticker: (sticker) => unawaited(_sendSticker(sticker)),
      onLoadStickers: () => unawaited(_loadStickerPacks(forceReload: true)),
      onRefreshStickers: () => unawaited(_loadStickerPacks(forceReload: true)),
      onStickerSourceChanged: _changeStickerSource,
      onStartVoice: () => unawaited(_startVoiceRecording()),
      onSendVoice: () => unawaited(_finishAndSendVoice()),
      onCancelVoice: () => unawaited(_cancelVoiceRecording()),
      onPickFile: () => unawaited(_pickAttachments()),
      onPasteFiles: _pasteAttachments,
      onRemoveAttachment: _removeAttachment,
      onRetryAttachment: _retryAttachment,
      onRetry: () => unawaited(_retryOpenSelectedRoom()),
      onOpenLiveChannel: _openLiveChannel,
      onOpenRoomMembers: () => unawaited(_openRoomMembers()),
      onOpenRoomSettings: () => unawaited(_openRoomSettings()),
      onResolveSenderProfile: _resolveSenderProfile,
      composerDropKey: _composerDropKey,
    );
  }

  Widget _buildSidebar({
    required double width,
    required bool openContentOnSelect,
  }) {
    return HomeSidebar(
      width: width,
      currentUser: _currentUser,
      servers: _sidebarServers,
      selectedServerId: _selectedServerId,
      joinedLiveRoomId: _joinedLiveRoomId,
      searchQuery: _filteringSidebarBySearch ? _searchQuery : '',
      loading: _loadingServers || _loadingSidebarSearch,
      error: _serverLoadError,
      settingsActive: _settingsOpen,
      createRoomActive:
          !_settingsOpen && _contentMode == _ContentMode.createRoom,
      notificationsActive:
          !_settingsOpen && _contentMode == _ContentMode.notifications,
      logoutActive: _logoutConfirming,
      hasPendingNotifications: _hasPendingRoomInvites,
      includeWindowChromeOffset: false,
      onServerSelected: (server) =>
          _selectServer(server, openContent: openContentOnSelect),
      onCreateRoom: () => _openCreateRoom(openContent: openContentOnSelect),
      onOpenNotifications: () =>
          _openNotifications(openContent: openContentOnSelect),
      onOpenSettings: () => _toggleSettings(openContent: openContentOnSelect),
      onLogout: () => unawaited(_confirmLogout()),
    );
  }
}
