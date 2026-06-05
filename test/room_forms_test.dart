import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/room_forms.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('createRoomDraftFromForm validates and trims the room name', () {
    expect(createRoomDraftFromForm(name: ' ').error, '房间名不能为空');

    final draft = createRoomDraftFromForm(name: '  General  ');

    expect(draft.isValid, isTrue);
    expect(draft.name, 'General');
  });

  test('create room submit patches preserve dialog busy and error state', () {
    expect(canStartCreateRoom(busy: false), isTrue);
    expect(canStartCreateRoom(busy: true), isFalse);

    final started = createRoomSubmitStarted();
    expect(started.busy, isTrue);
    expect(started.error, isNull);

    final failed = createRoomSubmitFailed(failure: 'create failed');
    expect(failed.busy, isTrue);
    expect(failed.error, 'create failed');

    final finished = createRoomSubmitFinished(error: failed.error);
    expect(finished.busy, isFalse);
    expect(finished.error, 'create failed');
  });

  test('roomProfileUpdateDraftFromForm trims room profile fields', () {
    final draft = roomProfileUpdateDraftFromForm(
      remarkName: '  Ops  ',
      notificationPolicy: 'mention_only',
      usingGlobalProfile: false,
      roomDisplayName: '  Room Logan  ',
      pendingAvatarAssetId: 'asset_1',
      usingProfilePresetAvatar: false,
      defaultAvatarKey: 'green-2',
    );

    expect(draft.remarkName, 'Ops');
    expect(draft.notificationPolicy, 'mentions');
    expect(draft.roomDisplayName, 'Room Logan');
    expect(draft.avatarAssetId, 'asset_1');
    expect(draft.defaultAvatarKey, 'green-2');
  });

  test(
    'room profile draft preserves clear semantics for global and preset',
    () {
      final global = roomProfileUpdateDraftFromForm(
        remarkName: '',
        notificationPolicy: 'all',
        usingGlobalProfile: true,
        roomDisplayName: 'Room Logan',
        pendingAvatarAssetId: 'asset_1',
        usingProfilePresetAvatar: false,
        defaultAvatarKey: 'green-2',
      );

      expect(global.roomDisplayName, '');
      expect(global.avatarAssetId, '');
      expect(global.defaultAvatarKey, '');

      expect(
        roomProfileAvatarAssetIdForSave(
          usingGlobalProfile: false,
          usingProfilePresetAvatar: true,
        ),
        '',
      );
      expect(
        roomProfileAvatarAssetIdForSave(
          usingGlobalProfile: false,
          usingProfilePresetAvatar: false,
        ),
        isNull,
      );
    },
  );

  test('roomInfoUpdateDraftFromForm validates trims and normalizes fields', () {
    expect(
      roomInfoUpdateDraftFromForm(
        name: '',
        description: '',
        visibility: 'public',
        joinPolicy: 'open',
        aiVoiceAnnouncementsEnabled: true,
        usingPresetAvatar: false,
        defaultAvatarKey: 'room-1',
      ).error,
      '房间名不能为空',
    );

    final draft = roomInfoUpdateDraftFromForm(
      name: '  General  ',
      description: '  Team room  ',
      visibility: 'PRIVATE',
      joinPolicy: 'allow_anyone',
      aiVoiceAnnouncementsEnabled: false,
      pendingAvatarAssetId: 'asset_2',
      usingPresetAvatar: false,
      defaultAvatarKey: 'room-2',
    );

    expect(draft.isValid, isTrue);
    expect(draft.name, 'General');
    expect(draft.description, 'Team room');
    expect(draft.visibility, 'private');
    expect(draft.joinPolicy, 'open');
    expect(draft.aiVoiceAnnouncementsEnabled, isFalse);
    expect(draft.avatarAssetId, 'asset_2');
    expect(draft.defaultAvatarKey, 'room-2');
  });

  test(
    'room avatar draft clears uploaded avatar only when preset is selected',
    () {
      expect(
        roomAvatarAssetIdForSave(
          pendingAvatarAssetId: 'asset_3',
          usingPresetAvatar: true,
        ),
        'asset_3',
      );
      expect(roomAvatarAssetIdForSave(usingPresetAvatar: true), '');
      expect(roomAvatarAssetIdForSave(usingPresetAvatar: false), isNull);
    },
  );

  test(
    'room action gates share busy semantics across profile and management',
    () {
      expect(canStartRoomProfileSave(saving: false, leaving: false), isTrue);
      expect(canStartRoomProfileSave(saving: true, leaving: false), isFalse);
      expect(canStartRoomLeave(saving: false, leaving: true), isFalse);

      expect(roomInfoManagementBusy(saving: false, deleting: false), isFalse);
      expect(roomInfoManagementBusy(saving: true, deleting: false), isTrue);
      expect(canStartRoomInfoSave(saving: false, deleting: false), isTrue);
      expect(canStartRoomInfoSave(saving: false, deleting: true), isFalse);

      expect(
        canStartRoomDeletion(
          canDeleteRoom: true,
          saving: false,
          deleting: false,
        ),
        isTrue,
      );
      expect(
        canStartRoomDeletion(
          canDeleteRoom: false,
          saving: false,
          deleting: false,
        ),
        isFalse,
      );
      expect(
        canStartRoomDeletion(
          canDeleteRoom: true,
          saving: true,
          deleting: false,
        ),
        isFalse,
      );
    },
  );

  test('room profile dialog patches copy and global profile state', () {
    final copied = roomProfileCopySucceeded(
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/avatar.png',
      usingGlobalProfile: false,
      usingProfilePresetAvatar: false,
      defaultAvatarKey: 'blue-1',
      saving: false,
      leaving: false,
      uploadingAvatar: false,
      label: 'RID',
    );
    expect(copied.pendingAvatarAssetId, 'asset_1');
    expect(copied.pendingAvatarUrl, '/avatar.png');
    expect(copied.usingGlobalProfile, isFalse);
    expect(copied.usingProfilePresetAvatar, isFalse);
    expect(copied.defaultAvatarKey, 'blue-1');
    expect(copied.saving, isFalse);
    expect(copied.leaving, isFalse);
    expect(copied.uploadingAvatar, isFalse);
    expect(copied.error, isNull);
    expect(copied.notice, 'RID 已复制');

    final copyFailed = roomProfileCopyFailed(
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/avatar.png',
      usingGlobalProfile: false,
      usingProfilePresetAvatar: false,
      defaultAvatarKey: 'blue-1',
      saving: false,
      leaving: false,
      uploadingAvatar: false,
      notice: 'kept',
      failure: Exception('clipboard'),
    );
    expect(copyFailed.notice, 'kept');
    expect(copyFailed.error, contains('clipboard'));

    final global = roomProfileUseGlobalProfile(
      currentUserDefaultAvatarKey: 'green-2',
      saving: false,
      leaving: false,
      uploadingAvatar: false,
    );
    expect(global.pendingAvatarAssetId, isNull);
    expect(global.pendingAvatarUrl, isNull);
    expect(global.usingGlobalProfile, isTrue);
    expect(global.usingProfilePresetAvatar, isFalse);
    expect(global.defaultAvatarKey, 'green-2');
    expect(global.error, isNull);
    expect(global.notice, '保存后将使用全局默认用户名和默认头像');

    final preset = roomProfileUsePresetAvatar(
      defaultAvatarKey: 'purple-2',
      saving: false,
      leaving: false,
      uploadingAvatar: false,
      error: 'kept error',
      notice: 'kept notice',
    );
    expect(preset.pendingAvatarAssetId, isNull);
    expect(preset.pendingAvatarUrl, isNull);
    expect(preset.usingGlobalProfile, isFalse);
    expect(preset.usingProfilePresetAvatar, isTrue);
    expect(preset.defaultAvatarKey, 'purple-2');
    expect(preset.error, 'kept error');
    expect(preset.notice, 'kept notice');
  });

  test('room profile notification policy patch normalizes values', () {
    final mentions = roomProfileNotificationPolicyChanged(
      notificationPolicy: 'mention_only',
    );
    final fallback = roomProfileNotificationPolicyChanged(
      notificationPolicy: 'unexpected',
    );

    expect(mentions.notificationPolicy, 'mentions');
    expect(fallback.notificationPolicy, 'all');
  });

  test('room profile dialog patches avatar upload lifecycle', () {
    final started = roomProfileAvatarUploadStarted(
      pendingAvatarAssetId: null,
      pendingAvatarUrl: null,
      usingGlobalProfile: true,
      usingProfilePresetAvatar: false,
      defaultAvatarKey: 'blue-1',
      saving: false,
      leaving: false,
    );
    expect(started.uploadingAvatar, isTrue);
    expect(started.error, isNull);
    expect(started.notice, isNull);
    expect(started.usingGlobalProfile, isTrue);

    final succeeded = roomProfileAvatarUploadSucceeded(
      assetId: 'asset_1',
      assetUrl: '/asset.png',
      defaultAvatarKey: 'blue-1',
      saving: false,
      leaving: false,
    );
    expect(succeeded.pendingAvatarAssetId, 'asset_1');
    expect(succeeded.pendingAvatarUrl, '/asset.png');
    expect(succeeded.usingGlobalProfile, isFalse);
    expect(succeeded.usingProfilePresetAvatar, isFalse);
    expect(succeeded.uploadingAvatar, isFalse);
    expect(succeeded.error, isNull);

    final failed = roomProfileAvatarUploadFailed(
      pendingAvatarAssetId: 'old_asset',
      pendingAvatarUrl: '/old.png',
      usingGlobalProfile: false,
      usingProfilePresetAvatar: true,
      defaultAvatarKey: 'blue-1',
      saving: false,
      leaving: false,
      failure: Exception('upload failed'),
    );
    expect(failed.pendingAvatarAssetId, 'old_asset');
    expect(failed.pendingAvatarUrl, '/old.png');
    expect(failed.usingProfilePresetAvatar, isTrue);
    expect(failed.uploadingAvatar, isFalse);
    expect(failed.error, contains('upload failed'));
    expect(failed.notice, isNull);
  });

  test('room profile dialog patches save and leave failures', () {
    final saveStarted = roomProfileSaveStarted(
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/avatar.png',
      usingGlobalProfile: false,
      usingProfilePresetAvatar: false,
      defaultAvatarKey: 'blue-1',
      leaving: false,
      uploadingAvatar: false,
    );
    expect(saveStarted.saving, isTrue);
    expect(saveStarted.leaving, isFalse);
    expect(saveStarted.error, isNull);
    expect(saveStarted.notice, isNull);

    final saveFailed = roomProfileSaveFailed(
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/avatar.png',
      usingGlobalProfile: false,
      usingProfilePresetAvatar: false,
      defaultAvatarKey: 'blue-1',
      leaving: false,
      uploadingAvatar: false,
      failure: Exception('save failed'),
    );
    expect(saveFailed.saving, isFalse);
    expect(saveFailed.error, contains('save failed'));

    final leaveStarted = roomProfileLeaveStarted(
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/avatar.png',
      usingGlobalProfile: false,
      usingProfilePresetAvatar: false,
      defaultAvatarKey: 'blue-1',
      saving: false,
      uploadingAvatar: false,
    );
    expect(leaveStarted.saving, isFalse);
    expect(leaveStarted.leaving, isTrue);
    expect(leaveStarted.error, isNull);
    expect(leaveStarted.notice, isNull);

    final leaveFailed = roomProfileLeaveFailed(
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/avatar.png',
      usingGlobalProfile: false,
      usingProfilePresetAvatar: false,
      defaultAvatarKey: 'blue-1',
      saving: false,
      uploadingAvatar: false,
      failure: Exception('leave failed'),
    );
    expect(leaveFailed.leaving, isFalse);
    expect(leaveFailed.error, contains('leave failed'));
    expect(leaveFailed.notice, isNull);
  });

  test('room management dialog patches avatar upload lifecycle', () {
    final room = _room('room_1');

    final started = roomManagementAvatarUploadStarted(
      section: RoomManagementSection.info,
      room: room,
      pendingAvatarAssetId: null,
      pendingAvatarUrl: null,
      usingPresetAvatar: true,
      defaultAvatarKey: 'room-1',
      saving: false,
      deleting: false,
      changed: false,
    );
    expect(started.section, RoomManagementSection.info);
    expect(started.room, same(room));
    expect(started.uploadingAvatar, isTrue);
    expect(started.usingPresetAvatar, isTrue);
    expect(started.error, isNull);
    expect(started.notice, isNull);

    final succeeded = roomManagementAvatarUploadSucceeded(
      section: RoomManagementSection.info,
      room: room,
      assetId: 'asset_1',
      assetUrl: '/room.png',
      defaultAvatarKey: 'room-1',
      saving: false,
      deleting: false,
      changed: true,
    );
    expect(succeeded.pendingAvatarAssetId, 'asset_1');
    expect(succeeded.pendingAvatarUrl, '/room.png');
    expect(succeeded.usingPresetAvatar, isFalse);
    expect(succeeded.uploadingAvatar, isFalse);
    expect(succeeded.changed, isTrue);
    expect(succeeded.error, isNull);

    final failed = roomManagementAvatarUploadFailed(
      section: RoomManagementSection.info,
      room: room,
      pendingAvatarAssetId: 'old_asset',
      pendingAvatarUrl: '/old.png',
      usingPresetAvatar: false,
      defaultAvatarKey: 'room-1',
      saving: false,
      deleting: false,
      changed: false,
      failure: Exception('upload failed'),
    );
    expect(failed.pendingAvatarAssetId, 'old_asset');
    expect(failed.pendingAvatarUrl, '/old.png');
    expect(failed.usingPresetAvatar, isFalse);
    expect(failed.uploadingAvatar, isFalse);
    expect(failed.changed, isFalse);
    expect(failed.error, contains('upload failed'));
    expect(failed.notice, isNull);

    final preset = roomManagementUsePresetAvatar(
      section: RoomManagementSection.info,
      room: room,
      defaultAvatarKey: 'room-3',
      uploadingAvatar: false,
      saving: false,
      deleting: false,
      changed: true,
      error: 'kept error',
      notice: 'kept notice',
    );
    expect(preset.room, same(room));
    expect(preset.pendingAvatarAssetId, isNull);
    expect(preset.pendingAvatarUrl, isNull);
    expect(preset.usingPresetAvatar, isTrue);
    expect(preset.defaultAvatarKey, 'room-3');
    expect(preset.changed, isTrue);
    expect(preset.error, 'kept error');
    expect(preset.notice, 'kept notice');
  });

  test('room management section changes can clear transient messages', () {
    final room = _room('room_1');

    final kept = roomManagementSectionChanged(
      section: RoomManagementSection.info,
      room: room,
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/room.png',
      usingPresetAvatar: false,
      defaultAvatarKey: 'room-1',
      uploadingAvatar: false,
      saving: false,
      deleting: false,
      changed: true,
      error: 'kept error',
      notice: 'kept notice',
    );

    expect(kept.section, RoomManagementSection.info);
    expect(kept.room, same(room));
    expect(kept.pendingAvatarAssetId, 'asset_1');
    expect(kept.pendingAvatarUrl, '/room.png');
    expect(kept.usingPresetAvatar, isFalse);
    expect(kept.changed, isTrue);
    expect(kept.error, 'kept error');
    expect(kept.notice, 'kept notice');

    final cleared = roomManagementSectionChanged(
      section: RoomManagementSection.stickers,
      room: room,
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/room.png',
      usingPresetAvatar: false,
      defaultAvatarKey: 'room-1',
      uploadingAvatar: false,
      saving: false,
      deleting: false,
      changed: true,
      error: 'old error',
      notice: 'old notice',
    );

    expect(cleared.section, RoomManagementSection.stickers);
    expect(cleared.pendingAvatarAssetId, 'asset_1');
    expect(cleared.pendingAvatarUrl, '/room.png');
    expect(cleared.changed, isTrue);
    expect(cleared.error, isNull);
    expect(cleared.notice, isNull);
  });

  test('room management info field patches preserve sibling fields', () {
    final visibility = roomManagementVisibilityChanged(
      visibility: 'private',
      joinPolicy: 'open',
      aiVoiceAnnouncementsEnabled: false,
    );

    expect(visibility.visibility, 'private');
    expect(visibility.joinPolicy, 'open');
    expect(visibility.aiVoiceAnnouncementsEnabled, isFalse);

    final joinPolicy = roomManagementJoinPolicyChanged(
      visibility: visibility.visibility,
      joinPolicy: 'unknown',
      aiVoiceAnnouncementsEnabled: visibility.aiVoiceAnnouncementsEnabled,
    );

    expect(joinPolicy.visibility, 'private');
    expect(joinPolicy.joinPolicy, 'approval_required');
    expect(joinPolicy.aiVoiceAnnouncementsEnabled, isFalse);

    final voiceAnnouncements = roomManagementAiVoiceAnnouncementsChanged(
      visibility: joinPolicy.visibility,
      joinPolicy: joinPolicy.joinPolicy,
      aiVoiceAnnouncementsEnabled: true,
    );

    expect(voiceAnnouncements.visibility, 'private');
    expect(voiceAnnouncements.joinPolicy, 'approval_required');
    expect(voiceAnnouncements.aiVoiceAnnouncementsEnabled, isTrue);
  });

  test('room management dialog patches save invalid success and failure', () {
    final room = _room('room_1');
    final updatedRoom = _room('room_1', avatarUrl: '/saved.png');

    final invalid = roomManagementInfoDraftInvalid(
      section: RoomManagementSection.info,
      room: room,
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/room.png',
      usingPresetAvatar: false,
      defaultAvatarKey: 'room-1',
      uploadingAvatar: false,
      saving: false,
      deleting: false,
      changed: false,
      notice: 'kept',
      error: '房间名不能为空',
    );
    expect(invalid.section, RoomManagementSection.info);
    expect(invalid.room, same(room));
    expect(invalid.pendingAvatarAssetId, 'asset_1');
    expect(invalid.saving, isFalse);
    expect(invalid.error, '房间名不能为空');
    expect(invalid.notice, 'kept');

    final started = roomManagementInfoSaveStarted(
      section: RoomManagementSection.info,
      room: room,
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/room.png',
      usingPresetAvatar: false,
      defaultAvatarKey: 'room-1',
      uploadingAvatar: false,
      deleting: false,
      changed: false,
    );
    expect(started.saving, isTrue);
    expect(started.deleting, isFalse);
    expect(started.error, isNull);
    expect(started.notice, isNull);

    final succeeded = roomManagementInfoSaveSucceeded(
      section: RoomManagementSection.info,
      updatedRoom: updatedRoom,
      defaultAvatarKey: 'room-1',
      uploadingAvatar: false,
      deleting: false,
    );
    expect(succeeded.room, same(updatedRoom));
    expect(succeeded.pendingAvatarAssetId, isNull);
    expect(succeeded.pendingAvatarUrl, isNull);
    expect(succeeded.usingPresetAvatar, isFalse);
    expect(succeeded.saving, isFalse);
    expect(succeeded.changed, isTrue);
    expect(succeeded.error, isNull);
    expect(succeeded.notice, '房间信息已保存');

    final failed = roomManagementInfoSaveFailed(
      section: RoomManagementSection.info,
      room: room,
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/room.png',
      usingPresetAvatar: false,
      defaultAvatarKey: 'room-1',
      uploadingAvatar: false,
      deleting: false,
      changed: true,
      failure: Exception('save failed'),
    );
    expect(failed.room, same(room));
    expect(failed.pendingAvatarAssetId, 'asset_1');
    expect(failed.saving, isFalse);
    expect(failed.changed, isTrue);
    expect(failed.error, contains('save failed'));
    expect(failed.notice, isNull);
  });

  test('room management dialog patches deletion lifecycle', () {
    final room = _room('room_1');

    final started = roomManagementDeletionStarted(
      section: RoomManagementSection.info,
      room: room,
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/room.png',
      usingPresetAvatar: false,
      defaultAvatarKey: 'room-1',
      uploadingAvatar: false,
      saving: false,
      changed: true,
    );
    expect(started.room, same(room));
    expect(started.deleting, isTrue);
    expect(started.saving, isFalse);
    expect(started.changed, isTrue);
    expect(started.error, isNull);
    expect(started.notice, isNull);

    final failed = roomManagementDeletionFailed(
      section: RoomManagementSection.info,
      room: room,
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/room.png',
      usingPresetAvatar: false,
      defaultAvatarKey: 'room-1',
      uploadingAvatar: false,
      saving: false,
      changed: true,
      failure: Exception('delete failed'),
    );
    expect(failed.room, same(room));
    expect(failed.deleting, isFalse);
    expect(failed.changed, isTrue);
    expect(failed.error, contains('delete failed'));
    expect(failed.notice, isNull);
  });
}

RoomDetail _room(String id, {String? avatarUrl}) {
  return RoomDetail(
    id: id,
    name: id,
    avatarUrl: avatarUrl,
    defaultAvatarKey: 'room-1',
    memberCount: 3,
    myMembership: RoomMembership(
      joinedAt: DateTime.utc(2026, 6, 5),
      role: 'admin',
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
