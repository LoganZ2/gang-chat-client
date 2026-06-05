class RoomNavigationBadgePatch {
  const RoomNavigationBadgePatch({
    required this.hasPendingRoomInvites,
    required this.selectedRoomHasPendingJoinRequests,
  });

  final bool hasPendingRoomInvites;
  final bool selectedRoomHasPendingJoinRequests;
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
  );
}

RoomNavigationBadgePatch? roomInviteBadgeUpdated({
  required bool currentHasPendingRoomInvites,
  required bool currentSelectedRoomHasPendingJoinRequests,
  required bool hasPending,
}) {
  if (currentHasPendingRoomInvites == hasPending) return null;
  return RoomNavigationBadgePatch(
    hasPendingRoomInvites: hasPending,
    selectedRoomHasPendingJoinRequests:
        currentSelectedRoomHasPendingJoinRequests,
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
