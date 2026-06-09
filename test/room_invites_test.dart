import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/room_invites.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('roomInviteCandidates combines search results and matching members', () {
    final candidates = roomInviteCandidates(
      searchResults: [_user('external'), _user('member')],
      members: [
        _member('member', uid: '1001'),
        _member('remark', remarkName: 'Alpha note'),
      ],
      query: 'alpha',
    );

    expect(candidates.map((item) => item.user.id), [
      'external',
      'member',
      'remark',
    ]);
    expect(candidates[0].existing, isFalse);
    expect(candidates[1].existing, isTrue);
    expect(candidates[2].existing, isTrue);
  });

  test('roomInviteCandidates marks pending and busy invite states', () {
    final candidates = roomInviteCandidates(
      searchResults: [_user('pending'), _user('busy')],
      members: const [],
      query: 'user',
      pendingInviteUserIds: const ['pending'],
      busyUserIds: const ['busy'],
    );

    expect(candidates[0].pending, isTrue);
    expect(candidates[0].inviteActionEnabled, isFalse);
    expect(candidates[0].canStartInvite, isFalse);
    expect(candidates[1].busy, isTrue);
    expect(candidates[1].inviteActionEnabled, isTrue);
    expect(candidates[1].canStartInvite, isFalse);
  });

  test('roomInviteCandidates filters out superusers', () {
    final candidates = roomInviteCandidates(
      searchResults: [_user('super', isSuperuser: true), _user('normal')],
      members: [_member('member_super', isSuperuser: true), _member('member')],
      query: 'user',
    );

    expect(candidates.map((item) => item.user.id), ['normal', 'member']);
  });

  test(
    'roomInviteSearchBodyState describes loading prompt empty and results',
    () {
      final candidate = RoomInviteCandidate(
        user: _user('user_1'),
        existing: false,
        pending: false,
        busy: false,
      );

      expect(
        roomInviteSearchBodyState(
          searching: true,
          query: '',
          candidates: const [],
        ),
        RoomInviteSearchBodyState.loading,
      );
      expect(
        roomInviteSearchBodyState(
          searching: false,
          query: '   ',
          candidates: [candidate],
        ),
        RoomInviteSearchBodyState.prompt,
      );
      expect(
        roomInviteSearchBodyState(
          searching: false,
          query: 'logan',
          candidates: const [],
        ),
        RoomInviteSearchBodyState.empty,
      );
      expect(
        roomInviteSearchBodyState(
          searching: false,
          query: 'logan',
          candidates: [candidate],
        ),
        RoomInviteSearchBodyState.results,
      );
    },
  );

  test('canStartRoomInvite rejects existing pending and busy users', () {
    final members = [_member('existing')];

    expect(roomInvitesEnabled('open'), isTrue);
    expect(roomInvitesEnabled('approval_required'), isTrue);
    expect(roomInvitesEnabled('closed'), isFalse);
    expect(canStartRoomInvite(userId: 'existing', members: members), isFalse);
    expect(
      canStartRoomInvite(
        userId: 'pending',
        members: members,
        pendingInviteUserIds: const ['pending'],
      ),
      isFalse,
    );
    expect(
      canStartRoomInvite(
        userId: 'busy',
        members: members,
        busyUserIds: const ['busy'],
      ),
      isFalse,
    );
    expect(canStartRoomInvite(userId: 'new', members: members), isTrue);
    expect(
      canStartRoomInvite(
        userId: 'new',
        members: members,
        invitesEnabled: false,
      ),
      isFalse,
    );
    expect(
      canStartRoomInvite(userId: 'super', members: members, isSuperuser: true),
      isFalse,
    );
  });

  test('roomInviteCandidates disables invite actions when room is closed', () {
    final candidates = roomInviteCandidates(
      searchResults: [_user('new')],
      members: const [],
      query: 'user',
      invitesEnabled: false,
    );

    expect(candidates.single.existing, isTrue);
    expect(candidates.single.inviteActionEnabled, isFalse);
    expect(candidates.single.canStartInvite, isFalse);
  });

  test('room member invite action reducers update pending and busy ids', () {
    final started = roomMemberInviteActionStarted(
      userId: 'new',
      pendingInviteUserIds: const ['pending'],
      busyUserIds: const ['other_busy'],
    );
    expect(started.pendingInviteUserIds, {'pending'});
    expect(started.busyUserIds, {'other_busy', 'new'});

    final succeeded = roomMemberInviteActionSucceeded(
      userId: 'new',
      pendingInviteUserIds: started.pendingInviteUserIds,
      busyUserIds: started.busyUserIds,
    );
    expect(succeeded.pendingInviteUserIds, {'pending', 'new'});
    expect(succeeded.busyUserIds, {'other_busy'});

    final failed = roomMemberInviteActionFailed(
      userId: 'new',
      pendingInviteUserIds: started.pendingInviteUserIds,
      busyUserIds: started.busyUserIds,
    );
    expect(failed.pendingInviteUserIds, {'pending'});
    expect(failed.busyUserIds, {'other_busy'});
  });

  test('room member invite dialog search patches preserve ui state', () {
    final existingResults = [_user('existing')];

    final cleared = roomMemberInviteSearchCleared(
      pendingInviteUserIds: const ['pending'],
      busyUserIds: const ['busy'],
    );
    expect(cleared.searchResults, isEmpty);
    expect(cleared.searching, isFalse);
    expect(cleared.error, isNull);
    expect(cleared.pendingInviteUserIds, {'pending'});
    expect(cleared.busyUserIds, {'busy'});

    final started = roomMemberInviteSearchStarted(
      searchResults: existingResults,
      pendingInviteUserIds: const ['pending'],
      busyUserIds: const ['busy'],
    );
    expect(started.searchResults, existingResults);
    expect(started.searching, isTrue);
    expect(started.error, isNull);
    expect(started.pendingInviteUserIds, {'pending'});
    expect(started.busyUserIds, {'busy'});

    final inputStarted = roomMemberInviteSearchQueryChanged(
      rawQuery: '  user  ',
      searchResults: existingResults,
      pendingInviteUserIds: const ['pending'],
      busyUserIds: const ['busy'],
    );
    expect(inputStarted.query, 'user');
    expect(inputStarted.shouldSearch, isTrue);
    expect(inputStarted.shouldCancelInFlightSearch, isTrue);
    expect(inputStarted.dialog.searchResults, existingResults);
    expect(inputStarted.dialog.searching, isTrue);
    expect(inputStarted.dialog.pendingInviteUserIds, {'pending'});
    expect(inputStarted.dialog.busyUserIds, {'busy'});

    final inputCleared = roomMemberInviteSearchQueryChanged(
      rawQuery: '   ',
      searchResults: existingResults,
      pendingInviteUserIds: const ['pending'],
      busyUserIds: const ['busy'],
    );
    expect(inputCleared.query, '');
    expect(inputCleared.shouldSearch, isFalse);
    expect(inputCleared.shouldCancelInFlightSearch, isTrue);
    expect(inputCleared.dialog.searchResults, isEmpty);
    expect(inputCleared.dialog.searching, isFalse);
    expect(inputCleared.dialog.error, isNull);
    expect(inputCleared.dialog.pendingInviteUserIds, {'pending'});
    expect(inputCleared.dialog.busyUserIds, {'busy'});

    final succeeded = roomMemberInviteSearchSucceeded(
      searchResults: [_user('result')],
      pendingInviteUserIds: const ['pending'],
      busyUserIds: const ['busy'],
    );
    expect(succeeded.searchResults.map((user) => user.id), ['result']);
    expect(succeeded.searching, isFalse);
    expect(succeeded.error, isNull);
    expect(succeeded.pendingInviteUserIds, {'pending'});
    expect(succeeded.busyUserIds, {'busy'});

    final failed = roomMemberInviteSearchFailed(
      searchResults: existingResults,
      pendingInviteUserIds: const ['pending'],
      busyUserIds: const ['busy'],
      failure: Exception('search failed'),
    );
    expect(failed.searchResults, existingResults);
    expect(failed.searching, isFalse);
    expect(failed.error, contains('search failed'));
    expect(failed.pendingInviteUserIds, {'pending'});
    expect(failed.busyUserIds, {'busy'});
  });

  test('room member invite dialog action patches update invite state', () {
    final results = [_user('new')];

    final started = roomMemberInviteStarted(
      searchResults: results,
      searching: false,
      userId: 'new',
      pendingInviteUserIds: const ['pending'],
      busyUserIds: const ['other_busy'],
    );
    expect(started.searchResults, results);
    expect(started.searching, isFalse);
    expect(started.error, isNull);
    expect(started.pendingInviteUserIds, {'pending'});
    expect(started.busyUserIds, {'other_busy', 'new'});

    final succeeded = roomMemberInviteSucceeded(
      searchResults: results,
      searching: true,
      error: 'kept',
      userId: 'new',
      pendingInviteUserIds: started.pendingInviteUserIds,
      busyUserIds: started.busyUserIds,
    );
    expect(succeeded.searchResults, results);
    expect(succeeded.searching, isTrue);
    expect(succeeded.error, 'kept');
    expect(succeeded.pendingInviteUserIds, {'pending', 'new'});
    expect(succeeded.busyUserIds, {'other_busy'});

    final failed = roomMemberInviteFailed(
      searchResults: results,
      searching: true,
      userId: 'new',
      pendingInviteUserIds: started.pendingInviteUserIds,
      busyUserIds: started.busyUserIds,
      failure: Exception('invite failed'),
    );
    expect(failed.searchResults, results);
    expect(failed.searching, isTrue);
    expect(failed.error, contains('invite failed'));
    expect(failed.pendingInviteUserIds, {'pending'});
    expect(failed.busyUserIds, {'other_busy'});
  });

  test('reviewedRoomInvites removes invite and tracks pending room ids', () {
    final invite = _invite('invite_1', roomId: 'room_1');
    final state = reviewedRoomInvites(
      invites: [
        invite,
        _invite('invite_2', roomId: 'room_2'),
      ],
      pendingRoomIds: const ['existing_room'],
      invite: invite,
      accept: true,
      result: const JoinRoomResult(pending: true),
    );

    expect(state.invites.map((item) => item.id), ['invite_2']);
    expect(state.pendingRoomIds, {'existing_room', 'room_1'});
    expect(state.hasPendingInvites, isTrue);

    final rejected = reviewedRoomInvites(
      invites: [invite],
      pendingRoomIds: const [],
      invite: invite,
      accept: false,
      result: const JoinRoomResult(),
    );

    expect(rejected.invites, isEmpty);
    expect(rejected.pendingRoomIds, isEmpty);
    expect(rejected.hasPendingInvites, isFalse);
  });
}

RoomMember _member(
  String id, {
  String? uid,
  String? remarkName,
  bool isSuperuser = false,
}) {
  return RoomMember(
    user: _user(id, uid: uid, isSuperuser: isSuperuser),
    role: 'member',
    joinedAt: DateTime.utc(2026, 6, 5),
    remarkName: remarkName,
  );
}

UserSummary _user(String id, {String? uid, bool isSuperuser = false}) {
  return UserSummary(
    id: id,
    username: 'user_$id',
    displayName: 'User $id',
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    uid: uid,
    isSuperuser: isSuperuser,
  );
}

RoomInvite _invite(String id, {required String roomId}) {
  return RoomInvite(
    id: id,
    status: 'pending',
    room: PublicRoom(
      id: roomId,
      rid: roomId,
      name: roomId,
      avatarUrl: null,
      defaultAvatarKey: 'room-1',
      visibility: 'public',
      joinPolicy: 'approval_required',
      memberCount: 3,
      liveParticipantCount: 0,
      joined: false,
      joinState: 'none',
    ),
    inviter: _user('inviter_$id'),
    createdAt: DateTime.utc(2026, 6, 5),
  );
}
