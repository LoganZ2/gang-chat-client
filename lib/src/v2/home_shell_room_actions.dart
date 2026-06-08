part of 'home_shell.dart';

extension _HomeShellRoomActions on _HomeShellState {
  Future<void> _loadServers() async {
    _setHomeState(() {
      _loadingServers = true;
      _serverLoadError = null;
    });

    try {
      final servers = await _roomsController.loadRooms();
      if (!mounted) return;
      _setHomeState(() {
        _servers = servers;
        _loadingServers = false;
        if (_selectedServerId != null &&
            !_servers.any((server) => server.id == _selectedServerId)) {
          final shouldDisconnectLive = _joinedLiveRoomId == _selectedServerId;
          _selectedServerId = null;
          _selectedRoom = null;
          _live = null;
          _messages = const [];
          _fileTransfers = const {};
          _contentMode = _ContentMode.chat;
          if (shouldDisconnectLive) {
            _joinedLiveRoomId = null;
            unawaited(_liveSessionController.disconnect());
          }
        }
      });
    } catch (error) {
      if (!mounted) return;
      _setHomeState(() {
        _loadingServers = false;
        _serverLoadError = error.toString();
      });
    }
  }

  void _selectServer(RoomCard server, {required bool openContent}) {
    unawaited(_openRoom(server, openContent: openContent));
  }

  Future<void> _openRoom(RoomCard server, {required bool openContent}) async {
    if (_loadingRoom && _selectedServerId == server.id) return;

    _setHomeState(() {
      _selectedServerId = server.id;
      _settingsOpen = false;
      _contentMode = _ContentMode.chat;
      if (openContent) _narrowContentOpen = true;
      _selectedRoom = null;
      _live = null;
      _messages = const [];
      _fileTransfers = const {};
      _roomError = null;
      _sendError = null;
      _loadingRoom = true;
    });

    try {
      final snapshot = await _roomsController.openRoom(server.id);
      if (!mounted || _selectedServerId != server.id) return;
      _setHomeState(() {
        _selectedRoom = snapshot.detail;
        _live = snapshot.live;
        _messages = snapshot.messages;
        _loadingRoom = false;
        _roomError = null;
      });
    } catch (error) {
      if (!mounted || _selectedServerId != server.id) return;
      _setHomeState(() {
        _loadingRoom = false;
        _roomError = error.toString();
      });
    }
  }

  void _toggleSettings({required bool openContent}) {
    _setHomeState(() {
      final opening = !_settingsOpen;
      _settingsOpen = opening;
      if (opening) _contentMode = _ContentMode.chat;
      if (openContent) {
        _narrowContentOpen = opening;
      }
    });
  }

  void _openCreateRoom({required bool openContent}) {
    _setHomeState(() {
      _settingsOpen = false;
      _contentMode = _ContentMode.createRoom;
      if (openContent) _narrowContentOpen = true;
    });
  }

  void _closeCreateRoom() {
    _setHomeState(() {
      _contentMode = _ContentMode.chat;
      if (_selectedServerId == null) _narrowContentOpen = false;
    });
  }

  void _closeSettings() {
    _setHomeState(() => _settingsOpen = false);
  }

  Future<void> _logout() async {
    _joinedLiveRoomId = null;
    await _liveSessionController.disconnect(
      timeout: const Duration(seconds: 1),
    );
    await widget.app.logout();
  }

  void _handleUserUpdated(CurrentUser user) {
    _setHomeState(() => _currentUser = user);
  }

  Future<void> _retryOpenSelectedRoom() async {
    final server = _selectedServer;
    if (server == null) return;
    await _openRoom(server, openContent: false);
  }

  void _openLiveChannel() {
    if (_selectedServerId == null) return;
    _setHomeState(() {
      _settingsOpen = false;
      _contentMode = _ContentMode.live;
      _narrowContentOpen = true;
    });
  }

  void _openChat() {
    _setHomeState(() => _contentMode = _ContentMode.chat);
  }

  Future<void> _openRoomMembers() async {
    final room = _selectedRoom;
    if (room == null) return;
    _setHomeState(() {
      _settingsOpen = false;
      _contentMode = _ContentMode.members;
      _narrowContentOpen = true;
    });
  }

  Future<void> _openRoomSettings() async {
    final room = _selectedRoom;
    if (room == null) return;
    _setHomeState(() {
      _settingsOpen = false;
      _contentMode = _ContentMode.roomSettings;
      _narrowContentOpen = true;
    });
  }

  void _handleRoomSettingsResult(String roomId, RoomManagementResult result) {
    switch (result.kind) {
      case RoomManagementResultKind.created:
        break;
      case RoomManagementResultKind.updated:
        final updated = result.room;
        if (updated != null) _applyManagedRoomUpdated(updated);
        unawaited(_loadServers());
        break;
      case RoomManagementResultKind.left:
      case RoomManagementResultKind.deleted:
        _applyManagedRoomRemoved(roomId);
        unawaited(_loadServers());
        break;
    }
  }

  void _handleCreateRoomResult(RoomManagementResult result) {
    if (result.kind != RoomManagementResultKind.created) return;
    final room = result.room;
    if (room == null) return;
    _applyCreatedRoom(room);
    unawaited(_loadServers());
  }

  void _applyCreatedRoom(RoomDetail room) {
    final patch = _roomsController.patchRoomDetailApplied(
      rooms: _servers,
      detail: room,
    );
    _setHomeState(() {
      _selectedServerId = room.id;
      _selectedRoom = patch.selectedRoom;
      _servers = patch.rooms;
      _live = room.live;
      _messages = const [];
      _fileTransfers = const {};
      _settingsOpen = false;
      _contentMode = _ContentMode.chat;
      _roomError = null;
      _sendError = null;
      _loadingRoom = false;
      _narrowContentOpen = true;
    });
  }

  void _applyManagedRoomUpdated(RoomDetail room) {
    if (_selectedServerId != room.id) return;
    final patch = _roomsController.patchRoomDetailApplied(
      rooms: _servers,
      detail: room,
    );
    _setHomeState(() {
      _selectedRoom = patch.selectedRoom;
      _servers = patch.rooms;
      _live = room.live;
      _roomError = null;
    });
  }

  void _applyManagedRoomRemoved(String roomId) {
    _setHomeState(() {
      _servers = _roomsController.removeRoomCard(_servers, roomId);
      if (_selectedServerId == roomId) {
        _selectedServerId = null;
        _selectedRoom = null;
        _live = null;
        _messages = const [];
        _fileTransfers = const {};
        _contentMode = _ContentMode.chat;
        _settingsOpen = false;
        _roomError = null;
        _sendError = null;
        _narrowContentOpen = false;
      }
      if (_joinedLiveRoomId == roomId) {
        _joinedLiveRoomId = null;
        _joiningLive = false;
      }
    });
  }
}
