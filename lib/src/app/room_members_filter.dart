import '../protocol/models.dart';

enum RoomMemberPresence { live, online, offline }

enum RoomMemberPresenceFilter { all, online, offline }

enum RoomMemberRoleFilter { all, member, admin }

class RoomMemberPermissionState {
  const RoomMemberPermissionState({
    required this.isSuperuser,
    required this.isOwner,
    required this.isAdmin,
    required this.canRoleEdit,
    required this.canRemoveMember,
  });

  final bool isSuperuser;
  final bool isOwner;
  final bool isAdmin;
  final bool canRoleEdit;
  final bool canRemoveMember;

  bool get canSetAdmin => canRoleEdit && !isAdmin;
  bool get canUnsetAdmin => canRoleEdit && isAdmin;
  bool get canTransferCreator => canRoleEdit;
  String get adminActionLabel => isAdmin ? '移除管理员' : '设为管理员';
}

class RoomMemberManagementPatch {
  const RoomMemberManagementPatch({
    required this.room,
    required this.members,
    required this.busyMemberIds,
    required this.changed,
    required this.error,
    required this.notice,
  });

  final RoomDetail room;
  final List<RoomMember> members;
  final Set<String> busyMemberIds;
  final bool changed;
  final String? error;
  final String? notice;
}

class RoomMemberLoadPatch {
  const RoomMemberLoadPatch({
    required this.members,
    required this.loading,
    required this.error,
  });

  final List<RoomMember> members;
  final bool loading;
  final String? error;
}

class RoomMemberFilterPatch {
  const RoomMemberFilterPatch({
    required this.searchQuery,
    required this.presenceFilter,
    required this.roleFilter,
  });

  final String searchQuery;
  final RoomMemberPresenceFilter presenceFilter;
  final RoomMemberRoleFilter roleFilter;
}

class RoomMemberPresenceGroup {
  const RoomMemberPresenceGroup({
    required this.presence,
    required this.members,
  });

  final RoomMemberPresence presence;
  final List<RoomMember> members;

  int get count => members.length;
}

class RoomMemberFilterCounts {
  const RoomMemberFilterCounts({
    required this.allPresence,
    required this.online,
    required this.offline,
    required this.allRoles,
    required this.roleMembers,
    required this.admins,
  });

  final int allPresence;
  final int online;
  final int offline;
  final int allRoles;
  final int roleMembers;
  final int admins;
}

bool canStartRoomMemberAction({
  required String userId,
  required Iterable<String> busyMemberIds,
}) {
  return !busyMemberIds.contains(userId);
}

bool roomMemberActionBusy({
  required RoomMember member,
  required Iterable<String> busyMemberIds,
}) {
  return busyMemberIds.contains(member.user.id);
}

String roomMemberRoleUpdateNotice(String role) {
  return role == 'admin' ? '已授予管理员身份' : '已移除管理员身份';
}

String roomMemberRoleUpdateConfirmTitle(String role) {
  return role == 'admin' ? '设为管理员' : '移除管理员';
}

String roomMemberRoleUpdateConfirmBody(RoomMember member, String role) {
  final name = roomMemberDisplayName(member);
  return role == 'admin' ? '确定要将 $name 设为管理员吗？' : '确定要移除 $name 的管理员身份吗？';
}

String roomMemberRoleUpdateConfirmLabel(String role) {
  return role == 'admin' ? '设为管理员' : '移除';
}

String transferCreatorDialogTitle() {
  return '转让创建者';
}

String transferCreatorConfirmBody(RoomMember member) {
  return '创建者身份会转让给 ${roomMemberDisplayName(member)}，你将成为管理员。';
}

String transferCreatorConfirmLabel() {
  return '转让';
}

String transferCreatorSuccessNotice() {
  return '创建者已转让';
}

String removeRoomMemberConfirmTitle() {
  return '踢出此用户';
}

String removeRoomMemberConfirmBody(RoomMember member) {
  return '确定要将 ${roomMemberDisplayName(member)} 从房间中移除吗？';
}

String removeRoomMemberConfirmLabel() {
  return '踢出';
}

String removeRoomMemberSuccessNotice(RoomMember member) {
  return '已踢出 ${roomMemberDisplayName(member)}';
}

RoomMemberLoadPatch roomMembersLoadStarted({
  required Iterable<RoomMember> members,
}) {
  return RoomMemberLoadPatch(
    members: members.toList(),
    loading: true,
    error: null,
  );
}

RoomMemberLoadPatch roomMembersLoadSucceeded({
  required Iterable<RoomMember> members,
}) {
  return RoomMemberLoadPatch(
    members: members.toList(),
    loading: false,
    error: null,
  );
}

RoomMemberLoadPatch roomMembersLoadFailed({
  required Iterable<RoomMember> members,
  required Object failure,
}) {
  return RoomMemberLoadPatch(
    members: members.toList(),
    loading: false,
    error: failure.toString(),
  );
}

RoomMemberFilterPatch roomMemberPresenceFilterChanged({
  required String searchQuery,
  required RoomMemberRoleFilter roleFilter,
  required RoomMemberPresenceFilter presenceFilter,
}) {
  return RoomMemberFilterPatch(
    searchQuery: searchQuery,
    presenceFilter: presenceFilter,
    roleFilter: roleFilter,
  );
}

RoomMemberFilterPatch roomMemberRoleFilterChanged({
  required String searchQuery,
  required RoomMemberPresenceFilter presenceFilter,
  required RoomMemberRoleFilter roleFilter,
}) {
  return RoomMemberFilterPatch(
    searchQuery: searchQuery,
    presenceFilter: presenceFilter,
    roleFilter: roleFilter,
  );
}

RoomMemberFilterPatch roomMemberSearchQueryChanged({
  required String searchQuery,
  required RoomMemberPresenceFilter presenceFilter,
  required RoomMemberRoleFilter roleFilter,
}) {
  return RoomMemberFilterPatch(
    searchQuery: searchQuery,
    presenceFilter: presenceFilter,
    roleFilter: roleFilter,
  );
}

RoomMemberManagementPatch roomMemberManagementActionStarted({
  required RoomDetail room,
  required Iterable<RoomMember> members,
  required bool changed,
  required String userId,
  required Iterable<String> busyMemberIds,
}) {
  return RoomMemberManagementPatch(
    room: room,
    members: members.toList(),
    busyMemberIds: {...busyMemberIds, userId},
    changed: changed,
    error: null,
    notice: null,
  );
}

RoomMemberManagementPatch roomMemberRoleUpdateSucceeded({
  required RoomDetail room,
  required Iterable<RoomMember> members,
  required RoomMember updated,
  required String role,
  required Iterable<String> busyMemberIds,
}) {
  return RoomMemberManagementPatch(
    room: room,
    members: replaceRoomMember(members, updated),
    busyMemberIds: {
      for (final userId in busyMemberIds)
        if (userId != updated.user.id) userId,
    },
    changed: true,
    error: null,
    notice: roomMemberRoleUpdateNotice(role),
  );
}

RoomMemberManagementPatch roomMemberRoleUpdateFailed({
  required RoomDetail room,
  required Iterable<RoomMember> members,
  required bool changed,
  required String userId,
  required Iterable<String> busyMemberIds,
  required Object failure,
}) {
  return RoomMemberManagementPatch(
    room: room,
    members: members.toList(),
    busyMemberIds: {
      for (final item in busyMemberIds)
        if (item != userId) item,
    },
    changed: changed,
    error: failure.toString(),
    notice: null,
  );
}

RoomMemberManagementPatch roomMemberRemovedSucceeded({
  required RoomDetail room,
  required Iterable<RoomMember> members,
  required RoomMember removed,
  required Iterable<String> busyMemberIds,
}) {
  return RoomMemberManagementPatch(
    room: room,
    members: [
      for (final member in members)
        if (member.user.id != removed.user.id) member,
    ],
    busyMemberIds: {
      for (final item in busyMemberIds)
        if (item != removed.user.id) item,
    },
    changed: true,
    error: null,
    notice: removeRoomMemberSuccessNotice(removed),
  );
}

RoomMemberManagementPatch roomMemberRemoveFailed({
  required RoomDetail room,
  required Iterable<RoomMember> members,
  required bool changed,
  required String userId,
  required Iterable<String> busyMemberIds,
  required Object failure,
}) {
  return RoomMemberManagementPatch(
    room: room,
    members: members.toList(),
    busyMemberIds: {
      for (final item in busyMemberIds)
        if (item != userId) item,
    },
    changed: changed,
    error: failure.toString(),
    notice: null,
  );
}

RoomMemberManagementPatch transferCreatorSucceeded({
  required RoomDetail updatedRoom,
  required Iterable<RoomMember> members,
  required String userId,
  required Iterable<String> busyMemberIds,
}) {
  return RoomMemberManagementPatch(
    room: updatedRoom,
    members: members.toList(),
    busyMemberIds: {
      for (final item in busyMemberIds)
        if (item != userId) item,
    },
    changed: true,
    error: null,
    notice: transferCreatorSuccessNotice(),
  );
}

RoomMemberManagementPatch transferCreatorFailed({
  required RoomDetail room,
  required Iterable<RoomMember> members,
  required bool changed,
  required String userId,
  required Iterable<String> busyMemberIds,
  required Object failure,
}) {
  return RoomMemberManagementPatch(
    room: room,
    members: members.toList(),
    busyMemberIds: {
      for (final item in busyMemberIds)
        if (item != userId) item,
    },
    changed: changed,
    error: failure.toString(),
    notice: null,
  );
}

String roomMemberPresenceLabel(RoomMemberPresence presence) {
  return switch (presence) {
    RoomMemberPresence.live => '语音',
    RoomMemberPresence.online => '在线',
    RoomMemberPresence.offline => '离线',
  };
}

RoomMemberFilterCounts roomMemberFilterCounts({
  required Iterable<RoomMember> members,
  required LiveState live,
  String? ownerUserId,
}) {
  var allPresence = 0;
  var online = 0;
  var offline = 0;
  var allRoles = 0;
  var roleMembers = 0;
  var admins = 0;

  for (final member in members) {
    allPresence += 1;
    allRoles += 1;

    final presence = roomMemberPresence(member, live: live);
    if (presence == RoomMemberPresence.offline) {
      offline += 1;
    } else {
      online += 1;
    }

    if (_matchesRoleFilter(
      member,
      RoomMemberRoleFilter.member,
      ownerUserId: ownerUserId,
    )) {
      roleMembers += 1;
    }
    if (_matchesRoleFilter(
      member,
      RoomMemberRoleFilter.admin,
      ownerUserId: ownerUserId,
    )) {
      admins += 1;
    }
  }

  return RoomMemberFilterCounts(
    allPresence: allPresence,
    online: online,
    offline: offline,
    allRoles: allRoles,
    roleMembers: roleMembers,
    admins: admins,
  );
}

String roomMemberPresenceFilterLabel(
  RoomMemberPresenceFilter filter,
  RoomMemberFilterCounts counts,
) {
  final (label, count) = switch (filter) {
    RoomMemberPresenceFilter.all => ('全部', counts.allPresence),
    RoomMemberPresenceFilter.online => ('在线', counts.online),
    RoomMemberPresenceFilter.offline => ('离线', counts.offline),
  };
  return '$label $count';
}

String roomMemberRoleFilterLabel(
  RoomMemberRoleFilter filter,
  RoomMemberFilterCounts counts,
) {
  final (label, count) = switch (filter) {
    RoomMemberRoleFilter.all => ('所有身份', counts.allRoles),
    RoomMemberRoleFilter.member => ('成员', counts.roleMembers),
    RoomMemberRoleFilter.admin => ('管理员', counts.admins),
  };
  return '$label $count';
}

List<RoomMember> visibleRoomMembers({
  required Iterable<RoomMember> members,
  required LiveState live,
  required RoomMemberPresenceFilter presenceFilter,
  required RoomMemberRoleFilter roleFilter,
  required String query,
  String? ownerUserId,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final visible = members.where((member) {
    final presence = roomMemberPresence(member, live: live);
    if (presenceFilter == RoomMemberPresenceFilter.online &&
        presence == RoomMemberPresence.offline) {
      return false;
    }
    if (presenceFilter == RoomMemberPresenceFilter.offline &&
        presence != RoomMemberPresence.offline) {
      return false;
    }
    if (!_matchesRoleFilter(member, roleFilter, ownerUserId: ownerUserId)) {
      return false;
    }
    if (normalizedQuery.isEmpty) return true;
    return roomMemberSearchRank(member, normalizedQuery) < 99;
  }).toList();
  visible.sort(
    (a, b) => compareRoomMembers(
      a,
      b,
      live: live,
      query: normalizedQuery,
      ownerUserId: ownerUserId,
    ),
  );
  return visible;
}

List<RoomMemberPresenceGroup> roomMemberPresenceGroups({
  required Iterable<RoomMember> members,
  required LiveState live,
}) {
  final buckets = {
    for (final presence in RoomMemberPresence.values) presence: <RoomMember>[],
  };
  for (final member in members) {
    buckets[roomMemberPresence(member, live: live)]!.add(member);
  }
  return [
    for (final presence in RoomMemberPresence.values)
      if (buckets[presence]!.isNotEmpty)
        RoomMemberPresenceGroup(
          presence: presence,
          members: List.unmodifiable(buckets[presence]!),
        ),
  ];
}

List<RoomMember> roomMembersWithCurrentUserPresence(
  Iterable<RoomMember> members, {
  required String currentUserId,
}) {
  return [
    for (final member in members)
      roomMemberWithCurrentUserPresence(member, currentUserId: currentUserId),
  ];
}

RoomMember roomMemberWithCurrentUserPresence(
  RoomMember member, {
  required String currentUserId,
}) {
  if (currentUserId.isEmpty || member.user.id != currentUserId) {
    return member;
  }
  if (member.isOnline == true && member.user.isOnline == true) {
    return member;
  }
  return RoomMember(
    user: member.user.copyWith(isOnline: true),
    role: member.role,
    joinedAt: member.joinedAt,
    roomDisplayName: member.roomDisplayName,
    remarkName: member.remarkName,
    textMutedUntil: member.textMutedUntil,
    isOnline: true,
  );
}

RoomMemberPresence roomMemberPresence(
  RoomMember member, {
  required LiveState live,
}) {
  final inLive = live.participants.any((p) => p.user.id == member.user.id);
  if (inLive) return RoomMemberPresence.live;
  if (member.isOnline ?? false) return RoomMemberPresence.online;
  return RoomMemberPresence.offline;
}

int compareRoomMembers(
  RoomMember a,
  RoomMember b, {
  required LiveState live,
  required String query,
  String? ownerUserId,
}) {
  final presence =
      _presenceRank(roomMemberPresence(a, live: live)) -
      _presenceRank(roomMemberPresence(b, live: live));
  if (presence != 0) return presence;

  final role =
      roomMemberRoleRank(a, ownerUserId: ownerUserId) -
      roomMemberRoleRank(b, ownerUserId: ownerUserId);
  if (role != 0) return role;

  if (query.isNotEmpty) {
    final search =
        roomMemberSearchRank(a, query) - roomMemberSearchRank(b, query);
    if (search != 0) return search;
  }

  final name = roomMemberDisplayName(
    a,
  ).toLowerCase().compareTo(roomMemberDisplayName(b).toLowerCase());
  if (name != 0) return name;
  return (a.user.uid ?? a.user.id).compareTo(b.user.uid ?? b.user.id);
}

int roomMemberRoleRank(RoomMember member, {String? ownerUserId}) {
  if (isSuperuserRoomMember(member)) return 0;
  if (isOwnerRoomMember(member, ownerUserId: ownerUserId)) return 1;
  if (isAdminRoomMember(member)) return 2;
  return 3;
}

bool isSuperuserRoomMember(RoomMember member) {
  final role = member.role.toLowerCase();
  return member.user.isSuperuser || role == 'superuser';
}

bool isOwnerRoomMember(RoomMember member, {String? ownerUserId}) {
  final role = member.role.toLowerCase();
  return member.user.id == ownerUserId || role == 'owner' || role == 'creator';
}

bool isAdminRoomMember(RoomMember member) {
  final role = member.role.toLowerCase();
  return role == 'admin' || role == 'administrator';
}

RoomMemberPermissionState roomMemberPermissionState({
  required RoomMember member,
  required CurrentUser currentUser,
  required bool canEditCreatorOnly,
  bool canManageMembers = false,
  String? ownerUserId,
}) {
  final isSuperuser = isSuperuserRoomMember(member);
  final isOwner = isOwnerRoomMember(member, ownerUserId: ownerUserId);
  final isAdmin = isAdminRoomMember(member);
  final canRoleEdit =
      canEditCreatorOnly &&
      !isSuperuser &&
      !isOwner &&
      member.user.id != currentUser.id;
  final canRemoveMember =
      canManageMembers &&
      !isSuperuser &&
      !isOwner &&
      member.user.id != currentUser.id &&
      (canEditCreatorOnly || !isAdmin);
  return RoomMemberPermissionState(
    isSuperuser: isSuperuser,
    isOwner: isOwner,
    isAdmin: isAdmin,
    canRoleEdit: canRoleEdit,
    canRemoveMember: canRemoveMember,
  );
}

String roomMemberDisplayName(RoomMember member) {
  return _nonEmpty(member.roomDisplayName) ??
      _nonEmpty(member.user.roomDisplayName) ??
      _nonEmpty(member.user.displayName) ??
      member.user.username;
}

int roomMemberSearchRank(RoomMember member, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return 0;

  bool contains(String? value) {
    final text = _nonEmpty(value)?.toLowerCase();
    return text != null && text.contains(normalizedQuery);
  }

  if (contains(member.user.uid) || contains(member.user.id)) return 0;
  if (contains(member.roomDisplayName) ||
      contains(member.user.roomDisplayName) ||
      contains(member.user.displayName) ||
      contains(member.user.username)) {
    return 1;
  }
  if (contains(member.remarkName)) return 2;
  return 99;
}

String roomMemberMeta(RoomMember member) {
  final uid = member.user.uid ?? member.user.id;
  final remark = _nonEmpty(member.remarkName);
  final parts = <String>[uid, '@${member.user.username}'];
  if (remark != null) parts.add('备注 $remark');
  return parts.join(' · ');
}

List<RoomMember> replaceRoomMember(
  Iterable<RoomMember> members,
  RoomMember updated,
) {
  return [
    for (final member in members)
      if (member.user.id == updated.user.id) updated else member,
  ];
}

bool _matchesRoleFilter(
  RoomMember member,
  RoomMemberRoleFilter filter, {
  String? ownerUserId,
}) {
  return switch (filter) {
    RoomMemberRoleFilter.all => true,
    RoomMemberRoleFilter.member =>
      !isSuperuserRoomMember(member) &&
          !isOwnerRoomMember(member, ownerUserId: ownerUserId) &&
          !isAdminRoomMember(member),
    RoomMemberRoleFilter.admin =>
      isSuperuserRoomMember(member) ||
          isOwnerRoomMember(member, ownerUserId: ownerUserId) ||
          isAdminRoomMember(member),
  };
}

int _presenceRank(RoomMemberPresence value) {
  return switch (value) {
    RoomMemberPresence.live => 0,
    RoomMemberPresence.online => 1,
    RoomMemberPresence.offline => 2,
  };
}

String? _nonEmpty(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  return text;
}
