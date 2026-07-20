import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/room_display.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('roomSubtitle includes last message preview when present', () {
    expect(roomSubtitle(_roomCard()), '8 名成员 · 3 人在线 · 2 人语音');

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
    expect(roomSidebarSubtitle(_roomCard()), '8 名成员 · 2 人语音');
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
    expect(
      roomSidebarSubtitle(
        _roomCard(
          lastMessage: LastMessagePreview(
            id: 'message_3',
            type: 'system',
            senderDisplayName: '丁',
            bodyPreview: '房间名称修改为123345',
            createdAt: DateTime.utc(2026, 6, 4),
          ),
        ),
      ),
      '[系统] 房间名称 被 丁 修改为 123345',
    );
    expect(
      roomSidebarSubtitle(
        _roomCard(
          lastMessage: LastMessagePreview(
            id: 'message_4',
            type: 'system',
            senderDisplayName: '',
            bodyPreview: '房间简介 被 丁 修改为 新简介',
            createdAt: DateTime.utc(2026, 6, 4),
          ),
        ),
      ),
      '[系统] 房间简介 被 丁 修改为 新简介',
    );
    expect(
      roomSidebarSubtitle(
        _roomCard(
          lastMessage: LastMessagePreview(
            id: 'message_5',
            type: 'system',
            senderDisplayName: '丁',
            bodyPreview: '房间可见性修改为私密',
            createdAt: DateTime.utc(2026, 6, 4),
          ),
        ),
      ),
      '[系统] 房间可见性 被 丁 修改为 私密',
    );
    expect(
      roomSidebarSubtitle(
        _roomCard(
          lastMessage: LastMessagePreview(
            id: 'message_6',
            type: 'system',
            senderDisplayName: '丁',
            bodyPreview: '房间加入方式修改为关闭',
            createdAt: DateTime.utc(2026, 6, 4),
          ),
        ),
      ),
      '[系统] 房间加入方式 被 丁 修改为 关闭',
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

  test('room draft preview normalizes visible draft text', () {
    expect(roomDraftPreview(null), isNull);
    expect(roomDraftPreview('   '), isNull);
    expect(roomDraftPreview(' hello\n  draft\tworld '), 'hello draft world');
    expect(
      roomDraftPreviewText(
        text: 'typed text',
        attachmentFilename: ' report final.pdf ',
        attachmentMimeType: 'application/pdf',
      ),
      '[文件] report final.pdf',
    );
    expect(
      roomDraftPreviewText(
        text: null,
        attachmentFilename: 'cat picture.png',
        attachmentMimeType: 'image/png',
      ),
      '[图片] cat picture.png',
    );
    expect(
      roomDraftPreviewText(
        text: 'reply text',
        attachmentFilename: null,
        attachmentMimeType: null,
        hasQuote: true,
      ),
      '[引用] reply text',
    );
    expect(
      roomDraftPreviewText(
        text: '',
        attachmentFilename: null,
        attachmentMimeType: null,
        hasQuote: true,
      ),
      '[引用]',
    );
  });

  test('room identity display helpers provide stable fallbacks', () {
    expect(roomIdentifier(_roomDetail(rid: 'R001')), 'R001');
    expect(roomIdentifier(_roomDetail()), 'room_1');
    expect(roomCreatedAtLabel(DateTime(2026, 6, 4, 9, 5)), '2026/06/04 09:05');
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
    expect(roomCopyFailureMessage('denied'), '无法复制');
    expect(userUidCopySuccessNotice(), 'UID 已复制');
    expect(userUidCopyFailureMessage('denied'), '无法复制 UID');
    expect(roomOpenFailureMessage('missing'), '无法打开房间');
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

  test('userAvatarLabel ignores the room display name', () {
    expect(
      userAvatarLabel(
        _user(
          username: 'testxxxx',
          displayName: 'Test Example',
          roomDisplayName: 'J',
        ),
      ),
      'Test Example',
    );
    expect(
      userAvatarLabel(
        _user(username: 'testxxxx', displayName: '', roomDisplayName: 'J'),
      ),
      'testxxxx',
    );
  });

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
    expect(
      currentUserPresenceLabel(_currentUser(status: 'active'), inLive: false),
      '在线',
    );
    expect(
      currentUserPresenceLabel(_currentUser(status: 'offline'), inLive: false),
      '离线',
    );
    expect(
      currentUserPresenceLabel(_currentUser(status: 'active'), inLive: true),
      '语音',
    );
    expect(
      currentUserPresenceLabel(
        _currentUser(status: 'active'),
        inLive: true,
        reconnecting: true,
      ),
      '重连中',
    );
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

    expect(commonRoomTitle(room), 'Ops · 1001');
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

  test('common room names prefer the viewer local room remark', () {
    const commonRooms = [
      UserCommonRoom(
        id: 'room_1',
        rid: 'REMOTE',
        name: 'Official Old',
        remarkName: 'Other User Remark',
        visibility: 'public',
        avatarUrl: '/remote.png',
        defaultAvatarKey: 'remote-1',
        roomDisplayName: 'Room Logan',
        roomRole: 'admin',
      ),
      UserCommonRoom(
        id: 'room_2',
        rid: 'R002',
        name: 'Unmatched',
        remarkName: 'Keep Remote',
      ),
    ];
    final localRooms = [
      RoomCard(
        id: 'room_1',
        rid: 'LOCAL',
        name: 'Official Local',
        visibility: 'private',
        remarkName: 'Viewer Remark',
        avatarUrl: '/local.png',
        defaultAvatarKey: 'local-1',
        memberCount: 3,
        onlineMemberCount: 1,
        liveParticipantCount: 0,
        liveAvatarPreview: const [],
        lastMessage: null,
        unreadCount: 0,
        updatedAt: DateTime.utc(2026, 7, 9),
      ),
    ];

    final resolved = commonRoomsWithLocalRoomNames(
      commonRooms: commonRooms,
      rooms: localRooms,
    );

    expect(resolved.first.rid, 'LOCAL');
    expect(resolved.first.name, 'Official Local');
    expect(resolved.first.visibility, 'private');
    expect(resolved.first.remarkName, 'Viewer Remark');
    expect(resolved.first.avatarUrl, '/local.png');
    expect(resolved.first.defaultAvatarKey, 'local-1');
    expect(resolved.first.roomDisplayName, 'Room Logan');
    expect(resolved.first.roomRole, 'admin');
    expect(commonRoomDisplayName(resolved.first), 'Viewer Remark');
    expect(commonRoomDisplayName(resolved.last), 'Keep Remote');

    final noRemark = commonRoomsWithLocalRoomNames(
      commonRooms: commonRooms,
      rooms: [
        RoomCard(
          id: 'room_1',
          rid: 'LOCAL',
          name: 'Official Local',
          visibility: 'private',
          remarkName: null,
          avatarUrl: null,
          defaultAvatarKey: 'local-1',
          memberCount: 3,
          onlineMemberCount: 1,
          liveParticipantCount: 0,
          liveAvatarPreview: const [],
          lastMessage: null,
          unreadCount: 0,
          updatedAt: DateTime.utc(2026, 7, 9),
        ),
      ],
    );

    expect(commonRoomDisplayName(noRemark.first), 'Official Local');
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

  test('former room member profile keeps current default account fields', () {
    final currentDefault = UserSummary(
      id: 'former',
      username: 'current_name',
      displayName: '当前默认名',
      avatarUrl: null,
      defaultAvatarKey: 'green-2',
      uid: '10002001',
      roomRole: 'left',
    );
    final historicalSnapshot = UserSummary(
      id: 'former',
      username: 'old_name',
      displayName: '发送时默认名',
      avatarUrl: '/old-avatar.png',
      defaultAvatarKey: 'blue-1',
      uid: '10002001',
      roomDisplayName: '发送时房间名',
      roomRole: 'member',
    );

    final resolved = resolvedRoomMemberProfileUser(
      profile: RoomMemberProfile(
        user: currentDefault,
        role: 'left',
        joinedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
      fallback: historicalSnapshot,
    );

    expect(resolved.username, 'current_name');
    expect(resolved.displayName, '当前默认名');
    expect(resolved.avatarUrl, isNull);
    expect(resolved.defaultAvatarKey, 'green-2');
    expect(resolved.roomDisplayName, isNull);
    expect(resolved.roomRole, 'left');
  });

  test(
    'current room member profile can still fill omitted snapshot fields',
    () {
      final resolved = resolvedRoomMemberProfileUser(
        profile: RoomMemberProfile(
          user: _user(id: 'member', bio: null, roomRole: 'member'),
          role: 'member',
          joinedAt: DateTime.utc(2026, 7, 20),
        ),
        fallback: _user(
          id: 'member',
          bio: '历史签名',
          roomDisplayName: '房间名',
          roomRole: 'member',
        ),
      );

      expect(resolved.bio, '历史签名');
      expect(resolved.roomDisplayName, '房间名');
    },
  );

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
    expect(normalizeRoomNotificationPolicy('mention_only'), 'silent');
    expect(normalizeRoomNotificationPolicy('dnd'), 'silent');
    expect(normalizeRoomNotificationPolicy('blocked'), 'blocked');
    expect(normalizeRoomNotificationPolicy('unknown'), 'all');

    expect(normalizeRoomVisibility('private'), 'private');
    expect(normalizeRoomVisibility('PUBLIC'), 'public');

    expect(normalizeRoomJoinPolicy('allow_anyone'), 'open');
    expect(normalizeRoomJoinPolicy('deny_all'), 'closed');
    expect(normalizeRoomJoinPolicy('unknown'), 'approval_required');
    expect(roomJoinPolicyLabel('open'), '开放');
    expect(roomJoinPolicyLabel('approval_required'), '需审批');
    expect(roomJoinPolicyLabel('closed'), '关闭');
    expect(roomJoinPolicyLabel('unknown'), '需审批');
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

CurrentUser _currentUser({bool isSuperuser = false, String? status}) {
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
    status: status,
  );
}
