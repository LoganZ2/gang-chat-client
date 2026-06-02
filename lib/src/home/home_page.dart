import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../settings/audio_device_store.dart';
import '../settings/settings_page.dart';
import '../ui/key_button.dart';
import '../ui/title_bar.dart';

const _primaryDark = Color(0xFF14171D);
const _primaryDarkRaised = Color(0xFF1F232C);
const _primaryDarkLow = Color(0xFF181C24);
const _bubbleBackground = Color(0xFF12161D);
const _selectedSurface = Color(0xFF1F2D27);
const _borderColor = Color(0xFF2A2F38);
const _cyan = Color(0xFF6FCFA6);
const _textPrimary = Color(0xFFECEFF1);
const _textSecondary = Color(0xFFB0B8C0);
const _textMuted = Color(0xFF6F7785);
const _danger = Color(0xFFE58383);

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
  });

  final AuthSession session;
  final String apiBaseUrl;
  final AccessTokenProvider accessTokenProvider;
  final Future<void> Function() onLogout;
  final GangApi? api;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late GangApi _api;
  late CurrentUser _currentUser;
  final LiveSession _liveSession = LiveSession();
  final AudioDeviceStore _audioDeviceStore = const AudioDeviceStore();

  final _messageController = TextEditingController();
  final _messageFocus = FocusNode();
  final Map<String, String> _messageDrafts = {};

  List<RoomCard> _rooms = [];
  List<Message> _messages = [];
  RoomDetail? _selectedRoom;
  LiveState? _live;
  String? _selectedRoomId;
  String? _joinedLiveRoomId;
  String? _error;
  // Transient, centered toast (antd Message style) for action errors. Kept
  // separate from _error (which drives the full-pane load-failure view).
  String? _toast;
  Timer? _toastTimer;
  bool _loadingRooms = true;
  bool _loadingRoom = false;
  bool _sending = false;
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
    _startLiveStream();
    unawaited(_restoreStoredAudioSettings());
  }

  void _onMessageDraftChanged() {
    final roomId = _selectedRoomId;
    if (roomId == null) return;
    _messageDrafts[roomId] = _messageController.text;
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
    final selected = _selectedRoomId;
    if (selected != null) unawaited(_refreshLiveSilently(selected));
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
    setState(() {
      _selectedRoom = current.copyWithRole(role);
    });
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
    _loadRooms();
  }

  GangApi _newApiClient() {
    final api = widget.api;
    if (api != null) return api;
    return GangApiClient(
      baseUrl: widget.apiBaseUrl,
      accessTokenProvider: widget.accessTokenProvider,
    );
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

  Future<void> _openRoom(RoomCard room, {bool joinLive = false}) async {
    if (_loadingRoom && _selectedRoomId == room.id) return;
    _saveCurrentMessageDraft();
    setState(() {
      _settingsOpen = false;
      _selectedRoomId = room.id;
      _loadingRoom = true;
      _error = null;
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
      if (joinLive) await _joinLive('room_card_speaker');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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
    await _openRoom(created.toCard());
  }

  /// Opens the search-and-join dialog. On a successful join the dialog returns
  /// the new room detail; we add it to the list and open it. A pending
  /// (approval-required) join returns null and the dialog shows its own state.
  Future<void> _joinRoom() async {
    final joined = await showDialog<RoomDetail>(
      context: context,
      builder: (context) => _JoinRoomDialog(api: _api),
    );
    if (joined == null || !mounted) return;
    setState(() {
      _rooms = _upsertRoomCard(_rooms, joined.toCard());
    });
    await _openRoom(joined.toCard());
  }

  /// Opens the admin join-request review queue for the current room. After it
  /// closes (some requests may have been approved, adding members), refresh the
  /// room so the member count stays accurate.
  Future<void> _reviewJoinRequests() async {
    final room = _selectedRoom;
    if (room == null) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _JoinRequestsDialog(api: _api, roomId: room.id, roomName: room.name),
    );
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

  Future<void> _sendMessage() async {
    final room = _selectedRoom;
    if (room == null || _sending) return;

    final body = _messageController.text.trimRight();
    if (body.trim().isEmpty) return;

    final clientMessageId = newClientId('cmsg');
    final local = Message.local(
      roomId: room.id,
      sender: _currentUser.toSummary(),
      clientMessageId: clientMessageId,
      body: body,
    );

    setState(() {
      _sending = true;
      _messages = [..._messages, local];
      _messageController.clear();
      _error = null;
    });

    try {
      final sent = await _api.sendMessage(
        roomId: room.id,
        clientMessageId: clientMessageId,
        body: body,
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
      } catch (e) {
        // We never reached LiveKit, so no webhook will fire. Make sure the
        // transport is fully torn down; the server-side live_participants row
        // is reconciled by the webhook once any prior connection drops, and
        // by the next joinLive snapshot.
        try {
          await _liveSession.disconnect();
        } catch (_) {}
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
    _api.close();
    _messageController.removeListener(_onMessageDraftChanged);
    _messageController.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  /// Shows a transient, horizontally-centered message near the top (antd
  /// Message style) that auto-dismisses. Used for action errors so they no
  /// longer sit in a top bar that overlaps the custom window controls.
  void _showToast(String message) {
    setState(() => _toast = message);
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
                  child: _MessageToast(message: _toast!),
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
              onReviewRequests: room.isAdmin ? _reviewJoinRequests : null,
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
                    localUserId: _currentUser.id,
                  )
                : _ChatPane(
                    roomId: _selectedRoomId!,
                    api: _api,
                    messages: _messages,
                    currentUserId: _currentUser.id,
                    controller: _messageController,
                    focusNode: _messageFocus,
                    sending: _sending,
                    onSend: _sendMessage,
                  ),
          ),
        ],
      ),
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
                    child: KeyButton(
                      width: double.infinity,
                      onPressed: onCreateRoom,
                      icon: const Icon(Icons.add),
                      tone: KeyButtonTone.primary,
                      child: const Text('创建房间'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: KeyButton(
                      width: double.infinity,
                      onPressed: onJoinRoom,
                      icon: const Icon(Icons.group_add),
                      child: const Text('加入房间'),
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
      child: KeySurface(
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
    return KeySurface(
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
                      label: room.name,
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
                            room.name,
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
                        label: widget.room.name,
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
    this.onReviewRequests,
  });

  final RoomDetail room;
  final LiveState live;
  final bool joined;
  final bool joining;
  final VoidCallback onExpand;
  final VoidCallback onJoin;
  // When non-null the current user is an admin and a join-request review
  // button is shown; null hides it for non-admins.
  final VoidCallback? onReviewRequests;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final tight = constraints.maxWidth < 300;
        return KeySurface(
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
          cutCorner: KeyCorner.topRight,
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
              if (onReviewRequests != null) ...[
                Transform.translate(
                  offset: const Offset(0, 2),
                  child: KeyIconButton(
                    tooltip: '加入申请',
                    onPressed: onReviewRequests,
                    icon: const Icon(Icons.how_to_reg),
                    size: 36,
                  ),
                ),
                const SizedBox(width: 10),
              ],
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
              ? KeyIconButton(
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
                  tone: KeyButtonTone.primary,
                  size: 36,
                )
              : KeyButton(
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
                  tone: KeyButtonTone.primary,
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

class _ChatPane extends StatefulWidget {
  const _ChatPane({
    required this.roomId,
    required this.api,
    required this.messages,
    required this.currentUserId,
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final String roomId;
  final GangApi api;
  final List<Message> messages;
  final String currentUserId;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  State<_ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<_ChatPane> {
  _ComposerPanel? _openPanel;
  _StickerSource _stickerSource = _StickerSource.personal;
  List<StickerPack> _personalStickerPacks = const [];
  List<StickerPack> _roomStickerPacks = const [];
  bool _loadingStickerPacks = false;
  String? _stickerPackError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStickerPacks());
  }

  @override
  void didUpdateWidget(_ChatPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _openPanel = null;
      unawaited(_loadStickerPacks());
    } else if (oldWidget.api != widget.api) {
      unawaited(_loadStickerPacks());
    }
  }

  Future<void> _loadStickerPacks() async {
    final roomId = widget.roomId;
    setState(() {
      _loadingStickerPacks = true;
      _stickerPackError = null;
    });
    try {
      final packs = await Future.wait([
        widget.api.listStickerPacks(scope: 'personal'),
        widget.api.listStickerPacks(scope: 'room', roomId: roomId),
      ]);
      if (!mounted || widget.roomId != roomId) return;
      setState(() {
        _personalStickerPacks = packs[0];
        _roomStickerPacks = packs[1];
      });
    } catch (e) {
      if (!mounted || widget.roomId != roomId) return;
      setState(() => _stickerPackError = e.toString());
    } finally {
      if (mounted && widget.roomId == roomId) {
        setState(() => _loadingStickerPacks = false);
      }
    }
  }

  void _closePanel() {
    if (_openPanel == null) return;
    setState(() => _openPanel = null);
  }

  void _togglePanel(_ComposerPanel panel) {
    setState(() {
      _openPanel = _openPanel == panel ? null : panel;
    });
  }

  void _insertComposerText(String value) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    var start = text.length;
    var end = text.length;

    if (selection.isValid) {
      start = selection.start;
      end = selection.end;
      if (start < 0) start = 0;
      if (end < 0) end = 0;
      if (start > text.length) start = text.length;
      if (end > text.length) end = text.length;
      if (start > end) {
        final previousStart = start;
        start = end;
        end = previousStart;
      }
    }

    final next = text.replaceRange(start, end, value);
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    widget.focusNode.requestFocus();
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
      onFile: () => _togglePanel(_ComposerPanel.file),
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

    return _ComposerPanelSurface(
      panel: panel,
      tipColor: panel == _ComposerPanel.stickers
          ? (_stickerSource == _StickerSource.personal
                ? _selectedSurface
                : _bubbleBackground)
          : null,
      child: switch (panel) {
        _ComposerPanel.stickers => _StickerPanel(
          source: _stickerSource,
          personalPacks: _personalStickerPacks,
          roomPacks: _roomStickerPacks,
          loading: _loadingStickerPacks,
          error: _stickerPackError,
          onRefresh: _loadStickerPacks,
          onSourceChanged: (source) => setState(() => _stickerSource = source),
          onStickerSelected: _insertComposerText,
        ),
        _ComposerPanel.voice => const _PlaceholderPanel(text: '语音输入开发中'),
        _ComposerPanel.file => const _PlaceholderPanel(text: '文件上传开发中'),
        _ComposerPanel.tools => const _ToolboxPanel(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDarkLow,
      child: Column(
        children: [
          Expanded(
            child: widget.messages.isEmpty
                ? const Center(
                    child: Text('还没有消息', style: TextStyle(color: _textMuted)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                    itemCount: widget.messages.length,
                    itemBuilder: (context, index) {
                      final message = widget.messages[index];
                      return _MessageBubble(
                        message: message,
                        mine: message.sender.id == widget.currentUserId,
                      );
                    },
                  ),
          ),
          TapRegion(
            onTapOutside: (_) => _closePanel(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) {
                    if (currentChild != null) return currentChild;
                    return Stack(
                      alignment: Alignment.bottomRight,
                      clipBehavior: Clip.none,
                      children: previousChildren,
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_openPanel),
                    child: _buildPanel(),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  color: _primaryDarkLow,
                  child: _buildComposerInput(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
  final VoidCallback onFile;
  final VoidCallback onTools;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ComposerIconButton(
          tooltip: '表情包',
          onPressed: onStickers,
          selected: openPanel == _ComposerPanel.stickers,
          icon: const Icon(Icons.emoji_emotions_outlined),
        ),
        const SizedBox(width: 8),
        _ComposerIconButton(
          tooltip: '语音',
          onPressed: onVoice,
          interactive: true,
          selected: false,
          icon: const Icon(Icons.mic_none),
        ),
        const SizedBox(width: 8),
        _ComposerIconButton(
          tooltip: '文件上传',
          onPressed: onFile,
          selected: false,
          icon: const Icon(Icons.attach_file),
        ),
        const SizedBox(width: 8),
        _ComposerIconButton(
          tooltip: '工具箱',
          onPressed: onTools,
          selected: openPanel == _ComposerPanel.tools,
          icon: const Icon(Icons.extension_outlined),
        ),
        const SizedBox(width: 8),
        KeyIconButton(
          tooltip: '发送',
          onPressed: sending ? null : onSend,
          loading: sending,
          tone: KeyButtonTone.primary,
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

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    required this.selected,
    this.interactive = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;
  final bool selected;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    const size = 40.0;

    return SizedBox(
      width: size,
      child: KeySurface(
        tooltip: tooltip,
        onPressed: onPressed,
        interactive: interactive,
        selected: selected,
        height: size,
        padding: EdgeInsets.zero,
        backgroundColor: _primaryDarkRaised,
        selectedBackgroundColor: _selectedSurface,
        pressedBackgroundColor: _selectedSurface,
        borderColor: _primaryDarkRaised,
        selectedBorderColor: _cyan,
        child: IconTheme.merge(
          data: IconThemeData(color: selected ? _cyan : _textPrimary, size: 20),
          child: Center(child: icon),
        ),
      ),
    );
  }
}

class _ComposerPanelSurface extends StatelessWidget {
  const _ComposerPanelSurface({
    required this.panel,
    required this.child,
    this.tipColor,
  });

  final _ComposerPanel panel;
  final Widget child;
  final Color? tipColor;

  static const double _tipWidth = 18;
  static const double _tipHeight = 10;
  static const double _tipOverlap = 1;
  static const double _tipBottomClearance = 4;
  static const double _surfaceYOffset = 2;
  static const double _tipSideInset = 12;
  static const double _horizontalInset = 18;
  static const double _bubbleWidth = 360;

  // Distance from the right edge of the action bar (== bubble's right edge)
  // to the center of each composer button. Keep in sync with
  // _ComposerActionBar's layout: send(44) | gap(8) | tools(40) | gap(8) |
  // file(40) | gap(8) | voice(40) | gap(8) | stickers(40).
  static const Map<_ComposerPanel, double> _buttonCenterFromRight = {
    _ComposerPanel.tools: 72,
    _ComposerPanel.file: 120,
    _ComposerPanel.voice: 168,
    _ComposerPanel.stickers: 216,
  };

  double _tipRightPadding() {
    final targetCenterFromRight = _buttonCenterFromRight[panel]!;
    final raw = targetCenterFromRight - (_tipWidth / 2);
    final maxPadding = _bubbleWidth - _tipWidth - _tipSideInset;
    return raw.clamp(_tipSideInset, maxPadding).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, _surfaceYOffset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _horizontalInset,
          0,
          _horizontalInset,
          _tipHeight + _surfaceYOffset + _tipBottomClearance,
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: _bubbleWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _bubbleBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                child,
                Positioned(
                  right: _tipRightPadding(),
                  bottom: -(_tipHeight - _tipOverlap),
                  child: CustomPaint(
                    size: const Size(_tipWidth, _tipHeight),
                    painter: _BubbleTipPainter(
                      color: tipColor ?? _bubbleBackground,
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
  final ValueChanged<String> onStickerSelected;

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
        _SourceSwitch(
          firstLabel: '个人表情包',
          secondLabel: '房间表情包',
          firstSelected: source == _StickerSource.personal,
          onFirst: () => onSourceChanged(_StickerSource.personal),
          onSecond: () => onSourceChanged(_StickerSource.room),
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
            onPressed: () => onStickerSelected('[${sticker.name}]'),
          ),
      ],
    );
  }
}

class _BubbleTipPainter extends CustomPainter {
  const _BubbleTipPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleTipPainter oldDelegate) {
    return oldDelegate.color != color;
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

class _SourceSwitch extends StatelessWidget {
  const _SourceSwitch({
    required this.firstLabel,
    required this.secondLabel,
    required this.firstSelected,
    required this.onFirst,
    required this.onSecond,
  });

  final String firstLabel;
  final String secondLabel;
  final bool firstSelected;
  final VoidCallback onFirst;
  final VoidCallback onSecond;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(8),
        bottomRight: Radius.circular(8),
      ),
      child: SizedBox(
        height: _SourceSwitchButton.height,
        child: Row(
          children: [
            Expanded(
              child: _SourceSwitchButton(
                onPressed: onFirst,
                selected: firstSelected,
                label: firstLabel,
              ),
            ),
            Expanded(
              child: _SourceSwitchButton(
                onPressed: onSecond,
                selected: !firstSelected,
                label: secondLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceSwitchButton extends StatelessWidget {
  const _SourceSwitchButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  static const height = 34.0;

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _selectedSurface : Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: height,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? _cyan : _textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerButton extends StatelessWidget {
  const _StickerButton({required this.sticker, required this.onPressed});

  final Sticker sticker;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final imageUrl = AppConfigScope.of(context).resolveAssetUrl(
      sticker.asset.thumbnailUrl ?? sticker.asset.url,
    );
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
          KeyIconButton(
            tooltip: '刷新表情包',
            onPressed: () => unawaited(onRefresh()),
            icon: const Icon(Icons.refresh),
            size: 32,
            backgroundColor: _bubbleBackground,
            borderColor: _bubbleBackground,
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
      child: KeySurface(
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
  const _MessageBubble({required this.message, required this.mine});

  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
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
              _Avatar(
                label: message.sender.displayName,
                imageUrl: AppConfigScope.of(
                  context,
                ).resolveAssetUrl(message.sender.avatarUrl),
                defaultAvatarKey: message.sender.defaultAvatarKey,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
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
                    SelectableText(
                      message.body,
                      cursorColor: _cyan,
                      selectionColor: _cyan.withValues(alpha: 0.28),
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    if (message.pending || message.failed) ...[
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
    this.cameraTrack,
  });

  final LiveParticipant participant;
  final bool speaking;
  final LiveVideoTrack? cameraTrack;

  @override
  Widget build(BuildContext context) {
    final broadcasting = participant.cameraOn || participant.screenSharing;
    final highlight = speaking || broadcasting;
    final cameraTrack = this.cameraTrack;
    // When a live camera track is available, fill the tile with the video and
    // overlay the name + status; otherwise fall back to the avatar layout.
    if (cameraTrack != null) {
      return KeySurface(
        height: 148,
        interactive: true,
        pressRequiresHover: true,
        onPressed: () {},
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
    return KeySurface(
      height: 148,
      interactive: broadcasting,
      pressRequiresHover: true,
      onPressed: broadcasting ? () {} : null,
      backgroundColor: _primaryDarkRaised,
      selectedBackgroundColor: _primaryDarkRaised,
      borderColor: _borderColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Avatar(
            label: participant.user.displayName,
            imageUrl: AppConfigScope.of(
              context,
            ).resolveAssetUrl(participant.user.avatarUrl),
            defaultAvatarKey: participant.user.defaultAvatarKey,
            size: 54,
            borderColor: highlight ? _cyan : _borderColor,
            borderWidth: highlight ? 2.4 : 1,
          ),
          const SizedBox(height: 12),
          Text(
            participant.user.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: highlight ? _textPrimary : _textSecondary,
              fontWeight: FontWeight.w700,
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
                  KeyButton(
                    onPressed: () => Navigator.of(context).pop(),
                    height: 38,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  KeyButton(
                    onPressed: _selectedId == null ? null : _confirm,
                    tone: KeyButtonTone.primary,
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
    return KeySurface(
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
        ? KeyButtonTone.danger
        : active
        ? KeyButtonTone.primary
        : KeyButtonTone.neutral;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: KeyIconButton(
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
                  KeyButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    height: 38,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  KeyButton(
                    onPressed: _submit,
                    loading: _busy,
                    tone: KeyButtonTone.primary,
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
  const _JoinRoomDialog({required this.api});

  final GangApi api;

  @override
  State<_JoinRoomDialog> createState() => _JoinRoomDialogState();
}

class _JoinRoomDialogState extends State<_JoinRoomDialog> {
  final _queryController = TextEditingController();
  Timer? _debounce;
  int _searchSeq = 0;
  bool _searching = false;
  String? _error;
  String? _busyRoomId;
  List<PublicRoom> _results = const [];
  final Set<String> _pendingRoomIds = <String>{};

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
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  KeyIconButton(
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
                            contentPadding: EdgeInsets.symmetric(vertical: 13),
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
              if (_queryController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Flexible(child: _buildResults()),
              ],
            ],
          ),
        ),
      ),
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
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final room = _results[index];
        final pending =
            room.joinState == 'pending' || _pendingRoomIds.contains(room.id);
        return _JoinRoomResultTile(
          room: room,
          pending: pending,
          busy: _busyRoomId == room.id,
          onJoin: () => _join(room),
        );
      },
    );
  }
}

class _JoinRoomResultTile extends StatelessWidget {
  const _JoinRoomResultTile({
    required this.room,
    required this.pending,
    required this.busy,
    required this.onJoin,
  });

  final PublicRoom room;
  final bool pending;
  final bool busy;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final approval = room.joinPolicy == 'approval_required';
    final label = room.joined
        ? '已加入'
        : pending
        ? '待审批'
        : approval
        ? '申请'
        : '加入';
    final actionable = !room.joined && !pending;
    return KeySurface(
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
          KeyButton(
            onPressed: actionable && !busy ? onJoin : null,
            loading: busy,
            tone: actionable ? KeyButtonTone.primary : KeyButtonTone.neutral,
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

/// Admin-only review queue for a room's pending join requests. Lists each
/// pending requester and lets the admin approve (adds them as a member) or
/// reject. Pops `true` if any decision was made so the caller can refresh the
/// room's member count.
class _JoinRequestsDialog extends StatefulWidget {
  const _JoinRequestsDialog({
    required this.api,
    required this.roomId,
    required this.roomName,
  });

  final GangApi api;
  final String roomId;
  final String roomName;

  @override
  State<_JoinRequestsDialog> createState() => _JoinRequestsDialogState();
}

class _JoinRequestsDialogState extends State<_JoinRequestsDialog> {
  List<JoinRequest> _requests = const [];
  final Set<String> _busyIds = <String>{};
  bool _loading = true;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await widget.api.listJoinRequests(widget.roomId);
      if (!mounted) return;
      setState(() {
        _requests = requests;
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

  Future<void> _decide(JoinRequest request, bool approve) async {
    if (_busyIds.contains(request.id)) return;
    setState(() {
      _busyIds.add(request.id);
      _error = null;
    });
    try {
      await widget.api.reviewJoinRequest(
        roomId: widget.roomId,
        requestId: request.id,
        approve: approve,
      );
      if (!mounted) return;
      setState(() {
        _changed = true;
        _requests = _requests.where((r) => r.id != request.id).toList();
        _busyIds.remove(request.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busyIds.remove(request.id);
      });
    }
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
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
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
                          '加入申请',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.roomName,
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
                  KeyIconButton(
                    onPressed: () => Navigator.of(context).pop(_changed),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    size: 32,
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: _danger)),
              ],
              const SizedBox(height: 14),
              Flexible(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(color: _cyan)),
      );
    }
    if (_requests.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text('暂无加入申请', style: TextStyle(color: _textMuted)),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final request = _requests[index];
        return _JoinRequestTile(
          request: request,
          busy: _busyIds.contains(request.id),
          onApprove: () => _decide(request, true),
          onReject: () => _decide(request, false),
        );
      },
    );
  }
}

class _JoinRequestTile extends StatelessWidget {
  const _JoinRequestTile({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final JoinRequest request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final user = request.user;
    return KeySurface(
      height: 64,
      backgroundColor: _primaryDarkLow,
      selectedBackgroundColor: _primaryDarkLow,
      borderColor: _borderColor,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _Avatar(
            label: user.displayName,
            imageUrl: AppConfigScope.of(
              context,
            ).resolveAssetUrl(user.avatarUrl),
            defaultAvatarKey: user.defaultAvatarKey,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
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
                  '@${user.username}',
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
            KeyIconButton(
              tooltip: '拒绝',
              onPressed: onReject,
              icon: const Icon(Icons.close),
              tone: KeyButtonTone.danger,
              size: 34,
            ),
            const SizedBox(width: 8),
            KeyIconButton(
              tooltip: '通过',
              onPressed: onApprove,
              icon: const Icon(Icons.check),
              tone: KeyButtonTone.primary,
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
            KeyButton(
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
  const _MessageToast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
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
                const Icon(Icons.error_outline, color: _danger, size: 18),
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

String _formatMessageTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
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
