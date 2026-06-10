import '../protocol/models.dart';
import 'room_display.dart';

enum JoinRequestListBodyState { empty, results }

class JoinRequestCandidate {
  const JoinRequestCandidate({required this.request, required this.busy});

  final JoinRequest request;
  final bool busy;

  bool get canReview => !busy;

  UserSummary get userForInfo {
    return request.user.copyWith(roomRole: 'pending');
  }
}

class JoinRequestReviewActionState {
  const JoinRequestReviewActionState({
    required this.requests,
    required this.busyRequestIds,
    required this.changed,
  });

  final List<JoinRequest> requests;
  final Set<String> busyRequestIds;
  final bool changed;

  bool get hasPendingRequests => requests.isNotEmpty;
}

List<JoinRequestCandidate> joinRequestCandidates({
  required Iterable<JoinRequest> requests,
  Iterable<String> busyRequestIds = const [],
}) {
  final busySet = busyRequestIds.toSet();
  return [
    for (final request in requests)
      JoinRequestCandidate(
        request: request,
        busy: busySet.contains(request.id),
      ),
  ];
}

JoinRequestListBodyState joinRequestListBodyState(
  Iterable<JoinRequestCandidate> candidates,
) {
  if (candidates.isEmpty) return JoinRequestListBodyState.empty;
  return JoinRequestListBodyState.results;
}

String joinRequestUserMeta(JoinRequest request) {
  return userIdentityMeta(request.user);
}

String? joinRequestReasonText(JoinRequest request) {
  final reason = request.reason.trim();
  if (reason.isEmpty) return null;
  return reason;
}

bool canStartJoinRequestReview({
  required String requestId,
  Iterable<String> busyRequestIds = const [],
}) {
  return !busyRequestIds.contains(requestId);
}

bool shouldRefreshJoinRequestBadgeForEvent({
  required Map<String, dynamic> data,
  required String? selectedRoomId,
  required bool canReviewJoinRequests,
}) {
  final roomId = data['room_id'] as String?;
  if (roomId == null) return false;
  return shouldRefreshJoinRequestBadgeForRoom(
    roomId: roomId,
    selectedRoomId: selectedRoomId,
    canReviewJoinRequests: canReviewJoinRequests,
  );
}

bool shouldRefreshJoinRequestBadgeForRoom({
  required String roomId,
  required String? selectedRoomId,
  required bool canReviewJoinRequests,
}) {
  return roomId == selectedRoomId && canReviewJoinRequests;
}

RoomDetail? joinRequestBadgeRefreshTarget({
  required RoomDetail? room,
  required bool canReviewJoinRequests,
}) {
  if (room == null) return null;
  if (!canReviewJoinRequests) return null;
  return room;
}

bool canApplyJoinRequestBadgeRefresh({
  required String targetRoomId,
  required String? selectedRoomId,
}) {
  return targetRoomId == selectedRoomId;
}

JoinRequestReviewActionState joinRequestReviewStarted({
  required Iterable<JoinRequest> requests,
  required String requestId,
  Iterable<String> busyRequestIds = const [],
}) {
  return JoinRequestReviewActionState(
    requests: requests.toList(),
    busyRequestIds: {...busyRequestIds, requestId},
    changed: false,
  );
}

JoinRequestReviewActionState joinRequestReviewSucceeded({
  required Iterable<JoinRequest> requests,
  required String requestId,
  Iterable<String> busyRequestIds = const [],
}) {
  return JoinRequestReviewActionState(
    requests: [
      for (final request in requests)
        if (request.id != requestId) request,
    ],
    busyRequestIds: {
      for (final id in busyRequestIds)
        if (id != requestId) id,
    },
    changed: true,
  );
}

JoinRequestReviewActionState joinRequestReviewFailed({
  required Iterable<JoinRequest> requests,
  required String requestId,
  Iterable<String> busyRequestIds = const [],
}) {
  return JoinRequestReviewActionState(
    requests: requests.toList(),
    busyRequestIds: {
      for (final id in busyRequestIds)
        if (id != requestId) id,
    },
    changed: false,
  );
}
