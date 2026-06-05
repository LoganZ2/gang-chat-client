import '../protocol/models.dart';
import 'room_members_filter.dart';

enum RoomInviteSearchBodyState { loading, prompt, empty, results }

class RoomMemberInviteDialogPatch {
  const RoomMemberInviteDialogPatch({
    required this.searchResults,
    required this.searching,
    required this.error,
    required this.pendingInviteUserIds,
    required this.busyUserIds,
  });

  final List<UserSummary> searchResults;
  final bool searching;
  final String? error;
  final Set<String> pendingInviteUserIds;
  final Set<String> busyUserIds;
}

class RoomMemberInviteSearchInputPatch {
  const RoomMemberInviteSearchInputPatch({
    required this.dialog,
    required this.query,
    required this.shouldSearch,
    required this.shouldCancelInFlightSearch,
  });

  final RoomMemberInviteDialogPatch dialog;
  final String query;
  final bool shouldSearch;
  final bool shouldCancelInFlightSearch;
}

class RoomInviteCandidate {
  const RoomInviteCandidate({
    required this.user,
    required this.existing,
    required this.pending,
    required this.busy,
  });

  final UserSummary user;
  final bool existing;
  final bool pending;
  final bool busy;

  bool get inviteActionEnabled => !existing && !pending;
  bool get canStartInvite => inviteActionEnabled && !busy;
}

RoomInviteSearchBodyState roomInviteSearchBodyState({
  required bool searching,
  required String query,
  required Iterable<RoomInviteCandidate> candidates,
}) {
  if (searching) return RoomInviteSearchBodyState.loading;
  if (query.trim().isEmpty) return RoomInviteSearchBodyState.prompt;
  if (candidates.isEmpty) return RoomInviteSearchBodyState.empty;
  return RoomInviteSearchBodyState.results;
}

class RoomInviteReviewState {
  const RoomInviteReviewState({
    required this.invites,
    required this.pendingRoomIds,
  });

  final List<RoomInvite> invites;
  final Set<String> pendingRoomIds;

  bool get hasPendingInvites => invites.isNotEmpty;
}

class RoomMemberInviteActionState {
  const RoomMemberInviteActionState({
    required this.pendingInviteUserIds,
    required this.busyUserIds,
  });

  final Set<String> pendingInviteUserIds;
  final Set<String> busyUserIds;
}

List<RoomInviteCandidate> roomInviteCandidates({
  required Iterable<UserSummary> searchResults,
  required Iterable<RoomMember> members,
  required String query,
  Iterable<String> pendingInviteUserIds = const [],
  Iterable<String> busyUserIds = const [],
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final pendingSet = pendingInviteUserIds.toSet();
  final busySet = busyUserIds.toSet();
  final membersByUserId = {
    for (final member in members) member.user.id: member,
  };
  final users = <UserSummary>[];
  final seenUserIds = <String>{};

  void add(UserSummary user) {
    if (user.isSuperuser) return;
    if (seenUserIds.add(user.id)) users.add(user);
  }

  for (final user in searchResults) {
    add(user);
  }
  if (normalizedQuery.isNotEmpty) {
    for (final member in members) {
      if (roomMemberSearchRank(member, normalizedQuery) < 99) {
        add(member.user);
      }
    }
  }

  return [
    for (final user in users)
      RoomInviteCandidate(
        user: user,
        existing: membersByUserId.containsKey(user.id),
        pending: pendingSet.contains(user.id),
        busy: busySet.contains(user.id),
      ),
  ];
}

bool canStartRoomInvite({
  required String userId,
  required Iterable<RoomMember> members,
  Iterable<String> pendingInviteUserIds = const [],
  Iterable<String> busyUserIds = const [],
  bool isSuperuser = false,
}) {
  if (isSuperuser) return false;
  for (final member in members) {
    if (member.user.id == userId) return false;
  }
  return !pendingInviteUserIds.contains(userId) &&
      !busyUserIds.contains(userId);
}

RoomMemberInviteDialogPatch roomMemberInviteSearchCleared({
  required Iterable<String> pendingInviteUserIds,
  required Iterable<String> busyUserIds,
}) {
  return RoomMemberInviteDialogPatch(
    searchResults: const [],
    searching: false,
    error: null,
    pendingInviteUserIds: pendingInviteUserIds.toSet(),
    busyUserIds: busyUserIds.toSet(),
  );
}

RoomMemberInviteSearchInputPatch roomMemberInviteSearchQueryChanged({
  required String rawQuery,
  required Iterable<UserSummary> searchResults,
  required Iterable<String> pendingInviteUserIds,
  required Iterable<String> busyUserIds,
}) {
  final query = rawQuery.trim();
  if (query.isEmpty) {
    return RoomMemberInviteSearchInputPatch(
      dialog: roomMemberInviteSearchCleared(
        pendingInviteUserIds: pendingInviteUserIds,
        busyUserIds: busyUserIds,
      ),
      query: '',
      shouldSearch: false,
      shouldCancelInFlightSearch: true,
    );
  }
  return RoomMemberInviteSearchInputPatch(
    dialog: roomMemberInviteSearchStarted(
      searchResults: searchResults,
      pendingInviteUserIds: pendingInviteUserIds,
      busyUserIds: busyUserIds,
    ),
    query: query,
    shouldSearch: true,
    shouldCancelInFlightSearch: true,
  );
}

RoomMemberInviteDialogPatch roomMemberInviteSearchStarted({
  required Iterable<UserSummary> searchResults,
  required Iterable<String> pendingInviteUserIds,
  required Iterable<String> busyUserIds,
}) {
  return RoomMemberInviteDialogPatch(
    searchResults: searchResults.toList(),
    searching: true,
    error: null,
    pendingInviteUserIds: pendingInviteUserIds.toSet(),
    busyUserIds: busyUserIds.toSet(),
  );
}

RoomMemberInviteDialogPatch roomMemberInviteSearchSucceeded({
  required Iterable<UserSummary> searchResults,
  required Iterable<String> pendingInviteUserIds,
  required Iterable<String> busyUserIds,
}) {
  return RoomMemberInviteDialogPatch(
    searchResults: searchResults.toList(),
    searching: false,
    error: null,
    pendingInviteUserIds: pendingInviteUserIds.toSet(),
    busyUserIds: busyUserIds.toSet(),
  );
}

RoomMemberInviteDialogPatch roomMemberInviteSearchFailed({
  required Iterable<UserSummary> searchResults,
  required Iterable<String> pendingInviteUserIds,
  required Iterable<String> busyUserIds,
  required Object failure,
}) {
  return RoomMemberInviteDialogPatch(
    searchResults: searchResults.toList(),
    searching: false,
    error: failure.toString(),
    pendingInviteUserIds: pendingInviteUserIds.toSet(),
    busyUserIds: busyUserIds.toSet(),
  );
}

RoomMemberInviteActionState roomMemberInviteActionStarted({
  required String userId,
  Iterable<String> pendingInviteUserIds = const [],
  Iterable<String> busyUserIds = const [],
}) {
  return RoomMemberInviteActionState(
    pendingInviteUserIds: pendingInviteUserIds.toSet(),
    busyUserIds: {...busyUserIds, userId},
  );
}

RoomMemberInviteActionState roomMemberInviteActionSucceeded({
  required String userId,
  Iterable<String> pendingInviteUserIds = const [],
  Iterable<String> busyUserIds = const [],
}) {
  return RoomMemberInviteActionState(
    pendingInviteUserIds: {...pendingInviteUserIds, userId},
    busyUserIds: {
      for (final item in busyUserIds)
        if (item != userId) item,
    },
  );
}

RoomMemberInviteActionState roomMemberInviteActionFailed({
  required String userId,
  Iterable<String> pendingInviteUserIds = const [],
  Iterable<String> busyUserIds = const [],
}) {
  return RoomMemberInviteActionState(
    pendingInviteUserIds: pendingInviteUserIds.toSet(),
    busyUserIds: {
      for (final item in busyUserIds)
        if (item != userId) item,
    },
  );
}

RoomMemberInviteDialogPatch roomMemberInviteStarted({
  required Iterable<UserSummary> searchResults,
  required bool searching,
  required String userId,
  required Iterable<String> pendingInviteUserIds,
  required Iterable<String> busyUserIds,
}) {
  final state = roomMemberInviteActionStarted(
    userId: userId,
    pendingInviteUserIds: pendingInviteUserIds,
    busyUserIds: busyUserIds,
  );
  return RoomMemberInviteDialogPatch(
    searchResults: searchResults.toList(),
    searching: searching,
    error: null,
    pendingInviteUserIds: state.pendingInviteUserIds,
    busyUserIds: state.busyUserIds,
  );
}

RoomMemberInviteDialogPatch roomMemberInviteSucceeded({
  required Iterable<UserSummary> searchResults,
  required bool searching,
  required String? error,
  required String userId,
  required Iterable<String> pendingInviteUserIds,
  required Iterable<String> busyUserIds,
}) {
  final state = roomMemberInviteActionSucceeded(
    userId: userId,
    pendingInviteUserIds: pendingInviteUserIds,
    busyUserIds: busyUserIds,
  );
  return RoomMemberInviteDialogPatch(
    searchResults: searchResults.toList(),
    searching: searching,
    error: error,
    pendingInviteUserIds: state.pendingInviteUserIds,
    busyUserIds: state.busyUserIds,
  );
}

RoomMemberInviteDialogPatch roomMemberInviteFailed({
  required Iterable<UserSummary> searchResults,
  required bool searching,
  required String userId,
  required Iterable<String> pendingInviteUserIds,
  required Iterable<String> busyUserIds,
  required Object failure,
}) {
  final state = roomMemberInviteActionFailed(
    userId: userId,
    pendingInviteUserIds: pendingInviteUserIds,
    busyUserIds: busyUserIds,
  );
  return RoomMemberInviteDialogPatch(
    searchResults: searchResults.toList(),
    searching: searching,
    error: failure.toString(),
    pendingInviteUserIds: state.pendingInviteUserIds,
    busyUserIds: state.busyUserIds,
  );
}

RoomInviteReviewState reviewedRoomInvites({
  required Iterable<RoomInvite> invites,
  required Iterable<String> pendingRoomIds,
  required RoomInvite invite,
  required bool accept,
  required JoinRoomResult result,
}) {
  final nextPendingRoomIds = pendingRoomIds.toSet();
  if (accept && result.pending) {
    nextPendingRoomIds.add(invite.room.id);
  }
  return RoomInviteReviewState(
    invites: [
      for (final item in invites)
        if (item.id != invite.id) item,
    ],
    pendingRoomIds: nextPendingRoomIds,
  );
}
