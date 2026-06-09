part of 'home_shell.dart';

extension _HomeShellNotifications on _HomeShellState {
  void _openNotifications({required bool openContent}) {
    _setHomeState(() {
      _settingsOpen = false;
      _contentMode = _ContentMode.notifications;
      if (openContent) _narrowContentOpen = true;
    });
    unawaited(_loadNotifications(silent: _notificationInvites.isNotEmpty));
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
      final invites = await _roomsController.listRoomInvites(status: 'all');
      if (!mounted) return;
      _setHomeState(() {
        _notificationInvites = invites;
        _loadingNotifications = false;
        _notificationError = null;
        _hasPendingRoomInvites =
            room_notifications.pendingRoomInviteCount(invites) > 0;
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
      final hasPending = await _roomsController.hasPendingRoomInvites();
      if (!mounted) return;
      _setHomeState(() => _hasPendingRoomInvites = hasPending);
    } catch (_) {}
  }

  Future<void> _reviewNotificationInvite(RoomInvite invite, bool accept) async {
    if (!room_notifications.canReviewNotificationInvite(
      invite: invite,
      busyInviteId: _busyNotificationInviteId,
    )) {
      return;
    }

    _setHomeState(() {
      _busyNotificationInviteId = invite.id;
      _notificationError = null;
    });

    try {
      final result = await _roomsController.reviewRoomInvite(
        inviteId: invite.id,
        accept: accept,
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

  void _applyRoomInvitesUpdated() {
    unawaited(_refreshPendingRoomInviteBadge());
    if (_contentMode == _ContentMode.notifications) {
      unawaited(_loadNotifications(silent: true));
    }
  }
}
