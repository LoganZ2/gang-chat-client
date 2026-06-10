import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/room_join_requests.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('joinRequestCandidates marks busy requests and pending info role', () {
    final candidates = joinRequestCandidates(
      requests: [_request('a'), _request('b')],
      busyRequestIds: const ['b'],
    );

    expect(candidates.map((item) => item.request.id), ['a', 'b']);
    expect(candidates[0].busy, isFalse);
    expect(candidates[0].canReview, isTrue);
    expect(candidates[0].userForInfo.roomRole, 'pending');
    expect(candidates[1].busy, isTrue);
    expect(candidates[1].canReview, isFalse);
  });

  test('canStartJoinRequestReview rejects busy request ids', () {
    expect(
      canStartJoinRequestReview(
        requestId: 'busy',
        busyRequestIds: const ['busy'],
      ),
      isFalse,
    );
    expect(canStartJoinRequestReview(requestId: 'idle'), isTrue);
  });

  test('joinRequestReasonText returns trimmed reason only when present', () {
    expect(
      joinRequestReasonText(_request('with_reason', reason: '  hello  ')),
      'hello',
    );
    expect(
      joinRequestReasonText(_request('blank_reason', reason: '  ')),
      isNull,
    );
  });

  test('join request badge refresh gate follows room and permission', () {
    expect(
      shouldRefreshJoinRequestBadgeForEvent(
        data: const {'room_id': 'room_1'},
        selectedRoomId: 'room_1',
        canReviewJoinRequests: true,
      ),
      isTrue,
    );
    expect(
      shouldRefreshJoinRequestBadgeForEvent(
        data: const {'room_id': 'room_2'},
        selectedRoomId: 'room_1',
        canReviewJoinRequests: true,
      ),
      isFalse,
    );
    expect(
      shouldRefreshJoinRequestBadgeForEvent(
        data: const {'room_id': 'room_1'},
        selectedRoomId: 'room_1',
        canReviewJoinRequests: false,
      ),
      isFalse,
    );
    expect(
      shouldRefreshJoinRequestBadgeForEvent(
        data: const {},
        selectedRoomId: 'room_1',
        canReviewJoinRequests: true,
      ),
      isFalse,
    );
  });

  test('join request badge refresh target follows room role', () {
    final adminRoom = _room('room_1', role: 'admin');
    final memberRoom = _room('room_2', role: 'member');

    expect(
      joinRequestBadgeRefreshTarget(
        room: adminRoom,
        canReviewJoinRequests: true,
      ),
      same(adminRoom),
    );
    expect(
      joinRequestBadgeRefreshTarget(
        room: memberRoom,
        canReviewJoinRequests: false,
      ),
      isNull,
    );
    expect(
      joinRequestBadgeRefreshTarget(
        room: memberRoom,
        canReviewJoinRequests: true,
      ),
      same(memberRoom),
    );
    expect(
      joinRequestBadgeRefreshTarget(room: null, canReviewJoinRequests: true),
      isNull,
    );

    expect(
      canApplyJoinRequestBadgeRefresh(
        targetRoomId: 'room_1',
        selectedRoomId: 'room_1',
      ),
      isTrue,
    );
    expect(
      canApplyJoinRequestBadgeRefresh(
        targetRoomId: 'room_1',
        selectedRoomId: 'room_2',
      ),
      isFalse,
    );
  });

  test('join request review reducers update requests and busy ids', () {
    final requests = [_request('a'), _request('b')];

    final started = joinRequestReviewStarted(
      requests: requests,
      requestId: 'a',
      busyRequestIds: const ['other'],
    );
    expect(started.requests.map((request) => request.id), ['a', 'b']);
    expect(started.busyRequestIds, {'other', 'a'});
    expect(started.changed, isFalse);
    expect(started.hasPendingRequests, isTrue);

    final succeeded = joinRequestReviewSucceeded(
      requests: started.requests,
      requestId: 'a',
      busyRequestIds: started.busyRequestIds,
    );
    expect(succeeded.requests.map((request) => request.id), ['b']);
    expect(succeeded.busyRequestIds, {'other'});
    expect(succeeded.changed, isTrue);
    expect(succeeded.hasPendingRequests, isTrue);

    final failed = joinRequestReviewFailed(
      requests: started.requests,
      requestId: 'a',
      busyRequestIds: started.busyRequestIds,
    );
    expect(failed.requests.map((request) => request.id), ['a', 'b']);
    expect(failed.busyRequestIds, {'other'});
    expect(failed.changed, isFalse);
  });

  test('joinRequestListBodyState separates empty and result lists', () {
    expect(joinRequestListBodyState(const []), JoinRequestListBodyState.empty);

    expect(
      joinRequestListBodyState(
        joinRequestCandidates(requests: [_request('a')]),
      ),
      JoinRequestListBodyState.results,
    );
  });

  test('joinRequestUserMeta prefers uid and falls back to user id', () {
    expect(
      joinRequestUserMeta(
        _request('with_uid', user: _user('user_1', uid: '1001')),
      ),
      '1001 · @user_1',
    );

    expect(
      joinRequestUserMeta(_request('without_uid', user: _user('user_2'))),
      'user_2 · @user_2',
    );
  });
}

JoinRequest _request(String id, {UserSummary? user, String reason = ''}) {
  return JoinRequest(
    id: id,
    status: 'pending',
    reason: reason,
    user: user ?? _user('user_$id'),
    createdAt: DateTime.utc(2026, 6, 5),
  );
}

UserSummary _user(String id, {String? uid}) {
  return UserSummary(
    id: id,
    username: id,
    displayName: 'User $id',
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    uid: uid,
  );
}

RoomDetail _room(String id, {required String role}) {
  return RoomDetail(
    id: id,
    name: id,
    avatarUrl: null,
    defaultAvatarKey: 'room-1',
    memberCount: 1,
    myMembership: RoomMembership(
      joinedAt: DateTime.utc(2026, 6, 5),
      role: role,
    ),
    live: LiveState(
      roomId: id,
      participantCount: 0,
      participants: const [],
      updatedAt: DateTime.utc(2026, 6, 5),
    ),
    createdAt: DateTime.utc(2026, 6, 5),
    updatedAt: DateTime.utc(2026, 6, 5),
  );
}
