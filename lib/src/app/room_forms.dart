import '../protocol/models.dart';
import 'error_display.dart';
import 'room_display.dart';

class CreateRoomDraft {
  const CreateRoomDraft._({this.name, this.error});

  const CreateRoomDraft.invalid(String error) : this._(error: error);

  const CreateRoomDraft.valid({required this.name}) : error = null;

  final String? name;
  final String? error;

  bool get isValid => error == null;
}

class CreateRoomDialogPatch {
  const CreateRoomDialogPatch({required this.busy, required this.error});

  final bool busy;
  final String? error;
}

class RoomProfileUpdateDraft {
  const RoomProfileUpdateDraft({
    required this.remarkName,
    required this.notificationPolicy,
    required this.roomDisplayName,
    required this.avatarAssetId,
    required this.defaultAvatarKey,
  });

  final String remarkName;
  final String notificationPolicy;
  final String roomDisplayName;
  final String? avatarAssetId;
  final String defaultAvatarKey;
}

class RoomProfileDialogStatePatch {
  const RoomProfileDialogStatePatch({
    required this.pendingAvatarAssetId,
    required this.pendingAvatarUrl,
    required this.usingGlobalProfile,
    required this.usingProfilePresetAvatar,
    required this.defaultAvatarKey,
    required this.saving,
    required this.leaving,
    required this.uploadingAvatar,
    required this.error,
    required this.notice,
  });

  final String? pendingAvatarAssetId;
  final String? pendingAvatarUrl;
  final bool usingGlobalProfile;
  final bool usingProfilePresetAvatar;
  final String defaultAvatarKey;
  final bool saving;
  final bool leaving;
  final bool uploadingAvatar;
  final String? error;
  final String? notice;
}

class RoomProfileNotificationPolicyPatch {
  const RoomProfileNotificationPolicyPatch({required this.notificationPolicy});

  final String notificationPolicy;
}

class RoomInfoUpdateDraft {
  const RoomInfoUpdateDraft._({
    this.name,
    this.description,
    this.visibility,
    this.joinPolicy,
    this.avatarAssetId,
    this.defaultAvatarKey,
    this.error,
  });

  const RoomInfoUpdateDraft.invalid(String error) : this._(error: error);

  const RoomInfoUpdateDraft.valid({
    required this.name,
    required this.description,
    required this.visibility,
    required this.joinPolicy,
    required this.avatarAssetId,
    required this.defaultAvatarKey,
  }) : error = null;

  final String? name;
  final String? description;
  final String? visibility;
  final String? joinPolicy;
  final String? avatarAssetId;
  final String? defaultAvatarKey;
  final String? error;

  bool get isValid => error == null;
}

enum RoomManagementSection { info, stickers }

class RoomManagementDialogStatePatch {
  const RoomManagementDialogStatePatch({
    required this.section,
    required this.room,
    required this.pendingAvatarAssetId,
    required this.pendingAvatarUrl,
    required this.usingPresetAvatar,
    required this.defaultAvatarKey,
    required this.uploadingAvatar,
    required this.saving,
    required this.deleting,
    required this.changed,
    required this.error,
    required this.notice,
  });

  final RoomManagementSection section;
  final RoomDetail room;
  final String? pendingAvatarAssetId;
  final String? pendingAvatarUrl;
  final bool usingPresetAvatar;
  final String defaultAvatarKey;
  final bool uploadingAvatar;
  final bool saving;
  final bool deleting;
  final bool changed;
  final String? error;
  final String? notice;
}

class RoomManagementInfoFieldsPatch {
  const RoomManagementInfoFieldsPatch({
    required this.visibility,
    required this.joinPolicy,
  });

  final String visibility;
  final String joinPolicy;
}

bool canStartRoomProfileSave({required bool saving, required bool leaving}) {
  return !saving && !leaving;
}

bool canStartCreateRoom({required bool busy}) {
  return !busy;
}

CreateRoomDialogPatch createRoomSubmitStarted() {
  return const CreateRoomDialogPatch(busy: true, error: null);
}

CreateRoomDialogPatch createRoomSubmitFailed({required Object failure}) {
  return CreateRoomDialogPatch(
    busy: true,
    error: userFacingErrorMessage(failure),
  );
}

CreateRoomDialogPatch createRoomSubmitFinished({required String? error}) {
  return CreateRoomDialogPatch(busy: false, error: error);
}

bool canStartRoomLeave({required bool saving, required bool leaving}) {
  return !saving && !leaving;
}

RoomProfileDialogStatePatch roomProfileCopySucceeded({
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingGlobalProfile,
  required bool usingProfilePresetAvatar,
  required String defaultAvatarKey,
  required bool saving,
  required bool leaving,
  required bool uploadingAvatar,
  required String label,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingGlobalProfile: usingGlobalProfile,
    usingProfilePresetAvatar: usingProfilePresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    saving: saving,
    leaving: leaving,
    uploadingAvatar: uploadingAvatar,
    error: null,
    notice: roomCopySuccessNotice(label),
  );
}

RoomProfileNotificationPolicyPatch roomProfileNotificationPolicyChanged({
  required String notificationPolicy,
}) {
  return RoomProfileNotificationPolicyPatch(
    notificationPolicy: normalizeRoomNotificationPolicy(notificationPolicy),
  );
}

RoomProfileDialogStatePatch roomProfileCopyFailed({
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingGlobalProfile,
  required bool usingProfilePresetAvatar,
  required String defaultAvatarKey,
  required bool saving,
  required bool leaving,
  required bool uploadingAvatar,
  required String? notice,
  required Object failure,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingGlobalProfile: usingGlobalProfile,
    usingProfilePresetAvatar: usingProfilePresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    saving: saving,
    leaving: leaving,
    uploadingAvatar: uploadingAvatar,
    error: roomCopyFailureMessage(failure),
    notice: notice,
  );
}

RoomProfileDialogStatePatch roomProfileAvatarPickFailed({
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingGlobalProfile,
  required bool usingProfilePresetAvatar,
  required String defaultAvatarKey,
  required bool saving,
  required bool leaving,
  required bool uploadingAvatar,
  required String? notice,
  required Object failure,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingGlobalProfile: usingGlobalProfile,
    usingProfilePresetAvatar: usingProfilePresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    saving: saving,
    leaving: leaving,
    uploadingAvatar: uploadingAvatar,
    error: userFacingErrorMessage(failure),
    notice: notice,
  );
}

RoomProfileDialogStatePatch roomProfileAvatarUploadStarted({
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingGlobalProfile,
  required bool usingProfilePresetAvatar,
  required String defaultAvatarKey,
  required bool saving,
  required bool leaving,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingGlobalProfile: usingGlobalProfile,
    usingProfilePresetAvatar: usingProfilePresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    saving: saving,
    leaving: leaving,
    uploadingAvatar: true,
    error: null,
    notice: null,
  );
}

RoomProfileDialogStatePatch roomProfileAvatarUploadSucceeded({
  required String assetId,
  required String assetUrl,
  required String defaultAvatarKey,
  required bool saving,
  required bool leaving,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: assetId,
    pendingAvatarUrl: assetUrl,
    usingGlobalProfile: false,
    usingProfilePresetAvatar: false,
    defaultAvatarKey: defaultAvatarKey,
    saving: saving,
    leaving: leaving,
    uploadingAvatar: false,
    error: null,
    notice: null,
  );
}

RoomProfileDialogStatePatch roomProfileAvatarUploadFailed({
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingGlobalProfile,
  required bool usingProfilePresetAvatar,
  required String defaultAvatarKey,
  required bool saving,
  required bool leaving,
  required Object failure,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingGlobalProfile: usingGlobalProfile,
    usingProfilePresetAvatar: usingProfilePresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    saving: saving,
    leaving: leaving,
    uploadingAvatar: false,
    error: userFacingErrorMessage(failure),
    notice: null,
  );
}

RoomProfileDialogStatePatch roomProfileUseGlobalProfile({
  required String currentUserDefaultAvatarKey,
  required bool saving,
  required bool leaving,
  required bool uploadingAvatar,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: null,
    pendingAvatarUrl: null,
    usingGlobalProfile: true,
    usingProfilePresetAvatar: false,
    defaultAvatarKey: currentUserDefaultAvatarKey,
    saving: saving,
    leaving: leaving,
    uploadingAvatar: uploadingAvatar,
    error: null,
    notice: roomUseGlobalProfileNotice(),
  );
}

RoomProfileDialogStatePatch roomProfileUsePresetAvatar({
  required String defaultAvatarKey,
  required bool saving,
  required bool leaving,
  required bool uploadingAvatar,
  required String? error,
  required String? notice,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: null,
    pendingAvatarUrl: null,
    usingGlobalProfile: false,
    usingProfilePresetAvatar: true,
    defaultAvatarKey: defaultAvatarKey,
    saving: saving,
    leaving: leaving,
    uploadingAvatar: uploadingAvatar,
    error: error,
    notice: notice,
  );
}

RoomProfileDialogStatePatch roomProfileSaveStarted({
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingGlobalProfile,
  required bool usingProfilePresetAvatar,
  required String defaultAvatarKey,
  required bool leaving,
  required bool uploadingAvatar,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingGlobalProfile: usingGlobalProfile,
    usingProfilePresetAvatar: usingProfilePresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    saving: true,
    leaving: leaving,
    uploadingAvatar: uploadingAvatar,
    error: null,
    notice: null,
  );
}

RoomProfileDialogStatePatch roomProfileSaveFailed({
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingGlobalProfile,
  required bool usingProfilePresetAvatar,
  required String defaultAvatarKey,
  required bool leaving,
  required bool uploadingAvatar,
  required Object failure,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingGlobalProfile: usingGlobalProfile,
    usingProfilePresetAvatar: usingProfilePresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    saving: false,
    leaving: leaving,
    uploadingAvatar: uploadingAvatar,
    error: userFacingErrorMessage(failure),
    notice: null,
  );
}

RoomProfileDialogStatePatch roomProfileLeaveStarted({
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingGlobalProfile,
  required bool usingProfilePresetAvatar,
  required String defaultAvatarKey,
  required bool saving,
  required bool uploadingAvatar,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingGlobalProfile: usingGlobalProfile,
    usingProfilePresetAvatar: usingProfilePresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    saving: saving,
    leaving: true,
    uploadingAvatar: uploadingAvatar,
    error: null,
    notice: null,
  );
}

RoomProfileDialogStatePatch roomProfileLeaveFailed({
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingGlobalProfile,
  required bool usingProfilePresetAvatar,
  required String defaultAvatarKey,
  required bool saving,
  required bool uploadingAvatar,
  required Object failure,
}) {
  return RoomProfileDialogStatePatch(
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingGlobalProfile: usingGlobalProfile,
    usingProfilePresetAvatar: usingProfilePresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    saving: saving,
    leaving: false,
    uploadingAvatar: uploadingAvatar,
    error: userFacingErrorMessage(failure),
    notice: null,
  );
}

bool roomInfoManagementBusy({required bool saving, required bool deleting}) {
  return saving || deleting;
}

bool canStartRoomInfoSave({required bool saving, required bool deleting}) {
  return !roomInfoManagementBusy(saving: saving, deleting: deleting);
}

bool canStartRoomDeletion({
  required bool canDeleteRoom,
  required bool saving,
  required bool deleting,
}) {
  return canDeleteRoom &&
      !roomInfoManagementBusy(saving: saving, deleting: deleting);
}

RoomManagementDialogStatePatch roomManagementAvatarPickFailed({
  required RoomManagementSection section,
  required RoomDetail room,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingPresetAvatar,
  required String defaultAvatarKey,
  required bool uploadingAvatar,
  required bool saving,
  required bool deleting,
  required bool changed,
  required String? notice,
  required Object failure,
}) {
  return RoomManagementDialogStatePatch(
    section: section,
    room: room,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingPresetAvatar: usingPresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: uploadingAvatar,
    saving: saving,
    deleting: deleting,
    changed: changed,
    error: userFacingErrorMessage(failure),
    notice: notice,
  );
}

RoomManagementDialogStatePatch roomManagementAvatarUploadStarted({
  required RoomManagementSection section,
  required RoomDetail room,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingPresetAvatar,
  required String defaultAvatarKey,
  required bool saving,
  required bool deleting,
  required bool changed,
}) {
  return RoomManagementDialogStatePatch(
    section: section,
    room: room,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingPresetAvatar: usingPresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: true,
    saving: saving,
    deleting: deleting,
    changed: changed,
    error: null,
    notice: null,
  );
}

RoomManagementDialogStatePatch roomManagementAvatarUploadSucceeded({
  required RoomManagementSection section,
  required RoomDetail room,
  required String assetId,
  required String assetUrl,
  required String defaultAvatarKey,
  required bool saving,
  required bool deleting,
  required bool changed,
}) {
  return RoomManagementDialogStatePatch(
    section: section,
    room: room,
    pendingAvatarAssetId: assetId,
    pendingAvatarUrl: assetUrl,
    usingPresetAvatar: false,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: false,
    saving: saving,
    deleting: deleting,
    changed: changed,
    error: null,
    notice: null,
  );
}

RoomManagementDialogStatePatch roomManagementAvatarUploadFailed({
  required RoomManagementSection section,
  required RoomDetail room,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingPresetAvatar,
  required String defaultAvatarKey,
  required bool saving,
  required bool deleting,
  required bool changed,
  required Object failure,
}) {
  return RoomManagementDialogStatePatch(
    section: section,
    room: room,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingPresetAvatar: usingPresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: false,
    saving: saving,
    deleting: deleting,
    changed: changed,
    error: userFacingErrorMessage(failure),
    notice: null,
  );
}

RoomManagementDialogStatePatch roomManagementUsePresetAvatar({
  required RoomManagementSection section,
  required RoomDetail room,
  required String defaultAvatarKey,
  required bool uploadingAvatar,
  required bool saving,
  required bool deleting,
  required bool changed,
  required String? error,
  required String? notice,
}) {
  return RoomManagementDialogStatePatch(
    section: section,
    room: room,
    pendingAvatarAssetId: null,
    pendingAvatarUrl: null,
    usingPresetAvatar: true,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: uploadingAvatar,
    saving: saving,
    deleting: deleting,
    changed: changed,
    error: error,
    notice: notice,
  );
}

RoomManagementDialogStatePatch roomManagementSectionChanged({
  required RoomManagementSection section,
  required RoomDetail room,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingPresetAvatar,
  required String defaultAvatarKey,
  required bool uploadingAvatar,
  required bool saving,
  required bool deleting,
  required bool changed,
  required String? error,
  required String? notice,
}) {
  final clearTransientMessages = section == RoomManagementSection.stickers;
  return RoomManagementDialogStatePatch(
    section: section,
    room: room,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingPresetAvatar: usingPresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: uploadingAvatar,
    saving: saving,
    deleting: deleting,
    changed: changed,
    error: clearTransientMessages ? null : error,
    notice: clearTransientMessages ? null : notice,
  );
}

RoomManagementInfoFieldsPatch roomManagementVisibilityChanged({
  required String visibility,
  required String joinPolicy,
}) {
  return RoomManagementInfoFieldsPatch(
    visibility: normalizeRoomVisibility(visibility),
    joinPolicy: joinPolicy,
  );
}

RoomManagementInfoFieldsPatch roomManagementJoinPolicyChanged({
  required String visibility,
  required String joinPolicy,
}) {
  return RoomManagementInfoFieldsPatch(
    visibility: visibility,
    joinPolicy: normalizeRoomJoinPolicy(joinPolicy),
  );
}

RoomManagementDialogStatePatch roomManagementInfoDraftInvalid({
  required RoomManagementSection section,
  required RoomDetail room,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingPresetAvatar,
  required String defaultAvatarKey,
  required bool uploadingAvatar,
  required bool saving,
  required bool deleting,
  required bool changed,
  required String? notice,
  required String? error,
}) {
  return RoomManagementDialogStatePatch(
    section: section,
    room: room,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingPresetAvatar: usingPresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: uploadingAvatar,
    saving: saving,
    deleting: deleting,
    changed: changed,
    error: error,
    notice: notice,
  );
}

RoomManagementDialogStatePatch roomManagementInfoSaveStarted({
  required RoomManagementSection section,
  required RoomDetail room,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingPresetAvatar,
  required String defaultAvatarKey,
  required bool uploadingAvatar,
  required bool deleting,
  required bool changed,
}) {
  return RoomManagementDialogStatePatch(
    section: section,
    room: room,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingPresetAvatar: usingPresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: uploadingAvatar,
    saving: true,
    deleting: deleting,
    changed: changed,
    error: null,
    notice: null,
  );
}

RoomManagementDialogStatePatch roomManagementInfoSaveSucceeded({
  required RoomManagementSection section,
  required RoomDetail updatedRoom,
  required String defaultAvatarKey,
  required bool uploadingAvatar,
  required bool deleting,
}) {
  return RoomManagementDialogStatePatch(
    section: section,
    room: updatedRoom,
    pendingAvatarAssetId: null,
    pendingAvatarUrl: null,
    usingPresetAvatar: updatedRoom.avatarUrl == null,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: uploadingAvatar,
    saving: false,
    deleting: deleting,
    changed: true,
    error: null,
    notice: roomInfoSavedNotice(),
  );
}

RoomManagementDialogStatePatch roomManagementInfoSaveFailed({
  required RoomManagementSection section,
  required RoomDetail room,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingPresetAvatar,
  required String defaultAvatarKey,
  required bool uploadingAvatar,
  required bool deleting,
  required bool changed,
  required Object failure,
}) {
  return RoomManagementDialogStatePatch(
    section: section,
    room: room,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingPresetAvatar: usingPresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: uploadingAvatar,
    saving: false,
    deleting: deleting,
    changed: changed,
    error: userFacingErrorMessage(failure),
    notice: null,
  );
}

RoomManagementDialogStatePatch roomManagementDeletionStarted({
  required RoomManagementSection section,
  required RoomDetail room,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingPresetAvatar,
  required String defaultAvatarKey,
  required bool uploadingAvatar,
  required bool saving,
  required bool changed,
}) {
  return RoomManagementDialogStatePatch(
    section: section,
    room: room,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingPresetAvatar: usingPresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: uploadingAvatar,
    saving: saving,
    deleting: true,
    changed: changed,
    error: null,
    notice: null,
  );
}

RoomManagementDialogStatePatch roomManagementDeletionFailed({
  required RoomManagementSection section,
  required RoomDetail room,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool usingPresetAvatar,
  required String defaultAvatarKey,
  required bool uploadingAvatar,
  required bool saving,
  required bool changed,
  required Object failure,
}) {
  return RoomManagementDialogStatePatch(
    section: section,
    room: room,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    usingPresetAvatar: usingPresetAvatar,
    defaultAvatarKey: defaultAvatarKey,
    uploadingAvatar: uploadingAvatar,
    saving: saving,
    deleting: false,
    changed: changed,
    error: userFacingErrorMessage(failure),
    notice: null,
  );
}

CreateRoomDraft createRoomDraftFromForm({required String name}) {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    return const CreateRoomDraft.invalid('房间名不能为空');
  }
  return CreateRoomDraft.valid(name: trimmedName);
}

RoomProfileUpdateDraft roomProfileUpdateDraftFromForm({
  required String remarkName,
  required String notificationPolicy,
  required bool usingGlobalProfile,
  required String roomDisplayName,
  String? pendingAvatarAssetId,
  required bool usingProfilePresetAvatar,
  required String defaultAvatarKey,
}) {
  return RoomProfileUpdateDraft(
    remarkName: remarkName.trim(),
    notificationPolicy: normalizeRoomNotificationPolicy(notificationPolicy),
    roomDisplayName: usingGlobalProfile ? '' : roomDisplayName.trim(),
    avatarAssetId: roomProfileAvatarAssetIdForSave(
      usingGlobalProfile: usingGlobalProfile,
      pendingAvatarAssetId: pendingAvatarAssetId,
      usingProfilePresetAvatar: usingProfilePresetAvatar,
    ),
    defaultAvatarKey: usingGlobalProfile ? '' : defaultAvatarKey,
  );
}

String? roomProfileAvatarAssetIdForSave({
  required bool usingGlobalProfile,
  String? pendingAvatarAssetId,
  required bool usingProfilePresetAvatar,
}) {
  if (usingGlobalProfile) return '';
  final pending = pendingAvatarAssetId;
  if (pending != null) return pending;
  if (usingProfilePresetAvatar) return '';
  return null;
}

RoomInfoUpdateDraft roomInfoUpdateDraftFromForm({
  required String name,
  required String description,
  required String visibility,
  required String joinPolicy,
  String? pendingAvatarAssetId,
  required bool usingPresetAvatar,
  required String defaultAvatarKey,
}) {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    return const RoomInfoUpdateDraft.invalid('房间名不能为空');
  }
  return RoomInfoUpdateDraft.valid(
    name: trimmedName,
    description: description.trim(),
    visibility: normalizeRoomVisibility(visibility),
    joinPolicy: normalizeRoomJoinPolicy(joinPolicy),
    avatarAssetId: roomAvatarAssetIdForSave(
      pendingAvatarAssetId: pendingAvatarAssetId,
      usingPresetAvatar: usingPresetAvatar,
    ),
    defaultAvatarKey: defaultAvatarKey,
  );
}

String? roomAvatarAssetIdForSave({
  String? pendingAvatarAssetId,
  required bool usingPresetAvatar,
}) {
  final pending = pendingAvatarAssetId;
  if (pending != null) return pending;
  if (usingPresetAvatar) return '';
  return null;
}
