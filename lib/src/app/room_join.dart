import '../protocol/models.dart';
import 'room_display.dart';
import 'room_invites.dart' as room_invites;

class RoomJoinSearchPatch {
  const RoomJoinSearchPatch({
    required this.results,
    required this.searching,
    required this.error,
  });

  final List<PublicRoom> results;
  final bool searching;
  final String? error;
}

class RoomJoinSearchInputPatch {
  const RoomJoinSearchInputPatch({
    required this.search,
    required this.query,
    required this.shouldSearch,
    required this.shouldCancelInFlightSearch,
  });

  final RoomJoinSearchPatch search;
  final String query;
  final bool shouldSearch;
  final bool shouldCancelInFlightSearch;
}

class RoomJoinInvitesPatch {
  const RoomJoinInvitesPatch({
    required this.invites,
    required this.loading,
    required this.error,
  });

  final List<RoomInvite> invites;
  final bool loading;
  final String? error;
}

class RoomJoinPublicActionPatch {
  const RoomJoinPublicActionPatch({
    required this.busyRoomId,
    required this.error,
    required this.pendingRoomIds,
  });

  final String? busyRoomId;
  final String? error;
  final Set<String> pendingRoomIds;
}

class RoomJoinInviteDecisionPatch {
  const RoomJoinInviteDecisionPatch({
    required this.invites,
    required this.pendingRoomIds,
    required this.busyInviteId,
    required this.error,
  });

  final List<RoomInvite> invites;
  final Set<String> pendingRoomIds;
  final String? busyInviteId;
  final String? error;
}

bool hasRoomSearchQuery(String query) {
  return query.trim().isNotEmpty;
}

bool shouldShowRoomInviteSection({
  required bool loadingInvites,
  required Iterable<RoomInvite> invites,
}) {
  return loadingInvites || invites.isNotEmpty;
}

bool canStartPublicRoomAction(String? busyRoomId) {
  return busyRoomId == null;
}

bool canStartRoomInviteDecision({
  required String? busyInviteId,
  required String? busyRoomId,
}) {
  return busyInviteId == null && busyRoomId == null;
}

String? joinRequestReasonValue(String rawReason) {
  final reason = rawReason.trim();
  if (reason.isEmpty) return null;
  return reason;
}

String publicRoomJoinSubtitle(PublicRoom room) {
  final rid = room.rid.trim();
  if (rid.isEmpty) return '${room.memberCount} 名成员';
  return '$rid · ${room.memberCount} 名成员';
}

String pendingRoomInviteSubtitle(RoomInvite invite) {
  final rid = invite.room.rid.trim();
  if (rid.isEmpty) return '邀请你加入';
  return '邀请你加入 · RID $rid';
}

class PublicRoomJoinCandidate {
  const PublicRoomJoinCandidate({
    required this.room,
    required this.pending,
    required this.busy,
  });

  final PublicRoom room;
  final bool pending;
  final bool busy;

  bool get opensJoinedRoom => room.joined;

  bool get actionable {
    return publicRoomJoinActionable(room, pending: pending);
  }

  bool get actionEnabled => actionable && !busy;
}

List<PublicRoomJoinCandidate> publicRoomJoinCandidates({
  required Iterable<PublicRoom> rooms,
  Iterable<String> pendingRoomIds = const [],
  String? busyRoomId,
}) {
  final pendingSet = pendingRoomIds.toSet();
  return [
    for (final room in rooms)
      PublicRoomJoinCandidate(
        room: room,
        pending: room.joinState == 'pending' || pendingSet.contains(room.id),
        busy: busyRoomId == room.id,
      ),
  ];
}

Set<String> pendingRoomIdsAfterJoinResult({
  required Iterable<String> pendingRoomIds,
  required PublicRoom room,
  required JoinRoomResult result,
}) {
  final next = pendingRoomIds.toSet();
  if (result.pending) next.add(room.id);
  return next;
}

RoomJoinSearchPatch roomJoinSearchCleared() {
  return const RoomJoinSearchPatch(results: [], searching: false, error: null);
}

RoomJoinSearchInputPatch roomJoinSearchQueryChanged({
  required String rawQuery,
  required Iterable<PublicRoom> results,
  required String? error,
}) {
  final query = rawQuery.trim();
  if (!hasRoomSearchQuery(query)) {
    return RoomJoinSearchInputPatch(
      search: roomJoinSearchCleared(),
      query: '',
      shouldSearch: false,
      shouldCancelInFlightSearch: true,
    );
  }
  return RoomJoinSearchInputPatch(
    search: roomJoinSearchStarted(results: results, error: error),
    query: query,
    shouldSearch: true,
    shouldCancelInFlightSearch: true,
  );
}

RoomJoinSearchPatch roomJoinSearchStarted({
  required Iterable<PublicRoom> results,
  required String? error,
}) {
  return RoomJoinSearchPatch(
    results: results.toList(),
    searching: true,
    error: error,
  );
}

RoomJoinSearchPatch roomJoinSearchSucceeded({
  required Iterable<PublicRoom> results,
}) {
  return RoomJoinSearchPatch(
    results: results.toList(),
    searching: false,
    error: null,
  );
}

RoomJoinSearchPatch roomJoinSearchFailed({
  required Iterable<PublicRoom> results,
  required Object failure,
}) {
  return RoomJoinSearchPatch(
    results: results.toList(),
    searching: false,
    error: failure.toString(),
  );
}

RoomJoinInvitesPatch roomJoinInvitesLoadStarted({
  required Iterable<RoomInvite> invites,
}) {
  return RoomJoinInvitesPatch(
    invites: invites.toList(),
    loading: true,
    error: null,
  );
}

RoomJoinInvitesPatch roomJoinInvitesLoadSucceeded({
  required Iterable<RoomInvite> invites,
}) {
  return RoomJoinInvitesPatch(
    invites: invites.toList(),
    loading: false,
    error: null,
  );
}

RoomJoinInvitesPatch roomJoinInvitesLoadFailed({
  required Iterable<RoomInvite> invites,
  required Object failure,
}) {
  return RoomJoinInvitesPatch(
    invites: invites.toList(),
    loading: false,
    error: failure.toString(),
  );
}

RoomJoinPublicActionPatch roomJoinPublicActionStarted({
  required String roomId,
  required Iterable<String> pendingRoomIds,
}) {
  return RoomJoinPublicActionPatch(
    busyRoomId: roomId,
    error: null,
    pendingRoomIds: pendingRoomIds.toSet(),
  );
}

RoomJoinPublicActionPatch roomJoinPublicActionPending({
  required String? busyRoomId,
  required String? error,
  required Iterable<String> pendingRoomIds,
  required PublicRoom room,
  required JoinRoomResult result,
}) {
  return RoomJoinPublicActionPatch(
    busyRoomId: busyRoomId,
    error: error,
    pendingRoomIds: pendingRoomIdsAfterJoinResult(
      pendingRoomIds: pendingRoomIds,
      room: room,
      result: result,
    ),
  );
}

RoomJoinPublicActionPatch roomJoinPublicActionFailed({
  required String? busyRoomId,
  required Iterable<String> pendingRoomIds,
  required Object failure,
}) {
  return RoomJoinPublicActionPatch(
    busyRoomId: busyRoomId,
    error: failure.toString(),
    pendingRoomIds: pendingRoomIds.toSet(),
  );
}

RoomJoinPublicActionPatch roomJoinPublicActionFinished({
  required String? error,
  required Iterable<String> pendingRoomIds,
}) {
  return RoomJoinPublicActionPatch(
    busyRoomId: null,
    error: error,
    pendingRoomIds: pendingRoomIds.toSet(),
  );
}

RoomJoinInviteDecisionPatch roomJoinInviteDecisionStarted({
  required Iterable<RoomInvite> invites,
  required Iterable<String> pendingRoomIds,
  required String inviteId,
}) {
  return RoomJoinInviteDecisionPatch(
    invites: invites.toList(),
    pendingRoomIds: pendingRoomIds.toSet(),
    busyInviteId: inviteId,
    error: null,
  );
}

RoomJoinInviteDecisionPatch roomJoinInviteDecisionSucceeded({
  required Iterable<RoomInvite> invites,
  required Iterable<String> pendingRoomIds,
  required RoomInvite invite,
  required bool accept,
  required JoinRoomResult result,
}) {
  final next = room_invites.reviewedRoomInvites(
    invites: invites,
    pendingRoomIds: pendingRoomIds,
    invite: invite,
    accept: accept,
    result: result,
  );
  return RoomJoinInviteDecisionPatch(
    invites: next.invites,
    pendingRoomIds: next.pendingRoomIds,
    busyInviteId: null,
    error: null,
  );
}

RoomJoinInviteDecisionPatch roomJoinInviteDecisionFailed({
  required Iterable<RoomInvite> invites,
  required Iterable<String> pendingRoomIds,
  required String? busyInviteId,
  required Object failure,
}) {
  return RoomJoinInviteDecisionPatch(
    invites: invites.toList(),
    pendingRoomIds: pendingRoomIds.toSet(),
    busyInviteId: busyInviteId,
    error: failure.toString(),
  );
}

RoomJoinInviteDecisionPatch roomJoinInviteDecisionFinished({
  required Iterable<RoomInvite> invites,
  required Iterable<String> pendingRoomIds,
  required String? error,
}) {
  return RoomJoinInviteDecisionPatch(
    invites: invites.toList(),
    pendingRoomIds: pendingRoomIds.toSet(),
    busyInviteId: null,
    error: error,
  );
}
