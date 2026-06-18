import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../app/audio_device_store.dart';
import '../app/audio_levels.dart';
import '../app/authenticated_app_services.dart';
import '../app/authenticated_app_context.dart';
import '../app/close_behavior.dart';
import '../app/file_display.dart' as file_display;
import '../app/file_downloads_controller.dart';
import '../app/file_transfer_state.dart';
import '../app/media_cache_controller.dart';
import '../app/composer_attachment_display.dart' as composer_attachment;
import '../app/global_search_controller.dart';
import '../app/live_controller.dart';
import '../app/live_display.dart' as live_display;
import '../app/live_session_controller.dart';
import '../app/message_display.dart' as message_display;
import '../app/messages_controller.dart';
import '../app/music_box_controller.dart';
import '../app/music_box_display.dart' as music_box_display;
import '../app/realtime_controller.dart';
import '../app/room_display.dart' as room_display;
import '../app/room_join.dart' as room_join;
import '../app/room_members_filter.dart' as member_filter;
import '../app/room_notifications.dart' as room_notifications;
import '../app/rooms_controller.dart';
import '../app/search_display.dart' as search_display;
import '../app/sticker_display.dart' as sticker_display;
import '../app/sticker_packs_controller.dart';
import '../app/voice_message_display.dart' as voice_display;
import '../app/voice_recorder_controller.dart';
import '../live/live_session.dart';
import '../protocol/api_client.dart'
    show ApiException, UploadCancelledException, UploadTransferController;
import '../protocol/models.dart';
import '../settings/settings_page.dart';
import '../shell/clipboard_service.dart';
import '../shell/desktop_window_controller.dart';
import '../shell/file_drop_service.dart';
import '../shell/file_selection_service.dart';
import '../shell/voice_playback_service.dart';
import '../ui/ui.dart';
import 'chat_pane.dart';
import 'home_content.dart';
import 'hover_card_anchor.dart';
import 'home_notifications.dart';
import 'home_sidebar.dart';
import 'live_channel_pane.dart';
import 'live_screen_share_picker.dart';
import 'navigation.dart';
import 'room_profile_card.dart';
import 'room_management.dart';

part 'home_shell_realtime.dart';
part 'home_shell_room_actions.dart';
part 'home_shell_live_actions.dart';
part 'home_shell_music_box.dart';
part 'home_shell_messages.dart';
part 'home_shell_downloads.dart';
part 'home_shell_image_preview.dart';
part 'home_shell_notifications.dart';
part 'home_shell_search.dart';
part 'home_shell_layout.dart';
part 'home_shell_title_bar.dart';
part 'home_shell_join_dialog.dart';

const _windowEdgeBorder = Color(0xFF303842);
const _defaultLiveVolumeRestore = 0.5;

bool get _supportsWindowManagement =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

enum _ContentMode {
  chat,
  live,
  members,
  roomSettings,
  createRoom,
  notifications,
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.app,
    required this.audioDeviceStore,
    required this.closeBehaviorStore,
    required this.windowController,
    this.liveSessionController,
    this.realtime,
  });

  final AuthenticatedAppContext app;
  final AudioDeviceStore audioDeviceStore;
  final CloseBehaviorStore closeBehaviorStore;
  final DesktopWindowController windowController;
  final LiveSessionController? liveSessionController;
  final RealtimeService? realtime;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late AuthenticatedAppServices _services;
  late CurrentUser _currentUser;
  final TextEditingController _composerController = TextEditingController();
  final ChatComposerController _composerPanelController =
      ChatComposerController();
  final TextEditingController _titleSearchController = TextEditingController();
  final GlobalKey _composerDropKey = GlobalKey();
  final Object _searchTapRegionGroup = Object();
  StreamSubscription<RealtimeEvent>? _realtimeEvents;
  StreamSubscription<FileDropEvent>? _fileDropEvents;

  List<RoomCard> _servers = const [];
  bool _loadingServers = false;
  String? _serverLoadError;
  String? _selectedServerId;
  RoomDetail? _selectedRoom;
  LiveState? _live;
  List<Message> _messages = const [];
  Map<String, FileTransferState> _fileTransfers = const {};
  // Active file downloads, keyed by [file_display.fileDownloadKey]. Kept apart
  // from [_fileTransfers] (outgoing uploads) so the two never collide on a
  // message id and each tile can pick the transfer that applies to it.
  Map<String, FileTransferState> _fileDownloads = const {};
  final Map<String, LiveStageSelection?> _liveStageSelections = {};
  LiveVideoTrack? _fullScreenLiveTrack;
  bool _loadingRoom = false;
  String? _roomError;
  bool _sending = false;
  String? _sendError;
  sticker_display.StickerPanelLoadState _stickerPanelState =
      const sticker_display.StickerPanelLoadState();
  voice_display.VoiceRecorderState _voiceState =
      const voice_display.VoiceRecorderState();
  final VoicePlaybackService _voicePlaybackService = VoicePlaybackService();
  VoicePlaybackSnapshot _voicePlayback = const VoicePlaybackSnapshot();
  Timer? _voiceTicker;
  DateTime? _voiceStartedAt;
  // Files picked for the next message, kept in pick order. Each uploads as
  // soon as it is picked; the message send later just collects the finished
  // assets. See [_StagedAttachment].
  final List<_StagedAttachment> _stagedAttachments = [];
  final ClipboardService _clipboardService = const ClipboardService();
  final FileDropService _fileDropService = const FileDropService();
  final FileSelectionService _fileSelectionService =
      const FileSelectionService();
  int _clipboardImagePasteSerial = 0;
  bool _pickingAttachments = false;
  bool _settingsOpen = false;
  bool _logoutConfirming = false;
  bool _closeConfirming = false;
  bool _exitingApplication = false;
  bool _narrowContentOpen = false;
  _ContentMode _contentMode = _ContentMode.chat;
  // Bumped to ask an open members panel to reload (e.g. after a
  // `room_join_requests_updated` or `room_role_changed` SSE event). The panel
  // watches this via didUpdateWidget and re-pulls its members/requests.
  int _membersReloadToken = 0;
  String _membersInitialSearchQuery = '';
  List<RoomInvite> _notificationInvites = const [];
  List<RoomApplication> _notificationApplications = const [];
  bool _loadingNotifications = false;
  String? _notificationError;
  String? _busyNotificationInviteId;
  String? _busyNotificationApplicationId;
  bool _hasPendingRoomInvites = false;
  String? _joinedLiveRoomId;
  bool _joiningLive = false;
  bool _micMuted = true;
  bool _headphonesMuted = false;
  double _lastInputVolumeBeforeMute = _defaultLiveVolumeRestore;
  double _lastOutputVolumeBeforeMute = _defaultLiveVolumeRestore;
  bool _cameraOn = false;
  bool _screenSharing = false;
  bool _voiceBlocked = false;
  // The selected room's music box snapshot, or null when not loaded / disabled.
  // Overwritten wholesale from state fetches, write responses, and the
  // `music_box_changed` SSE event; never merged field by field.
  MusicBoxState? _musicBox;
  // Whether the in-pane music box panel is expanded over the live channel.
  bool _musicBoxOpen = false;
  // Drives the music box search field; results are fetched debounced.
  final TextEditingController _musicBoxSearchController =
      TextEditingController();
  List<MusicBoxSearchResult> _musicBoxSearchResults = const [];
  bool _musicBoxSearching = false;
  String? _musicBoxSearchError;
  // The selected search source forwarded to the GD music API (defaults to
  // netease). Changing it re-runs the current query.
  String _musicBoxSource = music_box_display.musicBoxDefaultSource;
  int _musicBoxSearchSerial = 0;
  Timer? _musicBoxSearchDebounce;
  Timer? _searchDebounce;
  int _searchRequestSerial = 0;
  String _searchQuery = '';
  bool _searchExpanded = false;
  bool _searching = false;
  bool _searchLoadingMore = false;
  String? _searchError;
  GlobalSearchResults? _searchResults;
  search_display.GlobalSearchCategory? _activeSearchCategory;
  String? _busySearchPublicRoomId;
  Set<String> _searchPendingPublicRoomIds = const {};
  bool _showingJoinApplicationDialog = false;

  RoomsController get _roomsController => _services.rooms;
  MessagesController get _messagesController => _services.messages;
  GlobalSearchController get _globalSearchController => _services.search;
  StickerPacksController get _stickerPacksController => _services.stickers;
  VoiceRecorderController get _voiceRecorder => _services.voiceRecorder;
  LiveController get _liveController => _services.live;
  LiveSessionController get _liveSessionController => _services.liveSession;
  MusicBoxController get _musicBoxController => _services.musicBox;
  FileDownloadsController get _fileDownloadsController =>
      _services.fileDownloads;
  MediaCacheController get _mediaCacheController => _services.mediaCache;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.app.currentUser;
    _titleSearchController.addListener(_handleTitleSearchChanged);
    _musicBoxSearchController.addListener(_handleMusicBoxSearchChanged);
    _voicePlaybackService.state.addListener(_handleVoicePlaybackChanged);
    _installServices();
    _attachLiveSessionCallbacks();
    widget.windowController.setCloseRequestHandler(_handleWindowCloseRequest);
    widget.windowController.setTrayExitHandler(_exitApplication);
    _fileDropEvents = _fileDropService.drops.listen(_handleDroppedFiles);
    _startRealtime();
    unawaited(_loadServers());
    unawaited(_refreshPendingRoomInviteBadge());
  }

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowController != widget.windowController) {
      oldWidget.windowController.setCloseRequestHandler(null);
      oldWidget.windowController.setTrayExitHandler(null);
      widget.windowController.setCloseRequestHandler(_handleWindowCloseRequest);
      widget.windowController.setTrayExitHandler(_exitApplication);
    }
    final appChanged =
        widget.app.currentUser.id != oldWidget.app.currentUser.id ||
        !widget.app.hasSameApiSource(oldWidget.app);
    if (!appChanged) return;

    _detachLiveSessionCallbacks();
    _services.close();
    _installServices();
    _attachLiveSessionCallbacks();
    _startRealtime();
    _searchDebounce?.cancel();
    _searchRequestSerial++;
    _titleSearchController.removeListener(_handleTitleSearchChanged);
    _titleSearchController.clear();
    _titleSearchController.addListener(_handleTitleSearchChanged);
    setState(() {
      _currentUser = widget.app.currentUser;
      _servers = const [];
      _serverLoadError = null;
      _selectedServerId = null;
      _selectedRoom = null;
      _live = null;
      _messages = const [];
      _fileTransfers = const {};
      _fileDownloads = const {};
      _liveStageSelections.clear();
      _fullScreenLiveTrack = null;
      _loadingRoom = false;
      _roomError = null;
      _sending = false;
      _sendError = null;
      _stickerPanelState = const sticker_display.StickerPanelLoadState();
      _settingsOpen = false;
      _logoutConfirming = false;
      _narrowContentOpen = false;
      _contentMode = _ContentMode.chat;
      _membersInitialSearchQuery = '';
      _notificationInvites = const [];
      _notificationApplications = const [];
      _loadingNotifications = false;
      _notificationError = null;
      _busyNotificationInviteId = null;
      _busyNotificationApplicationId = null;
      _hasPendingRoomInvites = false;
      _joinedLiveRoomId = null;
      _joiningLive = false;
      _micMuted = true;
      _headphonesMuted = false;
      _cameraOn = false;
      _screenSharing = false;
      _voiceBlocked = false;
      _resetMusicBox();
      _searchQuery = '';
      _searchExpanded = false;
      _searching = false;
      _searchLoadingMore = false;
      _searchError = null;
      _searchResults = null;
      _activeSearchCategory = null;
      _busySearchPublicRoomId = null;
      _searchPendingPublicRoomIds = const {};
      _voicePlayback = const VoicePlaybackSnapshot();
    });
    unawaited(_voicePlaybackService.stop());
    unawaited(_loadServers());
    unawaited(_refreshPendingRoomInviteBadge());
  }

  @override
  void dispose() {
    final realtimeEvents = _realtimeEvents;
    if (realtimeEvents != null) unawaited(realtimeEvents.cancel());
    final fileDropEvents = _fileDropEvents;
    if (fileDropEvents != null) unawaited(fileDropEvents.cancel());
    unawaited(_setSystemFullScreen(false));
    _detachLiveSessionCallbacks();
    widget.windowController.setCloseRequestHandler(null);
    widget.windowController.setTrayExitHandler(null);
    _voiceTicker?.cancel();
    _musicBoxSearchDebounce?.cancel();
    _musicBoxSearchController.dispose();
    _searchDebounce?.cancel();
    _titleSearchController.removeListener(_handleTitleSearchChanged);
    _titleSearchController.dispose();
    _composerController.dispose();
    _composerPanelController.dispose();
    _voicePlaybackService.state.removeListener(_handleVoicePlaybackChanged);
    unawaited(_voicePlaybackService.dispose());
    _cancelActiveDownloads();
    _services.close();
    super.dispose();
  }

  void _installServices() {
    _services = AuthenticatedAppServices(
      widget.app,
      audioDeviceStore: widget.audioDeviceStore,
      liveSessionController: widget.liveSessionController,
      realtime: widget.realtime,
    );
  }

  void _setHomeState(VoidCallback update) => setState(update);

  void _handleVoicePlaybackChanged() {
    if (!mounted) return;
    _setHomeState(() => _voicePlayback = _voicePlaybackService.state.value);
  }

  Future<void> _toggleVoicePlayback({
    required String messageId,
    required String resolvedUrl,
  }) async {
    try {
      await _voicePlaybackService.toggle(
        messageId: messageId,
        resolvedUrl: resolvedUrl,
      );
    } catch (error) {
      if (!mounted) return;
      _setHomeState(() => _sendError = error.toString());
    }
  }

  void _attachLiveSessionCallbacks() {
    _liveSessionController.attachSessionCallbacks(
      onChanged: _onLiveSessionChanged,
      onForciblyRemoved: _onForciblyRemovedFromLive,
      onPublishPermissionChanged: _onPublishPermissionChanged,
    );
  }

  void _detachLiveSessionCallbacks() {
    _liveSessionController.detachSessionCallbacks(
      onChanged: _onLiveSessionChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullScreenTrack = _resolveFullScreenLiveTrack();
    return Scaffold(
      backgroundColor: UiColors.background,
      body: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: _windowEdgeBorder)),
        child: LayoutBuilder(
          builder: (context, shellConstraints) {
            final showSearchOverlay = _homeTitleBarCanShowSearch(
              context,
              shellConstraints.maxWidth,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                KeyedSubtree(
                  key: ValueKey(widget.app.currentUser.id),
                  child: Column(
                    children: [
                      _HomeTitleBar(
                        windowController: widget.windowController,
                        searchController: _titleSearchController,
                        searchTapRegionGroup: _searchTapRegionGroup,
                        searchQuery: _searchQuery,
                        onActivateSearch: _activateSearch,
                        onSearchTapOutside: _collapseSearch,
                        onClearSearchQuery: _clearSearchQuery,
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final narrow =
                                constraints.maxWidth < narrowBreakpoint;
                            if (narrow) {
                              return _buildNarrowLayout(constraints.maxWidth);
                            }

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
                    ],
                  ),
                ),
                if (_hasSearchQuery && _searchExpanded && showSearchOverlay)
                  Positioned(
                    top: _homeTitleBarHeight - 1,
                    left:
                        (shellConstraints.maxWidth - _homeTitleBarSearchWidth) /
                        2,
                    width: _homeTitleBarSearchWidth,
                    child: TapRegion(
                      key: const ValueKey('home-title-search-results'),
                      groupId: _searchTapRegionGroup,
                      child: HoverCardTapRegionScope(
                        tapRegionGroup: _searchTapRegionGroup,
                        child: _TitleSearchResultsPanel(
                          query: _searchQuery,
                          results: _searchResults,
                          loading: _searching,
                          loadingMore: _searchLoadingMore,
                          error: _searchError,
                          currentUser: widget.app.currentUser,
                          activeCategory: _activeSearchCategory,
                          visibleCategories: _visibleSearchCategories,
                          busyPublicRoomId: _busySearchPublicRoomId,
                          pendingPublicRoomIds: _searchPendingPublicRoomIds,
                          onCategorySelected: _selectSearchCategory,
                          onLoadMore: () => unawaited(_loadMoreSearchResults()),
                          onMyRoomSelected: _openSearchRoom,
                          onProfileRoomSelected: _openSearchProfileRoom,
                          onResolveRoomProfile: _resolveRoomProfile,
                          onResolveRoomUserProfile: _resolveRoomUserProfile,
                          onPublicRoomAction: (room) =>
                              unawaited(_handlePublicRoomSearchAction(room)),
                          onMessageSelected: _openMessageSearchResult,
                          onFileSelected: _openMessageSearchResult,
                        ),
                      ),
                    ),
                  ),
                if (fullScreenTrack != null)
                  Positioned.fill(
                    child: LiveFullScreenStage(
                      track: fullScreenTrack,
                      label: liveStageTrackLabel(_live, fullScreenTrack),
                      onExit: _exitLiveFullScreen,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  RoomCard? get _selectedServer {
    for (final server in _servers) {
      if (server.id == _selectedServerId) return server;
    }
    return null;
  }
}

String _roomTitle(RoomDetail? room, RoomCard? card) {
  final detailRemark = room?.remarkName?.trim();
  if (detailRemark != null && detailRemark.isNotEmpty) return detailRemark;
  final detailTitle = room?.name.trim();
  if (detailTitle != null && detailTitle.isNotEmpty) return detailTitle;
  final cardTitle = card?.displayName.trim();
  if (cardTitle != null && cardTitle.isNotEmpty) return cardTitle;
  return '聊天';
}

/// A file staged in the composer. Uploading starts the moment the file is
/// picked, so the entry tracks the in-flight upload (progress + cancellation)
/// and caches the resulting [asset] once it lands, ready for the next send.
class _StagedAttachment {
  _StagedAttachment({required this.id, required this.file})
    : status = composer_attachment.ComposerAttachmentStatus.uploading;

  final String id;
  final SelectedFile file;
  final UploadTransferController uploadController = UploadTransferController();

  composer_attachment.ComposerAttachmentStatus status;
  UploadedAsset? asset;
  int? sizeBytes;
  double? progress;
  Object? error;
  String? errorMessage;

  bool get isUploaded =>
      status == composer_attachment.ComposerAttachmentStatus.uploaded;
}
