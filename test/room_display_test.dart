import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/room_display.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('roomSubtitle includes last message preview when present', () {
    expect(roomSubtitle(_roomCard()), '8 名成员 · 3 人在线 · 2 语音');

    expect(
      roomSubtitle(
        _roomCard(
          lastMessage: LastMessagePreview(
            id: 'message_1',
            senderDisplayName: 'Logan',
            bodyPreview: 'hello',
            createdAt: DateTime.utc(2026, 6, 4),
          ),
        ),
      ),
      'Logan · hello',
    );
    expect(roomSidebarSubtitle(_roomCard()), '8 名成员 · 2 语音');
    expect(
      roomSidebarSubtitle(
        _roomCard(
          lastMessage: LastMessagePreview(
            id: 'message_1',
            senderDisplayName: 'Logan',
            bodyPreview: 'hello',
            createdAt: DateTime.utc(2026, 6, 4),
          ),
        ),
      ),
      'Logan · hello',
    );
    expect(
      roomSidebarSubtitle(
        _roomCard(
          lastMessage: LastMessagePreview(
            id: 'message_2',
            type: 'system',
            senderDisplayName: 'Logan',
            bodyPreview: '加入了房间',
            createdAt: DateTime.utc(2026, 6, 4),
          ),
        ),
      ),
      '[系统] Logan 加入了房间',
    );
  });

  test('room sidebar latest message time follows compact chat rules', () {
    final now = DateTime(2026, 6, 12, 10);
    expect(
      roomSidebarTimestamp(DateTime(2026, 6, 12, 7, 5), now: now),
      '07:05',
    );
    expect(
      roomSidebarTimestamp(DateTime(2026, 6, 11, 7, 5), now: now),
      '昨天 07:05',
    );
    expect(
      roomSidebarTimestamp(DateTime(2026, 6, 10, 7, 5), now: now),
      '前天 07:05',
    );
    expect(roomSidebarTimestamp(DateTime(2026, 6, 9, 7, 5), now: now), '星期二');
    expect(
      roomSidebarTimestamp(DateTime(2026, 5, 31, 7, 5), now: now),
      '2026/05/31',
    );
    expect(
      roomSidebarTimestamp(DateTime(2025, 12, 31, 7, 5), now: now),
      '2025/12/31',
    );
    expect(roomSidebarLastMessageTime(_roomCard(), now: now), '');
    expect(
      roomSidebarLastMessageTime(
        _roomCard(
          lastMessage: LastMessagePreview(
            id: 'message_1',
            senderDisplayName: 'Logan',
            bodyPreview: 'hello',
            createdAt: DateTime(2026, 6, 12, 7, 5),
          ),
        ),
        now: now,
      ),
      '07:05',
    );
  });

  test('room identity display helpers provide stable fallbacks', () {
    expect(roomIdentifier(_roomDetail(rid: 'R001')), 'R001');
    expect(roomIdentifier(_roomDetail()), 'room_1');
    expect(
      roomDescriptionValue(_roomDetail(description: '  Launch room  ')),
      'Launch room',
    );
    expect(roomDescriptionValue(_roomDetail(description: ' ')), isNull);
    expect(
      roomDescriptionText(_roomDetail(description: '  Launch room  ')),
      'Launch room',
    );
    expect(roomDescriptionText(_roomDetail(description: ' ')), '暂无介绍');
  });

  test(
    'room leave confirmation spec separates normal live and delete exits',
    () {
      final normal = roomLeaveConfirmationSpec(
        room: _roomDetail(memberCount: 3),
        isInLive: false,
      );
      expect(normal.confirmDeleteIfEmpty, isFalse);
      expect(normal.requiresStrongConfirmation, isFalse);
      expect(normal.title, '退出房间');
      expect(normal.body, contains('房间成员中移除'));
      expect(normal.confirmLabel, '退出');
      expect(normal.expectedText, isNull);

      final live = roomLeaveConfirmationSpec(
        room: _roomDetail(memberCount: 3),
        isInLive: true,
      );
      expect(live.body, contains('Live Channel'));

      final finalCreator = roomLeaveConfirmationSpec(
        room: _roomDetail(role: 'creator', memberCount: 1),
        isInLive: true,
      );
      expect(finalCreator.confirmDeleteIfEmpty, isTrue);
      expect(finalCreator.requiresStrongConfirmation, isTrue);
      expect(finalCreator.title, '退出并删除房间');
      expect(finalCreator.confirmLabel, '退出并删除');
      expect(finalCreator.expectedText, 'Room');
    },
  );

  test('room operation notices and delete confirmation stay outside UI', () {
    expect(roomCopySuccessNotice('RID'), 'RID 已复制');
    expect(roomCopyFailureMessage('denied'), '无法复制：denied');
    expect(userUidCopySuccessNotice(), 'UID 已复制');
    expect(userUidCopyFailureMessage('denied'), '无法复制 UID：denied');
    expect(roomOpenFailureMessage('missing'), '无法打开房间：missing');
    expect(roomOptimisticOpenRefreshFailureNotice(), '房间刷新失败，已先打开当前房间');
    expect(roomUseGlobalProfileNotice(), '保存后将使用全局默认用户名和默认头像');
    expect(roomInfoSavedNotice(), '房间信息已保存');

    final deletion = roomDeletionConfirmationSpec(_roomDetail());
    expect(deletion.title, '删除房间');
    expect(deletion.body, '将清空房间所有数据。这个动作不可恢复，请输入房间名确认。');
    expect(deletion.confirmLabel, '删除房间');
    expect(deletion.expectedText, 'Room');
  });

  test(
    'userPrimaryName prefers room display name then global display name',
    () {
      expect(
        userPrimaryName(
          _user(roomDisplayName: ' Room Logan ', displayName: ''),
        ),
        'Room Logan',
      );
      expect(
        userPrimaryName(_user(displayName: ' Global Logan ')),
        'Global Logan',
      );
      expect(userPrimaryName(_user(displayName: '')), 'logan');
    },
  );

  test('user identity labels prefer uid and include username handle', () {
    expect(userUidLabel(_user(uid: '1001')), '1001');
    expect(
      userUidLabel(_user(id: 'user_fallback', uid: null)),
      'user_fallback',
    );
    expect(userUsernameLabel(_user(username: 'logan')), '@logan');
    expect(
      userIdentityMeta(_user(id: 'user_fallback')),
      'user_fallback · @logan',
    );
    expect(userIdentityMeta(_user(uid: '1001')), '1001 · @logan');
    expect(userSignatureText(_user(bio: '  Hello  ')), 'Hello');
    expect(userSignatureText(_user(bio: '   ')), isNull);
    expect(userPresenceLabel(_user(isOnline: true)), '在线');
    expect(userPresenceLabel(_user(isOnline: false)), '离线');
    expect(userPresenceLabel(_user()), isNull);
  });

  test(
    'roomRoleLabel handles pending superuser owner admin and member roles',
    () {
      expect(roomRoleLabel(_user(roomRole: 'pending')), '待审批');
      expect(roomRoleLabel(_user(isSuperuser: true)), '超级用户');
      expect(roomRoleLabel(_user(id: 'owner'), ownerUserId: 'owner'), '创建者');
      expect(roomRoleLabel(_user(roomRole: 'administrator')), '管理员');
      expect(roomRoleLabel(_user(roomRole: 'member')), '成员');
    },
  );

  test('common room labels include rid visibility display name and role', () {
    final room = UserCommonRoom(
      id: 'room_1',
      rid: '1001',
      name: 'General',
      remarkName: 'Ops',
      visibility: 'public',
      roomDisplayName: 'Room Logan',
      roomRole: 'admin',
    );

    expect(commonRoomTitle(room), 'Ops (General) · 1001');
    expect(commonRoomAvatarLabel(room), 'General');
    expect(visibilityLabel(room.visibility), '公开');
    expect(commonRoomMeta(room), 'Room Logan · 管理员');
    expect(
      commonRoomTitle(
        const UserCommonRoom(id: 'room_2', rid: '', name: 'Private'),
      ),
      'Private',
    );
  });

  test('room user info profile merges owner and current user fields', () {
    final creator = _user(
      id: 'creator',
      username: 'creator',
      displayName: 'Creator',
      uid: 'C001',
    );
    final creatorProfile = roomUserInfoProfile(
      user: _user(id: 'creator', username: 'creator', displayName: '', uid: ''),
      room: _roomDetail(createdBy: creator),
      currentUser: _currentUser(),
    );

    expect(creatorProfile.displayName, 'Creator');
    expect(creatorProfile.uid, 'C001');
    expect(creatorProfile.roomRole, 'owner');

    final currentUserProfile = roomUserInfoProfile(
      user: _user(id: 'user_1', displayName: '', roomRole: null),
      room: _roomDetail(role: 'admin'),
      currentUser: _currentUser(),
    );

    expect(currentUserProfile.displayName, 'Logan');
    expect(currentUserProfile.roomRole, 'admin');
  });

  test('room user info common rooms handles selected room visibility', () {
    const existing = UserCommonRoom(
      id: 'room_2',
      rid: 'R002',
      name: 'Other',
      visibility: 'private',
    );
    final user = _user(
      id: 'other',
      commonRooms: const [
        UserCommonRoom(id: 'room_1', rid: 'old', name: 'Duplicate'),
        existing,
      ],
    );
    final selectedRoom = _roomDetail(rid: 'R001', visibility: 'public');

    expect(
      roomUserInfoCommonRooms(
        user: user,
        selectedRoom: selectedRoom,
        currentUser: _currentUser(),
        includeSelectedRoom: false,
      ).map((room) => room.id),
      ['room_1', 'room_2'],
    );

    final withSelected = roomUserInfoCommonRooms(
      user: user.copyWith(roomDisplayName: 'Room Other', roomRole: 'member'),
      selectedRoom: selectedRoom,
      currentUser: _currentUser(),
      includeSelectedRoom: true,
    );

    expect(withSelected.map((room) => room.id), ['room_1', 'room_2']);
    expect(withSelected.first.rid, 'R001');
    expect(withSelected.first.visibility, 'public');
    expect(withSelected.first.roomDisplayName, 'Room Other');
    expect(withSelected.first.roomRole, 'member');

    expect(
      roomUserInfoCommonRooms(
        user: _user(id: 'user_1'),
        selectedRoom: selectedRoom,
        currentUser: _currentUser(),
        includeSelectedRoom: true,
      ).map((room) => room.id),
      ['room_1'],
    );
    expect(
      roomUserInfoCommonRooms(
        user: _user(id: 'super', isSuperuser: true),
        selectedRoom: selectedRoom,
        currentUser: _currentUser(),
        includeSelectedRoom: true,
      ),
      isEmpty,
    );
    expect(
      roomUserInfoCommonRooms(
        user: _user(id: 'other', commonRooms: const []),
        selectedRoom: selectedRoom,
        currentUser: _currentUser(isSuperuser: true),
        includeSelectedRoom: false,
      ).map((room) => room.id),
      isEmpty,
    );
    expect(
      roomUserInfoCommonRooms(
        user: _user(id: 'other', commonRooms: const [existing]),
        selectedRoom: selectedRoom,
        currentUser: _currentUser(isSuperuser: true),
        includeSelectedRoom: false,
      ).map((room) => room.id),
      ['room_2'],
    );
    expect(
      userRoomsSectionTitle(
        user: _user(id: 'super', isSuperuser: true),
        currentUser: _currentUser(),
      ),
      isNull,
    );
    expect(
      userRoomsSectionTitle(
        user: _user(id: 'user_1'),
        currentUser: _currentUser(),
      ),
      '所有房间',
    );
    expect(
      userRoomsSectionTitle(user: user, currentUser: _currentUser()),
      '共同房间',
    );
  });

  test('room setting values are normalized for server payloads', () {
    expect(normalizeRoomNotificationPolicy('mention_only'), 'mentions');
    expect(normalizeRoomNotificationPolicy('dnd'), 'muted');
    expect(normalizeRoomNotificationPolicy('unknown'), 'all');

    expect(normalizeRoomVisibility('private'), 'private');
    expect(normalizeRoomVisibility('PUBLIC'), 'public');

    expect(normalizeRoomJoinPolicy('allow_anyone'), 'open');
    expect(normalizeRoomJoinPolicy('deny_all'), 'closed');
    expect(normalizeRoomJoinPolicy('unknown'), 'approval_required');
  });

  test('public room join action helpers reflect state', () {
    expect(
      publicRoomJoinActionLabel(_publicRoom(joined: true), pending: false),
      '进入',
    );
    expect(publicRoomJoinActionLabel(_publicRoom(), pending: true), '待审批');
    expect(
      publicRoomJoinActionLabel(
        _publicRoom(joinPolicy: 'approval_required'),
        pending: false,
      ),
      '加入',
    );
    expect(
      publicRoomJoinActionLabel(
        _publicRoom(joinPolicy: 'closed'),
        pending: false,
      ),
      '不可加入',
    );
    expect(publicRoomJoinActionLabel(_publicRoom(), pending: false), '加入');
    expect(publicRoomJoinActionable(_publicRoom(), pending: true), isFalse);
    expect(
      publicRoomJoinActionable(
        _publicRoom(joinPolicy: 'closed'),
        pending: false,
      ),
      isFalse,
    );
    expect(
      publicRoomJoinRequiresApplication(
        _publicRoom(joinPolicy: 'approval_required'),
      ),
      isTrue,
    );
    expect(
      publicRoomJoinActionable(_publicRoom(joined: true), pending: true),
      isTrue,
    );
  });

  test('roomManagementPermissionState reuses room and user privileges', () {
    var access = roomAccessState(
      room: _roomDetail(role: 'admin'),
      currentUser: _currentUser(),
    );
    expect(access.canManageRoom, isTrue);
    expect(access.canReviewJoinRequests, isTrue);
    expect(access.showJoinRequestBadge(true), isTrue);
    expect(access.showJoinRequestBadge(false), isFalse);

    access = roomAccessState(
      room: _roomDetail(role: 'member'),
      currentUser: _currentUser(),
    );
    expect(access.canManageRoom, isFalse);
    expect(access.canReviewJoinRequests, isFalse);
    expect(access.showJoinRequestBadge(true), isFalse);

    access = roomAccessState(
      room: _roomDetail(role: 'member'),
      currentUser: _currentUser(isSuperuser: true),
    );
    expect(access.canManageRoom, isTrue);
    expect(access.canReviewJoinRequests, isTrue);

    var permission = roomManagementPermissionState(
      room: _roomDetail(role: 'admin', canDeleteRoom: false),
      currentUser: _currentUser(),
    );
    expect(permission.canEditCreatorOnly, isFalse);
    expect(permission.canDeleteRoom, isFalse);

    permission = roomManagementPermissionState(
      room: _roomDetail(role: 'creator'),
      currentUser: _currentUser(),
    );
    expect(permission.canEditCreatorOnly, isTrue);
    expect(permission.canDeleteRoom, isTrue);

    permission = roomManagementPermissionState(
      room: _roomDetail(role: 'member', canDeleteRoom: false),
      currentUser: _currentUser(isSuperuser: true),
    );
    expect(permission.canEditCreatorOnly, isTrue);
    expect(permission.canDeleteRoom, isTrue);
  });

  test(
    'room profile avatar helpers preserve global preset and upload states',
    () {
      expect(
        roomProfileAvatarPath(
          usingGlobalProfile: true,
          currentUserAvatarUrl: '/global.png',
          pendingAvatarUrl: '/pending.png',
          usingPresetAvatar: false,
          personalAvatarUrl: '/personal.png',
        ),
        '/global.png',
      );
      expect(
        roomProfileAvatarPath(
          usingGlobalProfile: false,
          currentUserAvatarUrl: '/global.png',
          pendingAvatarUrl: '/pending.png',
          usingPresetAvatar: false,
          personalAvatarUrl: '/personal.png',
        ),
        '/pending.png',
      );
      expect(
        roomProfileAvatarPath(
          usingGlobalProfile: false,
          currentUserAvatarUrl: '/global.png',
          pendingAvatarUrl: null,
          usingPresetAvatar: true,
          personalAvatarUrl: '/personal.png',
        ),
        isNull,
      );
      expect(
        roomProfileUploadedAvatarSelected(
          usingGlobalProfile: false,
          usingPresetAvatar: false,
          pendingAvatarUrl: null,
          personalAvatarUrl: '/personal.png',
        ),
        isTrue,
      );
      expect(
        roomProfilePresetAvatarSelected(
          usingGlobalProfile: false,
          usingPresetAvatar: true,
        ),
        isTrue,
      );
    },
  );

  test('room profile and management display helpers trim fallback names', () {
    expect(
      roomProfileDisplayName(
        usingGlobalProfile: false,
        currentUserDisplayName: 'Global',
        roomDisplayNameText: ' Room ',
      ),
      'Room',
    );
    expect(
      roomProfileDisplayName(
        usingGlobalProfile: false,
        currentUserDisplayName: 'Global',
        roomDisplayNameText: ' ',
      ),
      'Global',
    );
    expect(
      roomManagementAvatarPath(
        usingPresetAvatar: false,
        pendingAvatarUrl: '/pending.png',
        roomAvatarUrl: '/room.png',
      ),
      '/pending.png',
    );
    expect(
      roomManagementAvatarPath(
        usingPresetAvatar: true,
        pendingAvatarUrl: '/pending.png',
        roomAvatarUrl: '/room.png',
      ),
      isNull,
    );
    expect(
      roomManagementUploadedAvatarSelected(usingPresetAvatar: false),
      isTrue,
    );
  });
}

RoomCard _roomCard({LastMessagePreview? lastMessage}) {
  return RoomCard(
    id: 'room_1',
    name: 'General',
    avatarUrl: null,
    defaultAvatarKey: 'room-1',
    memberCount: 8,
    onlineMemberCount: 3,
    liveParticipantCount: 2,
    liveAvatarPreview: const [],
    lastMessage: lastMessage,
    unreadCount: 0,
    updatedAt: DateTime.utc(2026, 6, 4),
  );
}

UserSummary _user({
  String id = 'user_1',
  String username = 'logan',
  String? uid,
  String? displayName = 'Logan',
  String? roomDisplayName,
  String? roomRole,
  String? bio,
  bool isSuperuser = false,
  bool? isOnline,
  List<UserCommonRoom> commonRooms = const [],
}) {
  return UserSummary(
    id: id,
    username: username,
    displayName: displayName ?? username,
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    uid: uid,
    bio: bio,
    roomDisplayName: roomDisplayName,
    roomRole: roomRole,
    isSuperuser: isSuperuser,
    isOnline: isOnline,
    commonRooms: commonRooms,
  );
}

PublicRoom _publicRoom({bool joined = false, String joinPolicy = 'open'}) {
  return PublicRoom(
    id: 'room_1',
    rid: 'R001',
    name: 'Room',
    avatarUrl: null,
    defaultAvatarKey: 'room-1',
    visibility: 'public',
    joinPolicy: joinPolicy,
    memberCount: 3,
    liveParticipantCount: 0,
    joined: joined,
    joinState: joined ? 'joined' : 'none',
  );
}

RoomDetail _roomDetail({
  String role = 'member',
  bool? canDeleteRoom,
  UserSummary? createdBy,
  String rid = '',
  String visibility = 'private',
  String description = '',
  int memberCount = 1,
}) {
  return RoomDetail(
    id: 'room_1',
    name: 'Room',
    rid: rid,
    visibility: visibility,
    avatarUrl: null,
    defaultAvatarKey: 'room-1',
    memberCount: memberCount,
    description: description,
    createdBy: createdBy,
    myMembership: RoomMembership(
      joinedAt: DateTime.utc(2026, 6, 4),
      role: role,
    ),
    live: LiveState(
      roomId: 'room_1',
      participantCount: 0,
      participants: const [],
      updatedAt: DateTime.utc(2026, 6, 4),
    ),
    createdAt: DateTime.utc(2026, 6, 4),
    updatedAt: DateTime.utc(2026, 6, 4),
    canDeleteRoom: canDeleteRoom,
  );
}

CurrentUser _currentUser({bool isSuperuser = false}) {
  return CurrentUser(
    id: 'user_1',
    uid: '1001',
    username: 'logan',
    displayName: 'Logan',
    bio: '',
    gender: 'secret',
    email: null,
    emailPublic: false,
    phoneNumber: null,
    phoneNumberPublic: false,
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    isSuperuser: isSuperuser,
    createdAt: DateTime.utc(2026, 6, 4),
  );
}
