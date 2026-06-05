import 'dart:async';

import 'package:flutter/material.dart';

import '../app/authenticated_app_context.dart';
import '../app/rooms_controller.dart';
import '../protocol/api_client.dart';
import '../protocol/models.dart';
import '../settings/settings_page.dart';
import '../ui/ui.dart';
import 'home_content.dart';
import 'home_sidebar.dart';
import 'navigation.dart';

const _windowEdgeBorder = Color(0xFF303842);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.app});

  final AuthenticatedAppContext app;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late GangApi _api;
  late RoomsController _roomsController;
  late CurrentUser _currentUser;

  List<RoomCard> _servers = const [];
  bool _loadingServers = false;
  String? _serverLoadError;
  String? _selectedServerId;
  bool _settingsOpen = false;
  bool _narrowContentOpen = false;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.app.currentUser;
    _installApi();
    unawaited(_loadServers());
  }

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final appChanged =
        widget.app.currentUser.id != oldWidget.app.currentUser.id ||
        !widget.app.hasSameApiSource(oldWidget.app);
    if (!appChanged) return;

    _api.close();
    _installApi();
    setState(() {
      _currentUser = widget.app.currentUser;
      _servers = const [];
      _serverLoadError = null;
      _selectedServerId = null;
      _settingsOpen = false;
      _narrowContentOpen = false;
    });
    unawaited(_loadServers());
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  void _installApi() {
    _api = widget.app.createApiClient();
    _roomsController = RoomsController(api: _api);
  }

  Future<void> _loadServers() async {
    setState(() {
      _loadingServers = true;
      _serverLoadError = null;
    });

    try {
      final servers = await _roomsController.loadRooms();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _loadingServers = false;
        if (_selectedServerId != null &&
            !_servers.any((server) => server.id == _selectedServerId)) {
          _selectedServerId = null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingServers = false;
        _serverLoadError = error.toString();
      });
    }
  }

  void _selectServer(RoomCard server, {required bool openContent}) {
    setState(() {
      _selectedServerId = server.id;
      _settingsOpen = false;
      if (openContent) _narrowContentOpen = true;
    });
  }

  void _toggleSettings({required bool openContent}) {
    setState(() {
      final opening = !_settingsOpen;
      _settingsOpen = opening;
      if (openContent) {
        _narrowContentOpen = opening;
      }
    });
  }

  void _closeSettings() {
    setState(() => _settingsOpen = false);
  }

  void _showNarrowSidebar() {
    setState(() {
      _settingsOpen = false;
      _narrowContentOpen = false;
    });
  }

  void _handleUserUpdated(CurrentUser user) {
    setState(() => _currentUser = user);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.background,
      body: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: _windowEdgeBorder)),
        child: KeyedSubtree(
          key: ValueKey(widget.app.currentUser.id),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < narrowBreakpoint;
              if (narrow) return _buildNarrowLayout(constraints.maxWidth);

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSidebar(
                    width: sidebarWidth,
                    openContentOnSelect: false,
                  ),
                  Expanded(child: _buildContentPane()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNarrowLayout(double width) {
    if (!_narrowContentOpen) {
      return _buildSidebar(width: width, openContentOnSelect: true);
    }

    return Column(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            color: UiColors.surfaceLow,
            border: Border(bottom: BorderSide(color: UiColors.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 16, 10),
            child: Row(
              children: [
                ButtonIcon(
                  tooltip: 'Show servers',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _showNarrowSidebar,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _settingsOpen
                        ? 'Settings'
                        : _selectedServer?.displayName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UiTypography.title,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: _buildContentPane()),
      ],
    );
  }

  Widget _buildContentPane() {
    if (!_settingsOpen) return const HomeContent();
    return SettingsPage(
      isSubWindow: true,
      api: _api,
      apiBaseUrl: widget.app.apiBaseUrl,
      stickerPackStore: widget.app.stickerPackStore,
      currentUser: _currentUser,
      onUserUpdated: _handleUserUpdated,
      onAccountDeleted: widget.app.logout,
      onClose: _closeSettings,
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
      loading: _loadingServers,
      error: _serverLoadError,
      settingsActive: _settingsOpen,
      onServerSelected: (server) =>
          _selectServer(server, openContent: openContentOnSelect),
      onOpenSettings: () => _toggleSettings(openContent: openContentOnSelect),
      onLogout: () => unawaited(widget.app.logout()),
    );
  }

  RoomCard? get _selectedServer {
    for (final server in _servers) {
      if (server.id == _selectedServerId) return server;
    }
    return null;
  }
}
