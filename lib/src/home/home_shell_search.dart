part of 'home_shell.dart';

extension _HomeShellSearch on _HomeShellState {
  bool get _hasSearchQuery => search_display.hasGlobalSearchQuery(_searchQuery);

  bool get _filteringSidebarBySearch =>
      _hasSearchQuery &&
      _activeSearchCategory == search_display.GlobalSearchCategory.myRooms;

  List<RoomCard> get _sidebarServers {
    return search_display.sidebarRoomsForSearch(
      rooms: _servers,
      query: _searchQuery,
      activeCategory: _activeSearchCategory,
      results: _searchResults,
    );
  }

  bool get _loadingSidebarSearch =>
      _filteringSidebarBySearch && _searching && _searchResults == null;

  void _handleTitleSearchChanged() {
    final query = _titleSearchController.text;
    _searchDebounce?.cancel();
    _searchRequestSerial++;
    final requestSerial = _searchRequestSerial;
    final hasQuery = search_display.hasGlobalSearchQuery(query);

    _setHomeState(() {
      _searchQuery = query;
      _searchExpanded = hasQuery;
      _searchError = null;
      if (hasQuery) {
        _searching = true;
        _searchResults = null;
      } else {
        _searching = false;
        _searchResults = null;
      }
    });

    if (!hasQuery) return;
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_runSearch(requestSerial, query));
    });
  }

  Future<void> _runSearch(int requestSerial, String rawQuery) async {
    final query = rawQuery.trim();
    if (!search_display.hasGlobalSearchQuery(query)) return;

    try {
      final results = await _globalSearchController.search(query: query);
      if (!mounted || requestSerial != _searchRequestSerial) return;
      if (_titleSearchController.text.trim() != query) return;
      _setHomeState(() {
        _searchResults = search_display.globalSearchResultsForView(
          results,
          query: query,
        );
        _searching = false;
        _searchError = null;
      });
    } catch (error) {
      if (!mounted || requestSerial != _searchRequestSerial) return;
      _setHomeState(() {
        _searching = false;
        _searchError = error.toString();
      });
    }
  }

  void _activateSearch() {
    if (_searchExpanded) return;
    _setHomeState(() => _searchExpanded = true);
  }

  void _collapseSearch() {
    if (!_searchExpanded) return;
    _setHomeState(() => _searchExpanded = false);
  }

  void _selectSearchCategory(search_display.GlobalSearchCategory category) {
    _setHomeState(() {
      _activeSearchCategory = _activeSearchCategory == category
          ? null
          : category;
    });
  }

  void _clearSearchQuery() {
    _titleSearchController.clear();
  }

  void _openSearchRoom(RoomCard room) {
    final narrow = MediaQuery.sizeOf(context).width < narrowBreakpoint;
    _selectServer(room, openContent: narrow);
  }

  Future<PublicRoom> _resolveRoomProfile(PublicRoom room) async {
    final detail = await _roomsController.getRoom(room.id);
    return room_display.publicRoomFromRoomDetail(detail);
  }

  Future<UserSummary> _resolveRoomUserProfile(
    String roomId,
    UserSummary user,
  ) async {
    try {
      final profile = await _roomsController.getRoomMemberProfile(
        roomId: roomId,
        userId: user.id,
      );
      return profile.user.mergeMissing(user);
    } catch (_) {
      return _resolveUserProfile(user);
    }
  }

  Future<UserSummary> _resolveUserProfile(UserSummary user) async {
    try {
      final profile = await _roomsController.getUserProfile(user.id);
      return profile.mergeMissing(user);
    } catch (_) {
      return user;
    }
  }

  Future<void> _handlePublicRoomSearchAction(PublicRoom room) async {
    final pending =
        room.joinState == 'pending' ||
        _searchPendingPublicRoomIds.contains(room.id);
    if (!room_display.publicRoomJoinActionable(room, pending: pending)) {
      return;
    }

    if (room.joined) {
      _openSearchRoom(_roomCardForPublicRoom(room));
      return;
    }

    String? reason;
    var startedBeforeDialog = false;
    if (room_display.publicRoomJoinRequiresApplication(room)) {
      final started = room_join.roomJoinPublicActionStarted(
        roomId: room.id,
        pendingRoomIds: _searchPendingPublicRoomIds,
      );
      _setHomeState(() {
        _busySearchPublicRoomId = started.busyRoomId;
        _searchError = started.error;
        _searchPendingPublicRoomIds = started.pendingRoomIds;
      });
      startedBeforeDialog = true;
      final rawReason = await _showJoinApplicationDialog(room);
      if (rawReason == null || !mounted) {
        if (mounted) {
          _setHomeState(() => _busySearchPublicRoomId = null);
        }
        return;
      }
      reason = room_join.joinRequestReasonValue(rawReason);
    }

    if (!startedBeforeDialog) {
      final started = room_join.roomJoinPublicActionStarted(
        roomId: room.id,
        pendingRoomIds: _searchPendingPublicRoomIds,
      );
      _setHomeState(() {
        _busySearchPublicRoomId = started.busyRoomId;
        _searchError = started.error;
        _searchPendingPublicRoomIds = started.pendingRoomIds;
      });
    }

    try {
      final result = await _roomsController.joinRoom(room.id, reason: reason);
      if (!mounted) return;
      if (result.joined && result.room != null) {
        _applyJoinedSearchRoom(result.room!);
        _setHomeState(() {
          _busySearchPublicRoomId = null;
          _searchResults = _searchResultsWithPublicRoomJoined(result.room!);
        });
        unawaited(_loadServersSilently());
        return;
      }

      final pendingPatch = room_join.roomJoinPublicActionPending(
        busyRoomId: null,
        error: null,
        pendingRoomIds: _searchPendingPublicRoomIds,
        room: room,
        result: result,
      );
      _setHomeState(() {
        _busySearchPublicRoomId = pendingPatch.busyRoomId;
        _searchError = pendingPatch.error;
        _searchPendingPublicRoomIds = pendingPatch.pendingRoomIds;
        _hasPendingRoomInvites = true;
      });
      unawaited(_refreshPendingRoomInviteBadge());
    } catch (error) {
      if (!mounted) return;
      final failed = room_join.roomJoinPublicActionFailed(
        busyRoomId: null,
        pendingRoomIds: _searchPendingPublicRoomIds,
        failure: error,
      );
      _setHomeState(() {
        _busySearchPublicRoomId = failed.busyRoomId;
        _searchError = failed.error;
        _searchPendingPublicRoomIds = failed.pendingRoomIds;
      });
    }
  }

  Future<String?> _showJoinApplicationDialog(PublicRoom room) async {
    if (_showingJoinApplicationDialog) return null;
    _showingJoinApplicationDialog = true;
    try {
      return await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (context) => _JoinApplicationDialog(room: room),
      );
    } finally {
      _showingJoinApplicationDialog = false;
    }
  }

  void _applyJoinedSearchRoom(RoomDetail room) {
    final patch = _roomsController.patchRoomDetailApplied(
      rooms: _servers,
      detail: room,
    );
    _setHomeState(() {
      _servers = patch.rooms;
      _selectedServerId = room.id;
      _selectedRoom = patch.selectedRoom;
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

  void _openMessageSearchResult(MessageSearchResult result) {
    _openSearchRoom(_roomCardForSearchResult(result));
  }

  RoomCard _roomCardForSearchResult(MessageSearchResult result) {
    final existing = _serverById(result.room.id);
    if (existing != null) return existing;
    return search_display.roomCardFromSearchContext(
      result.room,
      updatedAt: result.message.createdAt,
    );
  }

  RoomCard? _serverById(String roomId) {
    for (final server in _servers) {
      if (server.id == roomId) return server;
    }
    final results = _searchResults;
    if (results != null) {
      for (final room in results.myRooms) {
        if (room.id == roomId) return room;
      }
    }
    return null;
  }

  RoomCard _roomCardForPublicRoom(PublicRoom room) {
    final existing = _serverById(room.id);
    if (existing != null) return existing;
    return RoomCard(
      id: room.id,
      rid: room.rid,
      name: room.name,
      visibility: room.visibility,
      description: room.description,
      avatarUrl: room.avatarUrl,
      defaultAvatarKey: room.defaultAvatarKey,
      memberCount: room.memberCount,
      onlineMemberCount: room.onlineMemberCount,
      liveParticipantCount: room.liveParticipantCount,
      liveAvatarPreview: const [],
      lastMessage: null,
      unreadCount: 0,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  GlobalSearchResults? _searchResultsWithPublicRoomJoined(RoomDetail room) {
    final snapshot = _searchResults;
    if (snapshot == null) return null;
    return GlobalSearchResults(
      myRooms: snapshot.myRooms,
      publicRooms: [
        for (final publicRoom in snapshot.publicRooms)
          if (publicRoom.id == room.id)
            publicRoom.copyWith(
              joined: true,
              joinState: 'joined',
              memberCount: room.memberCount,
              onlineMemberCount: room.onlineMemberCount,
              liveParticipantCount: room.live.participantCount,
            )
          else
            publicRoom,
      ],
      messages: snapshot.messages,
      files: snapshot.files,
    );
  }
}
