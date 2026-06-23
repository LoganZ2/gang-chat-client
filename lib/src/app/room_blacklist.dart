import '../protocol/models.dart';
import 'room_members_filter.dart';

enum RoomBlacklistSearchBodyState { loading, prompt, empty, results }

class RoomBlacklistCandidate {
  const RoomBlacklistCandidate({
    required this.user,
    required this.member,
    required this.blocked,
    required this.superuser,
    required this.busy,
  });

  final UserSummary user;
  final bool member;
  final bool blocked;
  final bool superuser;
  final bool busy;

  bool get blockActionEnabled => !member && !superuser;
  bool get canBlock => blockActionEnabled && !blocked && !busy;
  bool get canUnblock => blocked && !busy;
}

RoomBlacklistSearchBodyState roomBlacklistSearchBodyState({
  required bool searching,
  required String query,
  required Iterable<RoomBlacklistCandidate> candidates,
}) {
  if (searching) return RoomBlacklistSearchBodyState.loading;
  if (query.trim().isEmpty) return RoomBlacklistSearchBodyState.prompt;
  if (candidates.isEmpty) return RoomBlacklistSearchBodyState.empty;
  return RoomBlacklistSearchBodyState.results;
}

List<RoomBlacklistCandidate> roomBlacklistCandidates({
  required Iterable<UserSummary> searchResults,
  required Iterable<RoomBlacklistEntry> blacklist,
  required Iterable<RoomMember> members,
  required String query,
  Iterable<String> busyUserIds = const [],
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final membersByUserId = {
    for (final member in members) member.user.id: member,
  };
  final blockedByUserId = {for (final entry in blacklist) entry.user.id: entry};
  final busySet = busyUserIds.toSet();
  final users = <UserSummary>[];
  final seenUserIds = <String>{};

  void add(UserSummary user) {
    if (seenUserIds.add(user.id)) users.add(user);
  }

  for (final user in searchResults) {
    if (_userIdentityMatchesQuery(user, normalizedQuery)) {
      add(user);
    }
  }
  if (normalizedQuery.isNotEmpty) {
    for (final entry in blacklist) {
      if (_userIdentityMatchesQuery(entry.user, normalizedQuery)) {
        add(entry.user);
      }
    }
    for (final member in members) {
      if (roomMemberSearchRank(member, normalizedQuery) < 99) {
        add(member.user);
      }
    }
  }

  return [
    for (final user in users)
      RoomBlacklistCandidate(
        user: user,
        member: membersByUserId.containsKey(user.id),
        blocked: blockedByUserId.containsKey(user.id),
        superuser: user.isSuperuser,
        busy: busySet.contains(user.id),
      ),
  ];
}

List<RoomBlacklistEntry> upsertRoomBlacklistEntry(
  Iterable<RoomBlacklistEntry> entries,
  RoomBlacklistEntry entry,
) {
  return [
    entry,
    for (final item in entries)
      if (item.user.id != entry.user.id) item,
  ];
}

List<RoomBlacklistEntry> removeRoomBlacklistEntry(
  Iterable<RoomBlacklistEntry> entries,
  String userId,
) {
  return [
    for (final item in entries)
      if (item.user.id != userId) item,
  ];
}

bool _userIdentityMatchesQuery(UserSummary user, String normalizedQuery) {
  if (normalizedQuery.isEmpty) return true;

  bool contains(String? value) {
    final text = value?.trim().toLowerCase();
    return text != null && text.isNotEmpty && text.contains(normalizedQuery);
  }

  return contains(user.uid) ||
      contains(user.id) ||
      contains(user.username) ||
      contains(user.displayName);
}
