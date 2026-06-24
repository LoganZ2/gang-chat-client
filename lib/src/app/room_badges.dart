class RoomNavigationBadgePatch {
  const RoomNavigationBadgePatch({
    required this.hasPendingRoomInvites,
    required this.selectedRoomHasPendingJoinRequests,
    this.pendingRoomNotificationCount,
  });

  final bool hasPendingRoomInvites;
  final bool selectedRoomHasPendingJoinRequests;
  final int? pendingRoomNotificationCount;
}

RoomNavigationBadgePatch? roomNavigationBadgesReset({
  required bool currentHasPendingRoomInvites,
  required bool currentSelectedRoomHasPendingJoinRequests,
}) {
  if (!currentHasPendingRoomInvites &&
      !currentSelectedRoomHasPendingJoinRequests) {
    return null;
  }
  return const RoomNavigationBadgePatch(
    hasPendingRoomInvites: false,
    selectedRoomHasPendingJoinRequests: false,
    pendingRoomNotificationCount: 0,
  );
}

RoomNavigationBadgePatch? roomInviteBadgeUpdated({
  required bool currentHasPendingRoomInvites,
  required bool currentSelectedRoomHasPendingJoinRequests,
  required bool hasPending,
  int? currentPendingRoomNotificationCount,
  int? pendingRoomNotificationCount,
}) {
  if (currentHasPendingRoomInvites == hasPending &&
      (pendingRoomNotificationCount == null ||
          currentPendingRoomNotificationCount ==
              pendingRoomNotificationCount)) {
    return null;
  }
  return RoomNavigationBadgePatch(
    hasPendingRoomInvites: hasPending,
    selectedRoomHasPendingJoinRequests:
        currentSelectedRoomHasPendingJoinRequests,
    pendingRoomNotificationCount: pendingRoomNotificationCount,
  );
}

RoomNavigationBadgePatch? selectedJoinRequestBadgeUpdated({
  required bool currentHasPendingRoomInvites,
  required bool currentSelectedRoomHasPendingJoinRequests,
  required bool hasPending,
}) {
  if (currentSelectedRoomHasPendingJoinRequests == hasPending) return null;
  return RoomNavigationBadgePatch(
    hasPendingRoomInvites: currentHasPendingRoomInvites,
    selectedRoomHasPendingJoinRequests: hasPending,
  );
}
