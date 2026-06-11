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
      case 'room_role_changed':
        _applyRoomRoleChanged(event.data);
        break;
      case 'room_join_requests_updated':
        _applyRoomJoinRequestsUpdated(event.data);
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

  /// Applies a `room_role_changed` event for the affected member (the current
  /// user). The shared room snapshot omits `my_role`, so this is the only way a
  /// promote/demote reaches the open room without a manual refetch. Updates the
  /// selected room's membership role in place so permission-gated UI (manage,
  /// review join requests) re-evaluates immediately.
  void _applyRoomRoleChanged(Map<String, dynamic> data) {
    final patch = _roomsController.patchRoomRoleChanged(
      selectedRoom: _selectedRoom,
      data: data,
    );
    if (patch == null || !mounted) return;
    _setHomeState(() {
      _selectedRoom = patch.selectedRoom;
      // A role change can flip whether the user may review join requests, so
      // bump the members reload token to re-pull that list if the panel's open.
      _membersReloadToken++;
    });
  }

  /// Applies a `room_join_requests_updated` event: the pending join-request set
  /// for [roomId] changed (new request, or one approved/denied elsewhere). If
  /// it targets the open room, nudge the members panel to reload its request
  /// list via the reload token. Also refresh the notification badge, since a
  /// new request may need the current user's attention.
  void _applyRoomJoinRequestsUpdated(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    if (!mounted) return;
    unawaited(_refreshPendingRoomInviteBadge());
    if (roomId == null || roomId != _selectedServerId) return;
    _setHomeState(() => _membersReloadToken++);
  }
}
