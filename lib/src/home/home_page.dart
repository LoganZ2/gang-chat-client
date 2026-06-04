import 'dart:async';
import 'dart:io' show File, IOSink, Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:window_manager/window_manager.dart';

import '../auth/auth_client.dart';
import '../config/app_config.dart';
import '../lifecycle/shutdown_hooks.dart';
import '../live/live_session.dart';
import '../live/live_stream_client.dart';
import '../live/livekit_url.dart';
import '../protocol/api_client.dart';
import '../protocol/models.dart';
import '../protocol/sticker_pack_store.dart';
import '../settings/audio_device_store.dart';
import '../settings/settings_page.dart';
import '../ui/ui.dart';

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

enum _ToastKind { error, success }

enum _RoomDialogCloseResult { left, deleted }

/// True on desktop platforms where window_manager (and thus OS full-screen) is
/// supported. Mirrors the gate used in main.dart.
bool get _supportsWindowManagement =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.session,
    required this.apiBaseUrl,
    required this.accessTokenProvider,
    required this.onLogout,
    this.api,
    this.stickerPackStore = const StickerPackStore(),
  });

  final AuthSession session;
  final String apiBaseUrl;
  final AccessTokenProvider accessTokenProvider;
  final Future<void> Function() onLogout;
  final GangApi? api;
  final StickerPackStore stickerPackStore;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const MethodChannel _clipboardChannel = MethodChannel(
    'gang_chat/clipboard',
  );

  late GangApi _api;
  late CurrentUser _currentUser;
  final LiveSession _liveSession = LiveSession();
  final AudioDeviceStore _audioDeviceStore = const AudioDeviceStore();

  final _messageController = TextEditingController();
  late final FocusNode _messageFocus;
  final Map<String, String> _messageDrafts = {};

  List<RoomCard> _rooms = [];
  List<Message> _messages = [];
  final Map<String, _FileTransferState> _fileTransfers = {};
  final Map<String, _FileTransferState> _fileDownloads = {};
  RoomDetail? _selectedRoom;
  LiveState? _live;
  String? _selectedRoomId;
  String? _joinedLiveRoomId;
  String? _error;
  // Transient, centered toast (antd Message style) for action errors. Kept
  // separate from _error (which drives the full-pane load-failure view).
  String? _toast;
  _ToastKind _toastKind = _ToastKind.error;
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

  LiveStreamClient? _streamClient;

  Object? _shutdownHookToken;

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
    _currentUser = widget.session.user;
    _api = _newApiClient();
    _messageController.addListener(_onMessageDraftChanged);
    _liveSession.addListener(_onLiveSessionChanged);
    _liveSession.onForciblyRemoved = _onForciblyRemovedFromLive;
    _liveSession.onPublishPermissionChanged = _onPublishPermissionChanged;
    _shutdownHookToken = ShutdownHooks.register(
      () => _shutdownLive(reason: 'app_exit'),
    );
    _loadRooms();
    unawaited(_refreshRoomInviteBadge());
    _startLiveStream();
    unawaited(_warmPersonalStickerCache());
    unawaited(_restoreStoredAudioSettings());
  }

  void _onMessageDraftChanged() {
    final roomId = _selectedRoomId;
    if (roomId == null) return;
    _messageDrafts[roomId] = _messageController.text;
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
    List<XFile> files;
    try {
      files = await _clipboardFiles();
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      if (mounted) {
        _showToast('Unable to read clipboard files: ${e.message ?? e.code}');
      }
      return false;
    } catch (e) {
      if (mounted) _showToast('Unable to read clipboard files: $e');
      return false;
    }
    if (files.isEmpty) return false;
    for (final file in files) {
      if (!mounted) break;
      unawaited(_sendFileFromXFile(file));
    }
    return true;
  }

  Future<List<XFile>> _clipboardFiles() async {
    if (kIsWeb || !Platform.isWindows) return const <XFile>[];

    final paths = await _clipboardChannel.invokeListMethod<String>(
      'readFilePaths',
    );
    if (paths == null || paths.isEmpty) return const <XFile>[];

    final seenPaths = <String>{};
    final files = <XFile>[];
    for (final path in paths) {
      final trimmedPath = path.trim();
      if (trimmedPath.isEmpty || !seenPaths.add(trimmedPath)) continue;
      files.add(XFile(trimmedPath));
    }
    return files;
  }

  Future<void> _pasteTextFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    final value = _messageController.value;
    final selection = value.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, value.text.length)
        : value.text.length;
    final end = selection.isValid
        ? selection.end.clamp(0, value.text.length)
        : value.text.length;
    final replaceStart = start < end ? start : end;
    final replaceEnd = start < end ? end : start;
    final nextText = value.text.replaceRange(replaceStart, replaceEnd, text);
    final nextOffset = replaceStart + text.length;
    _messageController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  void _saveCurrentMessageDraft() {
    final roomId = _selectedRoomId;
    if (roomId == null) return;
    _messageDrafts[roomId] = _messageController.text;
  }

  void _restoreMessageDraft(String roomId) {
    final draft = _messageDrafts[roomId] ?? '';
    _messageController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  void _startLiveStream() {
    final client = LiveStreamClient(
      apiBaseUrl: widget.apiBaseUrl,
      accessTokenProvider: widget.accessTokenProvider,
    );
    client.onReconnect = _onStreamReconnect;
    client.events.listen(_onLiveEvent);
    _streamClient = client;
    unawaited(client.start());
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
      final page = await _api.listRooms();
      if (!mounted) return;
      setState(() => _rooms = page.rooms);
    } catch (_) {
      // Swallow: the last good data stays on screen.
    }
  }

  Future<void> _refreshLiveSilently(String roomId) async {
    try {
      final live = await _api.getLiveState(roomId);
      if (!mounted || live.roomId != _selectedRoomId) return;
      setState(() => _live = live);
    } catch (_) {}
  }

  /// Dispatches a realtime event from the SSE stream into local UI state.
  void _onLiveEvent(LiveEvent ev) {
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
    final card = _roomCardFromSnapshot(data);
    if (card == null || !mounted) return;
    setState(() => _rooms = _upsertRoomCard(_rooms, card));
  }

  /// A room's public state changed (member count, settings, rename, new last
  /// message, ...). Replace the matching card but keep our local per-user
  /// fields, which the snapshot doesn't carry.
  void _applyRoomUpdated(Map<String, dynamic> data) {
    final incoming = _roomCardFromSnapshot(data);
    if (incoming == null || !mounted) return;
    setState(() {
      final idx = _rooms.indexWhere((r) => r.id == incoming.id);
      if (idx < 0) {
        // We don't have it yet (e.g. missed the room_added); treat as an insert
        // so the list still converges.
        _rooms = _upsertRoomCard(_rooms, incoming);
        return;
      }
      final existing = _rooms[idx];
      final next = [..._rooms];
      // Carry the local unread count forward — the public snapshot resets it
      // to 0. Real unread tracking still needs a badge + read-marking, which
      // this client doesn't have yet, so we just avoid clobbering it.
      next[idx] = incoming.copyWith(unreadCount: existing.unreadCount);
      _rooms = next;
    });
    if (_selectedRoomId == incoming.id && (_selectedRoom?.isAdmin ?? false)) {
      unawaited(_refreshSelectedJoinRequestBadge());
    }
  }

  void _applyRoomJoinRequestsUpdated(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    if (roomId == null || roomId != _selectedRoomId) return;
    if (!(_selectedRoom?.isAdmin ?? false)) return;
    unawaited(_refreshSelectedJoinRequestBadge());
  }

  /// We lost a room (left, were removed, or it was deleted). Drop the card and,
  /// if it's the open room, clear the chat pane back to the empty state.
  void _applyRoomDeleted(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    if (roomId == null || !mounted) return;
    final wasSelected = _selectedRoomId == roomId;
    setState(() {
      _rooms = _rooms.where((r) => r.id != roomId).toList();
      if (wasSelected) {
        _selectedRoomId = null;
        _selectedRoom = null;
        _selectedRoomHasPendingJoinRequests = false;
        _messages = const [];
        _live = null;
        _livePanelOpen = false;
        _settingsOpen = false;
      }
    });
    _messageDrafts.remove(roomId);
    if (wasSelected) _messageController.clear();
    // If we were live in that room, the LiveKit session is now orphaned; drop
    // it so we don't keep streaming into a room we no longer belong to.
    if (_joinedLiveRoomId == roomId) {
      _joinedLiveRoomId = null;
      unawaited(_liveSession.disconnect().catchError((_) {}));
    }
  }

  /// Our role in a room changed (promoted to / demoted from admin). The room
  /// list card carries no role, but the open room's detail does and gates the
  /// admin affordances, so patch its membership when it's the selected room.
  void _applyRoomRoleChanged(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    final role = data['role'] as String?;
    if (roomId == null || role == null || !mounted) return;
    final current = _selectedRoom;
    if (current == null || current.id != roomId) return;
    final updated = current.copyWithRole(role);
    setState(() {
      _selectedRoom = updated;
    });
    unawaited(_refreshSelectedJoinRequestBadge(updated));
  }

  RoomCard? _roomCardFromSnapshot(Map<String, dynamic> data) {
    if (data['id'] is! String) return null;
    try {
      return RoomCard.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  void _applyLiveSnapshot(Map<String, dynamic> data) {
    final roomId = data['room_id'] as String?;
    if (roomId == null) return;
    final liveJson = data['live'] as Map<String, dynamic>?;
    final count = data['participant_count'] as int?;
    final previewJson = data['preview'] as List?;
    final preview = previewJson
        ?.cast<Map<String, dynamic>>()
        .map(UserSummary.fromJson)
        .toList();

    if (!mounted) return;
    setState(() {
      final idx = _rooms.indexWhere((r) => r.id == roomId);
      if (idx >= 0 && count != null) {
        final existing = _rooms[idx];
        _rooms[idx] = RoomCard(
          id: existing.id,
          name: existing.name,
          rid: existing.rid,
          visibility: existing.visibility,
          remarkName: existing.remarkName,
          description: existing.description,
          notificationPolicy: existing.notificationPolicy,
          avatarUrl: existing.avatarUrl,
          defaultAvatarKey: existing.defaultAvatarKey,
          memberCount: existing.memberCount,
          liveParticipantCount: count,
          liveAvatarPreview: preview ?? existing.liveAvatarPreview,
          lastMessage: existing.lastMessage,
          unreadCount: existing.unreadCount,
          updatedAt: existing.updatedAt,
        );
      }
      if (_selectedRoomId == roomId && liveJson != null) {
        _live = LiveState.fromJson(liveJson);
      }
    });
  }

  void _onLiveSessionChanged() {
    if (!mounted) return;
    // If the OS-level "stop sharing" bar (or a track failure) ended our screen
    // share, the LiveKit session knows before the server does. Reconcile the
    // server flag so the roster stops showing us as sharing.
    if (_screenSharing &&
        !_liveSession.isScreenSharing &&
        _joinedLiveRoomId != null &&
        _joinedLiveRoomId == _selectedRoomId) {
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
    final roomId = _joinedLiveRoomId;
    setState(() {
      if (roomId != null) _removeSelfFromLive(roomId);
      _joinedLiveRoomId = null;
      _joiningLive = false;
      _cameraOn = false;
      _screenSharing = false;
      _voiceBlocked = false;
    });
    // Drop any lingering transport so a stale connection can't auto-reconnect.
    unawaited(_liveSession.disconnect().catchError((_) {}));
    _showToast('你已被移出语音');
  }

  /// LiveKit reported our publish permission changed (admin block_voice /
  /// restore_voice). LiveKit is authoritative, so mirror it into the mic UI:
  /// when blocked the mic is force-muted and the button is disabled; when
  /// restored the button is re-enabled but stays muted until the user opens it.
  void _onPublishPermissionChanged(bool canPublish) {
    if (!mounted) return;
    setState(() {
      _voiceBlocked = !canPublish;
      if (!canPublish) _micMuted = true;
    });
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
    try {
      await Future.any([
        _liveSession.disconnect().catchError((_) {}),
        Future<void>.delayed(const Duration(seconds: 1)),
      ]);
    } catch (_) {}
  }

  Future<void> _handleLogout() async {
    await _shutdownLive(reason: 'logout');
    await widget.onLogout();
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
    if (oldWidget.session.user.id != widget.session.user.id) {
      _currentUser = widget.session.user;
      _setPendingRoomInviteBadge(false);
      _setSelectedJoinRequestBadge(false);
      unawaited(_refreshRoomInviteBadge());
      unawaited(_warmPersonalStickerCache());
    }
    if (oldWidget.apiBaseUrl == widget.apiBaseUrl &&
        oldWidget.api == widget.api) {
      return;
    }
    _api.close();
    _api = _newApiClient();
    // The stream is keyed to apiBaseUrl, so restart it against the new host.
    _streamClient?.dispose();
    _startLiveStream();
    setState(() {
      _hasPendingRoomInvites = false;
      _selectedRoomHasPendingJoinRequests = false;
    });
    _loadRooms();
    unawaited(_refreshRoomInviteBadge());
    unawaited(_warmPersonalStickerCache());
  }

  GangApi _newApiClient() {
    final api = widget.api;
    if (api != null) return api;
    return GangApiClient(
      baseUrl: widget.apiBaseUrl,
      accessTokenProvider: widget.accessTokenProvider,
    );
  }

  Future<void> _warmPersonalStickerCache() async {
    final userId = _currentUser.id;
    final cached = await widget.stickerPackStore.readPersonalPacks(
      userId: userId,
      apiBaseUrl: widget.apiBaseUrl,
    );
    if (cached != null) return;
    try {
      final packs = await _api.listStickerPacks(scope: 'personal');
      await widget.stickerPackStore.writePersonalPacks(
        userId: userId,
        apiBaseUrl: widget.apiBaseUrl,
        packs: packs,
      );
    } catch (_) {}
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loadingRooms = true;
      _error = null;
    });
    try {
      final page = await _api.listRooms();
      if (!mounted) return;
      setState(() => _rooms = page.rooms);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  Future<void> _refreshRoomInviteBadge() async {
    try {
      final invites = await _api.listRoomInvites();
      if (!mounted) return;
      _setPendingRoomInviteBadge(invites.isNotEmpty);
    } catch (_) {
      // Keep the last known badge state; transient failures should not clear it.
    }
  }

  Future<void> _refreshSelectedJoinRequestBadge([RoomDetail? room]) async {
    final target = room ?? _selectedRoom;
    if (target == null || (!target.isAdmin && !_currentUser.isSuperuser)) {
      if (mounted) _setSelectedJoinRequestBadge(false);
      return;
    }
    try {
      final requests = await _api.listJoinRequests(target.id);
      if (!mounted || _selectedRoomId != target.id) return;
      _setSelectedJoinRequestBadge(requests.isNotEmpty);
    } catch (_) {
      // Keep the last known badge state; permission or network failures should
      // not create a distracting flicker.
    }
  }

  void _setPendingRoomInviteBadge(bool hasPending) {
    if (!mounted || _hasPendingRoomInvites == hasPending) return;
    setState(() => _hasPendingRoomInvites = hasPending);
  }

  void _setSelectedJoinRequestBadge(bool hasPending) {
    if (!mounted || _selectedRoomHasPendingJoinRequests == hasPending) return;
    setState(() => _selectedRoomHasPendingJoinRequests = hasPending);
  }

  Future<void> _openRoom(
    RoomCard room, {
    bool joinLive = false,
    RoomDetail? optimisticDetail,
  }) async {
    if (_loadingRoom && _selectedRoomId == room.id) return;
    _saveCurrentMessageDraft();
    setState(() {
      _settingsOpen = false;
      _selectedRoomId = room.id;
      _loadingRoom = true;
      _error = null;
      _selectedRoomHasPendingJoinRequests = false;
      if (optimisticDetail != null) {
        _selectedRoom = optimisticDetail;
        _messages = const [];
        _live = optimisticDetail.live;
      }
      if (!joinLive) _livePanelOpen = false;
    });
    _restoreMessageDraft(room.id);

    try {
      final detail = await _api.getRoom(room.id);
      final messagePage = await _api.listMessages(roomId: room.id);
      final live = await _api.getLiveState(room.id);
      if (!mounted || _selectedRoomId != room.id) return;
      setState(() {
        _selectedRoom = detail;
        _messages = messagePage.messages;
        _live = live;
        _livePanelOpen = joinLive;
      });
      unawaited(_refreshSelectedJoinRequestBadge(detail));
      if (joinLive) await _joinLive('room_card_speaker');
    } catch (e) {
      if (!mounted) return;
      if (optimisticDetail != null && _selectedRoomId == room.id) {
        _showToast('房间刷新失败，已先打开当前房间');
      } else {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && _selectedRoomId == room.id) {
        setState(() => _loadingRoom = false);
      }
    }
  }

  Future<void> _createRoom() async {
    final created = await showDialog<RoomDetail>(
      context: context,
      builder: (context) => _CreateRoomDialog(api: _api),
    );
    if (created == null || !mounted) return;
    setState(() {
      _rooms = _upsertRoomCard(_rooms, created.toCard());
    });
    await _openRoom(created.toCard(), optimisticDetail: created);
  }

  /// Opens the search-and-join dialog. On a successful join the dialog returns
  /// the new room detail; we add it to the list and open it. A pending
  /// (approval-required) join returns null and the dialog shows its own state.
  Future<void> _joinRoom() async {
    final joined = await showDialog<RoomDetail>(
      context: context,
      builder: (context) => _JoinRoomDialog(
        api: _api,
        onOpenUserInfo: (user) => _showUserInfo(user, basic: true),
        onPendingInvitesChanged: _setPendingRoomInviteBadge,
      ),
    );
    unawaited(_refreshRoomInviteBadge());
    if (joined == null || !mounted) return;
    setState(() {
      _rooms = _upsertRoomCard(_rooms, joined.toCard());
    });
    await _openRoom(joined.toCard(), optimisticDetail: joined);
  }

  /// Opens the room member list. After it closes (invites or approvals may
  /// have added members), refresh the room so the member count stays accurate.
  Future<void> _openRoomMembers() async {
    final room = _selectedRoom;
    if (room == null) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _RoomMembersDialog(
        api: _api,
        room: room,
        initialLive: _live ?? room.live,
        canReviewRequests: room.isAdmin || _currentUser.isSuperuser,
        onOpenUserInfo: _showUserInfo,
        onPendingRequestsChanged: _setSelectedJoinRequestBadge,
      ),
    );
    unawaited(_refreshSelectedJoinRequestBadge(room));
    if (changed != true || !mounted) return;
    try {
      final detail = await _api.getRoom(room.id);
      if (!mounted || _selectedRoomId != room.id) return;
      setState(() {
        _selectedRoom = detail;
        _rooms = _upsertRoomCard(_rooms, detail.toCard());
      });
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
        api: _api,
        room: room,
        currentUser: _currentUser,
        isInLive: _joinedLiveRoomId == room.id,
        onLeaveLive: _leaveLive,
      ),
    );
    _handleRoomDialogResult(room.id, result);
  }

  Future<void> _openRoomManagement() async {
    final room = _selectedRoom;
    if (room == null || (!room.isAdmin && !_currentUser.isSuperuser)) return;
    final result = await showDialog<Object?>(
      context: context,
      builder: (context) => _RoomManagementDialog(
        api: _api,
        room: room,
        currentUser: _currentUser,
      ),
    );
    _handleRoomDialogResult(room.id, result);
  }

  void _handleRoomDialogResult(String roomId, Object? result) {
    if (!mounted || result == null) return;
    if (result is RoomDetail) {
      setState(() {
        _selectedRoom = result;
        _rooms = _upsertRoomCard(_rooms, result.toCard());
      });
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
  }) {
    final room = _selectedRoom;
    if (basic || room == null) {
      showDialog<void>(
        context: context,
        builder: (context) => _BasicUserInfoDialog(
          user: user,
          onCopyUid: (uid) => unawaited(_copyUserInfoUid(uid)),
        ),
      );
      return;
    }
    final profile = _profileForDialog(user, room);
    showDialog<void>(
      context: context,
      builder: (context) => _UserInfoDialog(
        user: profile,
        room: room,
        commonRooms: _commonRoomsForDialog(
          profile,
          room,
          includeSelectedRoom: includeSelectedRoom,
        ),
        onOpenRoom: _openUserInfoRoom,
        onCopyUid: (uid) => unawaited(_copyUserInfoUid(uid)),
      ),
    );
  }

  Future<void> _copyUserInfoUid(String uid) async {
    try {
      await Clipboard.setData(ClipboardData(text: uid));
      if (!mounted) return;
      _showToast('UID 已复制', kind: _ToastKind.success);
    } catch (e) {
      if (!mounted) return;
      _showToast('无法复制 UID：$e');
    }
  }

  UserSummary _profileForDialog(UserSummary user, RoomDetail room) {
    var profile = user;
    final createdBy = room.createdBy;
    if (createdBy != null && user.id == createdBy.id) {
      profile = profile.mergeMissing(createdBy);
    }
    if (user.id == _currentUser.id) {
      profile = profile.mergeMissing(_currentUser.toSummary());
    }
    final roomRole =
        profile.roomRole ??
        (createdBy != null && user.id == createdBy.id
            ? 'owner'
            : user.id == _currentUser.id
            ? room.myMembership.role
            : null);
    return profile.copyWith(roomRole: roomRole);
  }

  List<UserCommonRoom> _commonRoomsForDialog(
    UserSummary user,
    RoomDetail room, {
    required bool includeSelectedRoom,
  }) {
    if (user.id == _currentUser.id || user.isSuperuser) {
      return const [];
    }
    if (_currentUser.isSuperuser || includeSelectedRoom) {
      return _commonRoomsForProfile(user, room);
    }
    return user.commonRooms;
  }

  List<UserCommonRoom> _commonRoomsForProfile(
    UserSummary user,
    RoomDetail room,
  ) {
    return [
      UserCommonRoom(
        id: room.id,
        rid: room.rid,
        name: room.name,
        visibility: room.visibility,
        roomDisplayName: user.roomDisplayName,
        roomRole: user.roomRole,
      ),
      for (final commonRoom in user.commonRooms)
        if (commonRoom.id != room.id) commonRoom,
    ];
  }

  void _openUserInfoRoom(String roomId) {
    if (roomId == _selectedRoomId) return;
    for (final room in _rooms) {
      if (room.id == roomId) {
        unawaited(_openRoom(room));
        return;
      }
    }
    unawaited(_fetchAndOpenRoom(roomId));
  }

  Future<void> _fetchAndOpenRoom(String roomId) async {
    try {
      final detail = await _api.getRoom(roomId);
      if (!mounted) return;
      final card = detail.toCard();
      setState(() {
        _rooms = _upsertRoomCard(_rooms, card);
      });
      await _openRoom(card);
    } catch (e) {
      if (!mounted) return;
      _showToast('无法打开房间：$e');
    }
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trimRight();
    if (body.trim().isEmpty) return;
    await _sendMessagePayload(body: body, clearDraft: true);
  }

  Future<void> _sendStickerMessage(Sticker sticker) async {
    final attachment = MessageAttachment(
      type: 'sticker',
      stickerId: sticker.id,
      name: sticker.name,
      asset: sticker.asset,
    );
    await _sendMessagePayload(
      body: '[${sticker.name}]',
      type: 'sticker',
      attachments: [attachment],
    );
  }

  Future<void> _pickAndSendFile() async {
    XFile? file;
    try {
      file = await openFile();
    } catch (e) {
      if (!mounted) return;
      _showToast('Unable to open file picker: $e');
      return;
    }
    if (file == null || !mounted) return;
    unawaited(_sendFileFromXFile(file));
  }

  Future<void> _sendFileFromXFile(XFile file) async {
    final room = _selectedRoom;
    if (room == null) return;

    final filename = _basename(file.name);
    int length;
    try {
      length = await file.length();
    } catch (e) {
      if (!mounted) return;
      _showToast('Unable to read file: $e');
      return;
    }
    if (length == 0) {
      _showToast('File is empty');
      return;
    }

    final clientMessageId = newClientId('cmsg');
    final transfer = _FileTransferState.upload(
      controller: UploadTransferController(),
      totalBytes: length,
    );
    final localAttachment = MessageAttachment(
      type: 'file',
      name: filename,
      asset: UploadedAsset(
        id: 'local_$clientMessageId',
        url: '',
        thumbnailUrl: null,
        mimeType: file.mimeType ?? _mimeTypeFromFilename(filename),
        filename: filename,
        sizeBytes: length,
      ),
    );
    final local = Message.local(
      roomId: room.id,
      sender: _currentUser.toSummary(),
      clientMessageId: clientMessageId,
      body: filename,
      type: 'file',
      attachments: [localAttachment],
    );

    setState(() {
      _fileTransfers[clientMessageId] = transfer;
      _messages = [..._messages, local];
      _error = null;
    });

    try {
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw StateError('File is empty');
      if (transfer.cancelled) return;

      final asset = await _api.uploadFileAsset(
        bytes: bytes,
        filename: filename,
        controller: transfer.controller,
        onProgress: ({required sentBytes, required totalBytes}) {
          if (!mounted) return;
          final current = _fileTransfers[clientMessageId];
          if (current == null || current.cancelled) return;
          setState(() {
            current.updateProgress(
              sentBytes: sentBytes,
              totalBytes: totalBytes,
            );
          });
        },
      );
      if (!mounted || transfer.cancelled) return;

      final attachment = MessageAttachment(
        type: 'file',
        name: filename,
        asset: asset,
      );
      setState(() {
        transfer.sendingMessage = true;
        transfer.updateProgress(
          sentBytes: transfer.totalBytes,
          totalBytes: transfer.totalBytes,
        );
        _messages = _updateMessageByClientId(
          _messages,
          clientMessageId,
          (message) => _copyMessage(message, attachments: [attachment]),
        );
      });

      final sent = await _api.sendMessage(
        roomId: room.id,
        clientMessageId: clientMessageId,
        body: filename,
        type: 'file',
        attachments: [attachment],
        idempotencyKey: newUuid(),
      );
      if (!mounted || transfer.cancelled) return;
      setState(() {
        _messages = _replaceMessageByClientId(_messages, sent);
        _fileTransfers.remove(clientMessageId);
      });
      await _loadRooms();
    } on UploadCancelledException {
      if (!mounted) return;
      _removeLocalFileMessage(clientMessageId);
    } catch (e) {
      if (!mounted) return;
      if (transfer.cancelled) {
        _removeLocalFileMessage(clientMessageId);
        return;
      }
      setState(() {
        transfer.failed = true;
        transfer.error = e.toString();
        _messages = _messages.map((message) {
          return message.clientMessageId == clientMessageId
              ? message.markFailed()
              : message;
        }).toList();
      });
      _showToast(e.toString());
    }
  }

  void _pauseFileUpload(String clientMessageId) {
    final transfer = _fileTransfers[clientMessageId];
    if (transfer == null || !transfer.active || transfer.paused) return;
    setState(() {
      transfer.controller.pause();
      transfer.stopSpeed();
    });
  }

  void _resumeFileUpload(String clientMessageId) {
    final transfer = _fileTransfers[clientMessageId];
    if (transfer == null || !transfer.paused) return;
    setState(() => transfer.controller.resume());
  }

  void _cancelFileUpload(String clientMessageId) {
    final transfer = _fileTransfers[clientMessageId];
    if (transfer == null || !transfer.active) return;
    transfer.controller.cancel();
    _removeLocalFileMessage(clientMessageId);
  }

  void _removeLocalFileMessage(String clientMessageId) {
    if (!mounted) return;
    setState(() {
      _fileTransfers.remove(clientMessageId);
      _messages = _messages
          .where((message) => message.clientMessageId != clientMessageId)
          .toList();
    });
  }

  Future<void> _downloadFileAttachment({
    required String downloadKey,
    required MessageAttachment attachment,
    required String url,
  }) async {
    if (_fileDownloads.containsKey(downloadKey)) return;

    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showToast('Cannot download file');
      return;
    }

    final filename = _fileAttachmentTitle(attachment);
    final location = await getSaveLocation(
      suggestedName: filename,
      confirmButtonText: 'Save',
    );
    if (location == null || !mounted) return;

    final destinationPath = location.path;
    final transfer = _FileTransferState.download(
      controller: UploadTransferController(),
      totalBytes: attachment.asset?.sizeBytes ?? 0,
      destinationPath: destinationPath,
    );
    setState(() => _fileDownloads[downloadKey] = transfer);

    http.Client? client;
    IOSink? sink;
    try {
      client = http.Client();
      transfer.downloadClient = client;
      final request = http.Request('GET', uri);
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Download failed (${response.statusCode})');
      }

      final totalBytes =
          response.contentLength ?? attachment.asset?.sizeBytes ?? 0;
      var receivedBytes = 0;
      if (mounted && _fileDownloads[downloadKey] == transfer) {
        setState(() {
          transfer.updateProgress(sentBytes: 0, totalBytes: totalBytes);
        });
      }

      final file = File(destinationPath);
      sink = file.openWrite();
      transfer.wroteDestination = true;
      await for (final chunk in response.stream) {
        await transfer.controller.waitIfPaused();
        if (transfer.cancelled) throw const _DownloadCancelledException();

        sink.add(chunk);
        receivedBytes += chunk.length;
        if (!mounted) continue;
        final current = _fileDownloads[downloadKey];
        if (current == null || current.cancelled) {
          throw const _DownloadCancelledException();
        }
        setState(() {
          current.updateProgress(
            sentBytes: receivedBytes,
            totalBytes: totalBytes,
          );
        });
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (!mounted || transfer.cancelled) return;
      setState(() => _fileDownloads.remove(downloadKey));
      _showToast('File downloaded', kind: _ToastKind.success);
    } on _DownloadCancelledException {
      if (transfer.wroteDestination) {
        await _deletePartialDownload(destinationPath);
      }
    } catch (e) {
      if (transfer.cancelled) {
        if (transfer.wroteDestination) {
          await _deletePartialDownload(destinationPath);
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        transfer.failed = true;
        transfer.error = e.toString();
        transfer.stopSpeed();
      });
      _showToast(e.toString());
    } finally {
      client?.close();
      transfer.downloadClient = null;
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          // The client may have been closed to cancel the response stream.
        }
      }
      if (transfer.cancelled && mounted) {
        setState(() => _fileDownloads.remove(downloadKey));
      }
    }
  }

  void _pauseFileDownload(String downloadKey) {
    final transfer = _fileDownloads[downloadKey];
    if (transfer == null || !transfer.active || transfer.paused) return;
    setState(() {
      transfer.controller.pause();
      transfer.stopSpeed();
    });
  }

  void _resumeFileDownload(String downloadKey) {
    final transfer = _fileDownloads[downloadKey];
    if (transfer == null || !transfer.paused) return;
    setState(() => transfer.controller.resume());
  }

  void _cancelFileDownload(String downloadKey) {
    final transfer = _fileDownloads[downloadKey];
    if (transfer == null) return;
    if (!transfer.active) {
      setState(() => _fileDownloads.remove(downloadKey));
      final destinationPath = transfer.destinationPath;
      if (destinationPath != null && transfer.wroteDestination) {
        unawaited(_deletePartialDownload(destinationPath));
      }
      return;
    }
    transfer.controller.cancel();
    transfer.downloadClient?.close();
    setState(() => _fileDownloads.remove(downloadKey));
  }

  Future<void> _deletePartialDownload(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort cleanup for a cancelled or failed partial download.
    }
  }

  Future<void> _sendMessagePayload({
    required String body,
    String type = 'text',
    List<MessageAttachment> attachments = const [],
    bool clearDraft = false,
  }) async {
    final room = _selectedRoom;
    if (room == null || _sending) return;

    if (type == 'text' && body.trim().isEmpty) return;
    if (type != 'text' && attachments.isEmpty) return;

    final clientMessageId = newClientId('cmsg');
    final local = Message.local(
      roomId: room.id,
      sender: _currentUser.toSummary(),
      clientMessageId: clientMessageId,
      type: type,
      body: body,
      attachments: attachments,
    );

    setState(() {
      _sending = true;
      _messages = [..._messages, local];
      if (clearDraft) _messageController.clear();
      _error = null;
    });

    try {
      final sent = await _api.sendMessage(
        roomId: room.id,
        clientMessageId: clientMessageId,
        body: body,
        type: type,
        attachments: attachments,
        idempotencyKey: newUuid(),
      );
      if (!mounted) return;
      setState(() {
        _messages = _replaceMessageByClientId(_messages, sent);
      });
      await _loadRooms();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages.map((message) {
          return message.clientMessageId == clientMessageId
              ? message.markFailed()
              : message;
        }).toList();
      });
      _showToast(e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _joinLive(String source) async {
    final room = _selectedRoom;
    if (room == null || _joiningLive) return;

    setState(() {
      _joiningLive = true;
      _livePanelOpen = true;
      _error = null;
    });

    final existingLiveRoomId = _joinedLiveRoomId;
    if (existingLiveRoomId != null && existingLiveRoomId != room.id) {
      // Switching rooms: drop the LiveKit connection to the previous room. The
      // server cleans up the old live_participants row via the LiveKit webhook
      // and broadcasts the departure over SSE — no explicit leave call needed.
      try {
        await _liveSession.disconnect();
      } catch (_) {}
      // Drop the stale joined marker immediately, and optimistically remove
      // ourselves from the previous room's live state so its count decrements
      // without waiting on the SSE snapshot (which can lag or briefly drop).
      if (mounted) {
        setState(() {
          _removeSelfFromLive(existingLiveRoomId);
          _joinedLiveRoomId = null;
        });
      }
    }

    try {
      final result = await _api.joinLive(
        roomId: room.id,
        clientLiveSessionId: newClientId('clive'),
        source: source,
        idempotencyKey: newUuid(),
      );
      if (!mounted) return;
      // Reflect the freshly-fetched live roster, but do NOT mark ourselves as
      // joined yet: that flips only once the LiveKit transport is actually up,
      // so the Join button keeps its loading spinner until we're truly in the
      // room (rather than briefly showing the in-room controls + a spinner on
      // the disconnect button).
      setState(() {
        _micMuted = result.participant.micMuted;
        _cameraOn = result.participant.cameraOn;
        _screenSharing = result.participant.screenSharing;
        _voiceBlocked = result.participant.voiceBlocked;
        _live = result.live;
        _rooms = _patchRoomLiveCount(_rooms, room.id, result.live);
      });
      try {
        await _connectLiveKitWithRetry(result);
      } catch (e) {
        if (!mounted) return;
        _showToast('Failed to connect to voice: $e');
        return;
      }
      // LiveKit transport is up — now we're genuinely in the room.
      if (!mounted) return;
      setState(() {
        _joinedLiveRoomId = room.id;
      });
    } catch (e) {
      if (!mounted) return;
      _showToast(e.toString());
    } finally {
      if (mounted) setState(() => _joiningLive = false);
    }
  }

  Future<void> _connectLiveKitWithRetry(LiveJoinResult result) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
      if (!mounted) throw 'Join cancelled';
      try {
        final liveKitUrl = resolveLiveKitServerUrl(
          serverUrl: result.liveKit.serverUrl,
          apiBaseUrl: widget.apiBaseUrl,
        );
        await _restoreStoredAudioSettings();
        await _liveSession.connect(
          url: liveKitUrl,
          token: result.liveKit.token,
          roomName: result.liveKit.roomName,
          micMuted: result.participant.micMuted,
        );
        return;
      } catch (e) {
        lastError = e;
        try {
          await _liveSession.disconnect();
        } catch (_) {}
      }
    }
    throw lastError ?? 'LiveKit connection failed';
  }

  Future<void> _restoreStoredAudioSettings() async {
    try {
      final stored = await _audioDeviceStore.read();
      await _liveSession.setInputVolume(stored.inputVolume);
      await _liveSession.setOutputVolume(stored.outputVolume);
      await restoreStoredAudioDevices(_audioDeviceStore);
    } catch (_) {
      // Joining voice should still work with LiveKit's current/default device
      // if a stored local preference cannot be applied.
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
    setState(() {
      _joiningLive = true;
      _removeSelfFromLive(roomId);
      _joinedLiveRoomId = null;
      _cameraOn = false;
      _screenSharing = false;
      _voiceBlocked = false;
    });
    try {
      // Drop the LiveKit connection. The server observes the disconnect via
      // the LiveKit webhook, removes the live_participants row, and pushes the
      // updated snapshot back to every client (including this one) over SSE.
      try {
        await _liveSession.disconnect();
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      _showToast(e.toString());
    } finally {
      if (mounted) setState(() => _joiningLive = false);
    }
  }

  /// Optimistically removes the current user from the cached live state and
  /// the room-list live count for [roomId]. The authoritative SSE snapshot
  /// reconciles afterward; this just keeps the UI from lagging on departure.
  void _removeSelfFromLive(String roomId) {
    final selfId = _currentUser.id;
    final current = _live;
    if (current != null && current.roomId == roomId) {
      final remaining = current.participants
          .where((p) => p.user.id != selfId)
          .toList();
      if (remaining.length != current.participants.length) {
        _live = LiveState(
          roomId: current.roomId,
          participantCount: remaining.length,
          participants: remaining,
          updatedAt: current.updatedAt,
        );
      }
    }
    final idx = _rooms.indexWhere((r) => r.id == roomId);
    if (idx >= 0) {
      final existing = _rooms[idx];
      final remainingPreview = existing.liveAvatarPreview
          .where((u) => u.id != selfId)
          .toList();
      final nextCount = existing.liveParticipantCount > 0
          ? existing.liveParticipantCount - 1
          : 0;
      _rooms[idx] = RoomCard(
        id: existing.id,
        name: existing.name,
        rid: existing.rid,
        visibility: existing.visibility,
        remarkName: existing.remarkName,
        description: existing.description,
        notificationPolicy: existing.notificationPolicy,
        avatarUrl: existing.avatarUrl,
        defaultAvatarKey: existing.defaultAvatarKey,
        memberCount: existing.memberCount,
        liveParticipantCount: nextCount,
        liveAvatarPreview: remainingPreview,
        lastMessage: existing.lastMessage,
        unreadCount: existing.unreadCount,
        updatedAt: existing.updatedAt,
      );
    }
  }

  Future<void> _patchLiveState({
    bool? micMuted,
    bool? cameraOn,
    bool? screenSharing,
  }) async {
    final roomId = _joinedLiveRoomId;
    if (roomId == null || roomId != _selectedRoomId) return;

    try {
      // Apply the microphone change to the LiveKit transport in parallel with
      // the server PATCH. Server stays the source of truth for the rendered
      // state - if its response disagrees with what we asked for we resync
      // the LiveKit side below.
      final liveKitMicFuture = micMuted == null
          ? Future<void>.value()
          : _liveSession.setMicMuted(micMuted).catchError((_) {});
      final participant = await _api.updateMyLiveState(
        roomId: roomId,
        micMuted: micMuted,
        cameraOn: cameraOn,
        screenSharing: screenSharing,
      );
      await liveKitMicFuture;
      if (micMuted != null && participant.micMuted != micMuted) {
        try {
          await _liveSession.setMicMuted(participant.micMuted);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _micMuted = participant.micMuted;
        _cameraOn = participant.cameraOn;
        _screenSharing = participant.screenSharing;
        // The server forces mic_muted/voice_blocked back on for a banned user
        // who tried to self-unmute; trust the returned values over what we
        // optimistically asked for.
        _voiceBlocked = participant.voiceBlocked;
        _live = _mergeParticipant(_live, participant);
      });
    } catch (e) {
      if (!mounted) return;
      // A 409 means the server already considers us gone (e.g. the LiveKit
      // webhook removed our row during teardown). That's benign here — a stray
      // state PATCH racing our own departure — so don't surface it as an error.
      if (e is ApiException && e.statusCode == 409) return;
      _showToast(e.toString());
    }
  }

  /// Toggle the local camera. We publish/unpublish the LiveKit track first and
  /// only tell the server once capture actually succeeded, so the roster never
  /// claims a camera that failed to start. The server response stays the
  /// source of truth for the rendered flag.
  Future<void> _toggleCamera() async {
    final roomId = _joinedLiveRoomId;
    if (roomId == null || roomId != _selectedRoomId) return;
    final enable = !_cameraOn;
    try {
      await _liveSession.setCameraEnabled(enable);
    } catch (e) {
      if (!mounted) return;
      _showToast('无法打开摄像头: $e');
      return;
    }
    await _patchLiveState(cameraOn: enable);
  }

  /// Toggle screen sharing. Turning it on opens a source picker, starts the
  /// LiveKit capture, and only then PATCHes the server. If the user cancels the
  /// picker or capture fails we leave both the transport and server untouched.
  Future<void> _toggleScreenShare() async {
    final roomId = _joinedLiveRoomId;
    if (roomId == null || roomId != _selectedRoomId) return;

    if (_screenSharing) {
      try {
        await _liveSession.setScreenShareEnabled(false);
      } catch (_) {
        // Even if the stop call throws, fall through and clear server state.
      }
      await _patchLiveState(screenSharing: false);
      return;
    }

    final source = await showDialog<ScreenSource>(
      context: context,
      builder: (context) => const _ScreenShareDialog(),
    );
    if (source == null || !mounted) return;
    // Re-check we're still live in this room after the async picker.
    if (_joinedLiveRoomId != roomId || roomId != _selectedRoomId) return;

    try {
      await _liveSession.setScreenShareEnabled(true, sourceId: source.id);
    } catch (e) {
      if (!mounted) return;
      _showToast('无法共享屏幕: $e');
      return;
    }
    await _patchLiveState(screenSharing: true);
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    // Make sure we never leave the window-controls hidden if we're torn down
    // (e.g. logout) while the immersive full-screen share was open.
    windowControlsHidden.value = false;
    _streamClient?.dispose();
    _streamClient = null;
    if (_shutdownHookToken != null) {
      ShutdownHooks.unregister(_shutdownHookToken!);
      _shutdownHookToken = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _liveSession.removeListener(_onLiveSessionChanged);
    _liveSession.onForciblyRemoved = null;
    _liveSession.onPublishPermissionChanged = null;
    _liveSession.dispose();
    for (final transfer in _fileDownloads.values) {
      transfer.controller.cancel();
      transfer.downloadClient?.close();
      final destinationPath = transfer.destinationPath;
      if (destinationPath != null && transfer.wroteDestination) {
        unawaited(_deletePartialDownload(destinationPath));
      }
    }
    _api.close();
    _messageController.removeListener(_onMessageDraftChanged);
    _messageController.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  /// Shows a transient, horizontally-centered message near the top (antd
  /// Message style) that auto-dismisses. Used for action errors so they no
  /// longer sit in a top bar that overlaps the custom window controls.
  void _showToast(String message, {_ToastKind kind = _ToastKind.error}) {
    setState(() {
      _toast = message;
      _toastKind = kind;
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  /// Resolves the live screen-share track for the participant currently held
  /// in [_fullScreenShareIdentity], or null if there's no such active share
  /// (e.g. the sharer stopped). Used to auto-exit full-screen when it vanishes.
  LiveVideoTrack? get _fullScreenShareTrack {
    final identity = _fullScreenShareIdentity;
    if (identity == null) return null;
    for (final track in _liveSession.videoTracks) {
      if (track.isScreenShare && track.identity == identity) return track;
    }
    return null;
  }

  /// Enters immersive full-screen for [track]: real OS full-screen, with the
  /// sidebar, header and custom window-controls hidden so only the video and a
  /// floating control bar show. Esc or the exit button leaves.
  Future<void> _enterShareFullScreen(LiveVideoTrack track) async {
    setState(() => _fullScreenShareIdentity = track.identity);
    windowControlsHidden.value = true;
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
    if (_fullScreenShareIdentity == null) return;
    setState(() => _fullScreenShareIdentity = null);
    windowControlsHidden.value = false;
    if (_supportsWindowManagement) {
      try {
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
      } catch (_) {}
    }
  }

  void _toggleSettings() {
    if (_settingsOpen) {
      _closeSettings();
      return;
    }
    setState(() {
      _settingsOpen = true;
      _error = null;
    });
  }

  void _closeSettings() {
    if (!_settingsOpen) return;
    setState(() {
      _settingsOpen = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Resolve the full-screen share track; if it vanished (sharer stopped),
    // schedule an exit so we don't stay stuck in an empty OS full-screen.
    final fullScreenShare = _fullScreenShareTrack;
    if (_fullScreenShareIdentity != null && fullScreenShare == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _exitShareFullScreen();
      });
    }
    return Scaffold(
      backgroundColor: _primaryDark,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxAllowed = (constraints.maxWidth - 240).clamp(
            _sidebarMinWidth,
            _sidebarMaxWidth,
          );
          final width = _sidebarCollapsed
              ? _sidebarCollapsedWidth
              : _sidebarWidth.clamp(_sidebarMinWidth, maxAllowed);
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
                        setState(() {
                          _sidebarWidth = (_sidebarWidth + details.delta.dx)
                              .clamp(_sidebarMinWidth, maxAllowed);
                        });
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
                      onTap: () => setState(
                        () => _sidebarCollapsed = !_sidebarCollapsed,
                      ),
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
                    label: _displayNameFor(fullScreenShare.identity),
                    onExit: _exitShareFullScreen,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Resolves the display name for a LiveKit identity from the live roster.
  String _displayNameFor(String userId) {
    final current = _live;
    if (current != null) {
      for (final p in current.participants) {
        if (p.user.id == userId) return p.user.displayName;
      }
    }
    return '';
  }

  Widget _buildRoomPane() {
    if (_settingsOpen) {
      return SettingsPage(
        isSubWindow: true,
        audioDeviceStore: _audioDeviceStore,
        api: _api,
        apiBaseUrl: widget.apiBaseUrl,
        stickerPackStore: widget.stickerPackStore,
        currentUser: _currentUser,
        onUserUpdated: (user) => setState(() => _currentUser = user),
        onVolumeChanged: (kind, volume) {
          if (kind == 'audioinput') {
            unawaited(_liveSession.setInputVolume(volume));
          } else if (kind == 'audiooutput') {
            unawaited(_liveSession.setOutputVolume(volume));
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
              onExpand: () => setState(() => _livePanelOpen = true),
              onJoin: () => _joinLive('live_header'),
              onOpenRoomManagement: _openRoomManagement,
              onOpenRoomInfo: _openRoomInfo,
              onOpenMembers: _openRoomMembers,
              showManagementButton: room.isAdmin || _currentUser.isSuperuser,
              showMemberRequestBadge:
                  (room.isAdmin || _currentUser.isSuperuser) &&
                  _selectedRoomHasPendingJoinRequests,
            ),
          Expanded(
            child: _livePanelOpen
                ? _LivePanel(
                    room: room,
                    live: live,
                    liveSession: _liveSession,
                    joined: _joinedLiveRoomId == room.id,
                    joining: _joiningLive,
                    micMuted: _micMuted,
                    headphonesMuted: _headphonesMuted,
                    voiceBlocked: _voiceBlocked,
                    cameraOn: _cameraOn,
                    screenSharing: _screenSharing,
                    speakingUserIds: _liveSession.speakingIdentities,
                    onJoin: () => _joinLive('live_panel'),
                    onLeave: _leaveLive,
                    onToggleMic: _voiceBlocked
                        ? null
                        : () => _patchLiveState(micMuted: !_micMuted),
                    onToggleHeadphones: () {
                      final muted = !_headphonesMuted;
                      setState(() => _headphonesMuted = muted);
                      unawaited(_liveSession.setOutputMuted(muted));
                    },
                    onToggleCamera: _toggleCamera,
                    onToggleShare: _toggleScreenShare,
                    onCollapse: () => setState(() => _livePanelOpen = false),
                    onEnterFullScreen: _enterShareFullScreen,
                    onOpenUserInfo: _showUserInfo,
                    localUserId: _currentUser.id,
                  )
                : _ChatPane(
                    roomId: _selectedRoomId!,
                    api: _api,
                    apiBaseUrl: widget.apiBaseUrl,
                    stickerPackStore: widget.stickerPackStore,
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
                  ),
          ),
        ],
      ),
    );
  }
}

class _BadgeAnchor extends StatelessWidget {
  const _BadgeAnchor({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (show) const Positioned(top: -3, right: -3, child: _BadgeDot()),
      ],
    );
  }
}

class _BadgeDot extends StatelessWidget {
  const _BadgeDot();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _danger,
        shape: BoxShape.circle,
        border: Border.all(color: _primaryDarkLow, width: 2),
      ),
      child: const SizedBox.square(dimension: 10),
    );
  }
}

class _RoomListPane extends StatelessWidget {
  const _RoomListPane({
    required this.rooms,
    required this.selectedRoomId,
    required this.loading,
    required this.currentUser,
    required this.collapsed,
    required this.settingsActive,
    required this.hasPendingRoomInvites,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onOpenSettings,
    required this.onLogout,
    required this.onOpenRoom,
    required this.onJoinLive,
  });

  final List<RoomCard> rooms;
  final String? selectedRoomId;
  final bool loading;
  final CurrentUser currentUser;
  final bool collapsed;
  final bool settingsActive;
  final bool hasPendingRoomInvites;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onLogout;
  final ValueChanged<RoomCard> onOpenRoom;
  final ValueChanged<RoomCard> onJoinLive;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDarkLow,
      child: Column(
        children: [
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(
                children: [
                  _Avatar(
                    label: currentUser.displayName,
                    imageUrl: AppConfigScope.of(
                      context,
                    ).resolveAssetUrl(currentUser.avatarUrl),
                    defaultAvatarKey: currentUser.defaultAvatarKey,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentUser.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        _UserStatusLabel(label: currentUser.status ?? '在线'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Button(
                      width: double.infinity,
                      onPressed: onCreateRoom,
                      icon: const Icon(Icons.add),
                      tone: ButtonTone.primary,
                      child: const Text('创建房间'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BadgeAnchor(
                      show: hasPendingRoomInvites,
                      child: Button(
                        width: double.infinity,
                        onPressed: onJoinRoom,
                        icon: const Icon(Icons.group_add),
                        child: const Text('加入房间'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (rooms.isEmpty && !loading)
                  Center(
                    child: collapsed
                        ? const SizedBox.shrink()
                        : const Text(
                            '选择一个房间开始聊天',
                            style: TextStyle(color: _textMuted),
                          ),
                  )
                else
                  ListView.builder(
                    padding: collapsed
                        ? const EdgeInsets.fromLTRB(0, 12, 0, 4)
                        : const EdgeInsets.fromLTRB(12, 0, 12, 18),
                    itemCount: rooms.length,
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      return _RoomCardTile(
                        room: room,
                        selected: room.id == selectedRoomId,
                        collapsed: collapsed,
                        onOpenRoom: () => onOpenRoom(room),
                        onJoinLive: () => onJoinLive(room),
                      );
                    },
                  ),
                if (loading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: _cyan,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
              ],
            ),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SidebarIconButton(
                      tooltip: 'Settings',
                      onPressed: onOpenSettings,
                      selected: settingsActive,
                      icon: const Icon(Icons.settings),
                    ),
                    const SizedBox(width: 8),
                    _SidebarIconButton(
                      tooltip: 'Logout',
                      onPressed: () => onLogout(),
                      icon: const Icon(Icons.logout),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: _SidebarIconButton(
                tooltip: 'Settings',
                onPressed: onOpenSettings,
                selected: settingsActive,
                icon: const Icon(Icons.settings),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarIconButton extends StatelessWidget {
  const _SidebarIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.selected = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    return SizedBox(
      width: size,
      child: PressableSurface(
        tooltip: tooltip,
        onPressed: onPressed,
        selected: selected,
        height: size,
        padding: EdgeInsets.zero,
        backgroundColor: _primaryDarkLow,
        selectedBackgroundColor: _selectedSurface,
        pressedBackgroundColor: _primaryDark,
        borderColor: _primaryDarkLow,
        selectedBorderColor: _cyan,
        child: IconTheme.merge(
          data: IconThemeData(color: selected ? _cyan : _textPrimary, size: 17),
          child: Center(child: icon),
        ),
      ),
    );
  }
}

class _UserStatusLabel extends StatelessWidget {
  const _UserStatusLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(color: _cyan, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomCardTile extends StatelessWidget {
  const _RoomCardTile({
    required this.room,
    required this.selected,
    required this.collapsed,
    required this.onOpenRoom,
    required this.onJoinLive,
  });

  final RoomCard room;
  final bool selected;
  final bool collapsed;
  final VoidCallback onOpenRoom;
  final VoidCallback onJoinLive;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return _CollapsedRoomTile(
        room: room,
        selected: selected,
        onOpenRoom: onOpenRoom,
        onJoinLive: onJoinLive,
      );
    }
    return _ExpandedRoomTile(
      room: room,
      selected: selected,
      onOpenRoom: onOpenRoom,
      onJoinLive: onJoinLive,
    );
  }
}

class _ExpandedRoomTile extends StatelessWidget {
  const _ExpandedRoomTile({
    required this.room,
    required this.selected,
    required this.onOpenRoom,
    required this.onJoinLive,
  });

  final RoomCard room;
  final bool selected;
  final VoidCallback onOpenRoom;
  final VoidCallback onJoinLive;

  @override
  Widget build(BuildContext context) {
    final liveActive = room.liveParticipantCount > 0;
    return PressableSurface(
      height: 112,
      margin: const EdgeInsets.only(bottom: 2),
      interactive: true,
      pressRequiresHover: true,
      selected: selected,
      backgroundColor: _primaryDarkRaised,
      selectedBackgroundColor: _selectedSurface,
      borderColor: _borderColor,
      selectedBorderColor: _cyan,
      hoverLift: 3,
      pressDepth: 3,
      baseDepth: 5,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenRoom,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _Avatar(
                      label: room.displayName,
                      imageUrl: AppConfigScope.of(
                        context,
                      ).resolveAssetUrl(room.avatarUrl),
                      defaultAvatarKey: room.defaultAvatarKey,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            room.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _roomSubtitle(room),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _AvatarStack(users: room.liveAvatarPreview),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, color: _borderColor),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onJoinLive,
              child: SizedBox.expand(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.volume_up,
                      color: liveActive ? _cyan : _textMuted,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${room.liveParticipantCount}',
                      style: TextStyle(
                        color: liveActive ? _cyan : _textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedRoomTile extends StatefulWidget {
  const _CollapsedRoomTile({
    required this.room,
    required this.selected,
    required this.onOpenRoom,
    required this.onJoinLive,
  });

  final RoomCard room;
  final bool selected;
  final VoidCallback onOpenRoom;
  final VoidCallback onJoinLive;

  @override
  State<_CollapsedRoomTile> createState() => _CollapsedRoomTileState();
}

class _CollapsedRoomTileState extends State<_CollapsedRoomTile> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  bool _overSlot = false;
  bool _overOverlay = false;

  bool get _expanded => _overSlot || _overOverlay;

  void _setOverSlot(bool v) {
    if (_overSlot == v) return;
    setState(() {
      _overSlot = v;
      _syncPortal();
    });
  }

  void _setOverOverlay(bool v) {
    if (_overOverlay == v) return;
    setState(() {
      _overOverlay = v;
      _syncPortal();
    });
  }

  void _syncPortal() {
    final shouldShow = _expanded;
    if (shouldShow && !_portal.isShowing) {
      _portal.show();
    } else if (!shouldShow && _portal.isShowing) {
      _portal.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = _ExpandedRoomTile(
      room: widget.room,
      selected: widget.selected,
      onOpenRoom: widget.onOpenRoom,
      onJoinLive: widget.onJoinLive,
    );

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) {
          return Positioned(
            width: 320,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.topLeft,
              child: MouseRegion(
                onEnter: (_) => _setOverOverlay(true),
                onExit: (_) => _setOverOverlay(false),
                child: Material(
                  color: Colors.transparent,
                  child: _ExpandedRoomTile(
                    room: widget.room,
                    selected: widget.selected,
                    onOpenRoom: widget.onOpenRoom,
                    onJoinLive: widget.onJoinLive,
                  ),
                ),
              ),
            ),
          );
        },
        child: MouseRegion(
          onEnter: (_) => _setOverSlot(true),
          onExit: (_) => _setOverSlot(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpenRoom,
            child: _expanded
                ? Visibility(
                    visible: false,
                    maintainState: true,
                    maintainSize: true,
                    maintainAnimation: true,
                    child: placeholder,
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Center(
                      child: _Avatar(
                        label: widget.room.displayName,
                        imageUrl: AppConfigScope.of(
                          context,
                        ).resolveAssetUrl(widget.room.avatarUrl),
                        defaultAvatarKey: widget.room.defaultAvatarKey,
                        size: 44,
                        borderColor: widget.selected ? _cyan : _borderColor,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _LiveHeader extends StatelessWidget {
  const _LiveHeader({
    required this.room,
    required this.live,
    required this.joined,
    required this.joining,
    required this.onExpand,
    required this.onJoin,
    required this.onOpenRoomManagement,
    required this.onOpenRoomInfo,
    required this.onOpenMembers,
    required this.showManagementButton,
    required this.showMemberRequestBadge,
  });

  final RoomDetail room;
  final LiveState live;
  final bool joined;
  final bool joining;
  final VoidCallback onExpand;
  final VoidCallback onJoin;
  final VoidCallback onOpenRoomManagement;
  final VoidCallback onOpenRoomInfo;
  final VoidCallback onOpenMembers;
  final bool showManagementButton;
  final bool showMemberRequestBadge;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final tight = constraints.maxWidth < 300;
        return PressableSurface(
          height: 72,
          onPressed: onExpand,
          backgroundColor: _primaryDarkRaised,
          borderColor: _borderColor,
          elevateOnHover: true,
          // Notch is shortened by the drop so its bottom still lines up with
          // the bottom of the window-control buttons.
          cornerCut: const Size(
            windowControlsWidth,
            titleBarHeight - windowDragHeight,
          ),
          cutCorner: SurfaceCorner.topRight,
          // Drop the whole header surface down so the top band stays free to
          // grab-and-drag the window, and inset its right edge so its right
          // shadow shows and the notch lines up with the inset buttons.
          margin: const EdgeInsets.only(
            top: windowDragHeight,
            right: windowControlsInset,
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: compact ? 16 : 22,
                    right: compact ? 8 : 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Flexible(
                        child: Text(
                          '${room.memberCount} members',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showManagementButton) ...[
                      ButtonIcon(
                        tooltip: '房间管理',
                        onPressed: onOpenRoomManagement,
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        size: 36,
                      ),
                      const SizedBox(width: 8),
                    ],
                    ButtonIcon(
                      tooltip: '房间信息',
                      onPressed: onOpenRoomInfo,
                      icon: const Icon(Icons.info_outline),
                      size: 36,
                    ),
                    const SizedBox(width: 8),
                    _BadgeAnchor(
                      show: showMemberRequestBadge,
                      child: ButtonIcon(
                        tooltip: '成员列表',
                        onPressed: onOpenMembers,
                        icon: const Icon(Icons.groups_2_outlined),
                        size: 36,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _LiveHeaderActions(
                live: live,
                joined: joined,
                joining: joining,
                onJoin: onJoin,
                showAvatars: !compact,
                showCount: !tight,
                compactButton: compact,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LiveHeaderActions extends StatelessWidget {
  const _LiveHeaderActions({
    required this.live,
    required this.joined,
    required this.joining,
    required this.onJoin,
    required this.showAvatars,
    required this.showCount,
    required this.compactButton,
  });

  final LiveState live;
  final bool joined;
  final bool joining;
  final VoidCallback onJoin;
  final bool showAvatars;
  final bool showCount;
  final bool compactButton;

  @override
  Widget build(BuildContext context) {
    final Widget joinControl = !joined
        ? (compactButton
              ? ButtonIcon(
                  tooltip: 'Join live',
                  onPressed: onJoin,
                  loading: joining,
                  icon: joining
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _cyan,
                          ),
                        )
                      : const Icon(Icons.call),
                  tone: ButtonTone.primary,
                  size: 36,
                )
              : Button(
                  onPressed: onJoin,
                  loading: joining,
                  width: double.infinity,
                  icon: joining
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _cyan,
                          ),
                        )
                      : const Icon(Icons.call),
                  tone: ButtonTone.primary,
                  height: 38,
                  child: const Text('Join'),
                ))
        : const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showAvatars) ...[
          _AvatarStack(users: live.participants.map((p) => p.user).toList()),
          const SizedBox(width: 10),
        ],
        if (showCount) ...[
          _LiveCount(count: live.participantCount),
          const SizedBox(width: 10),
        ],
        // Push the avatars/count further left of the cut column.
        const SizedBox(width: 16),
        // Join control nests under the cut: a full-width slot flush to the
        // right edge (aligned with the window buttons), dropped so it clears
        // the notch, with left/right padding inside the column. The
        // avatars/count above stay outside this column.
        SizedBox(
          width: windowControlsWidth,
          height: 72,
          child: Align(
            alignment: const Alignment(0, 0.7),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: joinControl,
            ),
          ),
        ),
      ],
    );
  }
}

enum _ComposerPanel { stickers, voice, file, tools }

enum _StickerSource { personal, room }

class _DownloadCancelledException implements Exception {
  const _DownloadCancelledException();

  @override
  String toString() => 'Download cancelled';
}

enum _FileTransferDirection { upload, download }

class _FileTransferState {
  _FileTransferState.upload({
    required this.controller,
    required this.totalBytes,
  }) : direction = _FileTransferDirection.upload,
       destinationPath = null;

  _FileTransferState.download({
    required this.controller,
    required this.totalBytes,
    required this.destinationPath,
  }) : direction = _FileTransferDirection.download;

  final _FileTransferDirection direction;
  final UploadTransferController controller;
  final String? destinationPath;
  int sentBytes = 0;
  int totalBytes;
  double bytesPerSecond = 0;
  http.Client? downloadClient;
  bool wroteDestination = false;
  bool sendingMessage = false;
  bool failed = false;
  String? error;
  DateTime? _speedSampleAt;
  int _speedSampleBytes = 0;

  bool get isDownload => direction == _FileTransferDirection.download;
  bool get paused => controller.isPaused;
  bool get cancelled => controller.isCancelled;
  bool get active => !failed && !cancelled && !sendingMessage;
  bool get hasKnownTotal => totalBytes > 0;
  double get progress {
    if (totalBytes <= 0) return 0;
    return (sentBytes / totalBytes).clamp(0.0, 1.0).toDouble();
  }

  void updateProgress({required int sentBytes, required int totalBytes}) {
    final now = DateTime.now();
    if (_speedSampleAt == null) {
      _speedSampleAt = now;
      _speedSampleBytes = this.sentBytes;
    } else {
      final elapsed = now.difference(_speedSampleAt!).inMilliseconds;
      if (elapsed >= 400 || sentBytes >= totalBytes && totalBytes > 0) {
        final deltaBytes = sentBytes - _speedSampleBytes;
        bytesPerSecond = elapsed > 0 ? deltaBytes * 1000 / elapsed : 0;
        _speedSampleAt = now;
        _speedSampleBytes = sentBytes;
      }
    }

    this.sentBytes = sentBytes;
    this.totalBytes = totalBytes;
  }

  void stopSpeed() {
    bytesPerSecond = 0;
    _speedSampleAt = null;
    _speedSampleBytes = sentBytes;
  }
}

class _ChatPane extends StatefulWidget {
  const _ChatPane({
    required this.roomId,
    required this.api,
    required this.apiBaseUrl,
    required this.stickerPackStore,
    required this.messages,
    required this.fileTransfers,
    required this.fileDownloads,
    required this.currentUserId,
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onStickerSend,
    required this.onFileSend,
    required this.onFilePause,
    required this.onFileResume,
    required this.onFileCancel,
    required this.onFileDownload,
    required this.onFileDownloadPause,
    required this.onFileDownloadResume,
    required this.onFileDownloadCancel,
    required this.onOpenUserInfo,
  });

  final String roomId;
  final GangApi api;
  final String apiBaseUrl;
  final StickerPackStore stickerPackStore;
  final List<Message> messages;
  final Map<String, _FileTransferState> fileTransfers;
  final Map<String, _FileTransferState> fileDownloads;
  final String currentUserId;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final Future<void> Function(Sticker sticker) onStickerSend;
  final Future<void> Function() onFileSend;
  final ValueChanged<String> onFilePause;
  final ValueChanged<String> onFileResume;
  final ValueChanged<String> onFileCancel;
  final Future<void> Function({
    required String downloadKey,
    required MessageAttachment attachment,
    required String url,
  })
  onFileDownload;
  final ValueChanged<String> onFileDownloadPause;
  final ValueChanged<String> onFileDownloadResume;
  final ValueChanged<String> onFileDownloadCancel;
  final ValueChanged<UserSummary> onOpenUserInfo;

  @override
  State<_ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<_ChatPane> {
  final Object _composerTapRegionGroup = Object();
  _ComposerPanel? _openPanel;
  _StickerSource _stickerSource = _StickerSource.personal;
  List<StickerPack> _personalStickerPacks = const [];
  List<StickerPack> _roomStickerPacks = const [];
  bool _loadingStickerPacks = false;
  bool _stickerPacksLoaded = false;
  String? _stickerPackError;
  double _composerInputHeight = 76;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(_ChatPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _openPanel = null;
      _resetStickerPacks();
    } else if (oldWidget.api != widget.api ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl ||
        oldWidget.currentUserId != widget.currentUserId) {
      _resetStickerPacks();
      if (_openPanel == _ComposerPanel.stickers) {
        unawaited(_ensureStickerPacksLoaded());
      }
    }
  }

  void _resetStickerPacks() {
    _personalStickerPacks = const [];
    _roomStickerPacks = const [];
    _loadingStickerPacks = false;
    _stickerPacksLoaded = false;
    _stickerPackError = null;
  }

  Future<void> _ensureStickerPacksLoaded({bool forceReload = false}) async {
    if (_loadingStickerPacks) return;
    if (!forceReload && _stickerPacksLoaded) return;
    await _loadStickerPacks(forceReload: forceReload);
  }

  Future<void> _loadStickerPacks({bool forceReload = false}) async {
    final roomId = widget.roomId;
    setState(() {
      _loadingStickerPacks = true;
      _stickerPackError = null;
    });
    try {
      final cachedPersonal = forceReload
          ? null
          : await widget.stickerPackStore.readPersonalPacks(
              userId: widget.currentUserId,
              apiBaseUrl: widget.apiBaseUrl,
            );
      if (!mounted || widget.roomId != roomId) return;
      if (cachedPersonal != null) {
        setState(() => _personalStickerPacks = cachedPersonal);
        _precacheStickerThumbnails(cachedPersonal, limit: 30);
      }
      final shouldFetchPersonal = forceReload || cachedPersonal == null;
      final packs = await Future.wait([
        shouldFetchPersonal
            ? widget.api.listStickerPacks(scope: 'personal')
            : Future<List<StickerPack>>.value(cachedPersonal),
        widget.api.listStickerPacks(scope: 'room', roomId: roomId),
      ]);
      if (!mounted || widget.roomId != roomId) return;
      setState(() {
        _personalStickerPacks = packs[0];
        _roomStickerPacks = packs[1];
        _stickerPacksLoaded = true;
      });
      _precacheStickerThumbnails([...packs[0], ...packs[1]]);
      if (shouldFetchPersonal) {
        await widget.stickerPackStore.writePersonalPacks(
          userId: widget.currentUserId,
          apiBaseUrl: widget.apiBaseUrl,
          packs: packs[0],
        );
      }
    } catch (e) {
      if (!mounted || widget.roomId != roomId) return;
      setState(() => _stickerPackError = e.toString());
    } finally {
      if (mounted && widget.roomId == roomId) {
        setState(() => _loadingStickerPacks = false);
      }
    }
  }

  void _precacheStickerThumbnails(List<StickerPack> packs, {int limit = 60}) {
    if (!mounted || packs.isEmpty || limit <= 0) return;
    final config = AppConfigScope.of(context);
    final seen = <String>{};
    var count = 0;
    for (final pack in packs) {
      for (final sticker in pack.stickers) {
        final imageUrl = config.resolveAssetUrl(
          sticker.asset.thumbnailUrl ?? sticker.asset.url,
        );
        if (imageUrl == null || !seen.add(imageUrl)) continue;
        unawaited(
          precacheImage(NetworkImage(imageUrl), context).catchError((_) {}),
        );
        count += 1;
        if (count >= limit) return;
      }
    }
  }

  void _closePanel() {
    if (_openPanel == null) return;
    setState(() => _openPanel = null);
  }

  void _togglePanel(_ComposerPanel panel) {
    final opening = _openPanel != panel;
    setState(() {
      _openPanel = opening ? panel : null;
    });
    if (opening && panel == _ComposerPanel.stickers) {
      unawaited(_ensureStickerPacksLoaded());
    }
  }

  void _onComposerInputSize(Size size) {
    if ((_composerInputHeight - size.height).abs() < 0.5) return;
    setState(() => _composerInputHeight = size.height);
  }

  Widget _buildComposerInput() {
    final input = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            '>',
            style: TextStyle(
              color: _textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => widget.onSend(),
            cursorColor: _textSecondary,
            decoration: const InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );

    final actions = _ComposerActionBar(
      openPanel: _openPanel,
      sending: widget.sending,
      onStickers: () => _togglePanel(_ComposerPanel.stickers),
      onVoice: () => _togglePanel(_ComposerPanel.voice),
      onFile: widget.sending
          ? null
          : () {
              _closePanel();
              unawaited(widget.onFileSend());
            },
      onTools: () => _togglePanel(_ComposerPanel.tools),
      onSend: () {
        _closePanel();
        widget.onSend();
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              input,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: input),
            const SizedBox(width: 10),
            Transform.translate(offset: const Offset(0, 2), child: actions),
          ],
        );
      },
    );
  }

  Widget _buildPanel() {
    final panel = _openPanel;
    if (panel == null) return const SizedBox.shrink();

    return switch (panel) {
      _ComposerPanel.stickers => _StickerPanel(
        source: _stickerSource,
        personalPacks: _personalStickerPacks,
        roomPacks: _roomStickerPacks,
        loading: _loadingStickerPacks,
        error: _stickerPackError,
        onRefresh: () => _loadStickerPacks(forceReload: true),
        onSourceChanged: (source) => setState(() => _stickerSource = source),
        onStickerSelected: (sticker) {
          _closePanel();
          unawaited(widget.onStickerSend(sticker));
        },
      ),
      _ComposerPanel.voice => const _PlaceholderPanel(text: '语音输入开发中'),
      _ComposerPanel.file => const _PlaceholderPanel(text: '文件上传开发中'),
      _ComposerPanel.tools => const _ToolboxPanel(),
    };
  }

  Widget _buildPanelOverlay() {
    return Positioned(
      left: 18,
      right: 18,
      bottom: _composerInputHeight + 6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 360.0
              ? constraints.maxWidth
              : 360.0;
          return Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: width,
              child: TapRegion(
                groupId: _composerTapRegionGroup,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      alignment: Alignment.bottomRight,
                      children: [...previousChildren, ?currentChild],
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_openPanel),
                    child: _buildPanel(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDarkLow,
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: widget.messages.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有消息',
                          style: TextStyle(color: _textMuted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                        itemCount: widget.messages.length,
                        itemBuilder: (context, index) {
                          final message = widget.messages[index];
                          return _MessageBubble(
                            message: message,
                            mine: message.sender.id == widget.currentUserId,
                            fileTransfer:
                                widget.fileTransfers[message.clientMessageId],
                            fileDownloads: widget.fileDownloads,
                            onFilePause: () =>
                                widget.onFilePause(message.clientMessageId),
                            onFileResume: () =>
                                widget.onFileResume(message.clientMessageId),
                            onFileCancel: () =>
                                widget.onFileCancel(message.clientMessageId),
                            onFileDownload: widget.onFileDownload,
                            onFileDownloadPause: widget.onFileDownloadPause,
                            onFileDownloadResume: widget.onFileDownloadResume,
                            onFileDownloadCancel: widget.onFileDownloadCancel,
                            onOpenUserInfo: () =>
                                widget.onOpenUserInfo(message.sender),
                          );
                        },
                      ),
              ),
              TapRegion(
                groupId: _composerTapRegionGroup,
                onTapOutside: (_) => _closePanel(),
                child: _SizeReporter(
                  onChange: _onComposerInputSize,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                    color: _primaryDarkLow,
                    child: _buildComposerInput(),
                  ),
                ),
              ),
            ],
          ),
          if (_openPanel != null) _buildPanelOverlay(),
        ],
      ),
    );
  }
}

class _SizeReporter extends StatefulWidget {
  const _SizeReporter({required this.child, required this.onChange});

  final Widget child;
  final ValueChanged<Size> onChange;

  @override
  State<_SizeReporter> createState() => _SizeReporterState();
}

class _SizeReporterState extends State<_SizeReporter> {
  Size? _lastSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportSize());
    return widget.child;
  }

  void _reportSize() {
    if (!mounted) return;
    final size = context.size;
    if (size == null || size == _lastSize) return;
    _lastSize = size;
    widget.onChange(size);
  }
}

class _ComposerActionBar extends StatelessWidget {
  const _ComposerActionBar({
    required this.openPanel,
    required this.sending,
    required this.onStickers,
    required this.onVoice,
    required this.onFile,
    required this.onTools,
    required this.onSend,
  });

  final _ComposerPanel? openPanel;
  final bool sending;
  final VoidCallback onStickers;
  final VoidCallback? onVoice;
  final VoidCallback? onFile;
  final VoidCallback onTools;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ButtonIcon(
          tooltip: '表情包',
          onPressed: onStickers,
          selected: openPanel == _ComposerPanel.stickers,
          icon: const Icon(Icons.emoji_emotions_outlined),
        ),
        const SizedBox(width: 8),
        ButtonIcon(
          tooltip: '语音',
          onPressed: onVoice,
          icon: const Icon(Icons.mic_none),
        ),
        const SizedBox(width: 8),
        ButtonIcon(
          tooltip: '文件上传',
          onPressed: onFile,
          icon: const Icon(Icons.attach_file),
        ),
        const SizedBox(width: 8),
        ButtonIcon(
          tooltip: '工具箱',
          onPressed: onTools,
          selected: openPanel == _ComposerPanel.tools,
          icon: const Icon(Icons.extension_outlined),
        ),
        const SizedBox(width: 8),
        ButtonIcon(
          tooltip: '发送',
          onPressed: sending ? null : onSend,
          loading: sending,
          tone: ButtonTone.primary,
          icon: sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _cyan,
                  ),
                )
              : const Icon(Icons.send_rounded),
          size: 44,
        ),
      ],
    );
  }
}

class _StickerPanel extends StatelessWidget {
  const _StickerPanel({
    required this.source,
    required this.personalPacks,
    required this.roomPacks,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onSourceChanged,
    required this.onStickerSelected,
  });

  final _StickerSource source;
  final List<StickerPack> personalPacks;
  final List<StickerPack> roomPacks;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<_StickerSource> onSourceChanged;
  final ValueChanged<Sticker> onStickerSelected;

  @override
  Widget build(BuildContext context) {
    final packs = source == _StickerSource.personal ? personalPacks : roomPacks;
    final stickers = [for (final pack in packs) ...pack.stickers];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: _buildBody(stickers),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: SegmentedControl<_StickerSource>(
            value: source,
            expanded: true,
            onChanged: onSourceChanged,
            segments: const [
              Segment(value: _StickerSource.personal, label: '个人表情包'),
              Segment(value: _StickerSource.room, label: '房间表情包'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody(List<Sticker> stickers) {
    if (loading && stickers.isEmpty) {
      return const SizedBox(
        height: 78,
        child: Center(child: CircularProgressIndicator(color: _cyan)),
      );
    }
    if (error != null && stickers.isEmpty) {
      return _StickerPanelMessage(
        text: error!,
        icon: Icons.warning_amber,
        onRefresh: onRefresh,
      );
    }
    if (stickers.isEmpty) {
      return _StickerPanelMessage(
        text: source == _StickerSource.personal ? '暂无个人表情' : '暂无房间表情',
        icon: Icons.emoji_emotions_outlined,
        onRefresh: onRefresh,
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final sticker in stickers)
          _StickerButton(
            sticker: sticker,
            onPressed: () => onStickerSelected(sticker),
          ),
      ],
    );
  }
}

class _ToolboxPanel extends StatelessWidget {
  const _ToolboxPanel();

  static const double buttonSize = 46;
  static const double spacing = 10;

  static const _items = [
    _ToolboxItem(
      icon: Icons.music_note,
      tooltip: '音乐盒',
      backgroundColor: Color(0xFF1F2D27),
      borderColor: Color(0xFF355C49),
      foregroundColor: Color(0xFF6FCFA6),
    ),
    _ToolboxItem(
      icon: Icons.poll_outlined,
      tooltip: '投票',
      backgroundColor: Color(0xFF2B2739),
      borderColor: Color(0xFF594D78),
      foregroundColor: Color(0xFFB8A3FF),
    ),
    _ToolboxItem(
      icon: Icons.bolt_outlined,
      tooltip: '快捷指令',
      backgroundColor: Color(0xFF33291C),
      borderColor: Color(0xFF6D5630),
      foregroundColor: Color(0xFFD4B675),
    ),
    _ToolboxItem(
      icon: Icons.add_box_outlined,
      tooltip: '后续扩展',
      backgroundColor: Color(0xFF2E1F22),
      borderColor: Color(0xFF6B3E45),
      foregroundColor: Color(0xFFE58383),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final item in _items)
            _ToolboxButton(
              icon: item.icon,
              tooltip: item.tooltip,
              backgroundColor: item.backgroundColor,
              borderColor: item.borderColor,
              foregroundColor: item.foregroundColor,
            ),
        ],
      ),
    );
  }
}

class _PlaceholderPanel extends StatelessWidget {
  const _PlaceholderPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: _textMuted, fontSize: 13),
        ),
      ),
    );
  }
}

class _ToolboxItem {
  const _ToolboxItem({
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;
}

class _StickerButton extends StatelessWidget {
  const _StickerButton({required this.sticker, required this.onPressed});

  final Sticker sticker;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final imageUrl = AppConfigScope.of(
      context,
    ).resolveAssetUrl(sticker.asset.thumbnailUrl ?? sticker.asset.url);
    final fallback = Icon(
      Icons.image_not_supported_outlined,
      color: _textMuted,
      size: 22,
    );
    return Tooltip(
      message: sticker.name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 46,
            width: 52,
            child: Center(
              child: SizedBox.square(
                dimension: 32,
                child: imageUrl == null
                    ? fallback
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => fallback,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerPanelMessage extends StatelessWidget {
  const _StickerPanelMessage({
    required this.text,
    required this.icon,
    required this.onRefresh,
  });

  final String text;
  final IconData icon;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Row(
        children: [
          Icon(icon, color: _textMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          ButtonIcon(
            tooltip: '刷新表情包',
            onPressed: () => unawaited(onRefresh()),
            icon: const Icon(Icons.refresh),
            size: 32,
            backgroundColor: _primaryDarkRaised,
            borderColor: _primaryDarkRaised,
          ),
        ],
      ),
    );
  }
}

class _BubbleIconAction extends StatelessWidget {
  const _BubbleIconAction({
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
    required this.onPressed,
    this.size = 50,
  });

  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: PressableSurface(
        tooltip: tooltip,
        onPressed: onPressed,
        height: size,
        padding: EdgeInsets.zero,
        backgroundColor: backgroundColor,
        selectedBackgroundColor: backgroundColor,
        pressedBackgroundColor: backgroundColor,
        borderColor: borderColor,
        selectedBorderColor: borderColor,
        child: Center(
          child: Icon(icon, color: foregroundColor, size: size * 0.42),
        ),
      ),
    );
  }
}

class _ToolboxButton extends StatelessWidget {
  const _ToolboxButton({
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return _BubbleIconAction(
      icon: icon,
      tooltip: tooltip,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      foregroundColor: foregroundColor,
      onPressed: () {},
      size: _ToolboxPanel.buttonSize,
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.fileTransfer,
    required this.fileDownloads,
    required this.onFilePause,
    required this.onFileResume,
    required this.onFileCancel,
    required this.onFileDownload,
    required this.onFileDownloadPause,
    required this.onFileDownloadResume,
    required this.onFileDownloadCancel,
    required this.onOpenUserInfo,
  });

  final Message message;
  final bool mine;
  final _FileTransferState? fileTransfer;
  final Map<String, _FileTransferState> fileDownloads;
  final VoidCallback onFilePause;
  final VoidCallback onFileResume;
  final VoidCallback onFileCancel;
  final Future<void> Function({
    required String downloadKey,
    required MessageAttachment attachment,
    required String url,
  })
  onFileDownload;
  final ValueChanged<String> onFileDownloadPause;
  final ValueChanged<String> onFileDownloadResume;
  final ValueChanged<String> onFileDownloadCancel;
  final VoidCallback onOpenUserInfo;

  @override
  Widget build(BuildContext context) {
    final sticker = message.stickerAttachment;
    final files = message.fileAttachments.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _borderColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _UserInfoTapTarget(
                tooltip: '查看用户信息',
                onTap: onOpenUserInfo,
                child: _Avatar(
                  label: message.sender.displayName,
                  imageUrl: AppConfigScope.of(
                    context,
                  ).resolveAssetUrl(message.sender.avatarUrl),
                  defaultAvatarKey: message.sender.defaultAvatarKey,
                  size: 32,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _UserInfoTapTarget(
                            tooltip: '查看用户信息',
                            onTap: onOpenUserInfo,
                            child: Text(
                              mine ? 'You' : message.sender.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: message.failed
                                    ? _danger
                                    : mine
                                    ? _cyan
                                    : _textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          _formatMessageTime(message.createdAt),
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (sticker != null)
                      _StickerMessageImage(message: message, sticker: sticker),
                    if (sticker == null && files.isNotEmpty)
                      _FileAttachmentList(
                        message: message,
                        attachments: files,
                        transfer: fileTransfer,
                        downloads: fileDownloads,
                        onPause: onFilePause,
                        onResume: onFileResume,
                        onCancel: onFileCancel,
                        onDownload: onFileDownload,
                        onDownloadPause: onFileDownloadPause,
                        onDownloadResume: onFileDownloadResume,
                        onDownloadCancel: onFileDownloadCancel,
                      ),
                    if (sticker == null && files.isEmpty)
                      _MessageText(text: message.body),
                    if (fileTransfer == null &&
                        (message.pending || message.failed)) ...[
                      const SizedBox(height: 6),
                      Text(
                        message.failed ? 'Failed' : 'Sending',
                        style: TextStyle(
                          color: message.failed ? _danger : _textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageText extends StatelessWidget {
  const _MessageText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      text,
      cursorColor: _cyan,
      selectionColor: _cyan.withValues(alpha: 0.28),
      style: const TextStyle(color: _textPrimary, fontSize: 15, height: 1.4),
    );
  }
}

class _UserInfoTapTarget extends StatelessWidget {
  const _UserInfoTapTarget({
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

class _FileAttachmentList extends StatelessWidget {
  const _FileAttachmentList({
    required this.message,
    required this.attachments,
    required this.transfer,
    required this.downloads,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onDownload,
    required this.onDownloadPause,
    required this.onDownloadResume,
    required this.onDownloadCancel,
  });

  final Message message;
  final List<MessageAttachment> attachments;
  final _FileTransferState? transfer;
  final Map<String, _FileTransferState> downloads;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final Future<void> Function({
    required String downloadKey,
    required MessageAttachment attachment,
    required String url,
  })
  onDownload;
  final ValueChanged<String> onDownloadPause;
  final ValueChanged<String> onDownloadResume;
  final ValueChanged<String> onDownloadCancel;

  @override
  Widget build(BuildContext context) {
    final body = message.body.trim();
    final showBody =
        body.isNotEmpty &&
        (attachments.length != 1 ||
            body != _fileAttachmentTitle(attachments[0]));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBody) ...[
          _MessageText(text: message.body),
          const SizedBox(height: 8),
        ],
        for (final entry in attachments.asMap().entries) ...[
          if (entry.key > 0) const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final downloadKey = _fileDownloadKey(
                message,
                entry.value,
                entry.key,
              );
              final uploadTransfer = entry.key == 0 ? transfer : null;
              final downloadTransfer = downloads[downloadKey];
              final activeTransfer = uploadTransfer ?? downloadTransfer;

              return _FileAttachmentCard(
                attachment: entry.value,
                transfer: activeTransfer,
                onDownload: ({required attachment, required url}) => onDownload(
                  downloadKey: downloadKey,
                  attachment: attachment,
                  url: url,
                ),
                onPause: uploadTransfer != null
                    ? onPause
                    : () => onDownloadPause(downloadKey),
                onResume: uploadTransfer != null
                    ? onResume
                    : () => onDownloadResume(downloadKey),
                onCancel: uploadTransfer != null
                    ? onCancel
                    : () => onDownloadCancel(downloadKey),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _FileAttachmentCard extends StatelessWidget {
  const _FileAttachmentCard({
    required this.attachment,
    required this.transfer,
    required this.onDownload,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final MessageAttachment attachment;
  final _FileTransferState? transfer;
  final Future<void> Function({
    required MessageAttachment attachment,
    required String url,
  })
  onDownload;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final asset = attachment.asset;
    final transfer = this.transfer;
    final config = AppConfigScope.of(context);
    final url = config.resolveAssetUrl(asset?.url);
    final title = _fileAttachmentTitle(attachment);
    final meta = _fileAttachmentMeta(asset);
    final previewUrl = asset != null && asset.mimeType.startsWith('image/')
        ? config.resolveAssetUrl(asset.thumbnailUrl ?? asset.url)
        : null;
    final canDownload = url != null && transfer == null;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Tooltip(
        message: canDownload ? 'Download file' : title,
        child: MouseRegion(
          cursor: canDownload
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canDownload
                ? () => unawaited(onDownload(attachment: attachment, url: url))
                : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _primaryDarkRaised,
                border: Border.all(color: _borderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _FileAttachmentIcon(
                          asset: asset,
                          previewUrl: previewUrl,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                              ),
                              if (meta.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FileAttachmentTrailing(
                          transfer: transfer,
                          canDownload: canDownload,
                          onPause: onPause,
                          onResume: onResume,
                          onCancel: onCancel,
                        ),
                      ],
                    ),
                    if (transfer != null) ...[
                      const SizedBox(height: 10),
                      _FileTransferProgress(transfer: transfer),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileAttachmentTrailing extends StatelessWidget {
  const _FileAttachmentTrailing({
    required this.transfer,
    required this.canDownload,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final _FileTransferState? transfer;
  final bool canDownload;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final transfer = this.transfer;
    if (transfer != null) {
      if (transfer.sendingMessage) {
        return const SizedBox.square(
          dimension: 30,
          child: Center(
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(color: _cyan, strokeWidth: 2),
            ),
          ),
        );
      }
      if (transfer.failed) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _danger, size: 20),
            if (transfer.isDownload) ...[
              const SizedBox(width: 6),
              _InlineIconButton(
                tooltip: 'Dismiss download',
                icon: Icons.close,
                onPressed: onCancel,
                danger: true,
              ),
            ],
          ],
        );
      }
      final action = transfer.isDownload ? 'download' : 'upload';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _InlineIconButton(
            tooltip: transfer.paused ? 'Resume $action' : 'Pause $action',
            icon: transfer.paused ? Icons.play_arrow : Icons.pause,
            onPressed: transfer.paused ? onResume : onPause,
          ),
          const SizedBox(width: 6),
          _InlineIconButton(
            tooltip: 'Cancel $action',
            icon: Icons.close,
            onPressed: onCancel,
            danger: true,
          ),
        ],
      );
    }

    if (!canDownload) {
      return const Icon(Icons.insert_drive_file_outlined, color: _textMuted);
    }
    return const Icon(Icons.download_outlined, color: _textMuted, size: 20);
  }
}

class _FileTransferProgress extends StatelessWidget {
  const _FileTransferProgress({required this.transfer});

  final _FileTransferState transfer;

  @override
  Widget build(BuildContext context) {
    final label = _fileTransferLabel(transfer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 4,
            value: transfer.sendingMessage
                ? 1
                : transfer.hasKnownTotal
                ? transfer.progress
                : null,
            backgroundColor: _borderColor,
            valueColor: AlwaysStoppedAnimation<Color>(
              transfer.failed ? _danger : _cyan,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          transfer.error ?? label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: transfer.failed ? _danger : _textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _InlineIconButton extends StatelessWidget {
  const _InlineIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? _danger : _cyan;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: danger ? const Color(0xFF2E1F22) : const Color(0xFF1F2D27),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: danger ? const Color(0xFF6B3E45) : const Color(0xFF355C49),
            ),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

class _FileAttachmentIcon extends StatelessWidget {
  const _FileAttachmentIcon({required this.asset, required this.previewUrl});

  final UploadedAsset? asset;
  final String? previewUrl;

  @override
  Widget build(BuildContext context) {
    final previewUrl = this.previewUrl;
    if (previewUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox.square(
          dimension: 42,
          child: Image.network(
            previewUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallbackIcon(),
          ),
        ),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: _selectedSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF355C49)),
      ),
      child: Icon(_fileIconForMime(asset?.mimeType), color: _cyan, size: 22),
    );
  }
}

class _StickerMessageImage extends StatelessWidget {
  const _StickerMessageImage({required this.message, required this.sticker});

  final Message message;
  final MessageAttachment sticker;

  @override
  Widget build(BuildContext context) {
    final asset = sticker.asset;
    final imageUrl = AppConfigScope.of(
      context,
    ).resolveAssetUrl(asset?.url ?? asset?.thumbnailUrl);
    if (imageUrl == null) return _MessageText(text: message.body);

    final label = sticker.name ?? message.body;
    return Tooltip(
      message: label,
      child: Semantics(
        image: true,
        label: label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 168, maxHeight: 168),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const SizedBox.square(
                  dimension: 72,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        color: _cyan,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                );
              },
              errorBuilder: (_, _, _) => _MessageText(text: message.body),
            ),
          ),
        ),
      ),
    );
  }
}

class _LivePanel extends StatelessWidget {
  const _LivePanel({
    required this.room,
    required this.live,
    required this.liveSession,
    required this.joined,
    required this.joining,
    required this.micMuted,
    required this.headphonesMuted,
    required this.voiceBlocked,
    required this.cameraOn,
    required this.screenSharing,
    required this.speakingUserIds,
    required this.onJoin,
    required this.onLeave,
    required this.onToggleMic,
    required this.onToggleHeadphones,
    required this.onToggleCamera,
    required this.onToggleShare,
    required this.onCollapse,
    required this.onEnterFullScreen,
    required this.onOpenUserInfo,
    required this.localUserId,
  });

  final RoomDetail room;
  final LiveState live;
  final LiveSession liveSession;
  final bool joined;
  final bool joining;
  final bool micMuted;
  final bool headphonesMuted;
  final bool voiceBlocked;
  final bool cameraOn;
  final bool screenSharing;
  final Set<String> speakingUserIds;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  // Null when the local user is voice-blocked: the mic can't be toggled.
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleShare;
  final VoidCallback onCollapse;
  // Invoked with the share track to enter immersive full-screen.
  final void Function(LiveVideoTrack track) onEnterFullScreen;
  final ValueChanged<UserSummary> onOpenUserInfo;
  // The local user's id. Used to decide whether the staged share belongs to us:
  // a sharer can't full-screen their own share (a local screen-capture track
  // can attach to only one renderer at a time), so the button is hidden for it.
  final String localUserId;

  @override
  Widget build(BuildContext context) {
    // A screen share, if any, gets a large stage above the participant grid.
    // Prefer a remote share; fall back to our own so we can see what we send.
    final stageShare = _pickStageShare();
    // Only a viewer (not the sharer) can expand a share to full-screen. A local
    // screen-capture track can attach to a single renderer at a time, so the
    // full-screen renderer would black out if we also kept the inline stage
    // bound to it. Hide the button when the staged share is our own.
    final canFullScreen =
        stageShare != null && stageShare.identity != localUserId;
    return ColoredBox(
      color: _primaryDarkLow,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
              child: Column(
                children: [
                  Text(
                    room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (stageShare != null) ...[
                    Expanded(
                      flex: 3,
                      child: _ScreenShareStage(
                        track: stageShare,
                        label: _displayNameFor(stageShare.identity),
                        onToggleFullScreen: canFullScreen
                            ? () => onEnterFullScreen(stageShare)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: live.participants.isEmpty
                        ? const SizedBox.shrink()
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 220,
                                  mainAxisExtent: 156,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemCount: live.participants.length,
                            itemBuilder: (context, index) {
                              final participant = live.participants[index];
                              return _LiveParticipantCard(
                                participant: participant,
                                speaking: speakingUserIds.contains(
                                  participant.user.id,
                                ),
                                cameraTrack: liveSession.cameraFor(
                                  participant.user.id,
                                ),
                                onOpenUserInfo: () =>
                                    onOpenUserInfo(participant.user),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          _LiveControls(
            joined: joined,
            joining: joining,
            micMuted: micMuted,
            headphonesMuted: headphonesMuted,
            voiceBlocked: voiceBlocked,
            cameraOn: cameraOn,
            screenSharing: screenSharing,
            onJoin: onJoin,
            onLeave: onLeave,
            onToggleMic: onToggleMic,
            onToggleHeadphones: onToggleHeadphones,
            onToggleCamera: onToggleCamera,
            onToggleShare: onToggleShare,
            onCollapse: onCollapse,
          ),
        ],
      ),
    );
  }

  String _displayNameFor(String userId) {
    for (final p in live.participants) {
      if (p.user.id == userId) return p.user.displayName;
    }
    return '';
  }

  LiveVideoTrack? _pickStageShare() {
    final shares = liveSession.videoTracks
        .where((t) => t.isScreenShare)
        .toList();
    if (shares.isEmpty) return null;
    return shares.firstWhere((t) => !t.isLocal, orElse: () => shares.first);
  }
}

class _LiveParticipantCard extends StatelessWidget {
  const _LiveParticipantCard({
    required this.participant,
    required this.speaking,
    required this.onOpenUserInfo,
    this.cameraTrack,
  });

  final LiveParticipant participant;
  final bool speaking;
  final VoidCallback onOpenUserInfo;
  final LiveVideoTrack? cameraTrack;

  @override
  Widget build(BuildContext context) {
    final broadcasting = participant.cameraOn || participant.screenSharing;
    final highlight = speaking || broadcasting;
    final cameraTrack = this.cameraTrack;
    // When a live camera track is available, fill the tile with the video and
    // overlay the name + status; otherwise fall back to the avatar layout.
    if (cameraTrack != null) {
      return PressableSurface(
        height: 148,
        interactive: true,
        pressRequiresHover: true,
        onPressed: onOpenUserInfo,
        tooltip: '查看用户信息',
        backgroundColor: _primaryDark,
        selectedBackgroundColor: _primaryDark,
        borderColor: highlight ? _cyan : _borderColor,
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            lk.VideoTrackRenderer(
              cameraTrack.track,
              fit: lk.VideoViewFit.cover,
              mirrorMode: cameraTrack.isLocal
                  ? lk.VideoViewMirrorMode.mirror
                  : lk.VideoViewMirrorMode.auto,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _VideoTileFooter(
                name: participant.user.displayName,
                micMuted: participant.micMuted,
                speaking: speaking,
                screenSharing: participant.screenSharing,
              ),
            ),
          ],
        ),
      );
    }
    return PressableSurface(
      height: 148,
      interactive: true,
      pressRequiresHover: true,
      onPressed: onOpenUserInfo,
      tooltip: '查看用户信息',
      backgroundColor: _primaryDarkRaised,
      selectedBackgroundColor: _primaryDarkRaised,
      borderColor: _borderColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _UserInfoTapTarget(
            tooltip: '查看用户信息',
            onTap: onOpenUserInfo,
            child: _Avatar(
              label: participant.user.displayName,
              imageUrl: AppConfigScope.of(
                context,
              ).resolveAssetUrl(participant.user.avatarUrl),
              defaultAvatarKey: participant.user.defaultAvatarKey,
              size: 54,
              borderColor: highlight ? _cyan : _borderColor,
              borderWidth: highlight ? 2.4 : 1,
            ),
          ),
          const SizedBox(height: 12),
          _UserInfoTapTarget(
            tooltip: '查看用户信息',
            onTap: onOpenUserInfo,
            child: Text(
              participant.user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: highlight ? _textPrimary : _textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              _StatusIcon(
                // A voice-blocked participant reads as force-muted; show the
                // off-mic glyph regardless of their own mic flag.
                icon: participant.voiceBlocked || participant.micMuted
                    ? Icons.mic_off
                    : Icons.mic,
                active:
                    !participant.voiceBlocked &&
                    !participant.micMuted &&
                    speaking,
              ),
              _StatusIcon(icon: Icons.videocam, active: participant.cameraOn),
              _StatusIcon(
                icon: Icons.screen_share,
                active: participant.screenSharing,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Large video stage for the active screen share, shown above the participant
/// grid in the live panel.
class _ScreenShareStage extends StatelessWidget {
  const _ScreenShareStage({
    required this.track,
    required this.label,
    this.onToggleFullScreen,
  });

  final LiveVideoTrack track;
  final String label;
  // When non-null, a fullscreen-enter button is shown in the top-right corner.
  final VoidCallback? onToggleFullScreen;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDark,
      child: Stack(
        fit: StackFit.expand,
        children: [
          lk.VideoTrackRenderer(track.track, fit: lk.VideoViewFit.contain),
          Positioned(
            left: 0,
            top: 0,
            child: _StageBadge(label: label.isEmpty ? '屏幕共享' : '$label 的屏幕'),
          ),
          if (onToggleFullScreen != null)
            Positioned(
              right: 8,
              top: 8,
              child: _StageIconButton(
                tooltip: '全屏',
                icon: Icons.fullscreen,
                onPressed: onToggleFullScreen!,
              ),
            ),
        ],
      ),
    );
  }
}

/// Translucent square icon button overlaid on the screen-share video (e.g. the
/// fullscreen toggle). Kept lightweight so it reads as an overlay control.
class _StageIconButton extends StatefulWidget {
  const _StageIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_StageIconButton> createState() => _StageIconButtonState();
}

class _StageIconButtonState extends State<_StageIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _primaryDark.withValues(alpha: _hover ? 0.92 : 0.7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _hover ? _cyan : _borderColor),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 20,
              color: _hover ? _cyan : _textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Immersive full-screen view of a single screen share. Fills the window over a
/// black backdrop with the video letterboxed inside. A floating control bar
/// (label + exit) auto-hides after a few seconds of mouse inactivity and
/// reappears on movement. Esc exits. The caller drives real OS full-screen and
/// hides the rest of the app chrome; this widget owns only the in-content UI.
class _FullScreenShare extends StatefulWidget {
  const _FullScreenShare({
    required this.track,
    required this.label,
    required this.onExit,
  });

  final LiveVideoTrack track;
  final String label;
  final VoidCallback onExit;

  @override
  State<_FullScreenShare> createState() => _FullScreenShareState();
}

class _FullScreenShareState extends State<_FullScreenShare> {
  final FocusNode _focusNode = FocusNode();
  Timer? _hideTimer;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    // Grab focus so Esc is delivered here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _wake() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label.isEmpty ? '屏幕共享' : '${widget.label} 的屏幕';
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        onHover: (_) => _wake(),
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              lk.VideoTrackRenderer(
                widget.track.track,
                fit: lk.VideoViewFit.contain,
              ),
              // Top control bar: label on the left, exit on the right.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.screen_share,
                            size: 16,
                            color: _cyan,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _StageIconButton(
                            tooltip: '退出全屏 (Esc)',
                            icon: Icons.fullscreen_exit,
                            onPressed: widget.onExit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  const _StageBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: _primaryDark.withValues(alpha: 0.82),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.screen_share, size: 14, color: _cyan),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Name + status overlay shown along the bottom of a participant's camera tile.
class _VideoTileFooter extends StatelessWidget {
  const _VideoTileFooter({
    required this.name,
    required this.micMuted,
    required this.speaking,
    required this.screenSharing,
  });

  final String name;
  final bool micMuted;
  final bool speaking;
  final bool screenSharing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_primaryDark.withValues(alpha: 0.85), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          Icon(
            micMuted ? Icons.mic_off : Icons.mic,
            size: 14,
            color: micMuted ? _textMuted : (speaking ? _cyan : _textSecondary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (screenSharing) ...[
            const SizedBox(width: 6),
            const Icon(Icons.screen_share, size: 14, color: _cyan),
          ],
        ],
      ),
    );
  }
}

/// Desktop screen-share source picker. Lists screens and windows with live
/// thumbnails and returns the chosen [ScreenSource], styled to match the app.
class _ScreenShareDialog extends StatefulWidget {
  const _ScreenShareDialog();

  @override
  State<_ScreenShareDialog> createState() => _ScreenShareDialogState();
}

class _ScreenShareDialogState extends State<_ScreenShareDialog> {
  List<ScreenSource>? _sources;
  String? _selectedId;
  String? _error;
  Timer? _refreshTimer;
  bool _loadingSources = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(LiveSession.refreshScreenSourceThumbnails());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadingSources) return;
    _loadingSources = true;
    try {
      final sources = await LiveSession.listScreenSources();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        final selectedId = _selectedId;
        _selectedId =
            selectedId != null && sources.any((s) => s.id == selectedId)
            ? selectedId
            : sources.isNotEmpty
            ? sources.first.id
            : null;
      });
      unawaited(LiveSession.refreshScreenSourceThumbnails());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      _loadingSources = false;
    }
  }

  void _confirm() {
    final source = _selectedSource;
    if (source == null) return;
    Navigator.of(context).pop(source);
  }

  ScreenSource? get _selectedSource {
    final id = _selectedId;
    final sources = _sources;
    if (id == null || sources == null) return null;
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '选择共享内容',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(child: _buildBody(sources)),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: _danger)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    onPressed: () => Navigator.of(context).pop(),
                    height: 38,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  Button(
                    onPressed: _selectedId == null ? null : _confirm,
                    tone: ButtonTone.primary,
                    height: 38,
                    child: const Text('共享'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(List<ScreenSource>? sources) {
    if (sources == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(color: _cyan)),
      );
    }
    if (sources.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text('没有可共享的屏幕或窗口', style: TextStyle(color: _textMuted)),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 158,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        final selected = source.id == _selectedId;
        return _ScreenSourceTile(
          source: source,
          selected: selected,
          onTap: () => setState(() => _selectedId = source.id),
        );
      },
    );
  }
}

class _ScreenSourceThumbnail extends StatefulWidget {
  const _ScreenSourceThumbnail({
    required this.source,
    required this.fit,
    required this.iconSize,
  });

  final ScreenSource source;
  final BoxFit fit;
  final double iconSize;

  @override
  State<_ScreenSourceThumbnail> createState() => _ScreenSourceThumbnailState();
}

class _ScreenSourceThumbnailState extends State<_ScreenSourceThumbnail> {
  Uint8List? _thumbnail;
  Object? _imageError;
  StreamSubscription<Uint8List>? _thumbnailSubscription;

  @override
  void initState() {
    super.initState();
    _bindSource(widget.source);
  }

  @override
  void didUpdateWidget(_ScreenSourceThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) _bindSource(widget.source);
  }

  @override
  void dispose() {
    unawaited(_thumbnailSubscription?.cancel());
    super.dispose();
  }

  void _bindSource(ScreenSource source) {
    unawaited(_thumbnailSubscription?.cancel());
    _thumbnail = source.thumbnail;
    _imageError = null;
    _thumbnailSubscription = source.thumbnailUpdates?.listen((thumbnail) {
      if (!mounted) return;
      setState(() {
        _thumbnail = thumbnail;
        _imageError = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final thumbnail = _thumbnail;
    if (thumbnail == null || thumbnail.isEmpty || _imageError != null) {
      return _ScreenSourceThumbnailFallback(iconSize: widget.iconSize);
    }

    return ClipRect(
      child: ColoredBox(
        color: _primaryDarkLow,
        child: Image.memory(
          thumbnail,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _imageError = error);
            });
            return _ScreenSourceThumbnailFallback(iconSize: widget.iconSize);
          },
        ),
      ),
    );
  }
}

class _ScreenSourceThumbnailFallback extends StatelessWidget {
  const _ScreenSourceThumbnailFallback({required this.iconSize});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDarkLow,
      child: Center(
        child: Icon(Icons.desktop_windows, color: _textMuted, size: iconSize),
      ),
    );
  }
}

class _ScreenSourceTile extends StatelessWidget {
  const _ScreenSourceTile({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final ScreenSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableSurface(
      height: 158,
      interactive: true,
      pressRequiresHover: true,
      selected: selected,
      onPressed: onTap,
      backgroundColor: _primaryDark,
      selectedBackgroundColor: _primaryDark,
      borderColor: _borderColor,
      selectedBorderColor: _cyan,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ScreenSourceThumbnail(
              source: source,
              fit: BoxFit.contain,
              iconSize: 32,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.desktop_windows,
                size: 13,
                color: selected ? _cyan : _textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _textPrimary : _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveControls extends StatelessWidget {
  const _LiveControls({
    required this.joined,
    required this.joining,
    required this.micMuted,
    required this.headphonesMuted,
    required this.voiceBlocked,
    required this.cameraOn,
    required this.screenSharing,
    required this.onJoin,
    required this.onLeave,
    required this.onToggleMic,
    required this.onToggleHeadphones,
    required this.onToggleCamera,
    required this.onToggleShare,
    required this.onCollapse,
  });

  final bool joined;
  final bool joining;
  final bool micMuted;
  final bool headphonesMuted;
  final bool voiceBlocked;
  final bool cameraOn;
  final bool screenSharing;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  // Null disables the mic button (the local user is voice-blocked).
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleShare;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      color: _primaryDarkLow,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!joined)
            _LiveControlKey(
              tooltip: 'Join',
              icon: Icons.call,
              active: true,
              busy: joining,
              onPressed: onJoin,
            )
          else ...[
            _LiveControlKey(
              tooltip: voiceBlocked
                  ? '已被管理员禁言'
                  : micMuted
                  ? 'Unmute'
                  : 'Mute',
              icon: voiceBlocked || micMuted ? Icons.mic_off : Icons.mic,
              active: !voiceBlocked && !micMuted,
              onPressed: voiceBlocked ? null : onToggleMic,
            ),
            _LiveControlKey(
              tooltip: headphonesMuted
                  ? 'Unmute headphones'
                  : 'Mute headphones',
              icon: headphonesMuted ? Icons.headset_off : Icons.headset,
              active: !headphonesMuted,
              onPressed: onToggleHeadphones,
            ),
            _LiveControlKey(
              tooltip: cameraOn ? 'Camera off' : 'Camera on',
              icon: Icons.videocam,
              active: cameraOn,
              onPressed: onToggleCamera,
            ),
            _LiveControlKey(
              tooltip: screenSharing ? 'Stop sharing' : 'Share screen',
              icon: Icons.screen_share,
              active: screenSharing,
              onPressed: onToggleShare,
            ),
            _LiveControlKey(
              tooltip: 'Leave',
              icon: Icons.call_end,
              active: true,
              danger: true,
              busy: joining,
              onPressed: onLeave,
            ),
          ],
          _LiveControlKey(
            tooltip: 'Collapse',
            icon: Icons.keyboard_arrow_up,
            active: false,
            onPressed: onCollapse,
          ),
        ],
      ),
    );
  }
}

class _LiveControlKey extends StatelessWidget {
  const _LiveControlKey({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
    this.danger = false,
    this.busy = false,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tone = danger
        ? ButtonTone.danger
        : active
        ? ButtonTone.primary
        : ButtonTone.neutral;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ButtonIcon(
        tooltip: tooltip,
        onPressed: onPressed,
        loading: busy,
        tone: tone,
        size: 48,
        icon: busy
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: danger ? _danger : _cyan,
                ),
              )
            : Icon(icon),
      ),
    );
  }
}

class _UserInfoDialog extends StatelessWidget {
  const _UserInfoDialog({
    required this.user,
    required this.room,
    required this.commonRooms,
    required this.onOpenRoom,
    required this.onCopyUid,
  });

  final UserSummary user;
  final RoomDetail room;
  final List<UserCommonRoom> commonRooms;
  final ValueChanged<String> onOpenRoom;
  final ValueChanged<String> onCopyUid;

  @override
  Widget build(BuildContext context) {
    final appConfig = AppConfigScope.of(context);
    final roleLabel = _roomRoleLabel(user, room);
    final primaryName = _userInfoPrimaryName(user);
    final uidValue = user.uid ?? user.id;
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(
                    label: primaryName,
                    imageUrl: appConfig.resolveAssetUrl(user.avatarUrl),
                    defaultAvatarKey: user.defaultAvatarKey,
                    size: 72,
                    borderColor: _cyan,
                    borderWidth: 1.4,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _NameWithGender(
                            name: primaryName,
                            gender: user.gender,
                            maxLines: 2,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '@${user.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _UserRoleBadge(label: roleLabel),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ButtonIcon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Divider(height: 1, color: _borderColor),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _UserInfoField(
                        label: 'UID',
                        value: uidValue,
                        trailing: ButtonIcon(
                          onPressed: () => onCopyUid(uidValue),
                          icon: const Icon(Icons.copy),
                          tooltip: '复制 UID',
                          size: 30,
                        ),
                      ),
                      if (commonRooms.isNotEmpty)
                        _CommonRoomsSection(
                          rooms: commonRooms,
                          onOpenRoom: (roomId) {
                            Navigator.of(context).pop();
                            onOpenRoom(roomId);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BasicUserInfoDialog extends StatelessWidget {
  const _BasicUserInfoDialog({required this.user, required this.onCopyUid});

  final UserSummary user;
  final ValueChanged<String> onCopyUid;

  @override
  Widget build(BuildContext context) {
    final appConfig = AppConfigScope.of(context);
    final uidValue = user.uid ?? user.id;
    final primaryName = _userInfoPrimaryName(user);
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(
                    label: primaryName,
                    imageUrl: appConfig.resolveAssetUrl(user.avatarUrl),
                    defaultAvatarKey: user.defaultAvatarKey,
                    size: 64,
                    borderColor: _cyan,
                    borderWidth: 1.4,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NameWithGender(
                          name: primaryName,
                          gender: user.gender,
                          maxLines: 2,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '@${user.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ButtonIcon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: _borderColor),
              _UserInfoField(
                label: 'UID',
                value: uidValue,
                trailing: ButtonIcon(
                  onPressed: () => onCopyUid(uidValue),
                  icon: const Icon(Icons.copy),
                  tooltip: '复制 UID',
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameWithGender extends StatelessWidget {
  const _NameWithGender({
    required this.name,
    required this.gender,
    required this.style,
    this.maxLines = 1,
  });

  final String name;
  final String? gender;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final mark = _genderMark(gender);
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: name),
          if (mark != null)
            TextSpan(
              text: ' ${mark.symbol}',
              style: style.copyWith(color: mark.color),
            ),
        ],
      ),
    );
  }
}

class _GenderMarkData {
  const _GenderMarkData({required this.symbol, required this.color});

  final String symbol;
  final Color color;
}

class _CommonRoomsSection extends StatelessWidget {
  const _CommonRoomsSection({required this.rooms, required this.onOpenRoom});

  final List<UserCommonRoom> rooms;
  final ValueChanged<String> onOpenRoom;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 102,
              child: Text(
                '共同房间',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in rooms.asMap().entries) ...[
                    if (entry.key > 0) const SizedBox(height: 8),
                    _CommonRoomLink(
                      room: entry.value,
                      onOpen: () => onOpenRoom(entry.value.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommonRoomLink extends StatelessWidget {
  const _CommonRoomLink({required this.room, required this.onOpen});

  final UserCommonRoom room;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final title = _commonRoomTitle(room);
    final meta = _commonRoomMeta(room);
    return Tooltip(
      message: '打开房间',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 14,
                height: 1.36,
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: '$title · ${_visibilityLabel(room.visibility)}',
                  style: const TextStyle(
                    color: _cyan,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (meta != null)
                  TextSpan(
                    text: ' ($meta)',
                    style: const TextStyle(
                      color: _textSecondary,
                      fontWeight: FontWeight.w600,
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

class _UserRoleBadge extends StatelessWidget {
  const _UserRoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _selectedSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF22332B)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _cyan,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _UserInfoField extends StatelessWidget {
  const _UserInfoField({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 102,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: SelectableText(
                value,
                maxLines: 3,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 14,
                  height: 1.36,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class _RoomInfoDialog extends StatefulWidget {
  const _RoomInfoDialog({
    required this.api,
    required this.room,
    required this.currentUser,
    required this.isInLive,
    required this.onLeaveLive,
  });

  final GangApi api;
  final RoomDetail room;
  final CurrentUser currentUser;
  final bool isInLive;
  final Future<void> Function() onLeaveLive;

  @override
  State<_RoomInfoDialog> createState() => _RoomInfoDialogState();
}

class _RoomInfoDialogState extends State<_RoomInfoDialog> {
  late final TextEditingController _remarkController;
  late final TextEditingController _roomDisplayNameController;
  late String _notificationPolicy;
  late String _defaultAvatarKey;
  String? _pendingAvatarAssetId;
  String? _pendingAvatarUrl;
  bool _usingGlobalProfile = false;
  bool _saving = false;
  bool _leaving = false;
  bool _uploadingAvatar = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final profile = widget.room.personalProfile;
    _remarkController = TextEditingController(
      text: widget.room.remarkName ?? '',
    );
    _roomDisplayNameController = TextEditingController(
      text: profile.displayName ?? '',
    );
    _notificationPolicy = _normalizedNotificationPolicy(
      widget.room.notificationPolicy,
    );
    _defaultAvatarKey =
        profile.defaultAvatarKey ?? widget.currentUser.defaultAvatarKey;
  }

  @override
  void dispose() {
    _remarkController.dispose();
    _roomDisplayNameController.dispose();
    super.dispose();
  }

  Future<void> _copyText(String value, String label) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (!mounted) return;
      setState(() {
        _notice = '$label 已复制';
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '无法复制：$e');
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '无法打开文件选择器：$e');
      return;
    }
    if (file == null) return;

    setState(() {
      _uploadingAvatar = true;
      _error = null;
      _notice = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final asset = await widget.api.uploadImageAsset(
        bytes: bytes,
        filename: _basename(file.name),
        purpose: 'avatar',
      );
      if (!mounted) return;
      setState(() {
        _pendingAvatarAssetId = asset.id;
        _pendingAvatarUrl = asset.url;
        _usingGlobalProfile = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _useGlobalProfile() {
    setState(() {
      _usingGlobalProfile = true;
      _roomDisplayNameController.clear();
      _pendingAvatarAssetId = null;
      _pendingAvatarUrl = null;
      _defaultAvatarKey = widget.currentUser.defaultAvatarKey;
      _notice = '保存后将使用全局默认用户名和默认头像';
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving || _leaving) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final updated = await widget.api.updateMyRoomSettings(
        roomId: widget.room.id,
        remarkName: _remarkController.text.trim(),
        notificationPolicy: _notificationPolicy,
        roomDisplayName: _usingGlobalProfile
            ? ''
            : _roomDisplayNameController.text.trim(),
        avatarAssetId: _usingGlobalProfile ? '' : _pendingAvatarAssetId,
        defaultAvatarKey: _usingGlobalProfile ? '' : _defaultAvatarKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leaveRoom() async {
    if (_saving || _leaving) return;
    final needsStrongConfirm =
        widget.room.isCreator && widget.room.memberCount <= 1;
    final confirmed = needsStrongConfirm
        ? await showDialog<bool>(
            context: context,
            builder: (context) => _StrongConfirmDialog(
              title: '退出并删除房间',
              body: '这是房间里的最后一位成员。退出会删除房间和所有房间内数据，请输入房间名确认。',
              expectedText: widget.room.name,
              confirmLabel: '退出并删除',
              confirmIcon: Icons.logout,
            ),
          )
        : await showDialog<bool>(
            context: context,
            builder: (context) => _ConfirmActionDialog(
              title: '退出房间',
              body: widget.isInLive
                  ? '退出后会离开当前房间，并同时离开 Live Channel。'
                  : '退出后你会从房间成员中移除，房间会从列表中消失。',
              confirmLabel: '退出',
              confirmIcon: Icons.logout,
              danger: true,
            ),
          );
    if (confirmed != true || !mounted) return;

    setState(() {
      _leaving = true;
      _error = null;
      _notice = null;
    });
    try {
      if (widget.isInLive) {
        await widget.onLeaveLive();
      }
      await widget.api.leaveRoom(
        roomId: widget.room.id,
        confirmDeleteIfEmpty: needsStrongConfirm,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_RoomDialogCloseResult.left);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = AppConfigScope.of(context);
    final profile = widget.room.personalProfile;
    final roomProfileAvatarUrl = _usingGlobalProfile
        ? widget.currentUser.avatarUrl
        : _pendingAvatarUrl ??
              profile.avatarUrl ??
              widget.currentUser.avatarUrl;
    final resolvedProfileAvatar = appConfig.resolveAssetUrl(
      roomProfileAvatarUrl,
    );
    final profileName = _usingGlobalProfile
        ? widget.currentUser.displayName
        : _nonEmpty(_roomDisplayNameController.text) ??
              widget.currentUser.displayName;

    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Column(
          children: [
            _RoomDialogHeader(
              title: '房间信息',
              onClose: () => Navigator.of(context).pop(),
            ),
            _RoomDialogRoomSummary(
              roomName: widget.room.name,
              avatarLabel: widget.room.name,
              avatarUrl: appConfig.resolveAssetUrl(widget.room.avatarUrl),
              defaultAvatarKey: widget.room.defaultAvatarKey,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                children: [
                  if (_notice != null) ...[
                    _RoomNotice(message: _notice!),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null) ...[
                    _RoomError(message: _error!),
                    const SizedBox(height: 12),
                  ],
                  _RoomSettingsGroup(
                    title: '基础信息',
                    children: [
                      _CopyableRoomField(
                        label: '房间永久 RID',
                        value: widget.room.rid.isEmpty
                            ? widget.room.id
                            : widget.room.rid,
                        onCopy: () => _copyText(
                          widget.room.rid.isEmpty
                              ? widget.room.id
                              : widget.room.rid,
                          'RID',
                        ),
                      ),
                      const SizedBox(height: 14),
                      _CopyableRoomField(
                        label: '房间介绍',
                        value: widget.room.description.isEmpty
                            ? '暂无介绍'
                            : widget.room.description,
                        maxLines: 3,
                        onCopy: () =>
                            _copyText(widget.room.description, '房间介绍'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _RoomSettingsGroup(
                    title: '我的房间设置',
                    children: [
                      _RoomTextField(
                        label: '房间备注名',
                        controller: _remarkController,
                        helperText: '仅影响你的房间列表，显示为“备注名 (原房间名)”。',
                      ),
                      const SizedBox(height: 14),
                      _RoomTextField(
                        label: '房间内昵称',
                        controller: _roomDisplayNameController,
                        helperText: '为空时使用全局默认用户名。',
                      ),
                      const SizedBox(height: 14),
                      _RoomAvatarPicker(
                        label: '房间内头像',
                        displayName: profileName,
                        avatarUrl: resolvedProfileAvatar,
                        defaultAvatarKey: _defaultAvatarKey,
                        uploading: _uploadingAvatar,
                        onUpload: _pickAvatar,
                        onPresetChanged: (key) => setState(() {
                          _defaultAvatarKey = key;
                          _pendingAvatarAssetId = null;
                          _pendingAvatarUrl = null;
                          _usingGlobalProfile = false;
                        }),
                        onUsePreset: () => setState(() {
                          _pendingAvatarAssetId = null;
                          _pendingAvatarUrl = null;
                          _usingGlobalProfile = false;
                        }),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Button(
                          onPressed: _useGlobalProfile,
                          height: 34,
                          icon: const Icon(Icons.person_outline),
                          child: const Text('使用全局默认资料'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _RoomSegmentedSetting(
                        label: '消息通知',
                        value: _notificationPolicy,
                        options: const [
                          _RoomOption('all', '全部消息'),
                          _RoomOption('mentions', '仅提及'),
                          _RoomOption('muted', '免打扰'),
                        ],
                        onChanged: (value) =>
                            setState(() => _notificationPolicy = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _RoomSettingsGroup(
                    title: '退出房间',
                    danger: true,
                    children: [
                      Button(
                        onPressed: _leaving || _saving ? null : _leaveRoom,
                        loading: _leaving,
                        tone: ButtonTone.danger,
                        icon: const Icon(Icons.logout),
                        width: double.infinity,
                        child: const Text('退出房间'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _RoomDialogFooter(
              saving: _saving,
              onCancel: () => Navigator.of(context).pop(),
              onSave: _save,
              saveLabel: '保存房间信息',
            ),
          ],
        ),
      ),
    );
  }
}

enum _RoomManagementSection { info, stickers }

class _RoomManagementDialog extends StatefulWidget {
  const _RoomManagementDialog({
    required this.api,
    required this.room,
    required this.currentUser,
  });

  final GangApi api;
  final RoomDetail room;
  final CurrentUser currentUser;

  @override
  State<_RoomManagementDialog> createState() => _RoomManagementDialogState();
}

class _RoomManagementDialogState extends State<_RoomManagementDialog> {
  late RoomDetail _room;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _visibility;
  late String _joinPolicy;
  late bool _aiVoiceAnnouncementsEnabled;
  late String _defaultAvatarKey;
  String? _pendingAvatarAssetId;
  String? _pendingAvatarUrl;
  bool _uploadingAvatar = false;
  bool _saving = false;
  bool _deleting = false;
  bool _loadingMembers = false;
  bool _changed = false;
  String? _error;
  String? _notice;
  _RoomManagementSection _section = _RoomManagementSection.info;
  List<RoomMember> _members = const [];
  final Set<String> _busyMemberIds = <String>{};

  bool get _canEditCreatorOnly =>
      _room.isCreator || _room.isSuperuser || widget.currentUser.isSuperuser;

  bool get _canDeleteRoom => _room.canDelete || widget.currentUser.isSuperuser;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _nameController = TextEditingController(text: _room.name);
    _descriptionController = TextEditingController(text: _room.description);
    _visibility = _normalizedVisibility(_room.visibility);
    _joinPolicy = _normalizedJoinPolicy(_room.joinPolicy);
    _aiVoiceAnnouncementsEnabled = _room.aiVoiceAnnouncementsEnabled;
    _defaultAvatarKey = _room.defaultAvatarKey;
    _loadMembers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(_changed ? _room : null);

  Future<void> _loadMembers() async {
    if (_loadingMembers) return;
    setState(() {
      _loadingMembers = true;
      _error = null;
    });
    try {
      final members = <RoomMember>[];
      String? cursor;
      var pageCount = 0;
      do {
        final page = await widget.api.listRoomMembers(
          _room.id,
          limit: 100,
          cursor: cursor,
        );
        members.addAll(page.members);
        cursor = _nonEmpty(page.nextCursor);
        pageCount += 1;
      } while (cursor != null && pageCount < 50);
      if (!mounted) return;
      setState(() {
        _members = members;
        _loadingMembers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingMembers = false;
      });
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '无法打开文件选择器：$e');
      return;
    }
    if (file == null) return;
    setState(() {
      _uploadingAvatar = true;
      _error = null;
      _notice = null;
    });
    try {
      final asset = await widget.api.uploadImageAsset(
        bytes: await file.readAsBytes(),
        filename: _basename(file.name),
        purpose: 'avatar',
      );
      if (!mounted) return;
      setState(() {
        _pendingAvatarAssetId = asset.id;
        _pendingAvatarUrl = asset.url;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _saveInfo() async {
    if (_saving || _deleting) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '房间名不能为空');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final updated = await widget.api.updateRoom(
        roomId: _room.id,
        name: name,
        description: _descriptionController.text.trim(),
        visibility: _visibility,
        joinPolicy: _joinPolicy,
        aiVoiceAnnouncementsEnabled: _aiVoiceAnnouncementsEnabled,
        avatarAssetId: _pendingAvatarAssetId,
        defaultAvatarKey: _defaultAvatarKey,
      );
      if (!mounted) return;
      setState(() {
        _room = updated;
        _changed = true;
        _pendingAvatarAssetId = null;
        _pendingAvatarUrl = null;
        _notice = '房间信息已保存';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteRoom() async {
    if (!_canDeleteRoom || _deleting || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _StrongConfirmDialog(
        title: '删除房间',
        body: '将清空房间所有数据。这个动作不可恢复，请输入房间名确认。',
        expectedText: _room.name,
        confirmLabel: '删除房间',
        confirmIcon: Icons.delete_forever_outlined,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.api.deleteRoom(roomId: _room.id, confirmName: _room.name);
      if (!mounted) return;
      Navigator.of(context).pop(_RoomDialogCloseResult.deleted);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _setMemberRole(RoomMember member, String role) async {
    if (_busyMemberIds.contains(member.user.id)) return;
    setState(() {
      _busyMemberIds.add(member.user.id);
      _error = null;
      _notice = null;
    });
    try {
      final updated = await widget.api.updateRoomMemberRole(
        roomId: _room.id,
        userId: member.user.id,
        role: role,
      );
      if (!mounted) return;
      setState(() {
        _members = _members
            .map((item) => item.user.id == updated.user.id ? updated : item)
            .toList();
        _busyMemberIds.remove(member.user.id);
        _changed = true;
        _notice = role == 'admin' ? '管理员已设置' : '管理员权限已撤回';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busyMemberIds.remove(member.user.id);
      });
    }
  }

  Future<void> _transferCreator(RoomMember member) async {
    if (_busyMemberIds.contains(member.user.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmActionDialog(
        title: '转让创建者',
        body: '创建者身份会转让给 ${_memberTileName(member)}，你将成为管理员。',
        confirmLabel: '转让',
        confirmIcon: Icons.swap_horiz,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busyMemberIds.add(member.user.id);
      _error = null;
      _notice = null;
    });
    try {
      final updated = await widget.api.transferRoomCreator(
        roomId: _room.id,
        userId: member.user.id,
      );
      if (!mounted) return;
      setState(() {
        _room = updated;
        _changed = true;
        _notice = '创建者已转让';
        _busyMemberIds.remove(member.user.id);
      });
      unawaited(_loadMembers());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busyMemberIds.remove(member.user.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = AppConfigScope.of(context);
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: Column(
          children: [
            _RoomDialogHeader(title: '房间管理', onClose: _close),
            _RoomDialogRoomSummary(
              roomName: _room.name,
              avatarLabel: _room.name,
              avatarUrl: appConfig.resolveAssetUrl(
                _pendingAvatarUrl ?? _room.avatarUrl,
              ),
              defaultAvatarKey: _defaultAvatarKey,
            ),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 170,
                    child: _RoomManagementNav(
                      selected: _section,
                      onChanged: (section) => setState(() {
                        _section = section;
                        if (section == _RoomManagementSection.stickers) {
                          _notice = null;
                          _error = null;
                        }
                      }),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: _borderColor),
                  Expanded(child: _buildSection(appConfig)),
                ],
              ),
            ),
            if (_section == _RoomManagementSection.info)
              _RoomDialogFooter(
                saving: _saving,
                onCancel: _close,
                onSave: _saveInfo,
                saveLabel: '保存房间管理',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(AppConfig appConfig) {
    return switch (_section) {
      _RoomManagementSection.info => _buildInfoSection(appConfig),
      _RoomManagementSection.stickers => _RoomStickerManager(
        api: widget.api,
        roomId: _room.id,
      ),
    };
  }

  Widget _buildInfoSection(AppConfig appConfig) {
    final busy = _saving || _deleting;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
      children: [
        if (_notice != null) ...[
          _RoomNotice(message: _notice!),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          _RoomError(message: _error!),
          const SizedBox(height: 12),
        ],
        _RoomSettingsGroup(
          title: '房间信息',
          children: [
            _RoomTextField(label: '房间重命名', controller: _nameController),
            const SizedBox(height: 14),
            _RoomAvatarPicker(
              label: '房间图标',
              displayName: _nameController.text,
              avatarUrl: appConfig.resolveAssetUrl(
                _pendingAvatarUrl ?? _room.avatarUrl,
              ),
              defaultAvatarKey: _defaultAvatarKey,
              uploading: _uploadingAvatar,
              onUpload: _pickAvatar,
              onPresetChanged: (key) => setState(() {
                _defaultAvatarKey = key;
                _pendingAvatarAssetId = null;
                _pendingAvatarUrl = null;
              }),
              onUsePreset: () => setState(() {
                _pendingAvatarAssetId = null;
                _pendingAvatarUrl = null;
              }),
            ),
            const SizedBox(height: 14),
            _RoomTextField(
              label: '房间介绍',
              controller: _descriptionController,
              maxLines: 4,
            ),
            const SizedBox(height: 14),
            _RoomSegmentedSetting(
              label: '房间公开性',
              value: _visibility,
              options: const [
                _RoomOption('public', '公开'),
                _RoomOption('private', '私密'),
              ],
              onChanged: (value) => setState(() => _visibility = value),
            ),
            const SizedBox(height: 14),
            _RoomSegmentedSetting(
              label: '加入策略',
              value: _joinPolicy,
              options: const [
                _RoomOption('approval_required', '管理员审核'),
                _RoomOption('open', '任何人加入'),
                _RoomOption('closed', '不允许加入'),
              ],
              onChanged: (value) => setState(() => _joinPolicy = value),
            ),
            const SizedBox(height: 14),
            _RoomSwitchSetting(
              label: 'AI 语音自动播报',
              value: _aiVoiceAnnouncementsEnabled,
              onChanged: (value) =>
                  setState(() => _aiVoiceAnnouncementsEnabled = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _RoomSettingsGroup(
          title: '成员权限',
          trailing: _loadingMembers
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    color: _cyan,
                    strokeWidth: 2,
                  ),
                )
              : ButtonIcon(
                  tooltip: '刷新成员',
                  onPressed: _loadMembers,
                  icon: const Icon(Icons.refresh),
                  size: 30,
                ),
          children: [
            if (_members.isEmpty && _loadingMembers)
              const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator(color: _cyan)),
              )
            else if (_members.isEmpty)
              const _RoomEmptyState(text: '暂无成员')
            else
              for (final member in _members) ...[
                _RoomMemberPermissionTile(
                  member: member,
                  room: _room,
                  currentUser: widget.currentUser,
                  busy: _busyMemberIds.contains(member.user.id),
                  canEditCreatorOnly: _canEditCreatorOnly,
                  onSetAdmin: () => _setMemberRole(member, 'admin'),
                  onUnsetAdmin: () => _setMemberRole(member, 'member'),
                  onTransferCreator: () => _transferCreator(member),
                ),
                if (member != _members.last) const SizedBox(height: 8),
              ],
          ],
        ),
        if (_canDeleteRoom) ...[
          const SizedBox(height: 16),
          _RoomSettingsGroup(
            title: '删除房间',
            danger: true,
            children: [
              Button(
                onPressed: busy ? null : _deleteRoom,
                loading: _deleting,
                tone: ButtonTone.danger,
                icon: const Icon(Icons.delete_forever_outlined),
                width: double.infinity,
                child: const Text('删除房间'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RoomStickerManager extends StatefulWidget {
  const _RoomStickerManager({required this.api, required this.roomId});

  final GangApi api;
  final String roomId;

  @override
  State<_RoomStickerManager> createState() => _RoomStickerManagerState();
}

class _RoomStickerManagerState extends State<_RoomStickerManager> {
  List<StickerPack> _packs = const [];
  bool _loading = true;
  bool _uploading = false;
  bool _deleting = false;
  bool _savingOrder = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Sticker> get _stickers {
    return [
      for (final pack in _packs)
        ...pack.stickers.toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
    ];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final packs = await widget.api.listStickerPacks(
        scope: 'room',
        roomId: widget.roomId,
      );
      if (!mounted) return;
      setState(() {
        _packs = packs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<StickerPack> _ensurePack() async {
    if (_packs.isNotEmpty) return _packs.first;
    final created = await widget.api.createStickerPack(
      name: '房间表情包',
      scope: 'room',
      roomId: widget.roomId,
      sortOrder: 10,
    );
    if (mounted) setState(() => _packs = [created]);
    return created;
  }

  Future<void> _upload() async {
    if (_uploading || _deleting || _savingOrder) return;
    List<XFile> files;
    try {
      files = await openFiles(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '无法打开文件选择器：$e');
      return;
    }
    if (files.isEmpty) return;
    setState(() {
      _uploading = true;
      _error = null;
      _notice = null;
    });
    try {
      final pack = await _ensurePack();
      var sortIndex = pack.stickers.length;
      for (final file in files) {
        final asset = await widget.api.uploadImageAsset(
          bytes: await file.readAsBytes(),
          filename: _basename(file.name),
          purpose: 'sticker',
        );
        await widget.api.addSticker(
          packId: pack.id,
          assetId: asset.id,
          name: _stickerNameFromFilename(file.name),
          sortOrder: (++sortIndex) * 10,
          scope: 'room',
          roomId: widget.roomId,
        );
      }
      await _load();
      if (!mounted) return;
      setState(() => _notice = '已添加 ${files.length} 个房间表情');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(Sticker sticker) async {
    if (_deleting) return;
    final pack = _packForSticker(sticker.id);
    if (pack == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmActionDialog(
        title: '删除房间表情',
        body: '将从这个房间的表情包中删除「${sticker.name}」。',
        confirmLabel: '删除',
        confirmIcon: Icons.delete_outline,
        danger: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.api.deleteSticker(
        packId: pack.id,
        stickerId: sticker.id,
        scope: 'room',
        roomId: widget.roomId,
      );
      await _load();
      if (!mounted) return;
      setState(() => _notice = '房间表情已删除');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _rename(Sticker sticker, String name) async {
    final pack = _packForSticker(sticker.id);
    if (pack == null || name.trim().isEmpty) return;
    try {
      await widget.api.updateSticker(
        packId: pack.id,
        stickerId: sticker.id,
        name: name.trim(),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _move(Sticker sticker, int delta) async {
    if (_savingOrder) return;
    final pack = _packForSticker(sticker.id);
    if (pack == null) return;
    final ordered = pack.stickers.toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final from = ordered.indexWhere((item) => item.id == sticker.id);
    if (from < 0) return;
    final to = (from + delta).clamp(0, ordered.length - 1).toInt();
    if (from == to) return;
    final moving = ordered.removeAt(from);
    ordered.insert(to, moving);
    setState(() {
      _savingOrder = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.api.reorderStickers(
        packId: pack.id,
        stickerIds: ordered.map((item) => item.id).toList(),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  Future<void> _download(Sticker sticker) async {
    try {
      final file = await widget.api.downloadStickers(stickerIds: [sticker.id]);
      final location = await getSaveLocation(
        suggestedName: file.filename,
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'zip'],
          ),
        ],
        confirmButtonText: '保存',
      );
      if (location == null) return;
      await XFile.fromData(
        file.bytes,
        mimeType: file.mimeType,
        name: file.filename,
      ).saveTo(location.path);
      if (!mounted) return;
      setState(() => _notice = '房间表情已下载');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  StickerPack? _packForSticker(String stickerId) {
    for (final pack in _packs) {
      if (pack.stickers.any((sticker) => sticker.id == stickerId)) return pack;
    }
    return null;
  }

  void _preview(Sticker sticker) {
    final imageUrl = AppConfigScope.of(
      context,
    ).resolveAssetUrl(sticker.asset.url);
    if (imageUrl == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => _RoomStickerPreviewDialog(
        sticker: sticker,
        imageUrl: imageUrl,
        onRename: _rename,
        onDelete: _delete,
        onMoveUp: () => _move(sticker, -1),
        onMoveDown: () => _move(sticker, 1),
        onDownload: () => _download(sticker),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stickers = _stickers;
    final busy = _uploading || _deleting || _savingOrder;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
      children: [
        if (_notice != null) ...[
          _RoomNotice(message: _notice!),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          _RoomError(message: _error!),
          const SizedBox(height: 12),
        ],
        _RoomSettingsGroup(
          title: '房间表情包',
          trailing: Text(
            '${stickers.length} 个',
            style: const TextStyle(
              color: _textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Button(
                    onPressed: busy ? null : _upload,
                    loading: _uploading,
                    tone: ButtonTone.primary,
                    icon: const Icon(Icons.upload_file),
                    child: const Text('本地上传'),
                  ),
                ),
                const SizedBox(width: 10),
                ButtonIcon(
                  tooltip: '刷新',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  size: 40,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading && stickers.isEmpty)
              const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator(color: _cyan)),
              )
            else if (stickers.isEmpty)
              const _RoomEmptyState(text: '房间表情包为空，上传后只在本房间可用')
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: stickers.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 120,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.92,
                ),
                itemBuilder: (context, index) {
                  final sticker = stickers[index];
                  final imageUrl = AppConfigScope.of(
                    context,
                  ).resolveAssetUrl(sticker.asset.url);
                  return _RoomStickerTile(
                    sticker: sticker,
                    imageUrl: imageUrl,
                    onTap: () => _preview(sticker),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _RoomDialogHeader extends StatelessWidget {
  const _RoomDialogHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ButtonIcon(
            tooltip: '关闭',
            onPressed: onClose,
            icon: const Icon(Icons.close),
            size: 32,
          ),
        ],
      ),
    );
  }
}

class _RoomDialogRoomSummary extends StatelessWidget {
  const _RoomDialogRoomSummary({
    required this.roomName,
    required this.avatarLabel,
    required this.avatarUrl,
    required this.defaultAvatarKey,
  });

  final String roomName;
  final String avatarLabel;
  final String? avatarUrl;
  final String defaultAvatarKey;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 20, 18),
        child: Row(
          children: [
            _Avatar(
              label: avatarLabel,
              imageUrl: avatarUrl,
              defaultAvatarKey: defaultAvatarKey,
              size: 56,
              borderColor: _cyan,
              borderWidth: 1.2,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                roomName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomDialogFooter extends StatelessWidget {
  const _RoomDialogFooter({
    required this.saving,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Button(
              onPressed: saving ? null : onCancel,
              child: const Text('取消'),
            ),
            const SizedBox(width: 10),
            Button(
              onPressed: saving ? null : onSave,
              loading: saving,
              tone: ButtonTone.primary,
              icon: const Icon(Icons.save_outlined),
              child: Text(saveLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomSettingsGroup extends StatelessWidget {
  const _RoomSettingsGroup({
    required this.title,
    required this.children,
    this.trailing,
    this.danger = false,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _primaryDarkLow,
        border: Border.all(
          color: danger ? const Color(0xFF3A2A2E) : _borderColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: danger ? _danger : _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _RoomNotice extends StatelessWidget {
  const _RoomNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _RoomBanner(
      message: message,
      icon: Icons.check_circle_outline,
      color: _cyan,
    );
  }
}

class _RoomError extends StatelessWidget {
  const _RoomError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _RoomBanner(
      message: message,
      icon: Icons.error_outline,
      color: _danger,
    );
  }
}

class _RoomBanner extends StatelessWidget {
  const _RoomBanner({
    required this.message,
    required this.icon,
    required this.color,
  });

  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _primaryDark,
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomFieldLabel extends StatelessWidget {
  const _RoomFieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _CopyableRoomField extends StatelessWidget {
  const _CopyableRoomField({
    required this.label,
    required this.value,
    required this.onCopy,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomFieldLabel(label),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _primaryDark,
            border: Border.all(color: _borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    value,
                    maxLines: maxLines,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ButtonIcon(
                  tooltip: '复制',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy),
                  size: 30,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomTextField extends StatelessWidget {
  const _RoomTextField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.helperText,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomFieldLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          cursorColor: _textSecondary,
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          decoration: const InputDecoration(isDense: true),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText!,
            style: const TextStyle(color: _textMuted, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _RoomOption {
  const _RoomOption(this.value, this.label);

  final String value;
  final String label;
}

class _RoomSegmentedSetting extends StatelessWidget {
  const _RoomSegmentedSetting({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<_RoomOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomFieldLabel(label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              Button(
                onPressed: () => onChanged(option.value),
                selected: option.value == value,
                tone: option.value == value
                    ? ButtonTone.primary
                    : ButtonTone.neutral,
                height: 34,
                child: Text(option.label),
              ),
          ],
        ),
      ],
    );
  }
}

class _RoomSwitchSetting extends StatelessWidget {
  const _RoomSwitchSetting({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _RoomFieldLabel(label)),
        Switch(
          value: value,
          activeThumbColor: _cyan,
          activeTrackColor: _cyan.withValues(alpha: 0.28),
          inactiveThumbColor: _textMuted,
          inactiveTrackColor: _borderColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RoomAvatarPicker extends StatelessWidget {
  const _RoomAvatarPicker({
    required this.label,
    required this.displayName,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    required this.uploading,
    required this.onUpload,
    required this.onPresetChanged,
    required this.onUsePreset,
  });

  static const _keys = [
    'room-1',
    'blue-3',
    'sky-2',
    'cyan-2',
    'mint-2',
    'green-2',
    'lime-2',
    'amber-2',
    'orange-2',
    'coral-2',
    'pink-2',
    'violet-2',
    'indigo-2',
    'rose-2',
    'teal-2',
    'olive-2',
    'slate-2',
    'steel-2',
    'graphite-2',
  ];

  final String label;
  final String displayName;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final bool uploading;
  final VoidCallback onUpload;
  final ValueChanged<String> onPresetChanged;
  final VoidCallback onUsePreset;

  @override
  Widget build(BuildContext context) {
    final uploadedSelected = avatarUrl != null;
    final presetSelected = !uploadedSelected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomFieldLabel(label),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Center(
                child: _Avatar(
                  label: displayName,
                  imageUrl: avatarUrl,
                  defaultAvatarKey: defaultAvatarKey,
                  size: 88,
                  borderColor: _cyan,
                  borderWidth: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final key in _keys)
                    _AvatarSwatch(
                      keyName: key,
                      selected: presetSelected && key == defaultAvatarKey,
                      onPressed: () => onPresetChanged(key),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Button(
                onPressed: uploading ? null : onUpload,
                loading: uploading,
                icon: const Icon(Icons.upload_file),
                tone: uploadedSelected
                    ? ButtonTone.primary
                    : ButtonTone.neutral,
                selected: uploadedSelected,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                width: double.infinity,
                child: const Text('上传图片'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Button(
                onPressed: uploading ? null : onUsePreset,
                icon: const Icon(Icons.restart_alt),
                tone: presetSelected ? ButtonTone.primary : ButtonTone.neutral,
                selected: presetSelected,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                width: double.infinity,
                child: const Text('预设图标'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AvatarSwatch extends StatelessWidget {
  const _AvatarSwatch({
    required this.keyName,
    required this.selected,
    required this.onPressed,
  });

  final String keyName;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: keyName,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _avatarColor(keyName),
            border: Border.all(
              color: selected ? _cyan : _borderColor,
              width: selected ? 2 : 1,
            ),
          ),
          child: const SizedBox.square(dimension: 30),
        ),
      ),
    );
  }
}

class _RoomManagementNav extends StatelessWidget {
  const _RoomManagementNav({required this.selected, required this.onChanged});

  final _RoomManagementSection selected;
  final ValueChanged<_RoomManagementSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDark,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        children: [
          _RoomNavButton(
            selected: selected == _RoomManagementSection.info,
            icon: Icons.info_outline,
            label: '房间信息',
            onPressed: () => onChanged(_RoomManagementSection.info),
          ),
          const SizedBox(height: 8),
          _RoomNavButton(
            selected: selected == _RoomManagementSection.stickers,
            icon: Icons.emoji_emotions_outlined,
            label: '房间表情包',
            onPressed: () => onChanged(_RoomManagementSection.stickers),
          ),
        ],
      ),
    );
  }
}

class _RoomNavButton extends StatelessWidget {
  const _RoomNavButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: onPressed,
      selected: selected,
      tone: selected ? ButtonTone.primary : ButtonTone.neutral,
      icon: Icon(icon),
      width: double.infinity,
      mainAxisSize: MainAxisSize.max,
      child: Text(label),
    );
  }
}

class _RoomMemberPermissionTile extends StatelessWidget {
  const _RoomMemberPermissionTile({
    required this.member,
    required this.room,
    required this.currentUser,
    required this.busy,
    required this.canEditCreatorOnly,
    required this.onSetAdmin,
    required this.onUnsetAdmin,
    required this.onTransferCreator,
  });

  final RoomMember member;
  final RoomDetail room;
  final CurrentUser currentUser;
  final bool busy;
  final bool canEditCreatorOnly;
  final VoidCallback onSetAdmin;
  final VoidCallback onUnsetAdmin;
  final VoidCallback onTransferCreator;

  bool get _isSuperuser =>
      member.user.isSuperuser || member.role == 'superuser';
  bool get _isOwner =>
      member.user.id == room.createdBy?.id ||
      member.role == 'owner' ||
      member.role == 'creator';
  bool get _isAdmin => member.role == 'admin' || member.role == 'administrator';

  @override
  Widget build(BuildContext context) {
    final name = _memberTileName(member);
    final canRoleEdit =
        canEditCreatorOnly &&
        !_isSuperuser &&
        !_isOwner &&
        member.user.id != currentUser.id;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _primaryDark,
        border: Border.all(color: _borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            _Avatar(
              label: name,
              imageUrl: AppConfigScope.of(
                context,
              ).resolveAssetUrl(member.user.avatarUrl),
              defaultAvatarKey: member.user.defaultAvatarKey,
              size: 38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _roomRoleLabel(
                      member.user.copyWith(roomRole: member.role),
                      room,
                    ),
                    style: const TextStyle(color: _textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(color: _cyan, strokeWidth: 2),
              )
            else if (canRoleEdit) ...[
              Button(
                onPressed: _isAdmin ? onUnsetAdmin : onSetAdmin,
                height: 32,
                icon: Icon(
                  _isAdmin
                      ? Icons.person_remove_alt_1_outlined
                      : Icons.admin_panel_settings_outlined,
                ),
                child: Text(_isAdmin ? '撤回管理员' : '设为管理员'),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: onTransferCreator,
                height: 32,
                icon: const Icon(Icons.swap_horiz),
                child: const Text('设为创建者'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoomStickerTile extends StatelessWidget {
  const _RoomStickerTile({
    required this.sticker,
    required this.imageUrl,
    required this.onTap,
  });

  final Sticker sticker;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableSurface(
      onPressed: onTap,
      height: 110,
      backgroundColor: _primaryDark,
      borderColor: _borderColor,
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: imageUrl == null
                ? const Icon(Icons.broken_image_outlined, color: _textMuted)
                : Image.network(
                    imageUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            sticker.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomStickerPreviewDialog extends StatefulWidget {
  const _RoomStickerPreviewDialog({
    required this.sticker,
    required this.imageUrl,
    required this.onRename,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDownload,
  });

  final Sticker sticker;
  final String imageUrl;
  final Future<void> Function(Sticker sticker, String name) onRename;
  final Future<void> Function(Sticker sticker) onDelete;
  final Future<void> Function() onMoveUp;
  final Future<void> Function() onMoveDown;
  final Future<void> Function() onDownload;

  @override
  State<_RoomStickerPreviewDialog> createState() =>
      _RoomStickerPreviewDialogState();
}

class _RoomStickerPreviewDialogState extends State<_RoomStickerPreviewDialog> {
  late final TextEditingController _nameController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.sticker.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool close = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (close && mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.sticker.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  ButtonIcon(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _primaryDark,
                    border: Border.all(color: _borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Image.network(widget.imageUrl, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _RoomTextField(label: '表情名称', controller: _nameController),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Button(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.onRename(
                              widget.sticker,
                              _nameController.text,
                            ),
                          ),
                    icon: const Icon(Icons.drive_file_rename_outline),
                    child: const Text('重命名'),
                  ),
                  Button(
                    onPressed: _busy ? null : () => _run(widget.onMoveUp),
                    icon: const Icon(Icons.keyboard_arrow_up),
                    child: const Text('上移'),
                  ),
                  Button(
                    onPressed: _busy ? null : () => _run(widget.onMoveDown),
                    icon: const Icon(Icons.keyboard_arrow_down),
                    child: const Text('下移'),
                  ),
                  Button(
                    onPressed: _busy ? null : () => _run(widget.onDownload),
                    icon: const Icon(Icons.download_outlined),
                    child: const Text('下载'),
                  ),
                  Button(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.onDelete(widget.sticker),
                            close: true,
                          ),
                    tone: ButtonTone.danger,
                    icon: const Icon(Icons.delete_outline),
                    child: const Text('删除'),
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

class _RoomEmptyState extends StatelessWidget {
  const _RoomEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _textMuted, fontSize: 13),
        ),
      ),
    );
  }
}

class _ConfirmActionDialog extends StatelessWidget {
  const _ConfirmActionDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.confirmIcon,
    this.danger = false,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final IconData confirmIcon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: danger ? _danger : _textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: const TextStyle(
                  color: _textSecondary,
                  height: 1.4,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  Button(
                    onPressed: () => Navigator.of(context).pop(true),
                    tone: danger ? ButtonTone.danger : ButtonTone.primary,
                    icon: Icon(confirmIcon),
                    child: Text(confirmLabel),
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

class _StrongConfirmDialog extends StatefulWidget {
  const _StrongConfirmDialog({
    required this.title,
    required this.body,
    required this.expectedText,
    required this.confirmLabel,
    required this.confirmIcon,
  });

  final String title;
  final String body;
  final String expectedText;
  final String confirmLabel;
  final IconData confirmIcon;

  @override
  State<_StrongConfirmDialog> createState() => _StrongConfirmDialogState();
}

class _StrongConfirmDialogState extends State<_StrongConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matched = _controller.text.trim() == widget.expectedText;
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  color: _danger,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.body,
                style: const TextStyle(
                  color: _textSecondary,
                  height: 1.4,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 14),
              _RoomTextField(
                label: '输入房间名确认：${widget.expectedText}',
                controller: _controller,
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  Button(
                    onPressed: matched
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    tone: ButtonTone.danger,
                    icon: Icon(widget.confirmIcon),
                    child: Text(widget.confirmLabel),
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

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog({required this.api});

  final GangApi api;

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final _nameController = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final room = await widget.api.createRoom(name: name);
      if (!mounted) return;
      Navigator.of(context).pop(room);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    required this.api,
    required this.onOpenUserInfo,
    required this.onPendingInvitesChanged,
  });

  final GangApi api;
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
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_search(query));
    });
  }

  Future<void> _search(String query) async {
    final seq = ++_searchSeq;
    try {
      final rooms = await widget.api.searchRooms(query: query);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = rooms;
        _searching = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _searching = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadInvites() async {
    setState(() {
      _loadingInvites = true;
      _inviteError = null;
    });
    try {
      final invites = await widget.api.listRoomInvites();
      if (!mounted) return;
      setState(() {
        _invites = invites;
        _loadingInvites = false;
      });
      widget.onPendingInvitesChanged(invites.isNotEmpty);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inviteError = e.toString();
        _loadingInvites = false;
      });
    }
  }

  Future<void> _join(PublicRoom room) async {
    if (_busyRoomId != null) return;
    setState(() {
      _busyRoomId = room.id;
      _error = null;
    });
    try {
      final result = await widget.api.joinRoom(room.id);
      if (!mounted) return;
      if (result.joined && result.room != null) {
        Navigator.of(context).pop(result.room);
        return;
      }
      // Approval required: mark the row as pending so the button reflects it.
      setState(() => _pendingRoomIds.add(room.id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyRoomId = null);
    }
  }

  Future<void> _openJoined(PublicRoom room) async {
    if (_busyRoomId != null) return;
    setState(() {
      _busyRoomId = room.id;
      _error = null;
    });
    try {
      final detail = await widget.api.getRoom(room.id);
      if (!mounted) return;
      Navigator.of(context).pop(detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyRoomId = null);
    }
  }

  Future<void> _decideInvite(RoomInvite invite, bool accept) async {
    if (_busyInviteId != null || _busyRoomId != null) return;
    setState(() {
      _busyInviteId = invite.id;
      _inviteError = null;
    });
    try {
      final result = await widget.api.reviewRoomInvite(
        inviteId: invite.id,
        accept: accept,
      );
      if (!mounted) return;
      if (accept && result.room != null) {
        Navigator.of(context).pop(result.room);
        return;
      }
      setState(() {
        if (accept && result.pending) {
          _pendingRoomIds.add(invite.room.id);
        }
        _invites = _invites.where((item) => item.id != invite.id).toList();
      });
      widget.onPendingInvitesChanged(_invites.isNotEmpty);
    } catch (e) {
      if (!mounted) return;
      setState(() => _inviteError = e.toString());
    } finally {
      if (mounted) setState(() => _busyInviteId = null);
    }
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
    if (_queryController.text.trim().isNotEmpty) {
      children.add(_buildResults());
    }
    if (_loadingInvites || _invites.isNotEmpty) {
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
    return Column(
      children: [
        for (final entry in _results.asMap().entries) ...[
          _JoinRoomResultTile(
            room: entry.value,
            pending:
                entry.value.joinState == 'pending' ||
                _pendingRoomIds.contains(entry.value.id),
            busy: _busyRoomId == entry.value.id,
            onJoin: () => _join(entry.value),
            onOpen: () => _openJoined(entry.value),
          ),
          if (entry.key != _results.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _JoinRoomResultTile extends StatelessWidget {
  const _JoinRoomResultTile({
    required this.room,
    required this.pending,
    required this.busy,
    required this.onJoin,
    required this.onOpen,
  });

  final PublicRoom room;
  final bool pending;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final approval = room.joinPolicy == 'approval_required';
    final label = room.joined
        ? '进入'
        : pending
        ? '待审批'
        : approval
        ? '申请'
        : '加入';
    final action = room.joined ? onOpen : onJoin;
    final actionable = room.joined || !pending;
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
                  room.rid.isNotEmpty
                      ? '${room.rid} · ${room.memberCount} 名成员'
                      : '${room.memberCount} 名成员',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Button(
            onPressed: actionable && !busy ? action : null,
            loading: busy,
            tone: actionable ? ButtonTone.primary : ButtonTone.neutral,
            height: 34,
            child: busy
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
                  room.rid.isNotEmpty ? '邀请你加入 · RID ${room.rid}' : '邀请你加入',
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

enum _MemberPresenceFilter { all, online, offline }

enum _MemberRoleFilter { all, member, admin }

enum _MemberPresence { live, online, offline }

class _RoomMembersDialog extends StatefulWidget {
  const _RoomMembersDialog({
    required this.api,
    required this.room,
    required this.initialLive,
    required this.canReviewRequests,
    required this.onOpenUserInfo,
    required this.onPendingRequestsChanged,
  });

  final GangApi api;
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
  _MemberPresenceFilter _presenceFilter = _MemberPresenceFilter.all;
  _MemberRoleFilter _roleFilter = _MemberRoleFilter.all;

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

  void _onFilterChanged() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _requestError = null;
    });
    try {
      final members = await _loadAllMembers();
      final live = await _loadLiveSnapshot();
      List<JoinRequest> requests = const [];
      String? requestError;
      if (widget.canReviewRequests) {
        try {
          requests = await widget.api.listJoinRequests(widget.room.id);
        } catch (e) {
          requestError = e.toString();
        }
      }
      if (!mounted) return;
      setState(() {
        _members = members;
        _live = live;
        _requests = requests;
        _requestError = requestError;
        _loading = false;
      });
      if (!widget.canReviewRequests || requestError == null) {
        widget.onPendingRequestsChanged(requests.isNotEmpty);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<RoomMember>> _loadAllMembers() async {
    final members = <RoomMember>[];
    String? cursor;
    var pageCount = 0;
    do {
      final page = await widget.api.listRoomMembers(
        widget.room.id,
        limit: 100,
        cursor: cursor,
      );
      members.addAll(page.members);
      cursor = _nonEmpty(page.nextCursor);
      pageCount += 1;
    } while (cursor != null && pageCount < 50);
    return members;
  }

  Future<LiveState> _loadLiveSnapshot() async {
    try {
      return await widget.api.getLiveState(widget.room.id);
    } catch (_) {
      return widget.initialLive;
    }
  }

  Future<void> _reloadMembersAndLive() async {
    try {
      final members = await _loadAllMembers();
      final live = await _loadLiveSnapshot();
      if (!mounted) return;
      setState(() {
        _members = members;
        _live = live;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _reloadRequests() async {
    if (!widget.canReviewRequests) return;
    try {
      final requests = await widget.api.listJoinRequests(widget.room.id);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _requestError = null;
      });
      widget.onPendingRequestsChanged(requests.isNotEmpty);
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestError = e.toString());
    }
  }

  Future<void> _decide(JoinRequest request, bool approve) async {
    if (_busyRequestIds.contains(request.id)) return;
    setState(() {
      _busyRequestIds.add(request.id);
      _requestError = null;
    });
    try {
      await widget.api.reviewJoinRequest(
        roomId: widget.room.id,
        requestId: request.id,
        approve: approve,
      );
      if (!mounted) return;
      setState(() {
        _changed = true;
        _requests = _requests.where((r) => r.id != request.id).toList();
        _busyRequestIds.remove(request.id);
      });
      widget.onPendingRequestsChanged(_requests.isNotEmpty);
      if (approve) unawaited(_reloadMembersAndLive());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _requestError = e.toString();
        _busyRequestIds.remove(request.id);
      });
    }
  }

  List<RoomMember> _visibleMembers() {
    final query = _filterController.text.trim().toLowerCase();
    final members = _members.where((member) {
      final presence = _presenceFor(member);
      if (_presenceFilter == _MemberPresenceFilter.online &&
          presence == _MemberPresence.offline) {
        return false;
      }
      if (_presenceFilter == _MemberPresenceFilter.offline &&
          presence != _MemberPresence.offline) {
        return false;
      }
      if (!_matchesRoleFilter(member)) return false;
      if (query.isEmpty) return true;
      return _memberSearchRank(member, query) < 99;
    }).toList();
    members.sort((a, b) => _compareMembers(a, b, query));
    return members;
  }

  bool _matchesRoleFilter(RoomMember member) {
    return switch (_roleFilter) {
      _MemberRoleFilter.all => true,
      _MemberRoleFilter.member =>
        !_isSuperuserMember(member) &&
            !_isOwnerMember(member) &&
            !_isAdminMember(member),
      _MemberRoleFilter.admin =>
        _isSuperuserMember(member) ||
            _isOwnerMember(member) ||
            _isAdminMember(member),
    };
  }

  int _compareMembers(RoomMember a, RoomMember b, String query) {
    final presence =
        _presenceRank(_presenceFor(a)) - _presenceRank(_presenceFor(b));
    if (presence != 0) return presence;
    final role = _memberRoleRank(a) - _memberRoleRank(b);
    if (role != 0) return role;
    if (query.isNotEmpty) {
      final search = _memberSearchRank(a, query) - _memberSearchRank(b, query);
      if (search != 0) return search;
    }
    final name = _memberDisplayName(
      a,
    ).toLowerCase().compareTo(_memberDisplayName(b).toLowerCase());
    if (name != 0) return name;
    return (a.user.uid ?? a.user.id).compareTo(b.user.uid ?? b.user.id);
  }

  _MemberPresence _presenceFor(RoomMember member) {
    final live = _live ?? widget.initialLive;
    final inLive = live.participants.any((p) => p.user.id == member.user.id);
    if (inLive) return _MemberPresence.live;
    if (member.isOnline ?? false) return _MemberPresence.online;
    return _MemberPresence.offline;
  }

  int _presenceRank(_MemberPresence value) {
    return switch (value) {
      _MemberPresence.live => 0,
      _MemberPresence.online => 1,
      _MemberPresence.offline => 2,
    };
  }

  int _memberRoleRank(RoomMember member) {
    if (_isSuperuserMember(member)) return 0;
    if (_isOwnerMember(member)) return 1;
    if (_isAdminMember(member)) return 2;
    return 3;
  }

  bool _isSuperuserMember(RoomMember member) {
    final role = member.role.toLowerCase();
    return member.user.isSuperuser || role == 'superuser';
  }

  bool _isOwnerMember(RoomMember member) {
    final role = member.role.toLowerCase();
    return member.user.id == widget.room.createdBy?.id ||
        role == 'owner' ||
        role == 'creator';
  }

  bool _isAdminMember(RoomMember member) {
    final role = member.role.toLowerCase();
    return role == 'admin' || role == 'administrator';
  }

  String _memberDisplayName(RoomMember member) {
    return _nonEmpty(member.roomDisplayName) ??
        _nonEmpty(member.user.roomDisplayName) ??
        _nonEmpty(member.user.displayName) ??
        member.user.username;
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
              _SegmentedFilterRow<_MemberPresenceFilter>(
                options: const [
                  _FilterOption(_MemberPresenceFilter.all, '全部'),
                  _FilterOption(_MemberPresenceFilter.online, '在线'),
                  _FilterOption(_MemberPresenceFilter.offline, '离线'),
                ],
                value: _presenceFilter,
                onChanged: (value) => setState(() => _presenceFilter = value),
              ),
              const SizedBox(height: 8),
              _SegmentedFilterRow<_MemberRoleFilter>(
                options: const [
                  _FilterOption(_MemberRoleFilter.all, '全部'),
                  _FilterOption(_MemberRoleFilter.member, '普通成员'),
                  _FilterOption(_MemberRoleFilter.admin, '管理员'),
                ],
                value: _roleFilter,
                onChanged: (value) => setState(() => _roleFilter = value),
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
    final groups = <_MemberPresence, List<RoomMember>>{
      _MemberPresence.live: [],
      _MemberPresence.online: [],
      _MemberPresence.offline: [],
    };
    for (final member in members) {
      groups[_presenceFor(member)]!.add(member);
    }
    final children = <Widget>[];
    for (final presence in _MemberPresence.values) {
      final items = groups[presence]!;
      if (items.isEmpty) continue;
      if (children.isNotEmpty) children.add(const SizedBox(height: 12));
      children.add(
        _MemberSectionHeader(presence: presence, count: items.length),
      );
      children.add(const SizedBox(height: 8));
      for (final item in items) {
        children.add(
          _RoomMemberTile(
            member: item,
            room: widget.room,
            presence: presence,
            onOpenUserInfo: () => widget.onOpenUserInfo(item.user),
          ),
        );
        if (item != items.last) children.add(const SizedBox(height: 8));
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
        api: widget.api,
        room: widget.room,
        members: _members,
        onOpenUserInfo: widget.onOpenUserInfo,
      ),
    );
  }

  Widget _buildRequestsSection() {
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
            if (_requests.isEmpty)
              const SizedBox(
                height: 42,
                child: Center(
                  child: Text('暂无待审批用户', style: TextStyle(color: _textMuted)),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 156),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _requests.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final request = _requests[index];
                    return _JoinRequestTile(
                      request: request,
                      busy: _busyRequestIds.contains(request.id),
                      onApprove: () => _decide(request, true),
                      onReject: () => _decide(request, false),
                      onOpenUserInfo: () => widget.onOpenUserInfo(
                        request.user.copyWith(roomRole: 'pending'),
                        includeSelectedRoom: false,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
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

  final _MemberPresence presence;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(_presenceIcon(presence), color: _textMuted, size: 16),
        const SizedBox(width: 6),
        Text(
          '${_presenceLabel(presence)} · $count',
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
  final _MemberPresence presence;
  final VoidCallback onOpenUserInfo;

  @override
  Widget build(BuildContext context) {
    final user = member.user;
    final name = _memberTileName(member);
    final meta = _memberTileMeta(member);
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
          _StatusPill(label: _presenceLabel(presence)),
          const SizedBox(width: 8),
          _UserRoleBadge(label: _roomRoleLabel(user, room)),
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
    required this.api,
    required this.room,
    required this.members,
    required this.onOpenUserInfo,
  });

  final GangApi api;
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

  void _onQueryChanged() {
    _debounce?.cancel();
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      _searchSeq += 1;
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    final seq = ++_searchSeq;
    setState(() {
      _searching = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_search(query, seq));
    });
  }

  Future<void> _search(String query, int seq) async {
    try {
      final users = await widget.api.searchUsers(query: query, limit: 20);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = users;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _error = e.toString();
        _searching = false;
      });
    }
  }

  Future<void> _invite(UserSummary user) async {
    if (_existingMember(user.id) != null ||
        _pendingInviteUserIds.contains(user.id) ||
        _busyUserIds.contains(user.id)) {
      return;
    }
    setState(() {
      _busyUserIds.add(user.id);
      _error = null;
    });
    try {
      await widget.api.inviteMember(roomId: widget.room.id, userId: user.id);
      if (!mounted) return;
      setState(() {
        _pendingInviteUserIds.add(user.id);
        _busyUserIds.remove(user.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busyUserIds.remove(user.id);
      });
    }
  }

  RoomMember? _existingMember(String userId) {
    for (final member in widget.members) {
      if (member.user.id == userId) return member;
    }
    return null;
  }

  List<UserSummary> _candidates() {
    final query = _queryController.text.trim().toLowerCase();
    final candidates = <UserSummary>[];
    final seen = <String>{};
    void add(UserSummary user) {
      if (seen.add(user.id)) candidates.add(user);
    }

    for (final user in _results) {
      add(user);
    }
    if (query.isNotEmpty) {
      for (final member in widget.members) {
        if (_memberSearchRank(member, query) < 99) add(member.user);
      }
    }
    return candidates;
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

  Widget _buildBody(List<UserSummary> candidates) {
    if (_searching) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator(color: _cyan)),
      );
    }
    if (_queryController.text.trim().isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text('输入关键词搜索用户', style: TextStyle(color: _textMuted)),
        ),
      );
    }
    if (candidates.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text('未找到用户', style: TextStyle(color: _textMuted)),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: candidates.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = candidates[index];
        final existing = _existingMember(user.id) != null;
        final pending = _pendingInviteUserIds.contains(user.id);
        return _InviteCandidateTile(
          user: user,
          existing: existing,
          pending: pending,
          busy: _busyUserIds.contains(user.id),
          onInvite: existing || pending ? null : () => _invite(user),
          onOpenUserInfo: () => widget.onOpenUserInfo(
            user,
            includeSelectedRoom: existing,
            basic: !existing,
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
                  '${user.uid ?? user.id} · @${user.username}',
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
                    '${user.uid ?? user.id} · @${user.username}',
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
    final avatarColor = _avatarColor(defaultAvatarKey);
    final fallback = Text(
      _initials(label),
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
  final _ToastKind kind;

  @override
  Widget build(BuildContext context) {
    final icon = kind == _ToastKind.success
        ? Icons.check_circle_outline
        : Icons.error_outline;
    final iconColor = kind == _ToastKind.success ? _cyan : _danger;

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

List<RoomCard> _upsertRoomCard(List<RoomCard> rooms, RoomCard room) {
  final next = rooms.where((item) => item.id != room.id).toList();
  return [room, ...next];
}

List<RoomCard> _patchRoomLiveCount(
  List<RoomCard> rooms,
  String roomId,
  LiveState live,
) {
  return rooms
      .map((room) => room.id == roomId ? _withLive(room, live) : room)
      .toList();
}

RoomCard _withLive(RoomCard room, LiveState live) {
  final preview = live.participants.take(5).map((p) => p.user).toList();
  return RoomCard(
    id: room.id,
    name: room.name,
    rid: room.rid,
    visibility: room.visibility,
    remarkName: room.remarkName,
    description: room.description,
    notificationPolicy: room.notificationPolicy,
    avatarUrl: room.avatarUrl,
    defaultAvatarKey: room.defaultAvatarKey,
    memberCount: room.memberCount,
    liveParticipantCount: live.participantCount,
    liveAvatarPreview: preview,
    lastMessage: room.lastMessage,
    unreadCount: room.unreadCount,
    updatedAt: room.updatedAt,
  );
}

List<Message> _replaceMessageByClientId(List<Message> messages, Message sent) {
  var replaced = false;
  final next = messages.map((message) {
    if (message.clientMessageId != sent.clientMessageId) return message;
    replaced = true;
    return sent;
  }).toList();
  if (replaced) return next;
  return [...next, sent];
}

List<Message> _updateMessageByClientId(
  List<Message> messages,
  String clientMessageId,
  Message Function(Message message) update,
) {
  return messages.map((message) {
    if (message.clientMessageId != clientMessageId) return message;
    return update(message);
  }).toList();
}

Message _copyMessage(
  Message message, {
  List<MessageAttachment>? attachments,
  bool? pending,
  bool? failed,
}) {
  return Message(
    id: message.id,
    roomId: message.roomId,
    sender: message.sender,
    clientMessageId: message.clientMessageId,
    type: message.type,
    body: message.body,
    createdAt: message.createdAt,
    attachments: attachments ?? message.attachments,
    pending: pending ?? message.pending,
    failed: failed ?? message.failed,
  );
}

LiveState? _mergeParticipant(LiveState? live, LiveParticipant participant) {
  if (live == null) return null;
  var replaced = false;
  final participants = live.participants.map((item) {
    if (item.liveSessionId != participant.liveSessionId) return item;
    replaced = true;
    return participant;
  }).toList();
  return LiveState(
    roomId: live.roomId,
    participantCount: replaced
        ? live.participantCount
        : live.participantCount + 1,
    participants: replaced ? participants : [...participants, participant],
    updatedAt: DateTime.now().toUtc(),
  );
}

String _roomSubtitle(RoomCard room) {
  final live = room.liveParticipantCount;
  final last = room.lastMessage;
  if (last != null) {
    return '${room.memberCount} members · $live live · ${last.senderDisplayName}: ${last.bodyPreview}';
  }
  return '${room.memberCount} members · $live live';
}

String _initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part.characters.first).join();
  return initials.toUpperCase();
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String _userInfoPrimaryName(UserSummary user) {
  return _nonEmpty(user.roomDisplayName) ??
      _nonEmpty(user.displayName) ??
      user.username;
}

String _roomRoleLabel(UserSummary user, RoomDetail room) {
  final role = _nonEmpty(user.roomRole)?.toLowerCase();
  if (role == 'pending') return '待审批';
  if (user.isSuperuser || role == 'superuser') return '超级用户';
  if (user.id == room.createdBy?.id || role == 'owner' || role == 'creator') {
    return '创建者';
  }
  if (role == 'admin' || role == 'administrator') return '管理员';
  return '普通成员';
}

IconData _presenceIcon(_MemberPresence presence) {
  return switch (presence) {
    _MemberPresence.live => Icons.call,
    _MemberPresence.online => Icons.circle,
    _MemberPresence.offline => Icons.circle_outlined,
  };
}

String _presenceLabel(_MemberPresence presence) {
  return switch (presence) {
    _MemberPresence.live => '语音房',
    _MemberPresence.online => '在线',
    _MemberPresence.offline => '离线',
  };
}

String _memberTileName(RoomMember member) {
  return _nonEmpty(member.roomDisplayName) ??
      _nonEmpty(member.user.roomDisplayName) ??
      _nonEmpty(member.user.displayName) ??
      member.user.username;
}

int _memberSearchRank(RoomMember member, String query) {
  bool contains(String? value) {
    final text = _nonEmpty(value)?.toLowerCase();
    return text != null && text.contains(query);
  }

  if (contains(member.user.uid) || contains(member.user.id)) return 0;
  if (contains(member.roomDisplayName) ||
      contains(member.user.roomDisplayName) ||
      contains(member.user.displayName) ||
      contains(member.user.username)) {
    return 1;
  }
  if (contains(member.remarkName)) return 2;
  return 99;
}

String _memberTileMeta(RoomMember member) {
  final uid = member.user.uid ?? member.user.id;
  final remark = _nonEmpty(member.remarkName);
  final parts = <String>[uid, '@${member.user.username}'];
  if (remark != null) parts.add('备注 $remark');
  return parts.join(' · ');
}

String _commonRoomTitle(UserCommonRoom room) {
  final rid = _nonEmpty(room.rid);
  if (rid == null) return room.name;
  return '$rid · ${room.name}';
}

String _visibilityLabel(String value) {
  return switch (value.toLowerCase()) {
    'public' => '公开',
    _ => '私有',
  };
}

String? _commonRoomMeta(UserCommonRoom room) {
  final roomDisplayName = _nonEmpty(room.roomDisplayName);
  final roleLabel = _roomRoleLabelFromValue(room.roomRole);
  final parts = [?roomDisplayName, ?roleLabel];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

String? _roomRoleLabelFromValue(String? value) {
  return switch (_nonEmpty(value)?.toLowerCase()) {
    'superuser' => '超级用户',
    'owner' || 'creator' => '创建者',
    'admin' || 'administrator' => '管理员',
    'member' => '普通成员',
    'pending' => '待审批',
    _ => null,
  };
}

_GenderMarkData? _genderMark(String? value) {
  return switch (_nonEmpty(value)?.toLowerCase()) {
    'male' ||
    'm' ||
    'man' => const _GenderMarkData(symbol: '♂', color: Color(0xFF5AA7FF)),
    'female' ||
    'f' ||
    'woman' => const _GenderMarkData(symbol: '♀', color: Color(0xFFFF6F8F)),
    _ => null,
  };
}

String _normalizedNotificationPolicy(String value) {
  return switch (value.trim().toLowerCase()) {
    'mention' || 'mentions' || 'only_mentions' || 'mention_only' => 'mentions',
    'mute' || 'muted' || 'do_not_disturb' || 'dnd' => 'muted',
    _ => 'all',
  };
}

String _normalizedVisibility(String value) {
  return switch (value.trim().toLowerCase()) {
    'private' => 'private',
    _ => 'public',
  };
}

String _normalizedJoinPolicy(String value) {
  return switch (value.trim().toLowerCase()) {
    'open' || 'allow_anyone' || 'anyone' => 'open',
    'closed' || 'none' || 'deny_all' || 'no_one' => 'closed',
    _ => 'approval_required',
  };
}

String _stickerNameFromFilename(String filename) {
  final base = _basename(filename);
  final dot = base.lastIndexOf('.');
  final withoutExtension = dot <= 0 ? base : base.substring(0, dot);
  final trimmed = withoutExtension.trim();
  return trimmed.isEmpty ? 'sticker' : trimmed;
}

String _formatMessageTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _basename(String value) {
  final normalized = value.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) return 'file';
  final slash = normalized.lastIndexOf('/');
  final name = slash >= 0 ? normalized.substring(slash + 1) : normalized;
  final query = name.indexOf('?');
  final fragment = name.indexOf('#');
  final end = [
    if (query >= 0) query,
    if (fragment >= 0) fragment,
  ].fold<int>(name.length, (min, value) => value < min ? value : min);
  final clean = name.substring(0, end).trim();
  return clean.isEmpty ? 'file' : clean;
}

String _fileAttachmentTitle(MessageAttachment attachment) {
  final explicitName = attachment.name?.trim();
  if (explicitName != null && explicitName.isNotEmpty) return explicitName;
  final assetName = attachment.asset?.filename?.trim();
  if (assetName != null && assetName.isNotEmpty) return assetName;
  return _filenameFromAssetUrl(attachment.asset?.url) ?? 'file';
}

String? _filenameFromAssetUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final uri = Uri.tryParse(url);
  final raw = uri != null && uri.pathSegments.isNotEmpty
      ? uri.pathSegments.last
      : url;
  final decoded = Uri.decodeComponent(raw);
  final name = _basename(decoded);
  return name.trim().isEmpty ? null : name;
}

String _fileAttachmentMeta(UploadedAsset? asset) {
  if (asset == null) return '';
  final parts = <String>[];
  final mimeType = asset.mimeType.trim();
  if (mimeType.isNotEmpty) parts.add(mimeType);
  final sizeBytes = asset.sizeBytes;
  if (sizeBytes != null) parts.add(_formatFileSize(sizeBytes));
  return parts.join(' - ');
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final digits = value < 10 ? 1 : 0;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

String _formatFileSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 B/s';
  return '${_formatFileSize(bytesPerSecond.round())}/s';
}

String _formatPercent(double value) {
  return '${(value.clamp(0.0, 1.0) * 100).round()}%';
}

String _fileTransferLabel(_FileTransferState transfer) {
  if (transfer.failed) return 'Failed';
  if (transfer.sendingMessage) return 'Sending';

  final status = transfer.paused
      ? 'Paused'
      : transfer.isDownload
      ? 'Downloading'
      : 'Uploading';
  final progress = transfer.hasKnownTotal
      ? _formatPercent(transfer.progress)
      : _formatFileSize(transfer.sentBytes);
  final speed = transfer.paused || transfer.bytesPerSecond <= 0
      ? ''
      : ' - ${_formatFileSpeed(transfer.bytesPerSecond)}';
  return '$status $progress$speed';
}

String _fileDownloadKey(
  Message message,
  MessageAttachment attachment,
  int index,
) {
  final asset = attachment.asset;
  final assetKey =
      asset?.id ??
      asset?.url ??
      attachment.name ??
      _fileAttachmentTitle(attachment);
  return '${message.clientMessageId}:$index:$assetKey';
}

String _mimeTypeFromFilename(String filename) {
  final extension = _extensionOf(filename);
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'json' => 'application/json',
    'zip' => 'application/zip',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'mp4' => 'video/mp4',
    _ => 'application/octet-stream',
  };
}

String _extensionOf(String filename) {
  final name = _basename(filename).toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1);
}

IconData _fileIconForMime(String? mimeType) {
  final value = (mimeType ?? '').toLowerCase();
  if (value.startsWith('image/')) return Icons.image_outlined;
  if (value == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (value.startsWith('audio/')) return Icons.audio_file_outlined;
  if (value.startsWith('video/')) return Icons.video_file_outlined;
  if (value.contains('zip') ||
      value.contains('tar') ||
      value.contains('compressed')) {
    return Icons.folder_zip_outlined;
  }
  if (value.startsWith('text/') || value.contains('json')) {
    return Icons.description_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

Color _avatarColor(String key) {
  return switch (key) {
    'blue-3' => const Color(0xFF526C9F),
    'sky-2' => const Color(0xFF4F7F92),
    'cyan-2' => const Color(0xFF47777A),
    'mint-2' => const Color(0xFF4F7A67),
    'green-2' => const Color(0xFF46695B),
    'lime-2' => const Color(0xFF687A47),
    'amber-2' => const Color(0xFF71614E),
    'orange-2' => const Color(0xFF7A6046),
    'coral-2' => const Color(0xFF7A5952),
    'pink-2' => const Color(0xFF75566F),
    'violet-2' => const Color(0xFF665B7D),
    'indigo-2' => const Color(0xFF5B638A),
    'rose-2' => const Color(0xFF7A5961),
    'teal-2' => const Color(0xFF536E73),
    'olive-2' => const Color(0xFF6A704B),
    'slate-2' => const Color(0xFF5E6472),
    'steel-2' => const Color(0xFF4F6672),
    'graphite-2' => const Color(0xFF5B5D63),
    _ => const Color(0xFF526C9F),
  };
}
