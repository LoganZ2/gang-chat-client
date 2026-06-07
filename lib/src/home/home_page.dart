import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app/account_display.dart' as account_display;
import '../app/audio_device_store.dart';
import '../app/authenticated_app_context.dart';
import '../app/authenticated_app_services.dart';
import '../app/chat_composer_state.dart';
import '../app/confirmation.dart';
import '../app/file_display.dart' as file_display;
import '../app/file_downloads_controller.dart';
import '../app/file_transfer_state.dart';
import '../app/home_shell_state.dart';
import '../app/live_controller.dart';
import '../app/live_display.dart' as live_display;
import '../app/live_session_controller.dart';
import '../app/message_display.dart' as message_display;
import '../app/messages_controller.dart';
import '../app/realtime_controller.dart';
import '../app/room_display.dart' as room_display;
import '../app/room_badges.dart';
import '../app/room_forms.dart';
import '../app/room_invites.dart';
import '../app/room_join.dart';
import '../app/room_join_requests.dart';
import '../app/room_members_filter.dart' as member_filter;
import '../app/rooms_controller.dart';
import '../app/sticker_display.dart' as sticker_display;
import '../app/sticker_management.dart';
import '../app/sticker_packs_controller.dart';
import '../app/sticker_ordering.dart' as sticker_ordering;
import '../app/sticker_uploads.dart';
import '../config/app_config.dart';
import '../lifecycle/shutdown_hooks.dart';
import '../live/live_session.dart';
import '../live/live_video_track_view.dart';
import '../protocol/api_client.dart';
import '../protocol/models.dart';
import '../settings/settings_page.dart';
import '../shell/clipboard_service.dart';
import '../shell/file_selection_service.dart';
import '../shell/secure_audio_device_store.dart';
import '../ui/avatar_crop_dialog.dart';
import '../ui/sticker_upload_adapter.dart';
import '../ui/ui.dart';

part 'home_sidebar.dart';
part 'home_chat.dart';
part 'home_live.dart';
part 'home_room_dialogs.dart';

const _primaryDark = Color(0xFF14171D);
const _primaryDarkRaised = Color(0xFF1F232C);
const _primaryDarkLow = Color(0xFF181C24);
const _selectedSurface = Color(0xFF1F2D27);
const _borderColor = Color(0xFF2A2F38);
const _cyan = Color(0xFF6FCFA6);
const _textPrimary = Color(0xFFECEFF1);
const _textSecondary = Color(0xFFB0B8C0);
const _textMuted = Color(0xFF6F7785);
const _danger = Color(0xFFE58383);

enum _RoomDialogCloseResult { left, deleted }

/// True on desktop platforms where window_manager (and thus OS full-screen) is
/// supported. Mirrors the gate used in main.dart.
bool get _supportsWindowManagement =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.app,
    this.audioDeviceStore = const SecureAudioDeviceStore(),
    this.clipboardService = const ClipboardService(),
    this.fileSelectionService = const FileSelectionService(),
  });

  final AuthenticatedAppContext app;
  final AudioDeviceStore audioDeviceStore;
  final ClipboardService clipboardService;
  final FileSelectionService fileSelectionService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late AuthenticatedAppServices _services;
  late CurrentUser _currentUser;

  final _messageController = TextEditingController();
  late final FocusNode _messageFocus;
  Map<String, String> _messageDrafts = {};

  List<RoomCard> _rooms = [];
  List<Message> _messages = [];
  Map<String, FileTransferState> _fileTransfers = {};
  Map<String, FileTransferState> _fileDownloads = {};
  RoomDetail? _selectedRoom;
  LiveState? _live;
  String? _selectedRoomId;
  String? _joinedLiveRoomId;
  String? _error;
  // Transient, centered toast (antd Message style) for action errors. Kept
  // separate from _error (which drives the full-pane load-failure view).
  String? _toast;
  HomeToastKind _toastKind = HomeToastKind.error;
  Timer? _toastTimer;
  bool _loadingRooms = true;
  bool _loadingRoom = false;
  bool _hasPendingRoomInvites = false;
  bool _selectedRoomHasPendingJoinRequests = false;
  bool _sending = false;
  bool _handlingMessagePaste = false;
  bool _joiningLive = false;
  bool _livePanelOpen = false;
  bool _settingsOpen = false;
  bool _micMuted = true;
  bool _headphonesMuted = false;
  bool _cameraOn = false;
  bool _screenSharing = false;
  // A persistent admin voice ban (block_voice) on the local user. While true
  // the mic is force-muted, the mic button is disabled, and self-unmute is
  // rejected by the server. Driven by LiveKit permission events and the
  // voice_blocked field on join/patch responses.
  bool _voiceBlocked = false;

  // Immersive full-screen screen-share. Holds the identity of the participant
  // whose share is expanded; null when not in full-screen. We track identity
  // (not the track) so we can re-resolve the live track each build and drop out
  // automatically if that share ends.
  String? _fullScreenShareIdentity;

  StreamSubscription<RealtimeEvent>? _realtimeEvents;

  Object? _shutdownHookToken;

  RoomsController get _roomsController => _services.rooms;
  MessagesController get _messagesController => _services.messages;
  LiveController get _liveController => _services.live;
  LiveSessionController get _liveSessionController => _services.liveSession;
  AudioDeviceStore get _audioDeviceStore =>
      _liveSessionController.audioDeviceStore;
  FileDownloadsController get _fileDownloadsController =>
      _services.fileDownloads;

  static const double _sidebarMinWidth = 288;
  static const double _sidebarMaxWidth = 520;
  static const double _sidebarCollapsedWidth = 64;
  double _sidebarWidth = 320;
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    _messageFocus = FocusNode(onKeyEvent: _onMessageKeyEvent);
    WidgetsBinding.instance.addObserver(this);
    _currentUser = widget.app.session.user;
    _services = AuthenticatedAppServices(
      widget.app,
      audioDeviceStore: widget.audioDeviceStore,
    );
    _messageController.addListener(_onMessageDraftChanged);
    _attachLiveSessionCallbacks();
    _shutdownHookToken = ShutdownHooks.register(
      () => _shutdownLive(reason: 'app_exit'),
    );
    _loadRooms();
    unawaited(_refreshRoomInviteBadge());
    _startLiveStream();
    unawaited(_warmPersonalStickerCache());
    unawaited(_liveSessionController.restoreStoredAudioSettings());
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

  void _onMessageDraftChanged() {
    _messageDrafts = message_display.saveMessageDraft(
      drafts: _messageDrafts,
      roomId: _selectedRoomId,
      text: _messageController.text,
    );
  }

  KeyEventResult _onMessageKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final pasteShortcut =
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (keyboard.isControlPressed || keyboard.isMetaPressed);
    if (!pasteShortcut) return KeyEventResult.ignored;
    unawaited(_handleMessagePaste());
    return KeyEventResult.handled;
  }

  Future<void> _handleMessagePaste() async {
    if (_handlingMessagePaste) return;
    _handlingMessagePaste = true;
    try {
      final pastedFiles = await _pasteFilesFromClipboard();
      if (pastedFiles) return;
      await _pasteTextFromClipboard();
    } finally {
      _handlingMessagePaste = false;
    }
  }

  Future<bool> _pasteFilesFromClipboard() async {
    List<SelectedFile> files;
    try {
      files = await _clipboardFiles();
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      if (mounted) {
        _showToast(
          file_display.clipboardFilesReadFailureMessage(e.message ?? e.code),
        );
      }
      return false;
    } catch (e) {
      if (mounted) {
        _showToast(file_display.clipboardFilesReadFailureMessage(e));
      }
      return false;
    }
    if (files.isEmpty) return false;
    for (final file in files) {
      if (!mounted) break;
      unawaited(_sendSelectedFile(file));
    }
    return true;
  }

  Future<List<SelectedFile>> _clipboardFiles() async {
    final paths = await widget.clipboardService.readFilePaths();
    if (paths.isEmpty) return const <SelectedFile>[];

    return widget.fileSelectionService.filesFromPaths(
      file_display.normalizedFilePaths(paths),
    );
  }

  Future<void> _pasteTextFromClipboard() async {
    final text = await widget.clipboardService.readText();
    if (text == null) return;

    final value = _messageController.value;
    final selection = value.selection;
    final edit = message_display.insertMessageText(
      currentText: value.text,
      insertedText: text,
      selectionStart: selection.isValid ? selection.start : null,
      selectionEnd: selection.isValid ? selection.end : null,
    );
    _messageController.value = value.copyWith(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.cursorOffset),
      composing: TextRange.empty,
    );
  }

  void _saveCurrentMessageDraft() {
    _messageDrafts = message_display.saveMessageDraft(
      drafts: _messageDrafts,
      roomId: _selectedRoomId,
      text: _messageController.text,
    );
  }

  void _restoreMessageDraft(String roomId) {
    final draft = message_display.messageDraftForRoom(
      drafts: _messageDrafts,
      roomId: roomId,
    );
    _messageController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  void _startLiveStream() {
    final previous = _realtimeEvents;
    if (previous != null) unawaited(previous.cancel());

    final realtime = _services.realtime;
    realtime.onReconnect = _onStreamReconnect;
    _realtimeEvents = realtime.events.listen(_onRealtimeEvent);
    unawaited(realtime.start());
  }

  /// After the SSE stream (re)connects we may have missed events, so pull a
  /// fresh snapshot of the room list and the currently open room's live state.
  void _onStreamReconnect() {
    if (!mounted) return;
    unawaited(_loadRoomsSilently());
    unawaited(_refreshRoomInviteBadge());
    final selected = _selectedRoomId;
    if (selected != null) {
      unawaited(_refreshLiveSilently(selected));
      unawaited(_refreshSelectedJoinRequestBadge());
    }
  }

  /// Background room-list refresh with no spinners or error banners; the SSE
  /// stream is the primary path, this just heals gaps.
  Future<void> _loadRoomsSilently() async {
    try {
      final rooms = await _roomsController.loadRooms();
      if (!mounted) return;
      setState(
        () => _applyRoomCardsPatch(
          _roomsController.patchRoomCardsRefreshed(rooms: rooms),
        ),
      );
    } catch (_) {
      // Swallow: the last good data stays on screen.
    }
  }

  Future<void> _refreshLiveSilently(String roomId) async {
    try {
      final live = await _roomsController.getLiveState(roomId);
      if (!mounted) return;
      final patch = _roomsController.patchSelectedLiveRefreshed(
        live: live,
        selectedRoomId: _selectedRoomId,
      );
      if (patch == null) {
        return;
      }
      setState(() => _applyRoomLiveRefreshPatch(patch));
    } catch (_) {}
  }

  /// Dispatches a realtime event from the SSE stream into local UI state.
  void _onRealtimeEvent(RealtimeEvent ev) {
    switch (ev.type) {
      case 'live_participant_joined':
      case 'live_participant_left':
      case 'live_participant_updated':
      case 'live_participant_moderated':
      case 'live_room_finished':
        _applyLiveSnapshot(ev.data);
        break;
      // Room-list sync: the server pushes the full public snapshot of a room
      // when membership, settings, or the last message change, so the sidebar
      // stays live without polling.
      case 'room_added':
        _applyRoomAdded(ev.data);
        break;
      case 'room_updated':
        _applyRoomUpdated(ev.data);
        break;
      case 'room_deleted':
        _applyRoomDeleted(ev.data);
        break;
      case 'room_role_changed':
        _applyRoomRoleChanged(ev.data);
        break;
      case 'room_invites_updated':
        unawaited(_refreshRoomInviteBadge());
        break;
      case 'room_join_requests_updated':
        _applyRoomJoinRequestsUpdated(ev.data);
        break;
      default:
        // Other event types aren't wired yet.
        break;
    }
  }

  /// A room we just gained membership in (created it, joined an open room, or
  /// an admin approved our request). Insert its public snapshot; the request
  /// approver flow relies on this even though our SSE never subscribed to the
  /// room. A duplicate id is replaced rather than added twice.
  void _applyRoomAdded(Map<String, dynamic> data) {
    final card = _roomsController.roomCardFromSnapshot(data);
    if (card == null || !mounted) return;
    setState(
      () => _applyRoomCardsPatch(
        _roomsController.patchRoomCardUpserted(rooms: _rooms, room: card),
      ),
    );
  }

  /// A room's public state changed (member count, settings, rename, new last
  /// message, ...). Replace the matching card but keep our local per-user
  /// fields, which the snapshot doesn't carry.
  void _applyRoomUpdated(Map<String, dynamic> data) {
    final incoming = _roomsController.roomCardFromSnapshot(data);
    if (incoming == null || !mounted) return;
    setState(
      () => _applyRoomCardsPatch(
        _roomsController.patchRoomCardUpdated(
          rooms: _rooms,
          incoming: incoming,
        ),
      ),
    );
    if (shouldRefreshJoinRequestBadgeForRoom(
      roomId: incoming.id,
      selectedRoomId: _selectedRoomId,
      canReviewJoinRequests: _selectedRoom?.isAdmin ?? false,
    )) {
      unawaited(_refreshSelectedJoinRequestBadge());
    }
  }

  void _applyRoomJoinRequestsUpdated(Map<String, dynamic> data) {
    if (!shouldRefreshJoinRequestBadgeForEvent(
      data: data,
      selectedRoomId: _selectedRoomId,
      canReviewJoinRequests: _selectedRoom?.isAdmin ?? false,
    )) {
      return;
    }
    unawaited(_refreshSelectedJoinRequestBadge());
  }

  /// We lost a room (left, were removed, or it was deleted). Drop the card and,
  /// if it's the open room, clear the chat pane back to the empty state.
  void _applyRoomDeleted(Map<String, dynamic> data) {
    final patch = _roomsController.patchRoomDeleted(
      rooms: _rooms,
      selectedRoomId: _selectedRoomId,
      selectedRoom: _selectedRoom,
      selectedRoomHasPendingJoinRequests: _selectedRoomHasPendingJoinRequests,
      messages: _messages,
      live: _live,
      livePanelOpen: _livePanelOpen,
      settingsOpen: _settingsOpen,
      joinedLiveRoomId: _joinedLiveRoomId,
      data: data,
    );
    if (patch == null || !mounted) return;
    setState(() {
      _rooms = patch.rooms;
      _selectedRoomId = patch.selectedRoomId;
      _selectedRoom = patch.selectedRoom;
      _selectedRoomHasPendingJoinRequests =
          patch.selectedRoomHasPendingJoinRequests;
      _messages = patch.messages;
      _live = patch.live;
      _livePanelOpen = patch.livePanelOpen;
      _settingsOpen = patch.settingsOpen;
      _joinedLiveRoomId = patch.joinedLiveRoomId;
    });
    _messageDrafts = message_display.removeMessageDraft(
      drafts: _messageDrafts,
      roomId: patch.roomId,
    );
    if (patch.wasSelected) _messageController.clear();
    // If we were live in that room, the LiveKit session is now orphaned; drop
    // it so we don't keep streaming into a room we no longer belong to.
    if (patch.shouldDisconnectLive) {
      unawaited(_liveSessionController.disconnect());
    }
  }

  /// Our role in a room changed (promoted to / demoted from admin). The room
  /// list card carries no role, but the open room's detail does and gates the
  /// admin affordances, so patch its membership when it's the selected room.
  void _applyRoomRoleChanged(Map<String, dynamic> data) {
    final patch = _roomsController.patchRoomRoleChanged(
      selectedRoom: _selectedRoom,
      data: data,
    );
    if (patch == null || !mounted) return;
    setState(() {
      _selectedRoom = patch.selectedRoom;
    });
    unawaited(_refreshSelectedJoinRequestBadge(patch.selectedRoom));
  }

  void _applyLiveSnapshot(Map<String, dynamic> data) {
    final patch = _roomsController.patchLiveSnapshot(
      rooms: _rooms,
      selectedRoomId: _selectedRoomId,
      data: data,
      joinedLiveRoomId: _joinedLiveRoomId,
      currentUserId: _currentUser.id,
      previousLive: _live,
    );
    if (patch == null || !mounted) return;
    setState(() {
      _rooms = patch.rooms;
      if (patch.selectedLive != null) _live = patch.selectedLive;
    });
  }

  void _onLiveSessionChanged() {
    if (!mounted) return;
    // If the OS-level "stop sharing" bar (or a track failure) ended our screen
    // share, the LiveKit session knows before the server does. Reconcile the
    // server flag so the roster stops showing us as sharing.
    if (live_display.shouldPatchEndedLocalScreenShare(
      localScreenSharing: _screenSharing,
      sessionScreenSharing: _liveSessionController.isScreenSharing,
      joinedLiveRoomId: _joinedLiveRoomId,
      selectedRoomId: _selectedRoomId,
    )) {
      unawaited(_patchLiveState(screenSharing: false));
    }
    setState(() {});
  }

  /// An admin kicked us: LiveKit tore down our session via RemoveParticipant.
  /// Drop joined state and exit the voice panel; do not auto-reconnect (the
  /// next deliberate Join goes through the normal join flow, which the server
  /// gates against any standing ban).
  void _onForciblyRemovedFromLive() {
    if (!mounted) return;
    final patch = _liveController.patchLocalDeparture(
      live: _live,
      rooms: _rooms,
      joinedLiveRoomId: _joinedLiveRoomId,
      userId: _currentUser.id,
      joiningLive: false,
    );
    setState(() => _applyLiveLocalDeparturePatch(patch));
    // Drop any lingering transport so a stale connection can't auto-reconnect.
    unawaited(_liveSessionController.disconnect());
    _showToast(live_display.liveForciblyRemovedNotice());
  }

  /// LiveKit reported our publish permission changed (admin block_voice /
  /// restore_voice). LiveKit is authoritative, so mirror it into the mic UI:
  /// when blocked the mic is force-muted and the button is disabled; when
  /// restored the button is re-enabled but stays muted until the user opens it.
  void _onPublishPermissionChanged(bool canPublish) {
    if (!mounted) return;
    final patch = _liveController.patchPublishPermission(
      canPublish: canPublish,
      micMuted: _micMuted,
    );
    setState(() => _applyLivePublishPermissionPatch(patch));
  }

  /// Best-effort live-session teardown. Caller is responsible for waiting on
  /// this before letting the process exit. Wrapped with a hard timeout so a
  /// hung server can't keep the window alive forever.
  ///
  /// Dropping the LiveKit connection is now the only thing we do: the server
  /// learns the participant left via the LiveKit webhook and broadcasts it
  /// over SSE. There is no `leaveLive` HTTP call any more. [reason] is kept
  /// for call-site readability even though the teardown is now uniform.
  Future<void> _shutdownLive({required String reason}) async {
    _joinedLiveRoomId = null;
    await _liveSessionController.disconnect(
      timeout: const Duration(seconds: 1),
    );
  }

  Future<void> _handleLogout() async {
    await _shutdownLive(reason: 'logout');
    await widget.app.logout();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Coming back to the foreground: pull a snapshot in case the SSE
      // connection went stale while hidden. The stream's own watchdog will
      // reconnect the transport if needed.
      _onStreamReconnect();
    }
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.session.user.id != widget.app.session.user.id) {
      _currentUser = widget.app.session.user;
      _resetNavigationBadges();
      unawaited(_refreshRoomInviteBadge());
      unawaited(_warmPersonalStickerCache());
    }
    if (widget.app.hasSameApiSource(oldWidget.app)) {
      return;
    }
    final realtimeEvents = _realtimeEvents;
    if (realtimeEvents != null) unawaited(realtimeEvents.cancel());
    _realtimeEvents = null;
    _detachLiveSessionCallbacks();
    _services.close();
    _services = AuthenticatedAppServices(
      widget.app,
      audioDeviceStore: widget.audioDeviceStore,
    );
    _attachLiveSessionCallbacks();
    // The stream is keyed to apiBaseUrl, so restart it against the new host.
    _startLiveStream();
    _resetNavigationBadges();
    _loadRooms();
    unawaited(_refreshRoomInviteBadge());
    unawaited(_warmPersonalStickerCache());
  }

  Future<void> _warmPersonalStickerCache() async {
    await _services.warmPersonalStickerCache(userId: _currentUser.id);
  }

  Future<void> _loadRooms() async {
    setState(
      () => _applyRoomListLoadPatch(
        _roomsController.patchRoomListLoadStarted(rooms: _rooms),
      ),
    );
    try {
      final rooms = await _roomsController.loadRooms();
      if (!mounted) return;
      setState(
        () => _applyRoomListLoadPatch(
          _roomsController.patchRoomListLoadSucceeded(rooms: rooms),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyRoomListLoadPatch(
          _roomsController.patchRoomListLoadFailed(rooms: _rooms, failure: e),
        ),
      );
    }
  }

  Future<void> _refreshRoomInviteBadge() async {
    try {
      final hasPending = await _roomsController.hasPendingRoomInvites();
      if (!mounted) return;
      _setPendingRoomInviteBadge(hasPending);
    } catch (_) {
      // Keep the last known badge state; transient failures should not clear it.
    }
  }

  Future<void> _refreshSelectedJoinRequestBadge([RoomDetail? room]) async {
    final candidate = room ?? _selectedRoom;
    final access = candidate == null
        ? null
        : room_display.roomAccessState(
            room: candidate,
            currentUser: _currentUser,
          );
    final target = joinRequestBadgeRefreshTarget(
      room: candidate,
      canReviewJoinRequests: access?.canReviewJoinRequests ?? false,
    );
    if (target == null) {
      if (mounted) _setSelectedJoinRequestBadge(false);
      return;
    }
    try {
      final hasPending = await _roomsController.hasPendingJoinRequests(
        target,
        canReviewJoinRequests: access?.canReviewJoinRequests ?? false,
      );
      if (!mounted ||
          !canApplyJoinRequestBadgeRefresh(
            targetRoomId: target.id,
            selectedRoomId: _selectedRoomId,
          )) {
        return;
      }
      _setSelectedJoinRequestBadge(hasPending);
    } catch (_) {
      // Keep the last known badge state; permission or network failures should
      // not create a distracting flicker.
    }
  }

  void _setPendingRoomInviteBadge(bool hasPending) {
    final patch = roomInviteBadgeUpdated(
      currentHasPendingRoomInvites: _hasPendingRoomInvites,
      currentSelectedRoomHasPendingJoinRequests:
          _selectedRoomHasPendingJoinRequests,
      hasPending: hasPending,
    );
    if (patch == null) return;
    _applyNavigationBadgePatch(patch);
  }

  void _setSelectedJoinRequestBadge(bool hasPending) {
    final patch = selectedJoinRequestBadgeUpdated(
      currentHasPendingRoomInvites: _hasPendingRoomInvites,
      currentSelectedRoomHasPendingJoinRequests:
          _selectedRoomHasPendingJoinRequests,
      hasPending: hasPending,
    );
    if (patch == null) return;
    _applyNavigationBadgePatch(patch);
  }

  void _resetNavigationBadges() {
    final patch = roomNavigationBadgesReset(
      currentHasPendingRoomInvites: _hasPendingRoomInvites,
      currentSelectedRoomHasPendingJoinRequests:
          _selectedRoomHasPendingJoinRequests,
    );
    if (patch == null) return;
    _applyNavigationBadgePatch(patch);
  }

  void _applyNavigationBadgePatch(RoomNavigationBadgePatch patch) {
    if (!mounted) return;
    setState(() {
      _hasPendingRoomInvites = patch.hasPendingRoomInvites;
      _selectedRoomHasPendingJoinRequests =
          patch.selectedRoomHasPendingJoinRequests;
    });
  }

  Future<void> _openRoom(
    RoomCard room, {
    bool joinLive = false,
    RoomDetail? optimisticDetail,
  }) async {
    if (shouldSkipRoomOpenRequest(
      loadingRoom: _loadingRoom,
      selectedRoomId: _selectedRoomId,
      roomId: room.id,
    )) {
      return;
    }
    _saveCurrentMessageDraft();
    setState(() {
      _applyRoomOpenPatch(
        _roomsController.patchRoomOpenStarted(
          roomId: room.id,
          currentSelectedRoom: _selectedRoom,
          currentMessages: _messages,
          currentLive: _live,
          currentLivePanelOpen: _livePanelOpen,
          joinLive: joinLive,
          optimisticDetail: optimisticDetail,
        ),
      );
    });
    _restoreMessageDraft(room.id);

    try {
      final snapshot = await _roomsController.openRoom(room.id);
      if (!mounted ||
          !canApplyRoomOpenResult(
            requestedRoomId: room.id,
            selectedRoomId: _selectedRoomId,
          )) {
        return;
      }
      setState(() {
        _applyRoomOpenPatch(
          _roomsController.patchRoomOpenSucceeded(
            currentSettingsOpen: _settingsOpen,
            currentLoadingRoom: _loadingRoom,
            currentError: _error,
            currentSelectedRoomHasPendingJoinRequests:
                _selectedRoomHasPendingJoinRequests,
            snapshot: snapshot,
            joinLive: joinLive,
          ),
        );
      });
      final effects = roomOpenSucceededEffects(
        snapshot: snapshot,
        joinLive: joinLive,
      );
      unawaited(_refreshSelectedJoinRequestBadge(effects.joinRequestBadgeRoom));
      final joinLiveSource = effects.joinLiveSource;
      if (joinLiveSource != null) await _joinLive(joinLiveSource);
    } catch (e) {
      if (!mounted) return;
      if (shouldShowOptimisticRoomOpenRefreshFailure(
        hasOptimisticDetail: optimisticDetail != null,
        requestedRoomId: room.id,
        selectedRoomId: _selectedRoomId,
      )) {
        _showToast(room_display.roomOptimisticOpenRefreshFailureNotice());
      } else {
        setState(() {
          _applyRoomOpenPatch(
            _roomsController.patchRoomOpenFailed(
              settingsOpen: _settingsOpen,
              selectedRoomId: _selectedRoomId,
              selectedRoom: _selectedRoom,
              loadingRoom: _loadingRoom,
              selectedRoomHasPendingJoinRequests:
                  _selectedRoomHasPendingJoinRequests,
              messages: _messages,
              live: _live,
              livePanelOpen: _livePanelOpen,
              failure: e,
            ),
          );
        });
      }
    } finally {
      if (mounted &&
          shouldFinishRoomOpenLoading(
            requestedRoomId: room.id,
            selectedRoomId: _selectedRoomId,
          )) {
        setState(() {
          _applyRoomOpenPatch(
            _roomsController.patchRoomOpenFinished(
              settingsOpen: _settingsOpen,
              selectedRoomId: _selectedRoomId,
              selectedRoom: _selectedRoom,
              error: _error,
              selectedRoomHasPendingJoinRequests:
                  _selectedRoomHasPendingJoinRequests,
              messages: _messages,
              live: _live,
              livePanelOpen: _livePanelOpen,
            ),
          );
        });
      }
    }
  }

  void _applyRoomOpenPatch(RoomOpenStatePatch patch) {
    _settingsOpen = patch.settingsOpen;
    _selectedRoomId = patch.selectedRoomId;
    _selectedRoom = patch.selectedRoom;
    _loadingRoom = patch.loadingRoom;
    _error = patch.error;
    _selectedRoomHasPendingJoinRequests =
        patch.selectedRoomHasPendingJoinRequests;
    _messages = patch.messages;
    _live = patch.live;
    _livePanelOpen = patch.livePanelOpen;
  }

  void _applyRoomListLoadPatch(RoomListLoadPatch patch) {
    _rooms = patch.rooms;
    _loadingRooms = patch.loading;
    _error = patch.error;
  }

  void _applyRoomCardsPatch(RoomCardsPatch patch) {
    _rooms = patch.rooms;
  }

  void _applyRoomSelectedDetailPatch(RoomSelectedDetailPatch patch) {
    _selectedRoom = patch.selectedRoom;
    _rooms = patch.rooms;
  }

  void _applyRoomLiveRefreshPatch(RoomLiveRefreshPatch patch) {
    _live = patch.live;
  }

  Future<void> _createRoom() async {
    final created = await showDialog<RoomDetail>(
      context: context,
      builder: (context) => _CreateRoomDialog(controller: _roomsController),
    );
    if (created == null || !mounted) return;
    setState(
      () => _applyRoomCardsPatch(
        _roomsController.patchRoomCardUpserted(
          rooms: _rooms,
          room: created.toCard(),
        ),
      ),
    );
    await _openRoom(created.toCard(), optimisticDetail: created);
  }

  /// Opens the search-and-join dialog. On a successful join the dialog returns
  /// the new room detail; we add it to the list and open it. A pending
  /// (approval-required) join returns null and the dialog shows its own state.
  Future<void> _joinRoom() async {
    final joined = await showDialog<RoomDetail>(
      context: context,
      builder: (context) => _JoinRoomDialog(
        controller: _roomsController,
        onOpenUserInfo: (user) => _showUserInfo(user, basic: true),
        onPendingInvitesChanged: _setPendingRoomInviteBadge,
      ),
    );
    unawaited(_refreshRoomInviteBadge());
    if (joined == null || !mounted) return;
    setState(
      () => _applyRoomCardsPatch(
        _roomsController.patchRoomCardUpserted(
          rooms: _rooms,
          room: joined.toCard(),
        ),
      ),
    );
    await _openRoom(joined.toCard(), optimisticDetail: joined);
  }

  /// Opens the room member list. After it closes (invites or approvals may
  /// have added members), refresh the room so the member count stays accurate.
  Future<void> _openRoomMembers() async {
    final room = _selectedRoom;
    if (room == null) return;
    final access = room_display.roomAccessState(
      room: room,
      currentUser: _currentUser,
    );
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _RoomMembersDialog(
        controller: _roomsController,
        room: room,
        initialLive: _live ?? room.live,
        canReviewRequests: access.canReviewJoinRequests,
        onOpenUserInfo: _showUserInfo,
        onPendingRequestsChanged: _setSelectedJoinRequestBadge,
      ),
    );
    unawaited(_refreshSelectedJoinRequestBadge(room));
    if (changed != true || !mounted) return;
    try {
      final detail = await _roomsController.getRoom(room.id);
      if (!mounted) return;
      final patch = _roomsController.patchSelectedRoomDetailRefreshed(
        rooms: _rooms,
        selectedRoomId: _selectedRoomId,
        detail: detail,
      );
      if (patch == null) return;
      setState(() => _applyRoomSelectedDetailPatch(patch));
    } catch (_) {
      // Best-effort refresh; the SSE/next fetch will reconcile.
    }
  }

  Future<void> _openRoomInfo() async {
    final room = _selectedRoom;
    if (room == null) return;
    final result = await showDialog<Object?>(
      context: context,
      builder: (context) => _RoomInfoDialog(
        controller: _roomsController,
        room: room,
        currentUser: _currentUser,
        clipboardService: widget.clipboardService,
        fileSelectionService: widget.fileSelectionService,
        isInLive: _joinedLiveRoomId == room.id,
        onLeaveLive: _leaveLive,
        onOpenUserInfo: (user) => _showUserInfo(user, roomContext: room),
      ),
    );
    _handleRoomDialogResult(room.id, result);
  }

  Future<void> _openRoomManagement() async {
    final room = _selectedRoom;
    if (room == null) return;
    final access = room_display.roomAccessState(
      room: room,
      currentUser: _currentUser,
    );
    if (!access.canManageRoom) return;
    final result = await showDialog<Object?>(
      context: context,
      builder: (context) => _RoomManagementDialog(
        controller: _roomsController,
        room: room,
        currentUser: _currentUser,
        fileSelectionService: widget.fileSelectionService,
      ),
    );
    _handleRoomDialogResult(room.id, result);
  }

  void _handleRoomDialogResult(String roomId, Object? result) {
    if (!mounted || result == null) return;
    if (result is RoomDetail) {
      setState(
        () => _applyRoomSelectedDetailPatch(
          _roomsController.patchRoomDetailApplied(
            rooms: _rooms,
            detail: result,
          ),
        ),
      );
      unawaited(_refreshSelectedJoinRequestBadge(result));
      return;
    }
    if (result == _RoomDialogCloseResult.left ||
        result == _RoomDialogCloseResult.deleted) {
      _applyRoomDeleted({'room_id': roomId});
    }
  }

  void _showUserInfo(
    UserSummary user, {
    bool includeSelectedRoom = true,
    bool basic = false,
    RoomDetail? roomContext,
  }) {
    unawaited(
      _showUserInfoDialog(
        user,
        includeSelectedRoom: includeSelectedRoom,
        basic: basic,
        roomContext: roomContext,
      ),
    );
  }

  Future<void> _showUserInfoDialog(
    UserSummary user, {
    required bool includeSelectedRoom,
    required bool basic,
    RoomDetail? roomContext,
  }) async {
    final room = roomContext ?? _selectedRoom;
    if (basic || room == null) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => _BasicUserInfoDialog(
          user: user,
          onCopyUid: (uid) => unawaited(_copyUserInfoUid(uid)),
        ),
      );
      return;
    }
    var userForCard = user;
    try {
      final memberProfile = await _roomsController.getRoomMemberProfile(
        roomId: room.id,
        userId: user.id,
      );
      userForCard = memberProfile.user.mergeMissing(user);
    } catch (_) {
      // Some legacy responses only contain the lightweight sender summary.
      // Keep opening the card with what we already have.
    }
    if (!mounted) return;
    final profile = room_display.roomUserInfoProfile(
      user: userForCard,
      room: room,
      currentUser: _currentUser,
    );
    final roomsSectionTitle = room_display.userRoomsSectionTitle(
      user: profile,
      currentUser: _currentUser,
    );
    showDialog<void>(
      context: context,
      builder: (context) => _UserInfoDialog(
        user: profile,
        room: room,
        roomsSectionTitle: roomsSectionTitle,
        commonRooms: room_display.roomUserInfoCommonRooms(
          user: profile,
          selectedRoom: room,
          currentUser: _currentUser,
          includeSelectedRoom: includeSelectedRoom,
        ),
        onOpenRoom: _showUserInfoRoomInfo,
        onCopyUid: (uid) => unawaited(_copyUserInfoUid(uid)),
      ),
    );
  }

  Future<void> _copyUserInfoUid(String uid) async {
    try {
      await widget.clipboardService.writeText(uid);
      if (!mounted) return;
      _showToast(
        room_display.userUidCopySuccessNotice(),
        kind: HomeToastKind.success,
      );
    } catch (e) {
      if (!mounted) return;
      _showToast(room_display.userUidCopyFailureMessage(e));
    }
  }

  Future<void> _showUserInfoRoomInfo(String roomId) async {
    try {
      final detail = roomId == _selectedRoom?.id
          ? _selectedRoom!
          : await _roomsController.getRoom(roomId);
      if (!mounted) return;
      final result = await showDialog<Object?>(
        context: context,
        builder: (context) => _RoomInfoDialog(
          controller: _roomsController,
          room: detail,
          currentUser: _currentUser,
          clipboardService: widget.clipboardService,
          fileSelectionService: widget.fileSelectionService,
          isInLive: _joinedLiveRoomId == detail.id,
          onLeaveLive: _leaveLive,
          onOpenUserInfo: (user) => _showUserInfo(user, roomContext: detail),
        ),
      );
      _handleRoomDialogResult(detail.id, result);
    } catch (e) {
      if (!mounted) return;
      _showToast(room_display.roomOpenFailureMessage(e));
    }
  }

  Future<void> _sendMessage() async {
    final body = message_display.outgoingTextMessageBody(
      _messageController.text,
    );
    if (body == null) return;
    await _sendMessagePayload(body: body, clearDraft: true);
  }

  Future<void> _sendStickerMessage(Sticker sticker) async {
    final draft = message_display.stickerMessageDraft(sticker);
    await _sendMessagePayload(
      body: draft.body,
      type: draft.type,
      attachments: draft.attachments,
    );
  }

  Future<void> _saveStickerToPersonal(Sticker sticker) async {
    final roomId = _selectedRoomId;
    if (roomId == null) return;
    try {
      await _services.stickers.saveSticker(
        roomId: roomId,
        stickerId: sticker.id,
        targetScope: 'personal',
        userId: _currentUser.id,
        name: sticker.name,
      );
      if (!mounted) return;
      _showToast('已添加到我的表情包', kind: HomeToastKind.success);
    } catch (e) {
      if (!mounted) return;
      _showToast(e.toString());
    }
  }

  Future<void> _saveStickerToRoom(Sticker sticker) async {
    final roomId = _selectedRoomId;
    if (roomId == null) return;
    try {
      await _services.stickers.saveSticker(
        roomId: roomId,
        stickerId: sticker.id,
        targetScope: 'room',
        userId: _currentUser.id,
        name: sticker.name,
      );
      if (!mounted) return;
      _showToast('已添加到房间表情包', kind: HomeToastKind.success);
    } catch (e) {
      if (!mounted) return;
      _showToast(e.toString());
    }
  }

  Future<void> _saveStickerAs(Sticker sticker) async {
    try {
      final file = await _roomsController.downloadStickers(
        stickerIds: [sticker.id],
      );
      if (!mounted) return;
      final location = await widget.fileSelectionService.getSaveLocation(
        suggestedName: file.filename,
        confirmButtonText: '保存',
      );
      if (location == null || !mounted) return;
      await widget.fileSelectionService.saveBytesToPath(
        bytes: file.bytes,
        path: location.path,
        filename: file.filename,
        mimeType: file.mimeType,
      );
      if (!mounted) return;
      _showToast('表情已保存', kind: HomeToastKind.success);
    } catch (e) {
      if (!mounted) return;
      _showToast(e.toString());
    }
  }

  Future<void> _pickAndSendFile() async {
    SelectedFile? file;
    try {
      file = await widget.fileSelectionService.openFile();
    } catch (e) {
      if (!mounted) return;
      _showToast(file_display.filePickerOpenFailureMessage(e));
      return;
    }
    if (file == null || !mounted) return;
    unawaited(_sendSelectedFile(file));
  }

  Future<void> _sendSelectedFile(SelectedFile file) async {
    final room = _selectedRoom;
    if (room == null) return;

    final filename = file_display.basename(file.name);
    int length;
    try {
      length = await file.length();
    } catch (e) {
      if (!mounted) return;
      _showToast(file_display.fileReadFailureMessage(e));
      return;
    }
    if (length == 0) {
      _showToast(file_display.fileEmptyMessage());
      return;
    }

    String? clientMessageId;
    FileTransferState? transfer;
    try {
      final sent = await _messagesController.sendFileMessage(
        roomId: room.id,
        sender: _currentUser.toSummary(),
        filename: filename,
        sizeBytes: length,
        mimeType: file.mimeType ?? file_display.mimeTypeFromFilename(filename),
        readBytes: file.readAsBytes,
        onPending: (pending) {
          clientMessageId = pending.clientMessageId;
          transfer = pending.transfer;
          if (!mounted) return;
          setState(() {
            _applyFileMessageStatePatch(
              _messagesController.patchPendingFileMessage(
                messages: _messages,
                fileTransfers: _fileTransfers,
                pending: pending,
              ),
            );
            _error = null;
          });
        },
        onProgress: (pending, {required sentBytes, required totalBytes}) {
          if (!mounted) return;
          final patch = _messagesController.patchFileTransferProgress(
            messages: _messages,
            fileTransfers: _fileTransfers,
            pending: pending,
            sentBytes: sentBytes,
            totalBytes: totalBytes,
          );
          if (patch == null) return;
          setState(() => _applyFileMessageStatePatch(patch));
        },
        onUploaded: (pending, attachment) {
          if (!mounted) return;
          setState(
            () => _applyFileMessageStatePatch(
              _messagesController.patchUploadedFileMessage(
                messages: _messages,
                fileTransfers: _fileTransfers,
                pending: pending,
                attachment: attachment,
              ),
            ),
          );
        },
      );
      final activeClientMessageId = clientMessageId;
      final activeTransfer = transfer;
      if (!mounted ||
          activeClientMessageId == null ||
          activeTransfer == null ||
          activeTransfer.cancelled) {
        return;
      }
      setState(
        () => _applyFileMessageStatePatch(
          _messagesController.patchSentFileMessage(
            messages: _messages,
            fileTransfers: _fileTransfers,
            clientMessageId: activeClientMessageId,
            sent: sent,
          ),
        ),
      );
      await _loadRooms();
    } on UploadCancelledException {
      if (!mounted) return;
      final activeClientMessageId = clientMessageId;
      if (activeClientMessageId != null) {
        _removeLocalFileMessage(activeClientMessageId);
      }
    } catch (e) {
      if (!mounted) return;
      final activeClientMessageId = clientMessageId;
      final activeTransfer = transfer;
      if (activeTransfer == null || activeClientMessageId == null) {
        _showToast(e.toString());
        return;
      }
      if (activeTransfer.cancelled) {
        _removeLocalFileMessage(activeClientMessageId);
        return;
      }
      setState(
        () => _applyFileMessageStatePatch(
          _messagesController.patchFailedFileMessage(
            messages: _messages,
            fileTransfers: _fileTransfers,
            clientMessageId: activeClientMessageId,
            failure: e,
          ),
        ),
      );
      _showToast(e.toString());
    }
  }

  void _pauseFileUpload(String clientMessageId) {
    final patch = _messagesController.patchPausedFileUpload(
      messages: _messages,
      fileTransfers: _fileTransfers,
      clientMessageId: clientMessageId,
    );
    if (patch == null) return;
    setState(() => _applyFileMessageStatePatch(patch));
  }

  void _resumeFileUpload(String clientMessageId) {
    final patch = _messagesController.patchResumedFileUpload(
      messages: _messages,
      fileTransfers: _fileTransfers,
      clientMessageId: clientMessageId,
    );
    if (patch == null) return;
    setState(() => _applyFileMessageStatePatch(patch));
  }

  void _cancelFileUpload(String clientMessageId) {
    final changed = _messagesController.cancelFileUpload(
      fileTransfers: _fileTransfers,
      clientMessageId: clientMessageId,
    );
    if (!changed) return;
    _removeLocalFileMessage(clientMessageId);
  }

  void _removeLocalFileMessage(String clientMessageId) {
    if (!mounted) return;
    setState(
      () => _applyFileMessageStatePatch(
        _messagesController.patchRemovedFileMessage(
          messages: _messages,
          fileTransfers: _fileTransfers,
          clientMessageId: clientMessageId,
        ),
      ),
    );
  }

  Future<void> _downloadFileAttachment({
    required String downloadKey,
    required MessageAttachment attachment,
    required String url,
  }) async {
    if (!_fileDownloadsController.canStartDownload(
      downloads: _fileDownloads,
      downloadKey: downloadKey,
    )) {
      return;
    }

    final uri = file_display.fileDownloadUri(url);
    if (uri == null) {
      _showToast(file_display.fileDownloadUnavailableMessage());
      return;
    }

    final filename = file_display.fileAttachmentTitle(attachment);
    final location = await widget.fileSelectionService.getSaveLocation(
      suggestedName: filename,
      confirmButtonText: 'Save',
    );
    if (location == null || !mounted) return;

    final destinationPath = location.path;
    final transfer = _fileDownloadsController.createDownload(
      totalBytes: attachment.asset?.sizeBytes ?? 0,
      destinationPath: destinationPath,
    );
    setState(
      () => _applyFileDownloadStatePatch(
        _fileDownloadsController.patchStartedDownload(
          downloads: _fileDownloads,
          downloadKey: downloadKey,
          transfer: transfer,
        ),
      ),
    );

    try {
      await _fileDownloadsController.downloadToFile(
        uri: uri,
        transfer: transfer,
        onProgress: ({required sentBytes, required totalBytes}) {
          if (!mounted) return;
          final patch = _fileDownloadsController.patchDownloadProgress(
            downloads: _fileDownloads,
            downloadKey: downloadKey,
            transfer: transfer,
          );
          if (patch == null) return;
          setState(() => _applyFileDownloadStatePatch(patch));
        },
      );
      if (!mounted ||
          !_fileDownloadsController.canCompleteDownload(
            downloads: _fileDownloads,
            downloadKey: downloadKey,
            transfer: transfer,
          )) {
        return;
      }
      setState(
        () => _applyFileDownloadStatePatch(
          _fileDownloadsController.patchCompletedDownload(
            downloads: _fileDownloads,
            downloadKey: downloadKey,
          ),
        ),
      );
      _showToast(
        file_display.fileDownloadedNotice(),
        kind: HomeToastKind.success,
      );
    } on DownloadCancelledException {
      // The controller has already cleaned up any partial file.
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyFileDownloadStatePatch(
          _fileDownloadsController.patchFailedDownload(
            downloads: _fileDownloads,
            transfer: transfer,
            failure: e,
          ),
        ),
      );
      _showToast(e.toString());
    } finally {
      if (transfer.cancelled && mounted) {
        setState(
          () => _applyFileDownloadStatePatch(
            _fileDownloadsController.patchRemovedDownload(
              downloads: _fileDownloads,
              downloadKey: downloadKey,
            ),
          ),
        );
      }
    }
  }

  void _pauseFileDownload(String downloadKey) {
    final patch = _fileDownloadsController.patchPausedDownload(
      downloads: _fileDownloads,
      downloadKey: downloadKey,
    );
    if (patch == null) return;
    setState(() => _applyFileDownloadStatePatch(patch));
  }

  void _resumeFileDownload(String downloadKey) {
    final patch = _fileDownloadsController.patchResumedDownload(
      downloads: _fileDownloads,
      downloadKey: downloadKey,
    );
    if (patch == null) return;
    setState(() => _applyFileDownloadStatePatch(patch));
  }

  void _cancelFileDownload(String downloadKey) {
    final transfer = _fileDownloads[downloadKey];
    if (transfer == null) return;
    if (!transfer.active) {
      setState(
        () => _applyFileDownloadStatePatch(
          _fileDownloadsController.patchRemovedDownload(
            downloads: _fileDownloads,
            downloadKey: downloadKey,
          ),
        ),
      );
      final destinationPath = _fileDownloadsController
          .partialDownloadPathToDelete(transfer);
      if (destinationPath != null) {
        unawaited(
          _fileDownloadsController.deletePartialDownload(destinationPath),
        );
      }
      return;
    }
    final changed = _fileDownloadsController.cancelDownload(
      downloads: _fileDownloads,
      downloadKey: downloadKey,
    );
    if (!changed) return;
    setState(
      () => _applyFileDownloadStatePatch(
        _fileDownloadsController.patchRemovedDownload(
          downloads: _fileDownloads,
          downloadKey: downloadKey,
        ),
      ),
    );
  }

  Future<void> _sendMessagePayload({
    required String body,
    String type = 'text',
    List<MessageAttachment> attachments = const [],
    bool clearDraft = false,
  }) async {
    final room = _selectedRoom;
    if (room == null || _sending) return;

    if (!canSendComposedMessage(
      body: body,
      type: type,
      attachments: attachments,
    )) {
      return;
    }

    String? clientMessageId;

    setState(
      () => _applyMessageSendStatePatch(
        _messagesController.patchMessageSendStarted(messages: _messages),
      ),
    );

    try {
      final sent = await _messagesController.sendComposedMessage(
        roomId: room.id,
        sender: _currentUser.toSummary(),
        body: body,
        type: type,
        attachments: attachments,
        onPending: (pending) {
          clientMessageId = pending.clientMessageId;
          if (!mounted) return;
          setState(() {
            _applyMessageSendStatePatch(
              _messagesController.patchMessageSendPending(
                messages: _messages,
                pending: pending,
                error: _error,
              ),
            );
            if (clearDraft) _messageController.clear();
          });
        },
      );
      if (!mounted) return;
      setState(
        () => _applyMessageSendStatePatch(
          _messagesController.patchMessageSendSucceeded(
            messages: _messages,
            sent: sent,
            error: _error,
          ),
        ),
      );
      await _loadRooms();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyMessageSendStatePatch(
          _messagesController.patchMessageSendFailed(
            messages: _messages,
            clientMessageId: clientMessageId,
            error: _error,
          ),
        ),
      );
      _showToast(e.toString());
    } finally {
      if (mounted) {
        setState(
          () => _applyMessageSendStatePatch(
            _messagesController.patchMessageSendFinished(
              messages: _messages,
              error: _error,
            ),
          ),
        );
      }
    }
  }

  void _applyMessageSendStatePatch(MessageSendStatePatch patch) {
    _messages = patch.messages;
    _sending = patch.sending;
    _error = patch.error;
  }

  void _applyFileMessageStatePatch(FileMessageStatePatch patch) {
    _messages = patch.messages;
    _fileTransfers = patch.fileTransfers;
  }

  void _applyFileDownloadStatePatch(FileDownloadStatePatch patch) {
    _fileDownloads = patch.downloads;
  }

  void _applyLiveJoinStatePatch(LiveJoinStatePatch patch) {
    _joinedLiveRoomId = patch.joinedLiveRoomId;
    _joiningLive = patch.joiningLive;
    _livePanelOpen = patch.livePanelOpen;
    _error = patch.error;
  }

  void _applyLiveJoinPreviousRoomDisconnectedPatch(
    LiveJoinPreviousRoomDisconnectedPatch patch,
  ) {
    _live = patch.live;
    _rooms = patch.rooms;
    _joinedLiveRoomId = patch.joinedLiveRoomId;
    _joiningLive = patch.joiningLive;
    _livePanelOpen = patch.livePanelOpen;
    _error = patch.error;
  }

  void _applyLiveLocalDeparturePatch(LiveLocalDeparturePatch patch) {
    _live = patch.live;
    _rooms = patch.rooms;
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
    _rooms = patch.rooms;
  }

  void _applyLiveStateUpdatePatch(LiveStateUpdatePatch patch) {
    _micMuted = patch.micMuted;
    _cameraOn = patch.cameraOn;
    _screenSharing = patch.screenSharing;
    _voiceBlocked = patch.voiceBlocked;
    _live = patch.live;
  }

  void _applyLiveOutputMutePatch(LiveOutputMutePatch patch) {
    setState(() {
      _headphonesMuted = patch.headphonesMuted;
    });
  }

  void _toggleHeadphonesMute() {
    final patch = liveOutputMuteToggled(headphonesMuted: _headphonesMuted);
    _applyLiveOutputMutePatch(patch);
    unawaited(_liveSessionController.setOutputMuted(patch.headphonesMuted));
  }

  Future<void> _joinLive(String source) async {
    final room = _selectedRoom;
    if (room == null || _joiningLive) return;

    setState(
      () => _applyLiveJoinStatePatch(
        _liveController.patchJoinStarted(joinedLiveRoomId: _joinedLiveRoomId),
      ),
    );

    final previousLiveRoomId = joinedLiveRoomToDisconnectBeforeJoin(
      joinedLiveRoomId: _joinedLiveRoomId,
      targetRoomId: room.id,
    );
    if (previousLiveRoomId != null) {
      // Switching rooms: drop the LiveKit connection to the previous room. The
      // server cleans up the old live_participants row via the LiveKit webhook
      // and broadcasts the departure over SSE — no explicit leave call needed.
      await _liveSessionController.disconnect();
      // Drop the stale joined marker immediately, and optimistically remove
      // ourselves from the previous room's live state so its count decrements
      // without waiting on the SSE snapshot (which can lag or briefly drop).
      if (mounted) {
        setState(() {
          _applyLiveJoinPreviousRoomDisconnectedPatch(
            _liveController.patchJoinPreviousRoomDisconnected(
              live: _live,
              rooms: _rooms,
              previousRoomId: previousLiveRoomId,
              userId: _currentUser.id,
              livePanelOpen: _livePanelOpen,
              error: _error,
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
      // Reflect the freshly-fetched live roster, but do NOT mark ourselves as
      // joined yet: that flips only once the LiveKit transport is actually up,
      // so the Join button keeps its loading spinner until we're truly in the
      // room (rather than briefly showing the in-room controls + a spinner on
      // the disconnect button).
      final patch = _liveController.patchJoinResult(
        rooms: _rooms,
        result: result,
      );
      setState(() => _applyLiveJoinResultPatch(patch));
      try {
        await _liveSessionController.connectWithRetry(
          result,
          isCancelled: () => !mounted,
        );
      } catch (e) {
        if (!mounted) return;
        _showToast(live_display.liveVoiceConnectFailureMessage(e));
        return;
      }
      // LiveKit transport is up — now we're genuinely in the room.
      if (!mounted) return;
      setState(
        () => _applyLiveJoinStatePatch(
          _liveController.patchJoinConnected(
            roomId: room.id,
            livePanelOpen: _livePanelOpen,
            error: _error,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showToast(e.toString());
    } finally {
      if (mounted) {
        setState(
          () => _applyLiveJoinStatePatch(
            _liveController.patchJoinFinished(
              joinedLiveRoomId: _joinedLiveRoomId,
              livePanelOpen: _livePanelOpen,
              error: _error,
            ),
          ),
        );
      }
    }
  }

  Future<void> _leaveLive() async {
    final roomId = _joinedLiveRoomId;
    if (roomId == null) return;

    // Clear our live identity *before* dropping the transport. disconnect()
    // synchronously ends our local tracks, which fires _onLiveSessionChanged;
    // while _joinedLiveRoomId / _screenSharing were still set that listener
    // would PATCH the server right as the LiveKit webhook deletes our row,
    // producing a spurious "user is not in live" 409 toast. Clearing first
    // makes the listener a no-op. We also optimistically drop ourselves from
    // the local live state so the count updates immediately — the LiveKit
    // webhook can lag and the SSE connection may briefly be down, so we can't
    // wait on the snapshot. A later snapshot reconciles if we guessed wrong.
    final patch = _liveController.patchLocalDeparture(
      live: _live,
      rooms: _rooms,
      joinedLiveRoomId: roomId,
      userId: _currentUser.id,
      joiningLive: true,
    );
    setState(() => _applyLiveLocalDeparturePatch(patch));
    try {
      // Drop the LiveKit connection. The server observes the disconnect via
      // the LiveKit webhook, removes the live_participants row, and pushes the
      // updated snapshot back to every client (including this one) over SSE.
      await _liveSessionController.disconnect();
    } catch (e) {
      if (!mounted) return;
      _showToast(e.toString());
    } finally {
      if (mounted) {
        setState(
          () => _applyLiveJoinStatePatch(
            _liveController.patchJoinFinished(
              joinedLiveRoomId: _joinedLiveRoomId,
              livePanelOpen: _livePanelOpen,
              error: _error,
            ),
          ),
        );
      }
    }
  }

  Future<void> _patchLiveState({
    bool? micMuted,
    bool? cameraOn,
    bool? screenSharing,
  }) async {
    final roomId = _joinedLiveRoomId;
    if (roomId == null ||
        !canPatchSelectedLiveState(
          joinedLiveRoomId: roomId,
          selectedRoomId: _selectedRoomId,
        )) {
      return;
    }

    try {
      // Apply the microphone change to the LiveKit transport in parallel with
      // the server PATCH. Server stays the source of truth for the rendered
      // state - if its response disagrees with what we asked for we resync
      // the LiveKit side below.
      final liveKitMicFuture = micMuted == null
          ? Future<void>.value()
          : _liveSessionController.setMicMuted(micMuted).catchError((_) {});
      final participant = await _liveController.updateMyState(
        roomId: roomId,
        micMuted: micMuted,
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
      final patch = _liveController.patchStateUpdate(
        live: _live,
        participant: participant,
      );
      // Server state wins over any optimistic LiveKit/UI request.
      setState(() => _applyLiveStateUpdatePatch(patch));
    } catch (e) {
      if (!mounted) return;
      // A 409 means the server already considers us gone (e.g. the LiveKit
      // webhook removed our row during teardown). That's benign here — a stray
      // state PATCH racing our own departure — so don't surface it as an error.
      if (isBenignGoneLiveStatePatch(e)) return;
      _showToast(e.toString());
    }
  }

  /// Toggle the local camera. We publish/unpublish the LiveKit track first and
  /// only tell the server once capture actually succeeded, so the roster never
  /// claims a camera that failed to start. The server response stays the
  /// source of truth for the rendered flag.
  Future<void> _toggleCamera() async {
    final roomId = _joinedLiveRoomId;
    if (roomId == null ||
        !canPatchSelectedLiveState(
          joinedLiveRoomId: roomId,
          selectedRoomId: _selectedRoomId,
        )) {
      return;
    }
    final enable = !_cameraOn;
    try {
      await _liveSessionController.setCameraEnabled(enable);
    } catch (e) {
      if (!mounted) return;
      _showToast(live_display.liveCameraOpenFailureMessage(e));
      return;
    }
    await _patchLiveState(cameraOn: enable);
  }

  /// Toggle screen sharing. Turning it on opens a source picker, starts the
  /// LiveKit capture, and only then PATCHes the server. If the user cancels the
  /// picker or capture fails we leave both the transport and server untouched.
  Future<void> _toggleScreenShare() async {
    final roomId = _joinedLiveRoomId;
    if (roomId == null ||
        !canPatchSelectedLiveState(
          joinedLiveRoomId: roomId,
          selectedRoomId: _selectedRoomId,
        )) {
      return;
    }

    if (_screenSharing) {
      try {
        await _liveSessionController.setScreenShareEnabled(false);
      } catch (_) {
        // Even if the stop call throws, fall through and clear server state.
      }
      await _patchLiveState(screenSharing: false);
      return;
    }

    final source = await showDialog<ScreenSource>(
      context: context,
      builder: (context) => _ScreenShareDialog(
        loadSources: _liveSessionController.listScreenSources,
        refreshThumbnails: _liveSessionController.refreshScreenSourceThumbnails,
      ),
    );
    if (source == null || !mounted) return;
    // Re-check we're still live in this room after the async picker.
    if (!canApplyPickedScreenShareSource(
      pickedForRoomId: roomId,
      joinedLiveRoomId: _joinedLiveRoomId,
      selectedRoomId: _selectedRoomId,
    )) {
      return;
    }

    try {
      await _liveSessionController.setScreenShareEnabled(
        true,
        sourceId: source.id,
      );
    } catch (e) {
      if (!mounted) return;
      _showToast(live_display.liveScreenShareFailureMessage(e));
      return;
    }
    await _patchLiveState(screenSharing: true);
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    // Keep the legacy title-bar visibility flag reset if we're torn down
    // (e.g. logout) while immersive full-screen share was open.
    windowControlsHidden.value = false;
    final realtimeEvents = _realtimeEvents;
    if (realtimeEvents != null) unawaited(realtimeEvents.cancel());
    _realtimeEvents = null;
    if (_shutdownHookToken != null) {
      ShutdownHooks.unregister(_shutdownHookToken!);
      _shutdownHookToken = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _detachLiveSessionCallbacks();
    for (final transfer in _fileDownloads.values) {
      _fileDownloadsController.cancel(transfer);
      final destinationPath = transfer.destinationPath;
      if (destinationPath != null && transfer.wroteDestination) {
        unawaited(
          _fileDownloadsController.deletePartialDownload(destinationPath),
        );
      }
    }
    _services.close();
    _messageController.removeListener(_onMessageDraftChanged);
    _messageController.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  /// Shows a transient, horizontally-centered message near the top (antd
  /// Message style) that auto-dismisses.
  void _showToast(String message, {HomeToastKind kind = HomeToastKind.error}) {
    _applyHomeToastPatch(homeToastShown(message: message, kind: kind));
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final patch = homeToastCleared(currentMessage: _toast);
      if (patch != null) _applyHomeToastPatch(patch);
    });
  }

  void _applyHomeToastPatch(HomeToastPatch patch) {
    setState(() {
      _toast = patch.message;
      _toastKind = patch.kind;
    });
  }

  /// Resolves the live screen-share track for the participant currently held
  /// in [_fullScreenShareIdentity], or null if there's no such active share
  /// (e.g. the sharer stopped). Used to auto-exit full-screen when it vanishes.
  LiveVideoTrack? get _fullScreenShareTrack {
    return live_display.liveScreenShareByIdentity(
      _liveSessionController.videoTracks,
      identity: _fullScreenShareIdentity,
      trackIdentity: (track) => track.identity,
      isScreenShare: (track) => track.isScreenShare,
    );
  }

  /// Enters immersive full-screen for [track]: real OS full-screen, with the
  /// sidebar and header hidden so only the video and a floating control bar
  /// show. Esc or the exit button leaves.
  Future<void> _enterShareFullScreen(LiveVideoTrack track) async {
    _applyHomeFullScreenSharePatch(
      homeFullScreenShareEntered(identity: track.identity),
    );
    if (_supportsWindowManagement) {
      try {
        if (!await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(true);
        }
      } catch (_) {}
    }
  }

  /// Leaves immersive full-screen, restoring the windowed live panel.
  Future<void> _exitShareFullScreen() async {
    final patch = homeFullScreenShareExited(
      currentIdentity: _fullScreenShareIdentity,
    );
    if (patch == null) return;
    _applyHomeFullScreenSharePatch(patch);
    if (_supportsWindowManagement) {
      try {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
      } catch (_) {}
    }
  }

  void _toggleSettings() {
    _applyHomeSettingsPanePatch(
      homeSettingsPaneToggled(settingsOpen: _settingsOpen),
    );
  }

  void _closeSettings() {
    final patch = homeSettingsPaneClosed(settingsOpen: _settingsOpen);
    if (patch == null) return;
    _applyHomeSettingsPanePatch(patch);
  }

  void _applyHomeSettingsPanePatch(HomeSettingsPanePatch patch) {
    setState(() {
      _settingsOpen = patch.settingsOpen;
      _error = patch.error;
    });
  }

  void _applyHomeFullScreenSharePatch(HomeFullScreenSharePatch patch) {
    setState(() {
      _fullScreenShareIdentity = patch.fullScreenShareIdentity;
    });
    windowControlsHidden.value = homeWindowControlsHiddenForFullScreenShare(
      patch.fullScreenShareIdentity,
    );
  }

  void _expandLivePanel() {
    final patch = homeLivePanelExpanded(currentLivePanelOpen: _livePanelOpen);
    if (patch == null) return;
    _applyHomeLivePanelPatch(patch);
  }

  void _collapseLivePanel() {
    final patch = homeLivePanelCollapsed(currentLivePanelOpen: _livePanelOpen);
    if (patch == null) return;
    _applyHomeLivePanelPatch(patch);
  }

  void _applyHomeLivePanelPatch(HomeLivePanelPatch patch) {
    setState(() {
      _livePanelOpen = patch.livePanelOpen;
    });
  }

  void _toggleSidebarCollapsed() {
    _applyHomeSidebarLayoutPatch(
      homeSidebarCollapsedToggled(
        sidebarWidth: _sidebarWidth,
        sidebarCollapsed: _sidebarCollapsed,
      ),
    );
  }

  void _resizeSidebar(double delta, double maxAllowedWidth) {
    final patch = homeSidebarWidthDragged(
      sidebarWidth: _sidebarWidth,
      sidebarCollapsed: _sidebarCollapsed,
      delta: delta,
      minWidth: _sidebarMinWidth,
      maxWidth: maxAllowedWidth,
    );
    if (patch == null) return;
    _applyHomeSidebarLayoutPatch(patch);
  }

  void _applyHomeSidebarLayoutPatch(HomeSidebarLayoutPatch patch) {
    setState(() {
      _sidebarWidth = patch.sidebarWidth;
      _sidebarCollapsed = patch.sidebarCollapsed;
    });
  }

  void _applyHomeCurrentUserPatch(HomeCurrentUserPatch<CurrentUser> patch) {
    setState(() {
      _currentUser = patch.currentUser;
    });
  }

  Future<void> _showPageContextMenu(TapUpDetails details) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: const [PopupMenuItem(value: 'refresh', child: Text('刷新'))],
    );
    if (action == 'refresh') {
      await _refreshCurrentPageContents();
    }
  }

  Future<void> _refreshCurrentPageContents() async {
    final selectedId = _selectedRoomId;
    final selectedBeforeRefresh = _selectedRoom;
    await _loadRooms();
    await _refreshRoomInviteBadge();
    unawaited(_warmPersonalStickerCache());
    if (!mounted) return;
    if (selectedId != null) {
      RoomCard? target;
      for (final room in _rooms) {
        if (room.id == selectedId) {
          target = room;
          break;
        }
      }
      target ??= selectedBeforeRefresh?.toCard();
      if (target != null) {
        await _openRoom(target, optimisticDetail: selectedBeforeRefresh);
      }
    }
    if (!mounted) return;
    _showToast('已刷新', kind: HomeToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    // Resolve the full-screen share track; if it vanished (sharer stopped),
    // schedule an exit so we don't stay stuck in an empty OS full-screen.
    final fullScreenShare = _fullScreenShareTrack;
    if (live_display.shouldExitMissingFullScreenShare(
      fullScreenShareIdentity: _fullScreenShareIdentity,
      fullScreenShare: fullScreenShare,
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _exitShareFullScreen();
      });
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (details) => unawaited(_showPageContextMenu(details)),
      child: Scaffold(
        backgroundColor: _primaryDark,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final maxAllowed = homeSidebarMaxAllowedWidth(
              availableWidth: constraints.maxWidth,
              contentMinWidth: 240,
              minWidth: _sidebarMinWidth,
              maxWidth: _sidebarMaxWidth,
            );
            final width = homeSidebarVisibleWidth(
              sidebarWidth: _sidebarWidth,
              sidebarCollapsed: _sidebarCollapsed,
              collapsedWidth: _sidebarCollapsedWidth,
              minWidth: _sidebarMinWidth,
              maxWidth: maxAllowed,
            );
            return Stack(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: width,
                      child: _RoomListPane(
                        rooms: _rooms,
                        selectedRoomId: _selectedRoomId,
                        loading: _loadingRooms,
                        currentUser: _currentUser,
                        collapsed: _sidebarCollapsed,
                        settingsActive: _settingsOpen,
                        hasPendingRoomInvites: _hasPendingRoomInvites,
                        onCreateRoom: _createRoom,
                        onJoinRoom: _joinRoom,
                        onOpenSettings: _toggleSettings,
                        onLogout: _handleLogout,
                        onOpenCurrentUser: () =>
                            _showUserInfo(_currentUser.toSummary()),
                        onOpenRoom: (room) => _openRoom(room),
                        onJoinLive: (room) => _openRoom(room, joinLive: true),
                      ),
                    ),
                    Expanded(child: _buildRoomPane()),
                  ],
                ),
                if (!_sidebarCollapsed)
                  Positioned(
                    left: width - 3,
                    top: 0,
                    bottom: 0,
                    width: 6,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (details) {
                          _resizeSidebar(details.delta.dx, maxAllowed);
                        },
                      ),
                    ),
                  ),
                Positioned(
                  left: width,
                  top: 0,
                  bottom: 0,
                  width: 18,
                  child: Center(
                    child: Material(
                      color: _primaryDarkLow,
                      shape: Border(
                        top: const BorderSide(color: _borderColor),
                        right: const BorderSide(color: _borderColor),
                        bottom: const BorderSide(color: _borderColor),
                      ),
                      child: InkWell(
                        onTap: _toggleSidebarCollapsed,
                        child: SizedBox(
                          width: 18,
                          height: 36,
                          child: Icon(
                            _sidebarCollapsed
                                ? Icons.chevron_right
                                : Icons.chevron_left,
                            size: 16,
                            color: _textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_toast != null)
                  Positioned(
                    top: titleBarHeight + 10,
                    left: 0,
                    right: 0,
                    child: _MessageToast(message: _toast!, kind: _toastKind),
                  ),
                if (fullScreenShare != null)
                  Positioned.fill(
                    child: _FullScreenShare(
                      track: fullScreenShare,
                      label: live_display.liveScreenShareStageLabel(
                        live_display.liveParticipantDisplayName(
                          _live,
                          fullScreenShare.identity,
                        ),
                      ),
                      onExit: _exitShareFullScreen,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRoomPane() {
    if (_settingsOpen) {
      return SettingsPage(
        isSubWindow: true,
        audioDeviceStore: _audioDeviceStore,
        controller: _services.settings,
        clipboardService: widget.clipboardService,
        fileSelectionService: widget.fileSelectionService,
        currentUser: _currentUser,
        onUserUpdated: (user) =>
            _applyHomeCurrentUserPatch(homeCurrentUserUpdated(user)),
        onVolumeChanged: (kind, volume) {
          if (kind == 'audioinput') {
            unawaited(_liveSessionController.setInputVolume(volume));
          } else if (kind == 'audiooutput') {
            unawaited(_liveSessionController.setOutputVolume(volume));
          }
        },
        onAccountDeleted: _handleLogout,
        onClose: _closeSettings,
      );
    }
    final room = _selectedRoom;
    if (_selectedRoomId == null) {
      return const _EmptyRoomPane();
    }
    if (_loadingRoom && room == null) {
      return const ColoredBox(
        color: _primaryDarkLow,
        child: Center(child: CircularProgressIndicator(color: _cyan)),
      );
    }
    if (room == null) {
      return _ErrorPane(message: _error, onRetry: _loadRooms);
    }

    final live = _live ?? room.live;
    final access = room_display.roomAccessState(
      room: room,
      currentUser: _currentUser,
    );
    return ColoredBox(
      color: _primaryDarkLow,
      child: Column(
        children: [
          if (!_livePanelOpen)
            _LiveHeader(
              room: room,
              live: live,
              joined: _joinedLiveRoomId == room.id,
              joining: _joiningLive,
              onExpand: _expandLivePanel,
              onJoin: () => _joinLive('live_header'),
              onOpenRoomManagement: _openRoomManagement,
              onOpenRoomInfo: _openRoomInfo,
              onOpenMembers: _openRoomMembers,
              showManagementButton: access.canManageRoom,
              showMemberRequestBadge: access.showJoinRequestBadge(
                _selectedRoomHasPendingJoinRequests,
              ),
            ),
          Expanded(
            child: _livePanelOpen
                ? _LivePanel(
                    room: room,
                    live: live,
                    liveSessionController: _liveSessionController,
                    joined: _joinedLiveRoomId == room.id,
                    joining: _joiningLive,
                    micMuted: _micMuted,
                    headphonesMuted: _headphonesMuted,
                    voiceBlocked: _voiceBlocked,
                    cameraOn: _cameraOn,
                    screenSharing: _screenSharing,
                    speakingUserIds: _liveSessionController.speakingIdentities,
                    onJoin: () => _joinLive('live_panel'),
                    onLeave: _leaveLive,
                    onToggleMic: _voiceBlocked
                        ? null
                        : () => _patchLiveState(micMuted: !_micMuted),
                    onToggleHeadphones: _toggleHeadphonesMute,
                    onToggleCamera: _toggleCamera,
                    onToggleShare: _toggleScreenShare,
                    onCollapse: _collapseLivePanel,
                    onEnterFullScreen: _enterShareFullScreen,
                    onOpenUserInfo: _showUserInfo,
                    localUserId: _currentUser.id,
                  )
                : _ChatPane(
                    roomId: _selectedRoomId!,
                    stickerPacksController: _services.stickers,
                    messages: _messages,
                    fileTransfers: _fileTransfers,
                    fileDownloads: _fileDownloads,
                    currentUserId: _currentUser.id,
                    controller: _messageController,
                    focusNode: _messageFocus,
                    sending: _sending,
                    onSend: _sendMessage,
                    onStickerSend: _sendStickerMessage,
                    onFileSend: _pickAndSendFile,
                    onFilePause: _pauseFileUpload,
                    onFileResume: _resumeFileUpload,
                    onFileCancel: _cancelFileUpload,
                    onFileDownload: _downloadFileAttachment,
                    onFileDownloadPause: _pauseFileDownload,
                    onFileDownloadResume: _resumeFileDownload,
                    onFileDownloadCancel: _cancelFileDownload,
                    onOpenUserInfo: _showUserInfo,
                    canManageRoomStickers: access.canManageRoom,
                    onStickerSaveToPersonal: _saveStickerToPersonal,
                    onStickerSaveToRoom: _saveStickerToRoom,
                    onStickerSaveAs: _saveStickerAs,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog({required this.controller});

  final RoomsController controller;

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final _nameController = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final draft = createRoomDraftFromForm(name: _nameController.text);
    if (!draft.isValid || !canStartCreateRoom(busy: _busy)) return;
    setState(() => _applyCreateRoomDialogPatch(createRoomSubmitStarted()));
    try {
      final room = await widget.controller.createRoom(name: draft.name!);
      if (!mounted) return;
      Navigator.of(context).pop(room);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyCreateRoomDialogPatch(createRoomSubmitFailed(failure: e)),
      );
    } finally {
      if (mounted) {
        setState(
          () => _applyCreateRoomDialogPatch(
            createRoomSubmitFinished(error: _error),
          ),
        );
      }
    }
  }

  void _applyCreateRoomDialogPatch(CreateRoomDialogPatch patch) {
    _busy = patch.busy;
    _error = patch.error;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '创建房间',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              const Center(
                child: _Avatar(
                  label: 'Room',
                  imageUrl: null,
                  defaultAvatarKey: 'room-1',
                  size: 62,
                ),
              ),
              const SizedBox(height: 18),
              _RoomNameInput(
                controller: _nameController,
                enabled: !_busy,
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: _danger)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    height: 38,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  Button(
                    onPressed: _submit,
                    loading: _busy,
                    tone: ButtonTone.primary,
                    height: 38,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _cyan,
                            ),
                          )
                        : const Text('创建'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search-and-join dialog. The user types a room name or RID; matching public
/// rooms are listed and can be joined directly (open rooms) or applied to
/// (approval-required rooms). Returns the joined [RoomDetail] on success.
class _JoinRoomDialog extends StatefulWidget {
  const _JoinRoomDialog({
    required this.controller,
    required this.onOpenUserInfo,
    required this.onPendingInvitesChanged,
  });

  final RoomsController controller;
  final ValueChanged<UserSummary> onOpenUserInfo;
  final ValueChanged<bool> onPendingInvitesChanged;

  @override
  State<_JoinRoomDialog> createState() => _JoinRoomDialogState();
}

class _JoinRoomDialogState extends State<_JoinRoomDialog> {
  final _queryController = TextEditingController();
  Timer? _debounce;
  int _searchSeq = 0;
  bool _searching = false;
  bool _loadingInvites = true;
  String? _error;
  String? _inviteError;
  String? _busyRoomId;
  String? _busyInviteId;
  List<PublicRoom> _results = const [];
  List<RoomInvite> _invites = const [];
  final Set<String> _pendingRoomIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final patch = roomJoinSearchQueryChanged(
      rawQuery: value,
      results: _results,
      error: _error,
    );
    if (patch.shouldCancelInFlightSearch) _searchSeq += 1;
    setState(() => _applyRoomJoinSearchPatch(patch.search));
    if (!patch.shouldSearch) return;
    final seq = _searchSeq;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_search(patch.query, seq));
    });
  }

  Future<void> _search(String query, int seq) async {
    try {
      final rooms = await widget.controller.searchRooms(query: query);
      if (!mounted || seq != _searchSeq) return;
      setState(
        () =>
            _applyRoomJoinSearchPatch(roomJoinSearchSucceeded(results: rooms)),
      );
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(
        () => _applyRoomJoinSearchPatch(
          roomJoinSearchFailed(results: _results, failure: e),
        ),
      );
    }
  }

  Future<void> _loadInvites() async {
    setState(
      () => _applyRoomJoinInvitesPatch(
        roomJoinInvitesLoadStarted(invites: _invites),
      ),
    );
    try {
      final invites = await widget.controller.listRoomInvites();
      if (!mounted) return;
      setState(
        () => _applyRoomJoinInvitesPatch(
          roomJoinInvitesLoadSucceeded(invites: invites),
        ),
      );
      widget.onPendingInvitesChanged(invites.isNotEmpty);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyRoomJoinInvitesPatch(
          roomJoinInvitesLoadFailed(invites: _invites, failure: e),
        ),
      );
    }
  }

  Future<void> _join(PublicRoom room) async {
    if (!canStartPublicRoomAction(_busyRoomId)) return;
    setState(
      () => _applyRoomJoinPublicActionPatch(
        roomJoinPublicActionStarted(
          roomId: room.id,
          pendingRoomIds: _pendingRoomIds,
        ),
      ),
    );
    try {
      final result = await widget.controller.joinRoom(room.id);
      if (!mounted) return;
      if (result.joined && result.room != null) {
        Navigator.of(context).pop(result.room);
        return;
      }
      setState(
        () => _applyRoomJoinPublicActionPatch(
          roomJoinPublicActionPending(
            busyRoomId: _busyRoomId,
            error: _error,
            pendingRoomIds: _pendingRoomIds,
            room: room,
            result: result,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyRoomJoinPublicActionPatch(
          roomJoinPublicActionFailed(
            busyRoomId: _busyRoomId,
            pendingRoomIds: _pendingRoomIds,
            failure: e,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(
          () => _applyRoomJoinPublicActionPatch(
            roomJoinPublicActionFinished(
              error: _error,
              pendingRoomIds: _pendingRoomIds,
            ),
          ),
        );
      }
    }
  }

  Future<void> _openJoined(PublicRoom room) async {
    if (!canStartPublicRoomAction(_busyRoomId)) return;
    setState(
      () => _applyRoomJoinPublicActionPatch(
        roomJoinPublicActionStarted(
          roomId: room.id,
          pendingRoomIds: _pendingRoomIds,
        ),
      ),
    );
    try {
      final detail = await widget.controller.getRoom(room.id);
      if (!mounted) return;
      Navigator.of(context).pop(detail);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyRoomJoinPublicActionPatch(
          roomJoinPublicActionFailed(
            busyRoomId: _busyRoomId,
            pendingRoomIds: _pendingRoomIds,
            failure: e,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(
          () => _applyRoomJoinPublicActionPatch(
            roomJoinPublicActionFinished(
              error: _error,
              pendingRoomIds: _pendingRoomIds,
            ),
          ),
        );
      }
    }
  }

  Future<void> _decideInvite(RoomInvite invite, bool accept) async {
    if (!canStartRoomInviteDecision(
      busyInviteId: _busyInviteId,
      busyRoomId: _busyRoomId,
    )) {
      return;
    }
    setState(
      () => _applyRoomJoinInviteDecisionPatch(
        roomJoinInviteDecisionStarted(
          invites: _invites,
          pendingRoomIds: _pendingRoomIds,
          inviteId: invite.id,
        ),
      ),
    );
    try {
      final result = await widget.controller.reviewRoomInvite(
        inviteId: invite.id,
        accept: accept,
      );
      if (!mounted) return;
      if (accept && result.room != null) {
        Navigator.of(context).pop(result.room);
        return;
      }
      final patch = roomJoinInviteDecisionSucceeded(
        invites: _invites,
        pendingRoomIds: _pendingRoomIds,
        invite: invite,
        accept: accept,
        result: result,
      );
      setState(() => _applyRoomJoinInviteDecisionPatch(patch));
      widget.onPendingInvitesChanged(_invites.isNotEmpty);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyRoomJoinInviteDecisionPatch(
          roomJoinInviteDecisionFailed(
            invites: _invites,
            pendingRoomIds: _pendingRoomIds,
            busyInviteId: _busyInviteId,
            failure: e,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(
          () => _applyRoomJoinInviteDecisionPatch(
            roomJoinInviteDecisionFinished(
              invites: _invites,
              pendingRoomIds: _pendingRoomIds,
              error: _inviteError,
            ),
          ),
        );
      }
    }
  }

  void _applyRoomJoinSearchPatch(RoomJoinSearchPatch patch) {
    _results = patch.results;
    _searching = patch.searching;
    _error = patch.error;
  }

  void _applyRoomJoinInvitesPatch(RoomJoinInvitesPatch patch) {
    _invites = patch.invites;
    _loadingInvites = patch.loading;
    _inviteError = patch.error;
  }

  void _applyRoomJoinPublicActionPatch(RoomJoinPublicActionPatch patch) {
    _busyRoomId = patch.busyRoomId;
    _error = patch.error;
    _pendingRoomIds
      ..clear()
      ..addAll(patch.pendingRoomIds);
  }

  void _applyRoomJoinInviteDecisionPatch(RoomJoinInviteDecisionPatch patch) {
    _invites = patch.invites;
    _pendingRoomIds
      ..clear()
      ..addAll(patch.pendingRoomIds);
    _busyInviteId = patch.busyInviteId;
    _inviteError = patch.error;
  }

  @override
  Widget build(BuildContext context) {
    final dialogHeight = (MediaQuery.sizeOf(context).height - 64)
        .clamp(360.0, 480.0)
        .toDouble();
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: SizedBox(
          height: dialogHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text(
                      '加入房间',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    ButtonIcon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: '关闭',
                      size: 32,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: const BoxDecoration(color: _primaryDarkLow),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 18, color: _textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _queryController,
                            autofocus: true,
                            onChanged: _onQueryChanged,
                            cursorColor: _textSecondary,
                            contextMenuBuilder: buildTextFieldContextMenu,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              hintText: '按房间名或 RID 搜索',
                              hintStyle: TextStyle(color: _textMuted),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                            ),
                          ),
                        ),
                        if (_searching)
                          const SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _cyan,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: _danger)),
                ],
                if (_inviteError != null) ...[
                  const SizedBox(height: 10),
                  Text(_inviteError!, style: const TextStyle(color: _danger)),
                ],
                const SizedBox(height: 14),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final children = <Widget>[];
    if (hasRoomSearchQuery(_queryController.text)) {
      children.add(_buildResults());
    }
    if (shouldShowRoomInviteSection(
      loadingInvites: _loadingInvites,
      invites: _invites,
    )) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 14));
      children.add(_buildInvitesSection());
    }
    return ListView(children: children);
  }

  Widget _buildInvitesSection() {
    if (_loadingInvites) {
      return const SizedBox(
        height: 64,
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '待处理邀请',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        for (final invite in _invites) ...[
          _PendingRoomInviteTile(
            invite: invite,
            busy: _busyInviteId == invite.id,
            onAccept: () => _decideInvite(invite, true),
            onReject: () => _decideInvite(invite, false),
            onOpenInviter: () => widget.onOpenUserInfo(invite.inviter),
          ),
          if (invite != _invites.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildResults() {
    if (!_searching && _results.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text('没有找到匹配的房间', style: TextStyle(color: _textMuted)),
        ),
      );
    }
    final candidates = publicRoomJoinCandidates(
      rooms: _results,
      pendingRoomIds: _pendingRoomIds,
      busyRoomId: _busyRoomId,
    );
    return Column(
      children: [
        for (final entry in candidates.asMap().entries) ...[
          _JoinRoomResultTile(
            candidate: entry.value,
            onJoin: () => _join(entry.value.room),
            onOpen: () => _openJoined(entry.value.room),
          ),
          if (entry.key != candidates.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _JoinRoomResultTile extends StatelessWidget {
  const _JoinRoomResultTile({
    required this.candidate,
    required this.onJoin,
    required this.onOpen,
  });

  final PublicRoomJoinCandidate candidate;
  final VoidCallback onJoin;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final room = candidate.room;
    final label = room_display.publicRoomJoinActionLabel(
      room,
      pending: candidate.pending,
    );
    final action = candidate.opensJoinedRoom ? onOpen : onJoin;
    return PressableSurface(
      height: 64,
      backgroundColor: _primaryDarkLow,
      selectedBackgroundColor: _primaryDarkLow,
      borderColor: _borderColor,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _Avatar(
            label: room.name,
            imageUrl: AppConfigScope.of(
              context,
            ).resolveAssetUrl(room.avatarUrl),
            defaultAvatarKey: room.defaultAvatarKey,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  publicRoomJoinSubtitle(room),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Button(
            onPressed: candidate.actionEnabled ? action : null,
            loading: candidate.busy,
            tone: candidate.actionable
                ? ButtonTone.primary
                : ButtonTone.neutral,
            height: 34,
            child: candidate.busy
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _cyan,
                    ),
                  )
                : Text(label),
          ),
        ],
      ),
    );
  }
}

class _PendingRoomInviteTile extends StatelessWidget {
  const _PendingRoomInviteTile({
    required this.invite,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    required this.onOpenInviter,
  });

  final RoomInvite invite;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onOpenInviter;

  @override
  Widget build(BuildContext context) {
    final room = invite.room;
    final inviter = invite.inviter;
    return PressableSurface(
      height: 92,
      backgroundColor: _primaryDarkLow,
      selectedBackgroundColor: _primaryDarkLow,
      borderColor: _borderColor,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _Avatar(
            label: room.name,
            imageUrl: AppConfigScope.of(
              context,
            ).resolveAssetUrl(room.avatarUrl),
            defaultAvatarKey: room.defaultAvatarKey,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Text(
                      '邀请人',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _textMuted, fontSize: 12),
                    ),
                    const SizedBox(width: 7),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onOpenInviter,
                      child: _Avatar(
                        label: inviter.displayName,
                        imageUrl: AppConfigScope.of(
                          context,
                        ).resolveAssetUrl(inviter.avatarUrl),
                        defaultAvatarKey: inviter.defaultAvatarKey,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onOpenInviter,
                        child: Text(
                          inviter.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _cyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  pendingRoomInviteSubtitle(invite),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (busy)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
            )
          else ...[
            ButtonIcon(
              tooltip: '拒绝',
              onPressed: onReject,
              icon: const Icon(Icons.close),
              tone: ButtonTone.danger,
              size: 34,
            ),
            const SizedBox(width: 8),
            ButtonIcon(
              tooltip: '接受',
              onPressed: onAccept,
              icon: const Icon(Icons.check),
              tone: ButtonTone.primary,
              size: 34,
            ),
          ],
        ],
      ),
    );
  }
}

class _RoomMembersDialog extends StatefulWidget {
  const _RoomMembersDialog({
    required this.controller,
    required this.room,
    required this.initialLive,
    required this.canReviewRequests,
    required this.onOpenUserInfo,
    required this.onPendingRequestsChanged,
  });

  final RoomsController controller;
  final RoomDetail room;
  final LiveState initialLive;
  final bool canReviewRequests;
  final void Function(UserSummary user, {bool includeSelectedRoom, bool basic})
  onOpenUserInfo;
  final ValueChanged<bool> onPendingRequestsChanged;

  @override
  State<_RoomMembersDialog> createState() => _RoomMembersDialogState();
}

class _RoomMembersDialogState extends State<_RoomMembersDialog> {
  final _filterController = TextEditingController();
  final Set<String> _busyRequestIds = <String>{};

  List<RoomMember> _members = const [];
  List<JoinRequest> _requests = const [];
  LiveState? _live;
  bool _loading = true;
  bool _changed = false;
  String? _error;
  String? _requestError;
  String _filterQuery = '';
  member_filter.RoomMemberPresenceFilter _presenceFilter =
      member_filter.RoomMemberPresenceFilter.all;
  member_filter.RoomMemberRoleFilter _roleFilter =
      member_filter.RoomMemberRoleFilter.all;

  @override
  void initState() {
    super.initState();
    _live = widget.initialLive;
    _filterController.addListener(_onFilterChanged);
    _load();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    final patch = member_filter.roomMemberSearchQueryChanged(
      searchQuery: _filterController.text,
      presenceFilter: _presenceFilter,
      roleFilter: _roleFilter,
    );
    setState(() => _applyRoomMemberFilterPatch(patch));
  }

  void _applyRoomMembersDialogPatch(RoomMembersDialogStatePatch patch) {
    _members = patch.members;
    _requests = patch.requests;
    _live = patch.live;
    _loading = patch.loading;
    _changed = patch.changed;
    _error = patch.error;
    _requestError = patch.requestError;
    _busyRequestIds
      ..clear()
      ..addAll(patch.busyRequestIds);
  }

  void _applyRoomMemberFilterPatch(member_filter.RoomMemberFilterPatch patch) {
    _filterQuery = patch.searchQuery;
    _presenceFilter = patch.presenceFilter;
    _roleFilter = patch.roleFilter;
  }

  Future<void> _load() async {
    setState(() {
      _applyRoomMembersDialogPatch(
        widget.controller.patchRoomMembersLoadStarted(
          members: _members,
          requests: _requests,
          live: _live,
          changed: _changed,
          busyRequestIds: _busyRequestIds,
        ),
      );
    });
    try {
      final snapshot = await widget.controller.loadRoomMembersSnapshot(
        roomId: widget.room.id,
        fallbackLive: widget.initialLive,
        includeJoinRequests: widget.canReviewRequests,
      );
      if (!mounted) return;
      final patch = widget.controller.patchRoomMembersLoadSucceeded(
        snapshot: snapshot,
        changed: _changed,
        busyRequestIds: _busyRequestIds,
      );
      setState(() {
        _applyRoomMembersDialogPatch(patch);
      });
      if (!widget.canReviewRequests || patch.shouldNotifyPendingRequests) {
        widget.onPendingRequestsChanged(patch.hasPendingRequests);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomMembersDialogPatch(
          widget.controller.patchRoomMembersLoadFailed(
            members: _members,
            requests: _requests,
            live: _live,
            changed: _changed,
            busyRequestIds: _busyRequestIds,
            failure: e,
          ),
        );
      });
    }
  }

  Future<void> _reloadMembersAndLive() async {
    try {
      final snapshot = await widget.controller.loadRoomMembersAndLive(
        roomId: widget.room.id,
        fallbackLive: widget.initialLive,
      );
      if (!mounted) return;
      setState(() {
        _applyRoomMembersDialogPatch(
          widget.controller.patchRoomMembersAndLiveReloadSucceeded(
            snapshot: snapshot,
            requests: _requests,
            loading: _loading,
            changed: _changed,
            requestError: _requestError,
            busyRequestIds: _busyRequestIds,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomMembersDialogPatch(
          widget.controller.patchRoomMembersAndLiveReloadFailed(
            members: _members,
            requests: _requests,
            live: _live,
            loading: _loading,
            changed: _changed,
            requestError: _requestError,
            busyRequestIds: _busyRequestIds,
            failure: e,
          ),
        );
      });
    }
  }

  Future<void> _reloadRequests() async {
    if (!widget.canReviewRequests) return;
    try {
      final requests = await widget.controller.listJoinRequests(widget.room.id);
      if (!mounted) return;
      final patch = widget.controller.patchRoomJoinRequestsReloadSucceeded(
        members: _members,
        live: _live,
        requests: requests,
        loading: _loading,
        changed: _changed,
        busyRequestIds: _busyRequestIds,
      );
      setState(() {
        _applyRoomMembersDialogPatch(patch);
      });
      widget.onPendingRequestsChanged(patch.hasPendingRequests);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomMembersDialogPatch(
          widget.controller.patchRoomJoinRequestsReloadFailed(
            members: _members,
            requests: _requests,
            live: _live,
            loading: _loading,
            changed: _changed,
            busyRequestIds: _busyRequestIds,
            failure: e,
          ),
        );
      });
    }
  }

  Future<void> _decide(JoinRequest request, bool approve) async {
    if (!canStartJoinRequestReview(
      requestId: request.id,
      busyRequestIds: _busyRequestIds,
    )) {
      return;
    }
    final started = widget.controller.patchJoinRequestReviewStarted(
      members: _members,
      requests: _requests,
      live: _live,
      loading: _loading,
      changed: _changed,
      requestId: request.id,
      busyRequestIds: _busyRequestIds,
    );
    setState(() {
      _applyRoomMembersDialogPatch(started);
    });
    try {
      await widget.controller.reviewJoinRequest(
        roomId: widget.room.id,
        requestId: request.id,
        approve: approve,
      );
      if (!mounted) return;
      final succeeded = widget.controller.patchJoinRequestReviewSucceeded(
        members: _members,
        requests: _requests,
        live: _live,
        loading: _loading,
        changed: _changed,
        error: _error,
        requestError: _requestError,
        requestId: request.id,
        busyRequestIds: _busyRequestIds,
      );
      setState(() {
        _applyRoomMembersDialogPatch(succeeded);
      });
      widget.onPendingRequestsChanged(succeeded.hasPendingRequests);
      if (approve) unawaited(_reloadMembersAndLive());
    } catch (e) {
      if (!mounted) return;
      final failed = widget.controller.patchJoinRequestReviewFailed(
        members: _members,
        requests: _requests,
        live: _live,
        loading: _loading,
        changed: _changed,
        error: _error,
        requestId: request.id,
        busyRequestIds: _busyRequestIds,
        failure: e,
      );
      setState(() {
        _applyRoomMembersDialogPatch(failed);
      });
    }
  }

  List<RoomMember> _visibleMembers() {
    return member_filter.visibleRoomMembers(
      members: _members,
      live: _live ?? widget.initialLive,
      presenceFilter: _presenceFilter,
      roleFilter: _roleFilter,
      query: _filterQuery,
      ownerUserId: widget.room.createdBy?.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: _danger)),
              ],
              const SizedBox(height: 14),
              _MemberSearchField(
                controller: _filterController,
                hintText: '输入成员 UID / 房间内用户名 / 备注名',
                icon: Icons.search,
              ),
              const SizedBox(height: 10),
              _SegmentedFilterRow<member_filter.RoomMemberPresenceFilter>(
                options: const [
                  _FilterOption(
                    member_filter.RoomMemberPresenceFilter.all,
                    '全部',
                  ),
                  _FilterOption(
                    member_filter.RoomMemberPresenceFilter.online,
                    '在线',
                  ),
                  _FilterOption(
                    member_filter.RoomMemberPresenceFilter.offline,
                    '离线',
                  ),
                ],
                value: _presenceFilter,
                onChanged: (value) => setState(
                  () => _applyRoomMemberFilterPatch(
                    member_filter.roomMemberPresenceFilterChanged(
                      searchQuery: _filterQuery,
                      presenceFilter: value,
                      roleFilter: _roleFilter,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _SegmentedFilterRow<member_filter.RoomMemberRoleFilter>(
                options: const [
                  _FilterOption(member_filter.RoomMemberRoleFilter.all, '全部'),
                  _FilterOption(
                    member_filter.RoomMemberRoleFilter.member,
                    '普通成员',
                  ),
                  _FilterOption(
                    member_filter.RoomMemberRoleFilter.admin,
                    '管理员',
                  ),
                ],
                value: _roleFilter,
                onChanged: (value) => setState(
                  () => _applyRoomMemberFilterPatch(
                    member_filter.roomMemberRoleFilterChanged(
                      searchQuery: _filterQuery,
                      presenceFilter: _presenceFilter,
                      roleFilter: value,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildMemberBody()),
              const SizedBox(height: 12),
              _buildInviteSection(),
              if (widget.canReviewRequests) ...[
                const SizedBox(height: 12),
                _buildRequestsSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '成员列表',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.room.name} · ${_members.length} 名成员',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        ButtonIcon(
          onPressed: () => Navigator.of(context).pop(_changed),
          icon: const Icon(Icons.close),
          tooltip: '关闭',
          size: 32,
        ),
      ],
    );
  }

  Widget _buildMemberBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _cyan));
    }
    final members = _visibleMembers();
    if (members.isEmpty) {
      return const Center(
        child: Text('暂无匹配成员', style: TextStyle(color: _textMuted)),
      );
    }
    final live = _live ?? widget.initialLive;
    final groups = member_filter.roomMemberPresenceGroups(
      members: members,
      live: live,
    );
    final children = <Widget>[];
    for (final group in groups) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 12));
      children.add(
        _MemberSectionHeader(presence: group.presence, count: group.count),
      );
      children.add(const SizedBox(height: 8));
      for (final item in group.members) {
        children.add(
          _RoomMemberTile(
            member: item,
            room: widget.room,
            presence: group.presence,
            onOpenUserInfo: () => widget.onOpenUserInfo(item.user),
          ),
        );
        if (item != group.members.last) children.add(const SizedBox(height: 8));
      }
    }
    return ListView(children: children);
  }

  Widget _buildInviteSection() {
    return Button(
      onPressed: _openInviteDialog,
      height: 40,
      icon: const Icon(Icons.person_add_alt_1),
      tone: ButtonTone.primary,
      child: const Text('邀请成员'),
    );
  }

  Future<void> _openInviteDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _InviteMemberDialog(
        controller: widget.controller,
        room: widget.room,
        members: _members,
        onOpenUserInfo: widget.onOpenUserInfo,
      ),
    );
  }

  Widget _buildRequestsSection() {
    final candidates = joinRequestCandidates(
      requests: _requests,
      busyRequestIds: _busyRequestIds,
    );
    final bodyState = joinRequestListBodyState(candidates);
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '待审批用户',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ButtonIcon(
                  onPressed: _reloadRequests,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新',
                  size: 30,
                ),
              ],
            ),
            if (_requestError != null) ...[
              const SizedBox(height: 8),
              Text(_requestError!, style: const TextStyle(color: _danger)),
            ],
            const SizedBox(height: 8),
            switch (bodyState) {
              JoinRequestListBodyState.empty => const SizedBox(
                height: 42,
                child: Center(
                  child: Text('暂无待审批用户', style: TextStyle(color: _textMuted)),
                ),
              ),
              JoinRequestListBodyState.results => ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 156),
                child: _buildJoinRequestList(candidates),
              ),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildJoinRequestList(List<JoinRequestCandidate> candidates) {
    return ListView.separated(
      shrinkWrap: true,
      itemCount: candidates.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final candidate = candidates[index];
        final request = candidate.request;
        return _JoinRequestTile(
          request: request,
          busy: candidate.busy,
          onApprove: () => _decide(request, true),
          onReject: () => _decide(request, false),
          onOpenUserInfo: () => widget.onOpenUserInfo(
            candidate.userForInfo,
            includeSelectedRoom: false,
          ),
        );
      },
    );
  }
}

class _FilterOption<T> {
  const _FilterOption(this.value, this.label);

  final T value;
  final String label;
}

class _SegmentedFilterRow<T> extends StatelessWidget {
  const _SegmentedFilterRow({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<_FilterOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in options) ...[
            Button(
              onPressed: () => onChanged(option.value),
              selected: option.value == value,
              tone: option.value == value
                  ? ButtonTone.primary
                  : ButtonTone.neutral,
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(option.label),
            ),
            if (option != options.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _MemberSearchField extends StatelessWidget {
  const _MemberSearchField({
    required this.controller,
    required this.hintText,
    required this.icon,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _primaryDarkLow,
        border: Border.all(color: _borderColor),
      ),
      child: SizedBox(
        height: 42,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(color: _textPrimary, fontSize: 14),
          cursorColor: _cyan,
          contextMenuBuilder: buildTextFieldContextMenu,
          decoration: InputDecoration(
            border: InputBorder.none,
            prefixIcon: Icon(icon, color: _textMuted, size: 18),
            hintText: hintText,
            hintStyle: const TextStyle(color: _textMuted),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberSectionHeader extends StatelessWidget {
  const _MemberSectionHeader({required this.presence, required this.count});

  final member_filter.RoomMemberPresence presence;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(roomMemberPresenceIcon(presence), color: _textMuted, size: 16),
        const SizedBox(width: 6),
        Text(
          '${member_filter.roomMemberPresenceLabel(presence)} · $count',
          style: const TextStyle(
            color: _textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _RoomMemberTile extends StatelessWidget {
  const _RoomMemberTile({
    required this.member,
    required this.room,
    required this.presence,
    required this.onOpenUserInfo,
  });

  final RoomMember member;
  final RoomDetail room;
  final member_filter.RoomMemberPresence presence;
  final VoidCallback onOpenUserInfo;

  @override
  Widget build(BuildContext context) {
    final user = member.user;
    final name = member_filter.roomMemberDisplayName(member);
    final meta = member_filter.roomMemberMeta(member);
    return PressableSurface(
      onPressed: onOpenUserInfo,
      height: 72,
      backgroundColor: _primaryDarkLow,
      selectedBackgroundColor: _primaryDarkLow,
      borderColor: _borderColor,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _Avatar(
            label: name,
            imageUrl: AppConfigScope.of(
              context,
            ).resolveAssetUrl(user.avatarUrl),
            defaultAvatarKey: user.defaultAvatarKey,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StatusPill(label: member_filter.roomMemberPresenceLabel(presence)),
          const SizedBox(width: 8),
          _UserRoleBadge(
            label: room_display.roomRoleLabel(
              user,
              ownerUserId: room.createdBy?.id,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _primaryDarkRaised,
        border: Border.all(color: _borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _InviteMemberDialog extends StatefulWidget {
  const _InviteMemberDialog({
    required this.controller,
    required this.room,
    required this.members,
    required this.onOpenUserInfo,
  });

  final RoomsController controller;
  final RoomDetail room;
  final List<RoomMember> members;
  final void Function(UserSummary user, {bool includeSelectedRoom, bool basic})
  onOpenUserInfo;

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  final _queryController = TextEditingController();
  final Set<String> _busyUserIds = <String>{};
  final Set<String> _pendingInviteUserIds = <String>{};
  Timer? _debounce;
  int _searchSeq = 0;
  bool _searching = false;
  String? _error;
  List<UserSummary> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _applyRoomMemberInviteDialogPatch(RoomMemberInviteDialogPatch patch) {
    _results = patch.searchResults;
    _searching = patch.searching;
    _error = patch.error;
    _pendingInviteUserIds
      ..clear()
      ..addAll(patch.pendingInviteUserIds);
    _busyUserIds
      ..clear()
      ..addAll(patch.busyUserIds);
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final patch = roomMemberInviteSearchQueryChanged(
      rawQuery: _queryController.text,
      searchResults: _results,
      pendingInviteUserIds: _pendingInviteUserIds,
      busyUserIds: _busyUserIds,
    );
    if (patch.shouldCancelInFlightSearch) _searchSeq += 1;
    setState(() => _applyRoomMemberInviteDialogPatch(patch.dialog));
    if (!patch.shouldSearch) return;
    final seq = _searchSeq;
    _debounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_search(patch.query, seq));
    });
  }

  Future<void> _search(String query, int seq) async {
    try {
      final users = await widget.controller.searchUsers(
        query: query,
        limit: 20,
      );
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _applyRoomMemberInviteDialogPatch(
          roomMemberInviteSearchSucceeded(
            searchResults: users,
            pendingInviteUserIds: _pendingInviteUserIds,
            busyUserIds: _busyUserIds,
          ),
        );
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _applyRoomMemberInviteDialogPatch(
          roomMemberInviteSearchFailed(
            searchResults: _results,
            pendingInviteUserIds: _pendingInviteUserIds,
            busyUserIds: _busyUserIds,
            failure: e,
          ),
        );
      });
    }
  }

  Future<void> _invite(UserSummary user) async {
    if (!canStartRoomInvite(
      userId: user.id,
      members: widget.members,
      pendingInviteUserIds: _pendingInviteUserIds,
      busyUserIds: _busyUserIds,
      isSuperuser: user.isSuperuser,
    )) {
      return;
    }
    final started = roomMemberInviteStarted(
      searchResults: _results,
      searching: _searching,
      userId: user.id,
      pendingInviteUserIds: _pendingInviteUserIds,
      busyUserIds: _busyUserIds,
    );
    setState(() {
      _applyRoomMemberInviteDialogPatch(started);
    });
    try {
      await widget.controller.inviteMember(
        roomId: widget.room.id,
        userId: user.id,
      );
      if (!mounted) return;
      final succeeded = roomMemberInviteSucceeded(
        searchResults: _results,
        searching: _searching,
        error: _error,
        userId: user.id,
        pendingInviteUserIds: _pendingInviteUserIds,
        busyUserIds: _busyUserIds,
      );
      setState(() {
        _applyRoomMemberInviteDialogPatch(succeeded);
      });
    } catch (e) {
      if (!mounted) return;
      final failed = roomMemberInviteFailed(
        searchResults: _results,
        searching: _searching,
        userId: user.id,
        pendingInviteUserIds: _pendingInviteUserIds,
        busyUserIds: _busyUserIds,
        failure: e,
      );
      setState(() {
        _applyRoomMemberInviteDialogPatch(failed);
      });
    }
  }

  List<RoomInviteCandidate> _candidates() {
    return roomInviteCandidates(
      searchResults: _results,
      members: widget.members,
      query: _queryController.text,
      pendingInviteUserIds: _pendingInviteUserIds,
      busyUserIds: _busyUserIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates();
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '邀请成员',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ButtonIcon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _MemberSearchField(
                controller: _queryController,
                hintText: 'UID / Username / 用户名关键字 / 备注名关键字',
                icon: Icons.person_search,
                onChanged: (_) => _onQueryChanged(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: _danger)),
              ],
              const SizedBox(height: 12),
              Flexible(child: _buildBody(candidates)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(List<RoomInviteCandidate> candidates) {
    final state = roomInviteSearchBodyState(
      searching: _searching,
      query: _queryController.text,
      candidates: candidates,
    );
    switch (state) {
      case RoomInviteSearchBodyState.loading:
        return const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator(color: _cyan)),
        );
      case RoomInviteSearchBodyState.prompt:
        return const SizedBox(
          height: 100,
          child: Center(
            child: Text('输入关键词搜索用户', style: TextStyle(color: _textMuted)),
          ),
        );
      case RoomInviteSearchBodyState.empty:
        return const SizedBox(
          height: 100,
          child: Center(
            child: Text('未找到用户', style: TextStyle(color: _textMuted)),
          ),
        );
      case RoomInviteSearchBodyState.results:
        break;
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: candidates.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final candidate = candidates[index];
        final user = candidate.user;
        return _InviteCandidateTile(
          user: user,
          existing: candidate.existing,
          pending: candidate.pending,
          busy: candidate.busy,
          onInvite: candidate.inviteActionEnabled ? () => _invite(user) : null,
          onOpenUserInfo: () => widget.onOpenUserInfo(
            user,
            includeSelectedRoom: candidate.existing,
            basic: !candidate.existing,
          ),
        );
      },
    );
  }
}

class _InviteCandidateTile extends StatelessWidget {
  const _InviteCandidateTile({
    required this.user,
    required this.existing,
    required this.pending,
    required this.busy,
    required this.onInvite,
    required this.onOpenUserInfo,
  });

  final UserSummary user;
  final bool existing;
  final bool pending;
  final bool busy;
  final VoidCallback? onInvite;
  final VoidCallback onOpenUserInfo;

  @override
  Widget build(BuildContext context) {
    return PressableSurface(
      height: 60,
      backgroundColor: _primaryDarkLow,
      selectedBackgroundColor: _primaryDarkLow,
      borderColor: _borderColor,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenUserInfo,
            child: _Avatar(
              label: user.displayName,
              imageUrl: AppConfigScope.of(
                context,
              ).resolveAssetUrl(user.avatarUrl),
              defaultAvatarKey: user.defaultAvatarKey,
              size: 36,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpenUserInfo,
                  child: Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  room_display.userIdentityMeta(user),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Button(
            onPressed: onInvite,
            loading: busy,
            height: 34,
            tone: existing ? ButtonTone.neutral : ButtonTone.primary,
            child: busy
                ? const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _cyan,
                    ),
                  )
                : Text(
                    existing
                        ? '已在房间'
                        : pending
                        ? '已邀请'
                        : '邀请',
                  ),
          ),
        ],
      ),
    );
  }
}

class _JoinRequestTile extends StatelessWidget {
  const _JoinRequestTile({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onOpenUserInfo,
  });

  final JoinRequest request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onOpenUserInfo;

  @override
  Widget build(BuildContext context) {
    final user = request.user;
    return PressableSurface(
      height: 64,
      backgroundColor: _primaryDarkLow,
      selectedBackgroundColor: _primaryDarkLow,
      borderColor: _borderColor,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenUserInfo,
            child: _Avatar(
              label: user.displayName,
              imageUrl: AppConfigScope.of(
                context,
              ).resolveAssetUrl(user.avatarUrl),
              defaultAvatarKey: user.defaultAvatarKey,
              size: 38,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenUserInfo,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    joinRequestUserMeta(request),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (busy)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
            )
          else ...[
            ButtonIcon(
              tooltip: '拒绝',
              onPressed: onReject,
              icon: const Icon(Icons.close),
              tone: ButtonTone.danger,
              size: 34,
            ),
            const SizedBox(width: 8),
            ButtonIcon(
              tooltip: '通过',
              onPressed: onApprove,
              icon: const Icon(Icons.check),
              tone: ButtonTone.primary,
              size: 34,
            ),
          ],
        ],
      ),
    );
  }
}

class _RoomNameInput extends StatelessWidget {
  const _RoomNameInput({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              '名字',
              style: TextStyle(
                color: _textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, child) {
                return Text(
                  '${value.text.length}/50',
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _primaryDarkLow,
            border: Border.all(color: _borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: TextField(
              controller: controller,
              enabled: enabled,
              autofocus: true,
              maxLength: 50,
              onSubmitted: onSubmitted,
              cursorColor: _textSecondary,
              contextMenuBuilder: buildTextFieldContextMenu,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => null,
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: 'room-name',
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.label,
    required this.imageUrl,
    required this.defaultAvatarKey,
    required this.size,
    this.borderColor = _borderColor,
    this.borderWidth = 1,
  });

  final String label;
  final String? imageUrl;
  final String defaultAvatarKey;
  final double size;
  final Color borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final imageUrl = this.imageUrl;
    final avatarColor = avatarFallbackColor(defaultAvatarKey);
    final fallback = Text(
      account_display.initials(label),
      style: TextStyle(
        color: _textPrimary,
        fontSize: (size * 0.36).clamp(11, 22).toDouble(),
        fontWeight: FontWeight.w800,
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: avatarColor,
        borderRadius: BorderRadius.zero,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: imageUrl == null
          ? fallback
          : Image.network(
              imageUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => fallback,
            ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.users});

  final List<UserSummary> users;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 28,
      width: 28 + (users.take(5).length - 1) * 18,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final entry in users.take(5).toList().asMap().entries)
            Positioned(
              left: entry.key * 18,
              child: _Avatar(
                label: entry.value.displayName,
                imageUrl: AppConfigScope.of(
                  context,
                ).resolveAssetUrl(entry.value.avatarUrl),
                defaultAvatarKey: entry.value.defaultAvatarKey,
                size: 28,
              ),
            ),
        ],
      ),
    );
  }
}

class _LiveCount extends StatelessWidget {
  const _LiveCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$count live',
      style: TextStyle(
        color: count > 0 ? _textSecondary : _textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.icon, required this.active});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 17, color: active ? _cyan : _textMuted);
  }
}

class _EmptyRoomPane extends StatelessWidget {
  const _EmptyRoomPane();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _primaryDarkLow,
      child: Center(
        child: Text(
          '选择一个房间开始聊天',
          style: TextStyle(color: _textMuted, fontSize: 16),
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDarkLow,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message ?? 'Request failed',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textSecondary),
            ),
            const SizedBox(height: 12),
            Button(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A transient, horizontally-centered message shown near the top of the window
/// (antd Message style). Fades/slides in and is auto-dismissed by the caller.
/// IgnorePointer keeps it from intercepting clicks on the content beneath.
class _MessageToast extends StatelessWidget {
  const _MessageToast({required this.message, required this.kind});

  final String message;
  final HomeToastKind kind;

  @override
  Widget build(BuildContext context) {
    final icon = kind == HomeToastKind.success
        ? Icons.check_circle_outline
        : Icons.error_outline;
    final iconColor = kind == HomeToastKind.success ? _cyan : _danger;

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * -8),
              child: child,
            ),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: _primaryDarkRaised,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.38),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
