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
      _activeSearchCategory = null;
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
        _searchResults = results;
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

  void _selectSearchCategory(search_display.GlobalSearchCategory category) {
    _setHomeState(() => _activeSearchCategory = category);
  }

  void _clearSearchCategory() {
    _setHomeState(() => _activeSearchCategory = null);
  }

  void _clearSearchQuery() {
    _titleSearchController.clear();
  }

  void _openSearchRoom(RoomCard room) {
    final narrow = MediaQuery.sizeOf(context).width < narrowBreakpoint;
    _selectServer(room, openContent: narrow);
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
}
