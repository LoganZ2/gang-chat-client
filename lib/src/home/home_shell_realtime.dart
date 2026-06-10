part of 'home_shell.dart';

extension _HomeShellRealtime on _HomeShellState {
  void _startRealtime() {
    final previous = _realtimeEvents;
    if (previous != null) unawaited(previous.cancel());

    final realtime = _services.realtime;
    realtime.onReconnect = _onRealtimeReconnect;
    _realtimeEvents = realtime.events.listen(_onRealtimeEvent);
    unawaited(realtime.start());
  }

  void _onRealtimeReconnect() {
    if (!mounted) return;
    unawaited(_loadServersSilently());
    final selected = _selectedServerId;
    if (selected != null) unawaited(_refreshLiveSilently(selected));
  }

  Future<void> _loadServersSilently() async {
    try {
      final servers = await _roomsController.loadRooms();
      if (!mounted) return;
      _setHomeState(() {
        _servers = _roomsController
            .patchRoomCardsRefreshed(rooms: servers)
            .rooms;
      });
    } catch (_) {}
  }

  Future<void> _refreshLiveSilently(String roomId) async {
    try {
      final live = await _roomsController.getLiveState(roomId);
      if (!mounted) return;
      final patch = _roomsController.patchSelectedLiveRefreshed(
        live: live,
        selectedRoomId: _selectedServerId,
      );
      if (patch == null) return;
      _setHomeState(() => _live = patch.live);
    } catch (_) {}
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    switch (event.type) {
      case 'live_participant_joined':
      case 'live_participant_left':
      case 'live_participant_updated':
      case 'live_participant_moderated':
      case 'live_room_finished':
        _applyLiveSnapshot(event.data);
        break;
      case 'room_added':
        _applyRoomAdded(event.data);
        break;
      case 'room_updated':
        _applyRoomUpdated(event.data);
        break;
      case 'room_deleted':
        _applyRoomDeleted(event.data);
        break;
      case 'room_invites_updated':
        _applyRoomInvitesUpdated();
        break;
      case 'room_applications_updated':
        _applyRoomApplicationsUpdated();
        break;
      case 'music_box_changed':
        _onMusicBoxChanged(event.data);
        break;
      default:
        break;
    }
  }

  void _applyLiveSnapshot(Map<String, dynamic> data) {
    final patch = _roomsController.patchLiveSnapshot(
      rooms: _servers,
      selectedRoomId: _selectedServerId,
      data: data,
      joinedLiveRoomId: _joinedLiveRoomId,
      currentUserId: _currentUser.id,
      previousLive: _live,
    );
    if (patch == null || !mounted) return;
    _setHomeState(() {
      _servers = patch.rooms;
      if (patch.selectedLive != null) _live = patch.selectedLive;
    });
  }

  void _applyRoomAdded(Map<String, dynamic> data) {
    final room = _roomsController.roomCardFromSnapshot(data);
    if (room == null || !mounted) return;
    _setHomeState(() {
      _servers = _roomsController
          .patchRoomCardUpserted(rooms: _servers, room: room)
          .rooms;
    });
  }

  void _applyRoomUpdated(Map<String, dynamic> data) {
    final room = _roomsController.roomCardFromSnapshot(data);
    if (room == null || !mounted) return;
    _setHomeState(() {
      _servers = _roomsController
          .patchRoomCardUpdated(rooms: _servers, incoming: room)
          .rooms;
    });
  }

  void _applyRoomDeleted(Map<String, dynamic> data) {
    final patch = _roomsController.patchRoomDeleted(
      rooms: _servers,
      selectedRoomId: _selectedServerId,
      selectedRoom: _selectedRoom,
      selectedRoomHasPendingJoinRequests: false,
      messages: _messages,
      live: _live,
      livePanelOpen: _contentMode == _ContentMode.live,
      settingsOpen: _settingsOpen,
      joinedLiveRoomId: _joinedLiveRoomId,
      data: data,
    );
    if (patch == null || !mounted) return;
    _setHomeState(() {
      _servers = patch.rooms;
      _selectedServerId = patch.selectedRoomId;
      _selectedRoom = patch.selectedRoom;
      _messages = patch.messages;
      _live = patch.live;
      _settingsOpen = patch.settingsOpen;
      _contentMode = patch.livePanelOpen
          ? _ContentMode.live
          : _ContentMode.chat;
      _joinedLiveRoomId = patch.joinedLiveRoomId;
      if (patch.wasSelected) {
        _fileTransfers = const {};
        _roomError = null;
        _sendError = null;
        _narrowContentOpen = false;
        _resetMusicBox();
      }
    });
    if (patch.shouldDisconnectLive) {
      unawaited(_liveSessionController.disconnect());
    }
  }
}
