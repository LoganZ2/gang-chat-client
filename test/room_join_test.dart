import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/room_join.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test(
    'publicRoomJoinCandidates marks pending from server and local state',
    () {
      final candidates = publicRoomJoinCandidates(
        rooms: [
          _room('joined', joined: true),
          _room('server_pending', joinState: 'pending'),
          _room('local_pending'),
          _room('open'),
        ],
        pendingRoomIds: const ['local_pending'],
      );

      expect(candidates.map((item) => item.pending), [
        false,
        true,
        true,
        false,
      ]);
      expect(candidates[0].opensJoinedRoom, isTrue);
      expect(candidates[1].actionable, isFalse);
      expect(candidates[3].actionable, isTrue);
    },
  );

  test('publicRoomJoinCandidates disables only the busy room action', () {
    final candidates = publicRoomJoinCandidates(
      rooms: [_room('busy'), _room('idle')],
      busyRoomId: 'busy',
    );

    expect(candidates[0].busy, isTrue);
    expect(candidates[0].actionEnabled, isFalse);
    expect(candidates[1].busy, isFalse);
    expect(candidates[1].actionEnabled, isTrue);
  });

  test('pendingRoomIdsAfterJoinResult tracks approval-required joins', () {
    expect(
      pendingRoomIdsAfterJoinResult(
        pendingRoomIds: const ['existing'],
        room: _room('room_1'),
        result: const JoinRoomResult(pending: true),
      ),
      {'existing', 'room_1'},
    );
    expect(
      pendingRoomIdsAfterJoinResult(
        pendingRoomIds: const ['existing'],
        room: _room('room_1'),
        result: JoinRoomResult(room: _roomDetail()),
      ),
      {'existing'},
    );
  });

  test('joinRequestReasonValue trims optional application text', () {
    expect(joinRequestReasonValue('  hello team  '), 'hello team');
    expect(joinRequestReasonValue('   '), isNull);
  });

  test(
    'join dialog search and invite list patches preserve state semantics',
    () {
      final existingResults = [_room('existing')];
      final invites = [_invite('invite_1')];

      final cleared = roomJoinSearchCleared();
      expect(cleared.results, isEmpty);
      expect(cleared.searching, isFalse);
      expect(cleared.error, isNull);

      final searchStarted = roomJoinSearchStarted(
        results: existingResults,
        error: 'stale error',
      );
      expect(searchStarted.results.map((room) => room.id), ['existing']);
      expect(searchStarted.searching, isTrue);
      expect(searchStarted.error, 'stale error');

      final inputStarted = roomJoinSearchQueryChanged(
        rawQuery: '  room  ',
        results: existingResults,
        error: 'stale error',
      );
      expect(inputStarted.query, 'room');
      expect(inputStarted.shouldSearch, isTrue);
      expect(inputStarted.shouldCancelInFlightSearch, isTrue);
      expect(inputStarted.search.results.map((room) => room.id), ['existing']);
      expect(inputStarted.search.searching, isTrue);
      expect(inputStarted.search.error, 'stale error');

      final inputCleared = roomJoinSearchQueryChanged(
        rawQuery: '   ',
        results: existingResults,
        error: 'stale error',
      );
      expect(inputCleared.query, '');
      expect(inputCleared.shouldSearch, isFalse);
      expect(inputCleared.shouldCancelInFlightSearch, isTrue);
      expect(inputCleared.search.results, isEmpty);
      expect(inputCleared.search.searching, isFalse);
      expect(inputCleared.search.error, isNull);

      final searchSucceeded = roomJoinSearchSucceeded(
        results: [_room('room_2')],
      );
      expect(searchSucceeded.results.single.id, 'room_2');
      expect(searchSucceeded.searching, isFalse);
      expect(searchSucceeded.error, isNull);

      final searchFailed = roomJoinSearchFailed(
        results: existingResults,
        failure: 'search failed',
      );
      expect(searchFailed.results.map((room) => room.id), ['existing']);
      expect(searchFailed.searching, isFalse);
      expect(searchFailed.error, 'search failed');

      final invitesStarted = roomJoinInvitesLoadStarted(invites: invites);
      expect(invitesStarted.invites.map((invite) => invite.id), ['invite_1']);
      expect(invitesStarted.loading, isTrue);
      expect(invitesStarted.error, isNull);

      final invitesSucceeded = roomJoinInvitesLoadSucceeded(invites: invites);
      expect(invitesSucceeded.invites.map((invite) => invite.id), ['invite_1']);
      expect(invitesSucceeded.loading, isFalse);
      expect(invitesSucceeded.error, isNull);

      final invitesFailed = roomJoinInvitesLoadFailed(
        invites: invites,
        failure: 'load failed',
      );
      expect(invitesFailed.invites.map((invite) => invite.id), ['invite_1']);
      expect(invitesFailed.loading, isFalse);
      expect(invitesFailed.error, 'load failed');
    },
  );

  test(
    'join dialog public room action patches track busy and pending state',
    () {
      final started = roomJoinPublicActionStarted(
        roomId: 'room_1',
        pendingRoomIds: const ['existing'],
      );
      expect(started.busyRoomId, 'room_1');
      expect(started.error, isNull);
      expect(started.pendingRoomIds, {'existing'});

      final pending = roomJoinPublicActionPending(
        busyRoomId: 'room_1',
        error: null,
        pendingRoomIds: started.pendingRoomIds,
        room: _room('room_2'),
        result: const JoinRoomResult(pending: true),
      );
      expect(pending.busyRoomId, 'room_1');
      expect(pending.error, isNull);
      expect(pending.pendingRoomIds, {'existing', 'room_2'});

      final failed = roomJoinPublicActionFailed(
        busyRoomId: 'room_1',
        pendingRoomIds: pending.pendingRoomIds,
        failure: 'join failed',
      );
      expect(failed.busyRoomId, 'room_1');
      expect(failed.error, 'join failed');
      expect(failed.pendingRoomIds, {'existing', 'room_2'});

      final finished = roomJoinPublicActionFinished(
        error: failed.error,
        pendingRoomIds: failed.pendingRoomIds,
      );
      expect(finished.busyRoomId, isNull);
      expect(finished.error, 'join failed');
      expect(finished.pendingRoomIds, {'existing', 'room_2'});
    },
  );

  test(
    'join dialog invite decision patches update invites and pending rooms',
    () {
      final invites = [_invite('invite_1'), _invite('invite_2')];

      final started = roomJoinInviteDecisionStarted(
        invites: invites,
        pendingRoomIds: const ['existing'],
        inviteId: 'invite_1',
      );
      expect(started.invites.map((invite) => invite.id), [
        'invite_1',
        'invite_2',
      ]);
      expect(started.pendingRoomIds, {'existing'});
      expect(started.busyInviteId, 'invite_1');
      expect(started.error, isNull);

      final succeeded = roomJoinInviteDecisionSucceeded(
        invites: started.invites,
        pendingRoomIds: started.pendingRoomIds,
        invite: invites.first,
        accept: true,
        result: const JoinRoomResult(pending: true),
      );
      expect(succeeded.invites.map((invite) => invite.id), ['invite_2']);
      expect(succeeded.pendingRoomIds, {'existing', invites.first.room.id});
      expect(succeeded.busyInviteId, isNull);
      expect(succeeded.error, isNull);

      final failed = roomJoinInviteDecisionFailed(
        invites: started.invites,
        pendingRoomIds: started.pendingRoomIds,
        busyInviteId: started.busyInviteId,
        failure: 'review failed',
      );
      expect(failed.invites.map((invite) => invite.id), [
        'invite_1',
        'invite_2',
      ]);
      expect(failed.pendingRoomIds, {'existing'});
      expect(failed.busyInviteId, 'invite_1');
      expect(failed.error, 'review failed');

      final finished = roomJoinInviteDecisionFinished(
        invites: failed.invites,
        pendingRoomIds: failed.pendingRoomIds,
        error: failed.error,
      );
      expect(finished.invites.map((invite) => invite.id), [
        'invite_1',
        'invite_2',
      ]);
      expect(finished.pendingRoomIds, {'existing'});
      expect(finished.busyInviteId, isNull);
      expect(finished.error, 'review failed');
    },
  );

  test('join dialog state helpers expose reusable gates', () {
    expect(hasRoomSearchQuery('  room  '), isTrue);
    expect(hasRoomSearchQuery('   '), isFalse);
    expect(
      shouldShowRoomInviteSection(loadingInvites: true, invites: const []),
      isTrue,
    );
    expect(
      shouldShowRoomInviteSection(
        loadingInvites: false,
        invites: [_invite('invite_1')],
      ),
      isTrue,
    );
    expect(
      shouldShowRoomInviteSection(loadingInvites: false, invites: const []),
      isFalse,
    );
    expect(canStartPublicRoomAction(null), isTrue);
    expect(canStartPublicRoomAction('room_1'), isFalse);
    expect(
      canStartRoomInviteDecision(busyInviteId: null, busyRoomId: null),
      isTrue,
    );
    expect(
      canStartRoomInviteDecision(busyInviteId: 'invite_1', busyRoomId: null),
      isFalse,
    );
    expect(
      canStartRoomInviteDecision(busyInviteId: null, busyRoomId: 'room_1'),
      isFalse,
    );
  });

  test('join dialog display helpers format room and invite subtitles', () {
    expect(publicRoomJoinSubtitle(_room('1001')), '1001 · 3 名成员');
    expect(publicRoomJoinSubtitle(_room('no_rid', rid: '')), '3 名成员');
    expect(
      publicRoomJoinSubtitle(_room('spaced', rid: '  R002  ')),
      'R002 · 3 名成员',
    );

    expect(
      pendingRoomInviteSubtitle(_invite('invite_1', rid: 'R100')),
      '邀请你加入 · RID R100',
    );
    expect(pendingRoomInviteSubtitle(_invite('invite_2', rid: '')), '邀请你加入');
  });
}

PublicRoom _room(
  String id, {
  String? rid,
  bool joined = false,
  String joinPolicy = 'open',
  String joinState = 'none',
}) {
  return PublicRoom(
    id: id,
    rid: rid ?? id,
    name: 'Room $id',
    avatarUrl: null,
    defaultAvatarKey: 'room-1',
    visibility: 'public',
    joinPolicy: joinPolicy,
    memberCount: 3,
    liveParticipantCount: 0,
    joined: joined,
    joinState: joined ? 'joined' : joinState,
  );
}

RoomDetail _roomDetail() {
  return RoomDetail(
    id: 'room_1',
    name: 'Room',
    rid: 'R001',
    visibility: 'public',
    avatarUrl: null,
    defaultAvatarKey: 'room-1',
    memberCount: 1,
    description: '',
    createdBy: null,
    myMembership: RoomMembership(
      joinedAt: DateTime.utc(2026, 6, 4),
      role: 'member',
    ),
    live: LiveState(
      roomId: 'room_1',
      participantCount: 0,
      participants: const [],
      updatedAt: DateTime.utc(2026, 6, 4),
    ),
    createdAt: DateTime.utc(2026, 6, 4),
    updatedAt: DateTime.utc(2026, 6, 4),
  );
}

RoomInvite _invite(String id, {String? rid}) {
  return RoomInvite(
    id: id,
    status: 'pending',
    room: _room('room_$id', rid: rid),
    inviter: const UserSummary(
      id: 'inviter',
      username: 'inviter',
      displayName: 'Inviter',
      avatarUrl: null,
      defaultAvatarKey: 'blue-3',
    ),
    createdAt: DateTime.utc(2026, 6, 4),
  );
}
