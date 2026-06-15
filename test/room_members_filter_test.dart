import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/room_members_filter.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('roomMemberPresenceLabel exposes reusable display labels', () {
    expect(roomMemberPresenceLabel(RoomMemberPresence.live), '语音');
    expect(roomMemberPresenceLabel(RoomMemberPresence.online), '在线');
    expect(roomMemberPresenceLabel(RoomMemberPresence.offline), '离线');
  });

  test('room member filter counts feed presence and role labels', () {
    final counts = roomMemberFilterCounts(
      members: [
        _member('owner', isOnline: false),
        _member('admin', role: 'admin', isOnline: true),
        _member('member', isOnline: false),
        _member('live_member', isOnline: false),
      ],
      live: _live(['live_member']),
      ownerUserId: 'owner',
    );

    expect(counts.allPresence, 4);
    expect(counts.online, 2);
    expect(counts.offline, 2);
    expect(counts.allRoles, 4);
    expect(counts.roleMembers, 2);
    expect(counts.admins, 2);
    expect(
      roomMemberPresenceFilterLabel(RoomMemberPresenceFilter.all, counts),
      '全部 4',
    );
    expect(
      roomMemberPresenceFilterLabel(RoomMemberPresenceFilter.online, counts),
      '在线 2',
    );
    expect(
      roomMemberPresenceFilterLabel(RoomMemberPresenceFilter.offline, counts),
      '离线 2',
    );
    expect(
      roomMemberRoleFilterLabel(RoomMemberRoleFilter.all, counts),
      '所有身份 4',
    );
    expect(
      roomMemberRoleFilterLabel(RoomMemberRoleFilter.member, counts),
      '成员 2',
    );
    expect(
      roomMemberRoleFilterLabel(RoomMemberRoleFilter.admin, counts),
      '管理员 2',
    );
  });

  test('room member filter patches preserve the other filter dimension', () {
    final presencePatch = roomMemberPresenceFilterChanged(
      searchQuery: 'alice',
      presenceFilter: RoomMemberPresenceFilter.online,
      roleFilter: RoomMemberRoleFilter.admin,
    );

    expect(presencePatch.searchQuery, 'alice');
    expect(presencePatch.presenceFilter, RoomMemberPresenceFilter.online);
    expect(presencePatch.roleFilter, RoomMemberRoleFilter.admin);

    final rolePatch = roomMemberRoleFilterChanged(
      searchQuery: 'bob',
      presenceFilter: RoomMemberPresenceFilter.offline,
      roleFilter: RoomMemberRoleFilter.member,
    );

    expect(rolePatch.searchQuery, 'bob');
    expect(rolePatch.presenceFilter, RoomMemberPresenceFilter.offline);
    expect(rolePatch.roleFilter, RoomMemberRoleFilter.member);

    final searchPatch = roomMemberSearchQueryChanged(
      searchQuery: 'carol',
      presenceFilter: RoomMemberPresenceFilter.all,
      roleFilter: RoomMemberRoleFilter.all,
    );
    expect(searchPatch.searchQuery, 'carol');
    expect(searchPatch.presenceFilter, RoomMemberPresenceFilter.all);
    expect(searchPatch.roleFilter, RoomMemberRoleFilter.all);
  });

  test('visibleRoomMembers sorts by live presence before online state', () {
    final members = [
      _member('offline_owner', role: 'member', isOnline: false),
      _member('online_member', isOnline: true),
      _member('live_member', isOnline: false),
    ];

    final visible = visibleRoomMembers(
      members: members,
      live: _live(['live_member']),
      presenceFilter: RoomMemberPresenceFilter.all,
      roleFilter: RoomMemberRoleFilter.all,
      query: '',
      ownerUserId: 'offline_owner',
    );

    expect(visible.map((member) => member.user.id), [
      'live_member',
      'online_member',
      'offline_owner',
    ]);
  });

  test('visibleRoomMembers sorts members with equal presence by room role', () {
    final members = [
      _member('member'),
      _member('admin', role: 'admin'),
      _member('owner'),
      _member('superuser', isSuperuser: true),
    ];

    final visible = visibleRoomMembers(
      members: members,
      live: _live(),
      presenceFilter: RoomMemberPresenceFilter.all,
      roleFilter: RoomMemberRoleFilter.all,
      query: '',
      ownerUserId: 'owner',
    );

    expect(visible.map((member) => member.user.id), [
      'superuser',
      'owner',
      'admin',
      'member',
    ]);
  });

  test('roomMemberPresenceGroups buckets members in display order', () {
    final members = [
      _member('offline', isOnline: false),
      _member('online', isOnline: true),
      _member('live', isOnline: false),
      _member('also_live', isOnline: true),
    ];

    final groups = roomMemberPresenceGroups(
      members: members,
      live: _live(['live', 'also_live']),
    );

    expect(groups.map((group) => group.presence), [
      RoomMemberPresence.live,
      RoomMemberPresence.online,
      RoomMemberPresence.offline,
    ]);
    expect(groups.map((group) => group.count), [2, 1, 1]);
    expect(groups[0].members.map((member) => member.user.id), [
      'live',
      'also_live',
    ]);
    expect(groups[1].members.single.user.id, 'online');
    expect(groups[2].members.single.user.id, 'offline');
  });

  test('current user presence fallback keeps the signed-in member online', () {
    final self = _member('self', isOnline: false);
    final other = _member('other', isOnline: false);

    final members = roomMembersWithCurrentUserPresence([
      self,
      other,
    ], currentUserId: 'self');

    expect(members.first.user.id, 'self');
    expect(members.first.isOnline, isTrue);
    expect(members.first.user.isOnline, isTrue);
    expect(members.last, same(other));
    expect(
      roomMemberPresence(members.first, live: _live()),
      RoomMemberPresence.online,
    );

    final online = visibleRoomMembers(
      members: members,
      live: _live(),
      presenceFilter: RoomMemberPresenceFilter.online,
      roleFilter: RoomMemberRoleFilter.all,
      query: '',
    );
    expect(online.map((member) => member.user.id), ['self']);
  });

  test('visibleRoomMembers filters presence and role consistently', () {
    final members = [
      _member('live_admin', role: 'admin', isOnline: false),
      _member('online_member', isOnline: true),
      _member('offline_member', isOnline: false),
    ];

    final online = visibleRoomMembers(
      members: members,
      live: _live(['live_admin']),
      presenceFilter: RoomMemberPresenceFilter.online,
      roleFilter: RoomMemberRoleFilter.all,
      query: '',
    );
    expect(online.map((member) => member.user.id), [
      'live_admin',
      'online_member',
    ]);

    final offlineMembers = visibleRoomMembers(
      members: members,
      live: _live(['live_admin']),
      presenceFilter: RoomMemberPresenceFilter.offline,
      roleFilter: RoomMemberRoleFilter.member,
      query: '',
    );
    expect(offlineMembers.map((member) => member.user.id), ['offline_member']);

    final admins = visibleRoomMembers(
      members: members,
      live: _live(['live_admin']),
      presenceFilter: RoomMemberPresenceFilter.all,
      roleFilter: RoomMemberRoleFilter.admin,
      query: '',
    );
    expect(admins.map((member) => member.user.id), ['live_admin']);
  });

  test('search rank prefers uid then display name then remark', () {
    final members = [
      _member('remark_match', remarkName: 'alpha note'),
      _member('name_match', displayName: 'Alpha Name'),
      _member('uid_match', uid: 'alpha-001'),
      _member('miss'),
    ];

    final visible = visibleRoomMembers(
      members: members,
      live: _live(),
      presenceFilter: RoomMemberPresenceFilter.all,
      roleFilter: RoomMemberRoleFilter.all,
      query: 'alpha',
    );

    expect(visible.map((member) => member.user.id), [
      'uid_match',
      'name_match',
      'remark_match',
    ]);
  });

  test('replaceRoomMember swaps the member with the same user id', () {
    final members = [_member('a'), _member('b'), _member('c')];
    final updated = _member('b', role: 'admin');

    final next = replaceRoomMember(members, updated);

    expect(next.map((member) => member.user.id), ['a', 'b', 'c']);
    expect(next[1].role, 'admin');
    expect(next[0], same(members[0]));
    expect(next[2], same(members[2]));
  });

  test('room member action helpers guard busy members', () {
    final member = _member('busy');
    final busyMemberIds = {'busy'};

    expect(
      canStartRoomMemberAction(userId: 'busy', busyMemberIds: busyMemberIds),
      isFalse,
    );
    expect(
      canStartRoomMemberAction(userId: 'idle', busyMemberIds: busyMemberIds),
      isTrue,
    );
    expect(
      roomMemberActionBusy(member: member, busyMemberIds: busyMemberIds),
      isTrue,
    );
  });

  test('room member action helpers provide role and transfer copy', () {
    final member = _member('target', roomDisplayName: 'Room Target');

    expect(roomMemberRoleUpdateNotice('admin'), '已授予管理员身份');
    expect(roomMemberRoleUpdateNotice('member'), '已移除管理员身份');
    expect(roomMemberRoleUpdateConfirmTitle('admin'), '设为管理员');
    expect(roomMemberRoleUpdateConfirmTitle('member'), '移除管理员');
    expect(
      roomMemberRoleUpdateConfirmBody(member, 'admin'),
      '确定要将 Room Target 设为管理员吗？',
    );
    expect(
      roomMemberRoleUpdateConfirmBody(member, 'member'),
      '确定要移除 Room Target 的管理员身份吗？',
    );
    expect(roomMemberRoleUpdateConfirmLabel('admin'), '设为管理员');
    expect(roomMemberRoleUpdateConfirmLabel('member'), '移除');
    expect(transferCreatorDialogTitle(), '转让创建者');
    expect(
      transferCreatorConfirmBody(member),
      '创建者身份会转让给 Room Target，你将成为管理员。',
    );
    expect(transferCreatorConfirmLabel(), '转让');
    expect(transferCreatorSuccessNotice(), '创建者已转让');
    expect(removeRoomMemberConfirmTitle(), '踢出此用户');
    expect(removeRoomMemberConfirmBody(member), '确定要将 Room Target 从房间中移除吗？');
    expect(removeRoomMemberConfirmLabel(), '踢出');
    expect(removeRoomMemberSuccessNotice(member), '已踢出 Room Target');
  });

  test('roomMemberPermissionState gates creator-only member role actions', () {
    final currentUser = _currentUser('current');

    final member = roomMemberPermissionState(
      member: _member('member'),
      currentUser: currentUser,
      canEditCreatorOnly: true,
      canManageMembers: true,
      ownerUserId: 'owner',
    );
    expect(member.canSetAdmin, isTrue);
    expect(member.canUnsetAdmin, isFalse);
    expect(member.canTransferCreator, isTrue);
    expect(member.canRemoveMember, isTrue);
    expect(member.adminActionLabel, '设为管理员');

    final admin = roomMemberPermissionState(
      member: _member('admin', role: 'admin'),
      currentUser: currentUser,
      canEditCreatorOnly: true,
      canManageMembers: true,
      ownerUserId: 'owner',
    );
    expect(admin.canSetAdmin, isFalse);
    expect(admin.canUnsetAdmin, isTrue);
    expect(admin.canRemoveMember, isTrue);
    expect(admin.adminActionLabel, '移除管理员');

    final adminManagedByAdmin = roomMemberPermissionState(
      member: _member('admin_peer', role: 'admin'),
      currentUser: currentUser,
      canEditCreatorOnly: false,
      canManageMembers: true,
      ownerUserId: 'owner',
    );
    expect(adminManagedByAdmin.canRoleEdit, isFalse);
    expect(adminManagedByAdmin.canRemoveMember, isFalse);

    final managedByAdmin = roomMemberPermissionState(
      member: _member('managed'),
      currentUser: currentUser,
      canEditCreatorOnly: false,
      canManageMembers: true,
      ownerUserId: 'owner',
    );
    expect(managedByAdmin.canRoleEdit, isFalse);
    expect(managedByAdmin.canRemoveMember, isTrue);
  });

  test('roomMemberPermissionState blocks self owner and superuser edits', () {
    final currentUser = _currentUser('current');

    expect(
      roomMemberPermissionState(
        member: _member('current'),
        currentUser: currentUser,
        canEditCreatorOnly: true,
        canManageMembers: true,
      ).canRoleEdit,
      isFalse,
    );
    expect(
      roomMemberPermissionState(
        member: _member('current'),
        currentUser: currentUser,
        canEditCreatorOnly: true,
        canManageMembers: true,
      ).canRemoveMember,
      isFalse,
    );
    expect(
      roomMemberPermissionState(
        member: _member('owner'),
        currentUser: currentUser,
        canEditCreatorOnly: true,
        canManageMembers: true,
        ownerUserId: 'owner',
      ).canRoleEdit,
      isFalse,
    );
    expect(
      roomMemberPermissionState(
        member: _member('owner'),
        currentUser: currentUser,
        canEditCreatorOnly: true,
        canManageMembers: true,
        ownerUserId: 'owner',
      ).canRemoveMember,
      isFalse,
    );
    expect(
      roomMemberPermissionState(
        member: _member('superuser', isSuperuser: true),
        currentUser: currentUser,
        canEditCreatorOnly: true,
        canManageMembers: true,
      ).canRoleEdit,
      isFalse,
    );
    expect(
      roomMemberPermissionState(
        member: _member('superuser', isSuperuser: true),
        currentUser: currentUser,
        canEditCreatorOnly: true,
        canManageMembers: true,
      ).canRemoveMember,
      isFalse,
    );
    expect(
      roomMemberPermissionState(
        member: _member('member'),
        currentUser: currentUser,
        canEditCreatorOnly: false,
      ).canRoleEdit,
      isFalse,
    );
    expect(
      roomMemberPermissionState(
        member: _member('member'),
        currentUser: currentUser,
        canEditCreatorOnly: false,
      ).canRemoveMember,
      isFalse,
    );
  });

  test('room member management action patches busy state', () {
    final room = _room('room_1');
    final members = [_member('a'), _member('b')];

    final patch = roomMemberManagementActionStarted(
      room: room,
      members: members,
      changed: true,
      userId: 'b',
      busyMemberIds: const {'other'},
    );

    expect(patch.room, same(room));
    expect(patch.members, members);
    expect(patch.busyMemberIds, {'other', 'b'});
    expect(patch.changed, isTrue);
    expect(patch.error, isNull);
    expect(patch.notice, isNull);
  });

  test('room member load patches loading members and error state', () {
    final currentMembers = [_member('a')];

    final started = roomMembersLoadStarted(members: currentMembers);
    expect(started.members, currentMembers);
    expect(started.loading, isTrue);
    expect(started.error, isNull);

    final loadedMembers = [_member('b'), _member('c')];
    final succeeded = roomMembersLoadSucceeded(members: loadedMembers);
    expect(succeeded.members, loadedMembers);
    expect(succeeded.loading, isFalse);
    expect(succeeded.error, isNull);

    final failed = roomMembersLoadFailed(
      members: currentMembers,
      failure: Exception('load failed'),
    );
    expect(failed.members, currentMembers);
    expect(failed.loading, isFalse);
    expect(failed.error, contains('load failed'));
  });

  test('room member role update patches members busy ids and notice', () {
    final room = _room('room_1');
    final members = [_member('a'), _member('b')];
    final updated = _member('b', role: 'admin');

    final succeeded = roomMemberRoleUpdateSucceeded(
      room: room,
      members: members,
      updated: updated,
      role: 'admin',
      busyMemberIds: const {'b', 'other'},
    );
    expect(succeeded.room, same(room));
    expect(succeeded.members.map((member) => member.user.id), ['a', 'b']);
    expect(succeeded.members[1], same(updated));
    expect(succeeded.busyMemberIds, {'other'});
    expect(succeeded.changed, isTrue);
    expect(succeeded.error, isNull);
    expect(succeeded.notice, '已授予管理员身份');

    final failed = roomMemberRoleUpdateFailed(
      room: room,
      members: members,
      changed: false,
      userId: 'b',
      busyMemberIds: const {'b', 'other'},
      failure: Exception('role failed'),
    );
    expect(failed.room, same(room));
    expect(failed.members.map((member) => member.user.id), ['a', 'b']);
    expect(failed.busyMemberIds, {'other'});
    expect(failed.changed, isFalse);
    expect(failed.error, contains('role failed'));
    expect(failed.notice, isNull);
  });

  test('room member remove patches members busy ids and notice', () {
    final room = _room('room_1');
    final removed = _member('b', roomDisplayName: 'Removed Target');
    final members = [_member('a'), removed, _member('c')];

    final succeeded = roomMemberRemovedSucceeded(
      room: room,
      members: members,
      removed: removed,
      busyMemberIds: const {'b', 'other'},
    );
    expect(succeeded.room, same(room));
    expect(succeeded.members.map((member) => member.user.id), ['a', 'c']);
    expect(succeeded.busyMemberIds, {'other'});
    expect(succeeded.changed, isTrue);
    expect(succeeded.error, isNull);
    expect(succeeded.notice, '已踢出 Removed Target');

    final failed = roomMemberRemoveFailed(
      room: room,
      members: members,
      changed: true,
      userId: 'b',
      busyMemberIds: const {'b', 'other'},
      failure: Exception('remove failed'),
    );
    expect(failed.room, same(room));
    expect(failed.members, members);
    expect(failed.busyMemberIds, {'other'});
    expect(failed.changed, isTrue);
    expect(failed.error, contains('remove failed'));
    expect(failed.notice, isNull);
  });

  test('transfer creator patches room busy ids and notice', () {
    final room = _room('room_1');
    final updatedRoom = _room('room_1', role: 'admin');
    final members = [_member('a'), _member('b')];

    final succeeded = transferCreatorSucceeded(
      updatedRoom: updatedRoom,
      members: members,
      userId: 'b',
      busyMemberIds: const {'b', 'other'},
    );
    expect(succeeded.room, same(updatedRoom));
    expect(succeeded.members, members);
    expect(succeeded.busyMemberIds, {'other'});
    expect(succeeded.changed, isTrue);
    expect(succeeded.error, isNull);
    expect(succeeded.notice, '创建者已转让');

    final failed = transferCreatorFailed(
      room: room,
      members: members,
      changed: true,
      userId: 'b',
      busyMemberIds: const {'b', 'other'},
      failure: Exception('transfer failed'),
    );
    expect(failed.room, same(room));
    expect(failed.members, members);
    expect(failed.busyMemberIds, {'other'});
    expect(failed.changed, isTrue);
    expect(failed.error, contains('transfer failed'));
    expect(failed.notice, isNull);
  });
}

RoomMember _member(
  String id, {
  String role = 'member',
  String? uid,
  String? displayName,
  String? roomDisplayName,
  String? remarkName,
  bool isOnline = true,
  bool isSuperuser = false,
}) {
  final user = UserSummary(
    id: id,
    username: 'user_$id',
    displayName: displayName ?? 'User $id',
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    uid: uid,
    roomDisplayName: roomDisplayName,
    roomRole: role,
    isSuperuser: isSuperuser,
  );
  return RoomMember(
    user: user,
    role: role,
    joinedAt: DateTime.utc(2026, 6, 4),
    roomDisplayName: roomDisplayName,
    remarkName: remarkName,
    isOnline: isOnline,
  );
}

LiveState _live([List<String> participantIds = const []]) {
  return LiveState(
    roomId: 'room_1',
    participantCount: participantIds.length,
    participants: [
      for (final id in participantIds)
        LiveParticipant(
          liveSessionId: 'live_$id',
          user: _user(id),
          joinedAt: DateTime.utc(2026, 6, 4),
          micMuted: true,
          headphonesMuted: false,
          voiceBlocked: false,
          cameraOn: false,
          screenSharing: false,
          connectionState: 'connected',
        ),
    ],
    updatedAt: DateTime.utc(2026, 6, 4),
  );
}

UserSummary _user(String id) {
  return UserSummary(
    id: id,
    username: 'user_$id',
    displayName: 'User $id',
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
  );
}

CurrentUser _currentUser(String id) {
  return CurrentUser(
    id: id,
    uid: id,
    username: 'user_$id',
    displayName: 'User $id',
    bio: '',
    gender: 'secret',
    email: null,
    emailPublic: false,
    phoneNumber: null,
    phoneNumberPublic: false,
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    isSuperuser: false,
    createdAt: DateTime.utc(2026, 6, 4),
  );
}

RoomDetail _room(String id, {String role = 'member'}) {
  return RoomDetail(
    id: id,
    name: id,
    avatarUrl: null,
    defaultAvatarKey: 'room-1',
    memberCount: 2,
    myMembership: RoomMembership(
      joinedAt: DateTime.utc(2026, 6, 4),
      role: role,
    ),
    live: _live(),
    createdAt: DateTime.utc(2026, 6, 4),
    updatedAt: DateTime.utc(2026, 6, 4),
  );
}
