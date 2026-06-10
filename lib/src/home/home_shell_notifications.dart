part of 'home_shell.dart';

extension _HomeShellNotifications on _HomeShellState {
  void _openNotifications({required bool openContent}) {
    _setHomeState(() {
      _settingsOpen = false;
      _contentMode = _ContentMode.notifications;
      if (openContent) _narrowContentOpen = true;
    });
    unawaited(
      _loadNotifications(
        silent:
            _notificationInvites.isNotEmpty ||
            _notificationApplications.isNotEmpty,
      ),
    );
  }

  void _closeNotifications() {
    _setHomeState(() {
      _contentMode = _ContentMode.chat;
      if (_selectedServerId == null) _narrowContentOpen = false;
    });
  }

  Future<void> _loadNotifications({bool silent = false}) async {
    if (!silent) {
      _setHomeState(() {
        _loadingNotifications = true;
        _notificationError = null;
      });
    }

    try {
      final (invites, applications) = await (
        _roomsController.listRoomInvites(status: 'all'),
        _roomsController.listRoomApplications(status: 'all'),
      ).wait;
      if (!mounted) return;
      _setHomeState(() {
        _notificationInvites = invites;
        _notificationApplications = applications;
        _loadingNotifications = false;
        _notificationError = null;
        _hasPendingRoomInvites =
            room_notifications.pendingRoomNotificationCount(
              invites: invites,
              applications: applications,
            ) >
            0;
      });
    } catch (error) {
      if (!mounted) return;
      _setHomeState(() {
        _loadingNotifications = false;
        _notificationError = error.toString();
      });
    }
  }

  Future<void> _refreshPendingRoomInviteBadge() async {
    try {
      final (invites, applications) = await (
        _roomsController.listRoomInvites(),
        _roomsController.listRoomApplications(),
      ).wait;
      if (!mounted) return;
      _setHomeState(
        () => _hasPendingRoomInvites =
            invites.isNotEmpty || applications.isNotEmpty,
      );
    } catch (_) {}
  }

  Future<void> _reviewNotificationInvite(RoomInvite invite, bool accept) async {
    if (!room_notifications.canReviewNotificationInvite(
      invite: invite,
      busyInviteId: _busyNotificationInviteId,
    )) {
      return;
    }

    String? reason;
    var startedBeforeDialog = false;
    if (accept &&
        room_notifications.roomInviteAcceptRequiresApplication(
          invite,
          roomInvites: _notificationInvites,
        )) {
      _setHomeState(() {
        _busyNotificationInviteId = invite.id;
        _notificationError = null;
      });
      startedBeforeDialog = true;
      final rawReason = await _showJoinApplicationDialog(invite.room);
      if (rawReason == null || !mounted) {
        if (mounted) {
          _setHomeState(() => _busyNotificationInviteId = null);
        }
        return;
      }
      reason = room_join.joinRequestReasonValue(rawReason);
    }

    if (!startedBeforeDialog) {
      _setHomeState(() {
        _busyNotificationInviteId = invite.id;
        _notificationError = null;
      });
    }

    try {
      final result = await _roomsController.reviewRoomInvite(
        inviteId: invite.id,
        accept: accept,
        reason: reason,
      );
      if (!mounted) return;
      _setHomeState(() {
        _busyNotificationInviteId = null;
        final room = result.room;
        if (accept && room != null) {
          _servers = _roomsController
              .patchRoomCardUpserted(rooms: _servers, room: room.toCard())
              .rooms;
        }
      });
      await _loadNotifications(silent: true);
      if (accept && result.joined) unawaited(_loadServersSilently());
    } catch (error) {
      if (!mounted) return;
      _setHomeState(() {
        _busyNotificationInviteId = null;
        _notificationError = error.toString();
      });
    }
  }

  Future<void> _withdrawNotificationApplication(
    RoomApplication application,
  ) async {
    if (!room_notifications.canWithdrawNotificationApplication(
      application: application,
      busyApplicationId: _busyNotificationApplicationId,
    )) {
      return;
    }

    _setHomeState(() {
      _busyNotificationApplicationId = application.id;
      _notificationError = null;
    });

    try {
      await _roomsController.withdrawRoomApplication(requestId: application.id);
      if (!mounted) return;
      _setHomeState(() {
        _busyNotificationApplicationId = null;
      });
      await _loadNotifications(silent: true);
    } catch (error) {
      if (!mounted) return;
      _setHomeState(() {
        _busyNotificationApplicationId = null;
        _notificationError = error.toString();
      });
    }
  }

  void _applyRoomInvitesUpdated() {
    unawaited(_refreshPendingRoomInviteBadge());
    if (_contentMode == _ContentMode.notifications) {
      unawaited(_loadNotifications(silent: true));
    }
  }

  void _applyRoomApplicationsUpdated() {
    unawaited(_refreshPendingRoomInviteBadge());
    if (_contentMode == _ContentMode.notifications) {
      unawaited(_loadNotifications(silent: true));
    }
  }
}
