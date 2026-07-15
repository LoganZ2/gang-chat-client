import '../protocol/models.dart';
import 'account_display.dart';
import 'error_display.dart';
import 'language_preference.dart';

enum AccountFormSaveTarget { account, profile, preferences }

enum AccountAvatarErrorTarget { account, sticker }

enum PasswordVisibilityField { current, newPassword, confirm }

class AccountUpdateDraft {
  const AccountUpdateDraft._({
    this.username,
    this.email,
    this.emailPublic,
    this.phoneNumber,
    this.phoneNumberPublic,
    this.language,
    this.error,
    this.noChanges = false,
  });

  const AccountUpdateDraft.invalid(String error) : this._(error: error);

  const AccountUpdateDraft.noChanges() : this._(noChanges: true);

  const AccountUpdateDraft.valid({
    this.username,
    this.email,
    this.emailPublic,
    this.phoneNumber,
    this.phoneNumberPublic,
    this.language,
  }) : error = null,
       noChanges = false;

  final String? username;
  final String? email;
  final bool? emailPublic;
  final String? phoneNumber;
  final bool? phoneNumberPublic;
  final String? language;
  final String? error;
  final bool noChanges;

  bool get isValid => error == null && !noChanges;
}

class ProfileUpdateDraft {
  const ProfileUpdateDraft._({
    this.displayName,
    this.bio,
    this.gender,
    this.defaultAvatarKey,
    this.avatarAssetId,
    this.error,
    this.noChanges = false,
  });

  const ProfileUpdateDraft.invalid(String error) : this._(error: error);

  const ProfileUpdateDraft.noChanges() : this._(noChanges: true);

  const ProfileUpdateDraft.valid({
    this.displayName,
    this.bio,
    this.gender,
    this.defaultAvatarKey,
    this.avatarAssetId,
  }) : error = null,
       noChanges = false;

  final String? displayName;
  final String? bio;
  final String? gender;
  final String? defaultAvatarKey;
  final String? avatarAssetId;
  final String? error;
  final bool noChanges;

  bool get isValid => error == null && !noChanges;
}

class PasswordChangeDraft {
  const PasswordChangeDraft._({
    this.currentPassword,
    this.newPassword,
    this.error,
  });

  const PasswordChangeDraft.invalid(String error) : this._(error: error);

  const PasswordChangeDraft.valid({
    required this.currentPassword,
    required this.newPassword,
  }) : error = null;

  final String? currentPassword;
  final String? newPassword;
  final String? error;

  bool get isValid => error == null;
}

final _loginUsernamePattern = RegExp(r'^[A-Za-z0-9_-]{3,32}$');

String? loginUsernameValidationError(String username) {
  final trimmed = username.trim();
  if (trimmed.isEmpty) {
    return '登录用户名不能为空';
  }
  if (!_loginUsernamePattern.hasMatch(trimmed)) {
    return '登录用户名需为 3-32 位，只能包含英文字母、数字、下划线或连字符';
  }
  return null;
}

bool isLoginUsernameFormatValid(String username) {
  return loginUsernameValidationError(username) == null;
}

String? loginUsernameAvailabilityError({
  required CurrentUser user,
  required String username,
  required Iterable<UserSummary> candidates,
}) {
  final normalizedUsername = username.trim().toLowerCase();
  final taken = candidates.any((candidate) {
    return candidate.id != user.id &&
        candidate.username.trim().toLowerCase() == normalizedUsername;
  });
  return taken ? '该登录用户名已被其他用户使用' : null;
}

class AccountFormSaveStatePatch {
  const AccountFormSaveStatePatch({
    required this.savingAccount,
    required this.savingProfile,
    required this.accountError,
    required this.notice,
  });

  final bool savingAccount;
  final bool savingProfile;
  final String? accountError;
  final String? notice;
}

class AccountEditableFieldsPatch {
  const AccountEditableFieldsPatch({
    required this.gender,
    required this.emailPublic,
    required this.phoneNumberPublic,
  });

  final String gender;
  final bool emailPublic;
  final bool phoneNumberPublic;
}

class PasswordChangeStatePatch {
  const PasswordChangeStatePatch({
    required this.changingPassword,
    required this.securityError,
    required this.notice,
  });

  final bool changingPassword;
  final String? securityError;
  final String? notice;
}

class PasswordVisibilityPatch {
  const PasswordVisibilityPatch({
    required this.obscureCurrentPassword,
    required this.obscureNewPassword,
    required this.obscureConfirmPassword,
  });

  final bool obscureCurrentPassword;
  final bool obscureNewPassword;
  final bool obscureConfirmPassword;
}

class AccountDeletionStatePatch {
  const AccountDeletionStatePatch({
    required this.deletingAccount,
    required this.securityError,
    required this.notice,
  });

  final bool deletingAccount;
  final String? securityError;
  final String? notice;
}

class AccountAvatarStatePatch {
  const AccountAvatarStatePatch({
    required this.pendingAvatarAssetId,
    required this.pendingAvatarUrl,
    required this.clearUploadedAvatar,
    required this.uploadingAvatar,
    required this.accountError,
    required this.stickerError,
    required this.notice,
  });

  final String? pendingAvatarAssetId;
  final String? pendingAvatarUrl;
  final bool clearUploadedAvatar;
  final bool uploadingAvatar;
  final String? accountError;
  final String? stickerError;
  final String? notice;
}

PasswordChangeStatePatch passwordChangeValidationFailed({
  required String error,
  required bool changingPassword,
  required String? notice,
}) {
  return PasswordChangeStatePatch(
    changingPassword: changingPassword,
    securityError: error,
    notice: notice,
  );
}

PasswordVisibilityPatch passwordVisibilityToggled({
  required PasswordVisibilityField field,
  required bool obscureCurrentPassword,
  required bool obscureNewPassword,
  required bool obscureConfirmPassword,
}) {
  return PasswordVisibilityPatch(
    obscureCurrentPassword: field == PasswordVisibilityField.current
        ? !obscureCurrentPassword
        : obscureCurrentPassword,
    obscureNewPassword: field == PasswordVisibilityField.newPassword
        ? !obscureNewPassword
        : obscureNewPassword,
    obscureConfirmPassword: field == PasswordVisibilityField.confirm
        ? !obscureConfirmPassword
        : obscureConfirmPassword,
  );
}

PasswordChangeStatePatch passwordChangeStarted() {
  return const PasswordChangeStatePatch(
    changingPassword: true,
    securityError: null,
    notice: null,
  );
}

PasswordChangeStatePatch passwordChangeFailed(Object failure) {
  return PasswordChangeStatePatch(
    changingPassword: false,
    securityError: userFacingErrorMessage(failure),
    notice: null,
  );
}

PasswordChangeStatePatch passwordChangeSucceeded() {
  return PasswordChangeStatePatch(
    changingPassword: false,
    securityError: null,
    notice: passwordUpdatedNotice(),
  );
}

AccountDeletionStatePatch accountDeletionStarted() {
  return const AccountDeletionStatePatch(
    deletingAccount: true,
    securityError: null,
    notice: null,
  );
}

AccountDeletionStatePatch accountDeletionFailed(Object failure) {
  return AccountDeletionStatePatch(
    deletingAccount: false,
    securityError: userFacingErrorMessage(failure),
    notice: null,
  );
}

AccountDeletionStatePatch accountDeletionFinished({
  required String? securityError,
  required String? notice,
}) {
  return AccountDeletionStatePatch(
    deletingAccount: false,
    securityError: securityError,
    notice: notice,
  );
}

AccountFormSaveStatePatch accountFormSaveValidationFailed({
  required String error,
  required bool savingAccount,
  required bool savingProfile,
  required String? notice,
}) {
  return AccountFormSaveStatePatch(
    savingAccount: savingAccount,
    savingProfile: savingProfile,
    accountError: error,
    notice: notice,
  );
}

AccountEditableFieldsPatch accountGenderChanged({
  required bool emailPublic,
  required bool phoneNumberPublic,
  required String gender,
}) {
  return AccountEditableFieldsPatch(
    gender: normalizeGender(gender),
    emailPublic: emailPublic,
    phoneNumberPublic: phoneNumberPublic,
  );
}

AccountEditableFieldsPatch accountEmailPublicChanged({
  required String gender,
  required bool phoneNumberPublic,
  required bool emailPublic,
}) {
  return AccountEditableFieldsPatch(
    gender: gender,
    emailPublic: emailPublic,
    phoneNumberPublic: phoneNumberPublic,
  );
}

AccountEditableFieldsPatch accountPhoneNumberPublicChanged({
  required String gender,
  required bool emailPublic,
  required bool phoneNumberPublic,
}) {
  return AccountEditableFieldsPatch(
    gender: gender,
    emailPublic: emailPublic,
    phoneNumberPublic: phoneNumberPublic,
  );
}

AccountFormSaveStatePatch accountFormSaveNoChanges({
  required AccountFormSaveTarget target,
  required bool savingAccount,
  required bool savingProfile,
  required String? accountError,
}) {
  return AccountFormSaveStatePatch(
    savingAccount: savingAccount,
    savingProfile: savingProfile,
    accountError: accountError,
    notice: _accountFormNoChangesNotice(target),
  );
}

AccountUpdateDraft loginUsernameUpdateDraftFromForm({
  required CurrentUser user,
  required String username,
}) {
  final nextUsername = username.trim();
  final validationError = loginUsernameValidationError(nextUsername);
  if (validationError != null) {
    return AccountUpdateDraft.invalid(validationError);
  }
  if (nextUsername == user.username) {
    return const AccountUpdateDraft.noChanges();
  }
  return AccountUpdateDraft.valid(username: nextUsername);
}

AccountFormSaveStatePatch accountFormSaveStarted({
  required AccountFormSaveTarget target,
  required bool savingAccount,
  required bool savingProfile,
}) {
  return AccountFormSaveStatePatch(
    savingAccount: _savingAccountForTarget(
      target,
      savingAccount: savingAccount,
      targetSaving: true,
    ),
    savingProfile: _savingProfileForTarget(
      target,
      savingProfile: savingProfile,
      targetSaving: true,
    ),
    accountError: null,
    notice: null,
  );
}

AccountFormSaveStatePatch accountFormSaveCancelled({
  required AccountFormSaveTarget target,
  required bool savingAccount,
  required bool savingProfile,
  required String? accountError,
  required String? notice,
}) {
  return AccountFormSaveStatePatch(
    savingAccount: _savingAccountForTarget(
      target,
      savingAccount: savingAccount,
      targetSaving: false,
    ),
    savingProfile: _savingProfileForTarget(
      target,
      savingProfile: savingProfile,
      targetSaving: false,
    ),
    accountError: accountError,
    notice: notice,
  );
}

AccountFormSaveStatePatch accountFormSaveFailed({
  required AccountFormSaveTarget target,
  required bool savingAccount,
  required bool savingProfile,
  required Object failure,
}) {
  return AccountFormSaveStatePatch(
    savingAccount: _savingAccountForTarget(
      target,
      savingAccount: savingAccount,
      targetSaving: false,
    ),
    savingProfile: _savingProfileForTarget(
      target,
      savingProfile: savingProfile,
      targetSaving: false,
    ),
    accountError: userFacingErrorMessage(failure),
    notice: null,
  );
}

AccountFormSaveStatePatch accountFormSaveSucceeded({
  required AccountFormSaveTarget target,
  required bool savingAccount,
  required bool savingProfile,
}) {
  return AccountFormSaveStatePatch(
    savingAccount: _savingAccountForTarget(
      target,
      savingAccount: savingAccount,
      targetSaving: false,
    ),
    savingProfile: _savingProfileForTarget(
      target,
      savingProfile: savingProfile,
      targetSaving: false,
    ),
    accountError: null,
    notice: _accountFormSavedNotice(target),
  );
}

class AccountPresetAvatarSelectionPatch {
  const AccountPresetAvatarSelectionPatch({
    required this.defaultAvatarKey,
    required this.pendingAvatarAssetId,
    required this.pendingAvatarUrl,
    required this.clearUploadedAvatar,
    required this.notice,
  });

  final String defaultAvatarKey;
  final String? pendingAvatarAssetId;
  final String? pendingAvatarUrl;
  final bool clearUploadedAvatar;
  final String? notice;
}

AccountPresetAvatarSelectionPatch accountPresetAvatarSelected({
  required String defaultAvatarKey,
  required String? currentAvatarUrl,
}) {
  final clearUploadedAvatar = shouldClearUploadedAvatarForPreset(
    currentAvatarUrl,
  );
  return AccountPresetAvatarSelectionPatch(
    defaultAvatarKey: defaultAvatarKey,
    pendingAvatarAssetId: null,
    pendingAvatarUrl: null,
    clearUploadedAvatar: clearUploadedAvatar,
    notice: accountPresetAvatarNotice(clearUploadedAvatar: clearUploadedAvatar),
  );
}

AccountAvatarStatePatch accountAvatarPreparationStarted({
  required AccountAvatarErrorTarget target,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool clearUploadedAvatar,
  required bool uploadingAvatar,
  required String? accountError,
  required String? stickerError,
}) {
  return _accountAvatarPatch(
    target: target,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    clearUploadedAvatar: clearUploadedAvatar,
    uploadingAvatar: uploadingAvatar,
    accountError: accountError,
    stickerError: stickerError,
    targetError: null,
    notice: null,
  );
}

AccountAvatarStatePatch accountAvatarUploadStarted({
  required AccountAvatarErrorTarget target,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool clearUploadedAvatar,
  required String? accountError,
  required String? stickerError,
}) {
  return _accountAvatarPatch(
    target: target,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    clearUploadedAvatar: clearUploadedAvatar,
    uploadingAvatar: true,
    accountError: accountError,
    stickerError: stickerError,
    targetError: null,
    notice: null,
  );
}

AccountAvatarStatePatch accountAvatarActionCancelled({
  required AccountAvatarErrorTarget target,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool clearUploadedAvatar,
  required String? accountError,
  required String? stickerError,
}) {
  return _accountAvatarPatch(
    target: target,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    clearUploadedAvatar: clearUploadedAvatar,
    uploadingAvatar: false,
    accountError: accountError,
    stickerError: stickerError,
    targetError: null,
    notice: null,
  );
}

AccountAvatarStatePatch accountAvatarActionFailed({
  required AccountAvatarErrorTarget target,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool clearUploadedAvatar,
  required String? accountError,
  required String? stickerError,
  required Object failure,
}) {
  return _accountAvatarPatch(
    target: target,
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    clearUploadedAvatar: clearUploadedAvatar,
    uploadingAvatar: false,
    accountError: accountError,
    stickerError: stickerError,
    targetError: userFacingErrorMessage(failure),
    notice: null,
  );
}

AccountAvatarStatePatch accountAvatarPendingUploadSucceeded({
  required String assetId,
  required String assetUrl,
  required String? stickerError,
}) {
  return AccountAvatarStatePatch(
    pendingAvatarAssetId: assetId,
    pendingAvatarUrl: assetUrl,
    clearUploadedAvatar: false,
    uploadingAvatar: false,
    accountError: null,
    stickerError: stickerError,
    notice: avatarUploadedPendingProfileNotice(),
  );
}

AccountAvatarStatePatch accountAvatarProfileUpdatedFromStickerSucceeded({
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool clearUploadedAvatar,
  required String? accountError,
}) {
  return AccountAvatarStatePatch(
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    clearUploadedAvatar: clearUploadedAvatar,
    uploadingAvatar: false,
    accountError: accountError,
    stickerError: null,
    notice: avatarUpdatedNotice(),
  );
}

String stickerAvatarUploadFilename({required String stickerId}) {
  return 'avatar-$stickerId.png';
}

AccountUpdateDraft accountUpdateDraftFromForm({
  required CurrentUser user,
  required String username,
  required String email,
  required bool emailPublic,
  required String phoneNumber,
  required bool phoneNumberPublic,
  required String language,
}) {
  final nextUsername = username.trim();
  final nextEmailValue = email.trim();
  final nextPhoneValue = phoneNumber.trim();
  final usernameError = loginUsernameValidationError(nextUsername);
  if (usernameError != null) {
    return AccountUpdateDraft.invalid(usernameError);
  }
  if (nextEmailValue.isEmpty) {
    return const AccountUpdateDraft.invalid('邮箱不能为空');
  }

  final changedUsername = nextUsername == user.username ? null : nextUsername;
  final changedEmail = nextEmailValue == (user.email ?? '')
      ? null
      : nextEmailValue;
  final changedEmailPublic = emailPublic == user.emailPublic
      ? null
      : emailPublic;
  final changedPhone = nextPhoneValue == (user.phoneNumber ?? '')
      ? null
      : nextPhoneValue;
  final changedPhonePublic = phoneNumberPublic == user.phoneNumberPublic
      ? null
      : phoneNumberPublic;
  final nextLanguage = normalizeAccountLanguage(language);
  final changedLanguage =
      nextLanguage == normalizeAccountLanguage(user.language)
      ? null
      : nextLanguage;

  if (changedUsername == null &&
      changedEmail == null &&
      changedEmailPublic == null &&
      changedPhone == null &&
      changedPhonePublic == null &&
      changedLanguage == null) {
    return const AccountUpdateDraft.noChanges();
  }

  return AccountUpdateDraft.valid(
    username: changedUsername,
    email: changedEmail,
    emailPublic: changedEmailPublic,
    phoneNumber: changedPhone,
    phoneNumberPublic: changedPhonePublic,
    language: changedLanguage,
  );
}

AccountUpdateDraft preferencesUpdateDraftFromForm({
  required CurrentUser user,
  required String language,
}) {
  final nextLanguage = normalizeAccountLanguage(language);
  if (nextLanguage == normalizeAccountLanguage(user.language)) {
    return const AccountUpdateDraft.noChanges();
  }
  return AccountUpdateDraft.valid(language: nextLanguage);
}

String normalizeAccountLanguage(String language) {
  return normalizeLanguagePreference(language);
}

ProfileUpdateDraft profileUpdateDraftFromForm({
  required CurrentUser user,
  required String displayName,
  required String bio,
  required String gender,
  required String defaultAvatarKey,
  String? pendingAvatarAssetId,
  required bool clearUploadedAvatar,
}) {
  final nextDisplayNameValue = displayName.trim();
  final nextBioValue = bio.trim();
  if (nextDisplayNameValue.isEmpty) {
    return const ProfileUpdateDraft.invalid('用户名不能为空');
  }

  final changedDisplayName = nextDisplayNameValue == user.displayName
      ? null
      : nextDisplayNameValue;
  final changedBio = nextBioValue == user.bio ? null : nextBioValue;
  final changedGender = gender == normalizeGender(user.gender) ? null : gender;
  final changedAvatarKey = defaultAvatarKey == user.defaultAvatarKey
      ? null
      : defaultAvatarKey;
  final changedAvatarAssetId =
      pendingAvatarAssetId ?? (clearUploadedAvatar ? '' : null);

  if (changedDisplayName == null &&
      changedBio == null &&
      changedGender == null &&
      changedAvatarKey == null &&
      changedAvatarAssetId == null) {
    return const ProfileUpdateDraft.noChanges();
  }

  return ProfileUpdateDraft.valid(
    displayName: changedDisplayName,
    bio: changedBio,
    gender: changedGender,
    defaultAvatarKey: changedAvatarKey,
    avatarAssetId: changedAvatarAssetId,
  );
}

PasswordChangeDraft passwordChangeDraftFromForm({
  required String currentPassword,
  required String newPassword,
  required String confirmPassword,
  bool currentPasswordRequired = true,
}) {
  if ((currentPasswordRequired && currentPassword.isEmpty) ||
      newPassword.isEmpty ||
      confirmPassword.isEmpty) {
    return PasswordChangeDraft.invalid(
      currentPasswordRequired ? '请完整填写当前密码、新密码和确认密码' : '请完整填写新密码和确认密码',
    );
  }
  if (newPassword.length < 8) {
    return const PasswordChangeDraft.invalid('新密码至少需要 8 个字符');
  }
  if (newPassword != confirmPassword) {
    return const PasswordChangeDraft.invalid('两次输入的新密码不一致');
  }
  return PasswordChangeDraft.valid(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );
}

bool _savingAccountForTarget(
  AccountFormSaveTarget target, {
  required bool savingAccount,
  required bool targetSaving,
}) {
  return target == AccountFormSaveTarget.profile ? savingAccount : targetSaving;
}

bool _savingProfileForTarget(
  AccountFormSaveTarget target, {
  required bool savingProfile,
  required bool targetSaving,
}) {
  return target == AccountFormSaveTarget.profile ? targetSaving : savingProfile;
}

String _accountFormNoChangesNotice(AccountFormSaveTarget target) {
  return switch (target) {
    AccountFormSaveTarget.account => accountNoBindingChangesNotice(),
    AccountFormSaveTarget.preferences => preferencesNoChangesNotice(),
    AccountFormSaveTarget.profile => profileNoChangesNotice(),
  };
}

String _accountFormSavedNotice(AccountFormSaveTarget target) {
  return switch (target) {
    AccountFormSaveTarget.account => accountBindingsSavedNotice(),
    AccountFormSaveTarget.preferences => preferencesSavedNotice(),
    AccountFormSaveTarget.profile => profileSavedNotice(),
  };
}

AccountAvatarStatePatch _accountAvatarPatch({
  required AccountAvatarErrorTarget target,
  required String? pendingAvatarAssetId,
  required String? pendingAvatarUrl,
  required bool clearUploadedAvatar,
  required bool uploadingAvatar,
  required String? accountError,
  required String? stickerError,
  required String? targetError,
  required String? notice,
}) {
  return AccountAvatarStatePatch(
    pendingAvatarAssetId: pendingAvatarAssetId,
    pendingAvatarUrl: pendingAvatarUrl,
    clearUploadedAvatar: clearUploadedAvatar,
    uploadingAvatar: uploadingAvatar,
    accountError: target == AccountAvatarErrorTarget.account
        ? targetError
        : accountError,
    stickerError: target == AccountAvatarErrorTarget.sticker
        ? targetError
        : stickerError,
    notice: notice,
  );
}
