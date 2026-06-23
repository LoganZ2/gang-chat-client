import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/room_blacklist.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('roomBlacklistCandidates combines search results and blocked users', () {
    final blocked = _blacklistEntry(
      _user('blocked', displayName: 'Alpha Gone'),
    );
    final candidates = roomBlacklistCandidates(
      searchResults: [
        _user('external', displayName: 'Alpha External'),
        _user('member', displayName: 'Alpha Member'),
      ],
      blacklist: [blocked],
      members: [_member('member')],
      query: 'alpha',
    );

    expect(candidates.map((item) => item.user.id), [
      'external',
      'member',
      'blocked',
    ]);
    expect(candidates[0].member, isFalse);
    expect(candidates[0].blocked, isFalse);
    expect(candidates[1].member, isTrue);
    expect(candidates[1].blockActionEnabled, isFalse);
    expect(candidates[2].blocked, isTrue);
    expect(candidates[2].canUnblock, isTrue);
  });

  test('roomBlacklistCandidates ignores room names in user search context', () {
    final candidates = roomBlacklistCandidates(
      searchResults: [
        _user(
          'room_context',
          roomDisplayName: 'Alpha Room Alias',
          commonRooms: const [
            UserCommonRoom(
              id: 'room_1',
              rid: 'R10001',
              name: 'Alpha Common Room',
              roomDisplayName: 'Alpha Shared Name',
            ),
          ],
        ),
        _user('display_match', displayName: 'Alpha Person'),
      ],
      blacklist: const [],
      members: [_member('room_member', roomDisplayName: 'Alpha Current Room')],
      query: 'alpha',
    );

    expect(candidates.map((item) => item.user.id), ['display_match']);
  });

  test('roomBlacklistCandidates marks protected and busy states', () {
    final candidates = roomBlacklistCandidates(
      searchResults: [_user('super', isSuperuser: true), _user('busy')],
      blacklist: const [],
      members: const [],
      query: 'user',
      busyUserIds: const ['busy'],
    );

    expect(candidates[0].superuser, isTrue);
    expect(candidates[0].blockActionEnabled, isFalse);
    expect(candidates[1].busy, isTrue);
    expect(candidates[1].canBlock, isFalse);
  });

  test(
    'roomBlacklistSearchBodyState describes loading prompt empty and results',
    () {
      final candidate = RoomBlacklistCandidate(
        user: _user('user_1'),
        member: false,
        blocked: false,
        superuser: false,
        busy: false,
      );

      expect(
        roomBlacklistSearchBodyState(
          searching: true,
          query: '',
          candidates: const [],
        ),
        RoomBlacklistSearchBodyState.loading,
      );
      expect(
        roomBlacklistSearchBodyState(
          searching: false,
          query: '   ',
          candidates: [candidate],
        ),
        RoomBlacklistSearchBodyState.prompt,
      );
      expect(
        roomBlacklistSearchBodyState(
          searching: false,
          query: 'logan',
          candidates: const [],
        ),
        RoomBlacklistSearchBodyState.empty,
      );
      expect(
        roomBlacklistSearchBodyState(
          searching: false,
          query: 'logan',
          candidates: [candidate],
        ),
        RoomBlacklistSearchBodyState.results,
      );
    },
  );

  test('upsert and remove room blacklist entries keep one row per user', () {
    final oldEntry = _blacklistEntry(_user('blocked', displayName: 'Old'));
    final newEntry = _blacklistEntry(_user('blocked', displayName: 'New'));
    final other = _blacklistEntry(_user('other'));

    final updated = upsertRoomBlacklistEntry([oldEntry, other], newEntry);

    expect(updated.map((item) => item.user.displayName), ['New', 'User other']);
    expect(removeRoomBlacklistEntry(updated, 'blocked'), [other]);
  });
}

RoomBlacklistEntry _blacklistEntry(UserSummary user) {
  return RoomBlacklistEntry(user: user, createdAt: DateTime.utc(2026, 6, 23));
}

RoomMember _member(String id, {String? roomDisplayName}) {
  return RoomMember(
    user: _user(id),
    role: 'member',
    joinedAt: DateTime.utc(2026, 6, 5),
    roomDisplayName: roomDisplayName,
  );
}

UserSummary _user(
  String id, {
  String? displayName,
  String? roomDisplayName,
  List<UserCommonRoom> commonRooms = const [],
  bool isSuperuser = false,
}) {
  return UserSummary(
    id: id,
    username: 'user_$id',
    displayName: displayName ?? 'User $id',
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    roomDisplayName: roomDisplayName,
    commonRooms: commonRooms,
    isSuperuser: isSuperuser,
  );
}
