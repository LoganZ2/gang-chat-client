part of 'room_management.dart';

class RoomMembersDialog extends StatefulWidget {
  const RoomMembersDialog({
    super.key,
    required this.controller,
    required this.room,
    required this.currentUser,
    required this.initialLive,
    this.reloadToken = 0,
    this.embedded = false,
    this.onClose,
    this.onChanged,
  });

  final RoomsController controller;
  final RoomDetail room;
  final CurrentUser currentUser;
  final LiveState initialLive;

  /// Incremented by the host when a realtime event (join requests updated, role
  /// changed) means this panel's data is stale. A change triggers a reload.
  final int reloadToken;

  final bool embedded;
  final VoidCallback? onClose;
  final VoidCallback? onChanged;

  @override
  State<RoomMembersDialog> createState() => _RoomMembersDialogState();
}

class _RoomMembersDialogState extends State<RoomMembersDialog> {
  final _memberSearchController = TextEditingController();
  final _inviteSearchController = TextEditingController();
  final _busyRequestIds = <String>{};
  final _busyMemberIds = <String>{};
  final _busyInviteUserIds = <String>{};
  final _pendingInviteUserIds = <String>{};

  Timer? _inviteSearchDebounce;
  int _inviteSearchSeq = 0;

  late RoomDetail _room;
  late LiveState _live;
  List<RoomMember> _members = const [];
  List<JoinRequest> _requests = const [];
  List<UserSummary> _inviteResults = const [];

  bool _loading = true;
  bool _searchingInvites = false;
  bool _changed = false;
  String _memberQuery = '';
  String _inviteQuery = '';
  String? _error;
  String? _requestError;
  String? _inviteError;
  String? _notice;
  member_filter.RoomMemberPresenceFilter _presenceFilter =
      member_filter.RoomMemberPresenceFilter.all;
  member_filter.RoomMemberRoleFilter _roleFilter =
      member_filter.RoomMemberRoleFilter.all;

  bool get _canReviewRequests => room_display
      .roomAccessState(room: _room, currentUser: widget.currentUser)
      .canReviewJoinRequests;

  bool get _canEditCreatorOnly => room_display
      .roomManagementPermissionState(
        room: _room,
        currentUser: widget.currentUser,
      )
      .canEditCreatorOnly;

  bool get _canInviteMembers =>
      room_invites.roomInvitesEnabled(_room.joinPolicy);

  bool get _canManageMembers => room_display
      .roomAccessState(room: _room, currentUser: widget.currentUser)
      .canManageRoom;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _live = widget.initialLive;
    _memberSearchController.addListener(_onMemberSearchChanged);
    _inviteSearchController.addListener(_onInviteSearchChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _inviteSearchDebounce?.cancel();
    _memberSearchController.dispose();
    _inviteSearchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RoomMembersDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveChanged = !identical(widget.initialLive, oldWidget.initialLive);
    final liveBelongsToRoom = widget.initialLive.roomId == widget.room.id;
    // The host bumps reloadToken when a realtime event invalidates this panel
    // (join requests changed, or the current user's role changed). Re-pull the
    // member/request lists, and adopt the freshest room so permission checks
    // (canReviewRequests, canManageMembers) reflect the new role.
    if (widget.reloadToken != oldWidget.reloadToken ||
        !identical(widget.room, oldWidget.room)) {
      _room = widget.room;
      if (liveChanged && liveBelongsToRoom) {
        _live = widget.initialLive;
      }
      unawaited(_load());
    } else if (liveChanged && liveBelongsToRoom) {
      setState(() => _live = widget.initialLive);
    }
  }

  void _close() {
    if (widget.embedded) {
      if (_changed) widget.onChanged?.call();
      widget.onClose?.call();
      return;
    }
    Navigator.of(context).pop(_changed);
  }

  void _onMemberSearchChanged() {
    setState(() => _memberQuery = _memberSearchController.text);
  }

  void _onInviteSearchChanged() {
    if (!_canInviteMembers) return;
    final query = _inviteSearchController.text.trim();
    setState(() {
      _inviteQuery = query;
      _inviteError = null;
      if (query.isEmpty) {
        _inviteResults = const [];
        _searchingInvites = false;
      }
    });
    _inviteSearchDebounce?.cancel();
    if (query.length < 2) {
      _inviteSearchSeq += 1;
      return;
    }
    final seq = ++_inviteSearchSeq;
    _inviteSearchDebounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_searchInviteCandidates(query, seq));
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _requestError = null;
    });
    try {
      final snapshot = await widget.controller.loadRoomMembersSnapshot(
        roomId: _room.id,
        fallbackLive: _live,
        includeJoinRequests: _canReviewRequests,
      );
      if (!mounted) return;
      setState(() {
        _members = snapshot.members;
        _live = snapshot.live;
        _requests = snapshot.joinRequests;
        _requestError = snapshot.joinRequestsError;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _searchInviteCandidates(String query, int seq) async {
    if (!_canInviteMembers) return;
    setState(() {
      _searchingInvites = true;
      _inviteError = null;
    });
    try {
      final results = await widget.controller.searchUsers(
        query: query,
        limit: 20,
      );
      if (!mounted || seq != _inviteSearchSeq) return;
      setState(() {
        _inviteResults = results;
        _searchingInvites = false;
      });
    } catch (error) {
      if (!mounted || seq != _inviteSearchSeq) return;
      setState(() {
        _searchingInvites = false;
        _inviteError = error.toString();
      });
    }
  }

  Future<void> _invite(UserSummary user) async {
    if (!_canInviteMembers) return;
    if (_busyInviteUserIds.contains(user.id)) return;
    if (_pendingInviteUserIds.contains(user.id)) return;
    if (_members.any((member) => member.user.id == user.id)) return;
    setState(() {
      _busyInviteUserIds.add(user.id);
      _inviteError = null;
      _notice = null;
    });
    try {
      await widget.controller.inviteMember(roomId: _room.id, userId: user.id);
      if (!mounted) return;
      setState(() {
        _busyInviteUserIds.remove(user.id);
        _pendingInviteUserIds.add(user.id);
        _changed = true;
        _notice = '邀请已发送';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyInviteUserIds.remove(user.id);
        _inviteError = error.toString();
      });
    }
  }

  Future<void> _reviewRequest(JoinRequest request, bool approve) async {
    if (_busyRequestIds.contains(request.id)) return;
    setState(() {
      _busyRequestIds.add(request.id);
      _requestError = null;
      _notice = null;
    });
    try {
      await widget.controller.reviewJoinRequest(
        roomId: _room.id,
        requestId: request.id,
        approve: approve,
      );
      if (!mounted) return;
      setState(() {
        _busyRequestIds.remove(request.id);
        _requests = [
          for (final item in _requests)
            if (item.id != request.id) item,
        ];
        _changed = true;
        _notice = approve ? '申请已通过' : '申请已拒绝';
      });
      if (approve) unawaited(_load());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyRequestIds.remove(request.id);
        _requestError = error.toString();
      });
    }
  }

  Future<void> _showJoinRequestDetails(JoinRequest request) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _JoinRequestDetailsDialog(request: request),
    );
  }

  Future<void> _setMemberRole(RoomMember member, String role) async {
    if (_busyMemberIds.contains(member.user.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmDialog(
        title: member_filter.roomMemberRoleUpdateConfirmTitle(role),
        message: member_filter.roomMemberRoleUpdateConfirmBody(member, role),
        confirmLabel: member_filter.roomMemberRoleUpdateConfirmLabel(role),
        danger: role != 'admin',
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busyMemberIds.add(member.user.id);
      _error = null;
      _notice = null;
    });
    try {
      final updated = await widget.controller.updateRoomMemberRole(
        roomId: _room.id,
        userId: member.user.id,
        role: role,
      );
      if (!mounted) return;
      setState(() {
        _busyMemberIds.remove(member.user.id);
        _members = member_filter.replaceRoomMember(_members, updated);
        _changed = true;
        _notice = member_filter.roomMemberRoleUpdateNotice(role);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyMemberIds.remove(member.user.id);
        _error = error.toString();
      });
    }
  }

  Future<void> _transferCreator(RoomMember member) async {
    if (_busyMemberIds.contains(member.user.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmDialog(
        title: member_filter.transferCreatorDialogTitle(),
        message: member_filter.transferCreatorConfirmBody(member),
        confirmLabel: member_filter.transferCreatorConfirmLabel(),
        danger: true,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busyMemberIds.add(member.user.id);
      _error = null;
      _notice = null;
    });
    try {
      final updated = await widget.controller.transferRoomCreator(
        roomId: _room.id,
        userId: member.user.id,
      );
      if (!mounted) return;
      setState(() {
        _busyMemberIds.remove(member.user.id);
        _room = updated;
        _changed = true;
        _notice = member_filter.transferCreatorSuccessNotice();
      });
      unawaited(_load());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyMemberIds.remove(member.user.id);
        _error = error.toString();
      });
    }
  }

  Future<void> _removeMember(RoomMember member) async {
    if (_busyMemberIds.contains(member.user.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmDialog(
        title: member_filter.removeRoomMemberConfirmTitle(),
        message: member_filter.removeRoomMemberConfirmBody(member),
        confirmLabel: member_filter.removeRoomMemberConfirmLabel(),
        danger: true,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busyMemberIds.add(member.user.id);
      _error = null;
      _notice = null;
    });
    try {
      await widget.controller.removeRoomMember(
        roomId: _room.id,
        userId: member.user.id,
      );
      if (!mounted) return;
      final patch = member_filter.roomMemberRemovedSucceeded(
        room: _room,
        members: _members,
        removed: member,
        busyMemberIds: _busyMemberIds,
      );
      setState(() {
        _busyMemberIds
          ..clear()
          ..addAll(patch.busyMemberIds);
        _members = patch.members;
        _changed = patch.changed;
        _error = patch.error;
        _notice = patch.notice;
      });
    } catch (error) {
      if (!mounted) return;
      final patch = member_filter.roomMemberRemoveFailed(
        room: _room,
        members: _members,
        changed: _changed,
        userId: member.user.id,
        busyMemberIds: _busyMemberIds,
        failure: error,
      );
      setState(() {
        _busyMemberIds
          ..clear()
          ..addAll(patch.busyMemberIds);
        _error = patch.error;
        _notice = patch.notice;
      });
    }
  }

  List<RoomMember> _visibleMembers() {
    return member_filter.visibleRoomMembers(
      members: _members,
      live: _live,
      presenceFilter: _presenceFilter,
      roleFilter: _roleFilter,
      query: _memberQuery,
      ownerUserId: _room.createdBy?.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RoomDialogShell(
      title: '成员',
      icon: Icons.group_outlined,
      maxWidth: _dialogMaxWidth,
      maxHeight: _dialogMaxHeight,
      embedded: widget.embedded,
      onClose: _close,
      headerAction: _canReviewRequests
          ? ButtonIcon(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              size: 38,
            )
          : null,
      child: SettingsList(
        children: [
          if (_notice != null)
            _NoticeStrip(message: _notice!, icon: Icons.check_circle_outline),
          if (_error != null) _NoticeStrip(message: _error!, danger: true),
          _MemberFilters(
            controller: _memberSearchController,
            presenceFilter: _presenceFilter,
            roleFilter: _roleFilter,
            onPresenceChanged: (value) =>
                setState(() => _presenceFilter = value),
            onRoleChanged: (value) => setState(() => _roleFilter = value),
          ),
          SizedBox(height: 220, child: _buildMemberList()),
          _InviteSection(
            controller: _inviteSearchController,
            query: _inviteQuery,
            searching: _searchingInvites,
            results: _inviteResults,
            members: _members,
            pendingInviteUserIds: _pendingInviteUserIds,
            busyUserIds: _busyInviteUserIds,
            error: _inviteError,
            enabled: _canInviteMembers,
            onInvite: _invite,
          ),
          if (_canReviewRequests)
            _JoinRequestsSection(
              requests: _requests,
              busyRequestIds: _busyRequestIds,
              error: _requestError,
              onDetail: _showJoinRequestDetails,
              onApprove: (request) => _reviewRequest(request, true),
              onReject: (request) => _reviewRequest(request, false),
            ),
        ],
      ),
    );
  }

  Widget _buildMemberList() {
    if (_loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: UiColors.accent,
          ),
        ),
      );
    }
    final members = _visibleMembers();
    if (members.isEmpty) {
      return const _EmptyState(
        icon: Icons.person_search_outlined,
        title: '没有匹配的成员',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: members.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final member = members[index];
        final permission = member_filter.roomMemberPermissionState(
          member: member,
          currentUser: widget.currentUser,
          canEditCreatorOnly: _canEditCreatorOnly,
          canManageMembers: _canManageMembers,
          ownerUserId: _room.createdBy?.id,
        );
        return _MemberRow(
          member: member,
          live: _live,
          permission: permission,
          ownerUserId: _room.createdBy?.id,
          busy: _busyMemberIds.contains(member.user.id),
          onSetAdmin: () => _setMemberRole(member, 'admin'),
          onUnsetAdmin: () => _setMemberRole(member, 'member'),
          onRemoveMember: () => _removeMember(member),
          onTransferCreator: () => _transferCreator(member),
        );
      },
    );
  }
}
