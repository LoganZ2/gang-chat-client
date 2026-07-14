import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/account_forms.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('accountUpdateDraftFromForm validates required fields', () {
    expect(
      accountUpdateDraftFromForm(
        user: _user(),
        username: '',
        email: 'logan@example.test',
        emailPublic: false,
        phoneNumber: '',
        phoneNumberPublic: false,
        language: defaultUserLanguage,
      ).error,
      '用户名不能为空',
    );
    expect(
      accountUpdateDraftFromForm(
        user: _user(),
        username: 'logan',
        email: '',
        emailPublic: false,
        phoneNumber: '',
        phoneNumberPublic: false,
        language: defaultUserLanguage,
      ).error,
      '邮箱不能为空',
    );
    expect(
      accountUpdateDraftFromForm(
        user: _user(),
        username: 'lo gan',
        email: 'logan@example.test',
        emailPublic: false,
        phoneNumber: '',
        phoneNumberPublic: false,
        language: defaultUserLanguage,
      ).error,
      'Username 需为 3-32 位，只能包含英文字母、数字、下划线或连字符',
    );
  });

  test('loginUsernameUpdateDraftFromForm validates username only', () {
    expect(loginUsernameValidationError('lo'), isNotNull);
    expect(loginUsernameValidationError('logan_01-test'), isNull);
    expect(isLoginUsernameFormatValid('logan.test'), isFalse);

    expect(
      loginUsernameUpdateDraftFromForm(
        user: _user(username: 'logan'),
        username: ' logan ',
      ).noChanges,
      isTrue,
    );

    final draft = loginUsernameUpdateDraftFromForm(
      user: _user(username: 'logan'),
      username: ' new_logan ',
    );
    expect(draft.error, isNull);
    expect(draft.username, 'new_logan');
    expect(draft.email, isNull);
    expect(draft.language, isNull);
  });

  test('loginUsernameAvailabilityError detects other users only', () {
    expect(
      loginUsernameAvailabilityError(
        user: _user(id: 'user_1', username: 'logan'),
        username: 'Logan',
        candidates: [
          _summary(id: 'user_1', username: 'logan'),
          _summary(id: 'user_2', username: 'logan_suffix'),
        ],
      ),
      isNull,
    );
    expect(
      loginUsernameAvailabilityError(
        user: _user(id: 'user_1', username: 'logan'),
        username: 'New_Logan',
        candidates: [_summary(id: 'user_2', username: 'new_logan')],
      ),
      '该登录 Username 已被其他用户使用',
    );
  });

  test('accountUpdateDraftFromForm returns changed account fields only', () {
    final draft = accountUpdateDraftFromForm(
      user: _user(email: 'old@example.test', phoneNumber: ''),
      username: ' logan ',
      email: 'new@example.test',
      emailPublic: true,
      phoneNumber: ' 123 ',
      phoneNumberPublic: false,
      language: 'zh-Hant',
    );

    expect(draft.error, isNull);
    expect(draft.noChanges, isFalse);
    expect(draft.username, isNull);
    expect(draft.email, 'new@example.test');
    expect(draft.emailPublic, true);
    expect(draft.phoneNumber, '123');
    expect(draft.phoneNumberPublic, isNull);
    expect(draft.language, 'zh-Hant');
  });

  test('preferencesUpdateDraftFromForm returns language changes only', () {
    expect(
      preferencesUpdateDraftFromForm(
        user: _user(language: 'zh-Hans'),
        language: 'zh-Hans',
      ).noChanges,
      isTrue,
    );

    final draft = preferencesUpdateDraftFromForm(
      user: _user(username: 'dirty', email: 'dirty@example.test'),
      language: 'en',
    );

    expect(draft.error, isNull);
    expect(draft.noChanges, isFalse);
    expect(draft.username, isNull);
    expect(draft.email, isNull);
    expect(draft.emailPublic, isNull);
    expect(draft.phoneNumber, isNull);
    expect(draft.phoneNumberPublic, isNull);
    expect(draft.language, 'en');
  });

  test(
    'profileUpdateDraftFromForm validates and returns changed fields only',
    () {
      expect(
        profileUpdateDraftFromForm(
          user: _user(),
          displayName: ' ',
          bio: '',
          gender: 'secret',
          defaultAvatarKey: 'blue-3',
          clearUploadedAvatar: false,
        ).error,
        '用户名不能为空',
      );

      final draft = profileUpdateDraftFromForm(
        user: _user(bio: 'old', gender: 'unknown'),
        displayName: ' Logan ',
        bio: 'new',
        gender: 'male',
        defaultAvatarKey: 'green-2',
        pendingAvatarAssetId: 'asset_1',
        clearUploadedAvatar: false,
      );

      expect(draft.error, isNull);
      expect(draft.displayName, isNull);
      expect(draft.bio, 'new');
      expect(draft.gender, 'male');
      expect(draft.defaultAvatarKey, 'green-2');
      expect(draft.avatarAssetId, 'asset_1');
    },
  );

  test('profile and account drafts report noChanges', () {
    expect(
      accountUpdateDraftFromForm(
        user: _user(email: 'logan@example.test'),
        username: 'logan',
        email: 'logan@example.test',
        emailPublic: false,
        phoneNumber: '',
        phoneNumberPublic: false,
        language: defaultUserLanguage,
      ).noChanges,
      isTrue,
    );
    expect(
      profileUpdateDraftFromForm(
        user: _user(),
        displayName: 'Logan',
        bio: '',
        gender: 'secret',
        defaultAvatarKey: 'blue-3',
        clearUploadedAvatar: false,
      ).noChanges,
      isTrue,
    );
  });

  test('account editable fields patches update one form field at a time', () {
    final genderPatch = accountGenderChanged(
      gender: 'female',
      emailPublic: true,
      phoneNumberPublic: false,
    );

    expect(genderPatch.gender, 'female');
    expect(genderPatch.emailPublic, isTrue);
    expect(genderPatch.phoneNumberPublic, isFalse);

    final emailPatch = accountEmailPublicChanged(
      gender: genderPatch.gender,
      emailPublic: false,
      phoneNumberPublic: genderPatch.phoneNumberPublic,
    );

    expect(emailPatch.gender, 'female');
    expect(emailPatch.emailPublic, isFalse);
    expect(emailPatch.phoneNumberPublic, isFalse);

    final phonePatch = accountPhoneNumberPublicChanged(
      gender: emailPatch.gender,
      emailPublic: emailPatch.emailPublic,
      phoneNumberPublic: true,
    );

    expect(phonePatch.gender, 'female');
    expect(phonePatch.emailPublic, isFalse);
    expect(phonePatch.phoneNumberPublic, isTrue);
  });

  test('passwordChangeDraftFromForm validates and preserves passwords', () {
    expect(
      passwordChangeDraftFromForm(
        currentPassword: '',
        newPassword: 'new-password',
        confirmPassword: 'new-password',
      ).error,
      '请完整填写当前密码、新密码和确认密码',
    );
    expect(
      passwordChangeDraftFromForm(
        currentPassword: 'old-password',
        newPassword: 'short',
        confirmPassword: 'short',
      ).error,
      '新密码至少需要 8 个字符',
    );
    expect(
      passwordChangeDraftFromForm(
        currentPassword: 'old-password',
        newPassword: 'new-password',
        confirmPassword: 'other-password',
      ).error,
      '两次输入的新密码不一致',
    );

    final draft = passwordChangeDraftFromForm(
      currentPassword: ' old-password ',
      newPassword: ' new-password ',
      confirmPassword: ' new-password ',
    );

    expect(draft.isValid, isTrue);
    expect(draft.currentPassword, ' old-password ');
    expect(draft.newPassword, ' new-password ');

    final verifiedDraft = passwordChangeDraftFromForm(
      currentPassword: '',
      newPassword: 'new-password',
      confirmPassword: 'new-password',
      currentPasswordRequired: false,
    );
    expect(verifiedDraft.isValid, isTrue);
    expect(verifiedDraft.currentPassword, isEmpty);
  });

  test('passwordVisibilityToggled flips only the requested field', () {
    final current = passwordVisibilityToggled(
      field: PasswordVisibilityField.current,
      obscureCurrentPassword: true,
      obscureNewPassword: true,
      obscureConfirmPassword: false,
    );

    expect(current.obscureCurrentPassword, isFalse);
    expect(current.obscureNewPassword, isTrue);
    expect(current.obscureConfirmPassword, isFalse);

    final next = passwordVisibilityToggled(
      field: PasswordVisibilityField.newPassword,
      obscureCurrentPassword: current.obscureCurrentPassword,
      obscureNewPassword: current.obscureNewPassword,
      obscureConfirmPassword: current.obscureConfirmPassword,
    );

    expect(next.obscureCurrentPassword, isFalse);
    expect(next.obscureNewPassword, isFalse);
    expect(next.obscureConfirmPassword, isFalse);

    final confirm = passwordVisibilityToggled(
      field: PasswordVisibilityField.confirm,
      obscureCurrentPassword: next.obscureCurrentPassword,
      obscureNewPassword: next.obscureNewPassword,
      obscureConfirmPassword: next.obscureConfirmPassword,
    );

    expect(confirm.obscureCurrentPassword, isFalse);
    expect(confirm.obscureNewPassword, isFalse);
    expect(confirm.obscureConfirmPassword, isTrue);
  });

  test('passwordChangeValidationFailed preserves busy state and notice', () {
    final patch = passwordChangeValidationFailed(
      error: '新密码至少需要 8 个字符',
      changingPassword: true,
      notice: 'previous notice',
    );

    expect(patch.changingPassword, isTrue);
    expect(patch.securityError, '新密码至少需要 8 个字符');
    expect(patch.notice, 'previous notice');
  });

  test('passwordChangeStarted clears security feedback and marks busy', () {
    final patch = passwordChangeStarted();

    expect(patch.changingPassword, isTrue);
    expect(patch.securityError, isNull);
    expect(patch.notice, isNull);
  });

  test('passwordChangeFailed clears busy state and reports error', () {
    final patch = passwordChangeFailed('request failed');

    expect(patch.changingPassword, isFalse);
    expect(patch.securityError, 'request failed');
    expect(patch.notice, isNull);
  });

  test('passwordChangeSucceeded clears busy state and reports notice', () {
    final patch = passwordChangeSucceeded();

    expect(patch.changingPassword, isFalse);
    expect(patch.securityError, isNull);
    expect(patch.notice, '密码已更新');
  });

  test('accountDeletionStarted clears security feedback and marks busy', () {
    final patch = accountDeletionStarted();

    expect(patch.deletingAccount, isTrue);
    expect(patch.securityError, isNull);
    expect(patch.notice, isNull);
  });

  test('accountDeletionFailed clears busy state and reports error', () {
    final patch = accountDeletionFailed('delete failed');

    expect(patch.deletingAccount, isFalse);
    expect(patch.securityError, 'delete failed');
    expect(patch.notice, isNull);
  });

  test('accountDeletionFinished clears busy state and preserves feedback', () {
    final patch = accountDeletionFinished(
      securityError: null,
      notice: 'previous notice',
    );

    expect(patch.deletingAccount, isFalse);
    expect(patch.securityError, isNull);
    expect(patch.notice, 'previous notice');
  });

  test('accountFormSaveValidationFailed preserves busy state and notice', () {
    final patch = accountFormSaveValidationFailed(
      error: '邮箱不能为空',
      savingAccount: true,
      savingProfile: false,
      notice: 'previous notice',
    );

    expect(patch.savingAccount, isTrue);
    expect(patch.savingProfile, isFalse);
    expect(patch.accountError, '邮箱不能为空');
    expect(patch.notice, 'previous notice');
  });

  test('accountFormSaveNoChanges reports notice without clearing error', () {
    final accountPatch = accountFormSaveNoChanges(
      target: AccountFormSaveTarget.account,
      savingAccount: false,
      savingProfile: true,
      accountError: 'previous error',
    );
    final profilePatch = accountFormSaveNoChanges(
      target: AccountFormSaveTarget.profile,
      savingAccount: true,
      savingProfile: false,
      accountError: null,
    );
    final preferencesPatch = accountFormSaveNoChanges(
      target: AccountFormSaveTarget.preferences,
      savingAccount: true,
      savingProfile: false,
      accountError: null,
    );

    expect(accountPatch.savingAccount, isFalse);
    expect(accountPatch.savingProfile, isTrue);
    expect(accountPatch.accountError, 'previous error');
    expect(accountPatch.notice, '没有账号绑定变更');
    expect(profilePatch.savingAccount, isTrue);
    expect(profilePatch.savingProfile, isFalse);
    expect(profilePatch.accountError, isNull);
    expect(profilePatch.notice, '没有用户资料变更');
    expect(preferencesPatch.savingAccount, isTrue);
    expect(preferencesPatch.savingProfile, isFalse);
    expect(preferencesPatch.notice, '没有偏好设置变更');
  });

  test('accountFormSaveStarted sets only the target busy flag', () {
    final accountPatch = accountFormSaveStarted(
      target: AccountFormSaveTarget.account,
      savingAccount: false,
      savingProfile: true,
    );
    final profilePatch = accountFormSaveStarted(
      target: AccountFormSaveTarget.profile,
      savingAccount: true,
      savingProfile: false,
    );
    final preferencesPatch = accountFormSaveStarted(
      target: AccountFormSaveTarget.preferences,
      savingAccount: false,
      savingProfile: true,
    );

    expect(accountPatch.savingAccount, isTrue);
    expect(accountPatch.savingProfile, isTrue);
    expect(accountPatch.accountError, isNull);
    expect(accountPatch.notice, isNull);
    expect(profilePatch.savingAccount, isTrue);
    expect(profilePatch.savingProfile, isTrue);
    expect(profilePatch.accountError, isNull);
    expect(profilePatch.notice, isNull);
    expect(preferencesPatch.savingAccount, isTrue);
    expect(preferencesPatch.savingProfile, isTrue);
  });

  test('accountFormSaveCancelled clears only the target busy flag', () {
    final patch = accountFormSaveCancelled(
      target: AccountFormSaveTarget.profile,
      savingAccount: true,
      savingProfile: true,
      accountError: 'previous error',
      notice: 'previous notice',
    );

    expect(patch.savingAccount, isTrue);
    expect(patch.savingProfile, isFalse);
    expect(patch.accountError, 'previous error');
    expect(patch.notice, 'previous notice');
  });

  test('accountFormSaveFailed clears target busy flag and sets error', () {
    final patch = accountFormSaveFailed(
      target: AccountFormSaveTarget.account,
      savingAccount: true,
      savingProfile: true,
      failure: 'request failed',
    );

    expect(patch.savingAccount, isFalse);
    expect(patch.savingProfile, isTrue);
    expect(patch.accountError, 'request failed');
    expect(patch.notice, isNull);
  });

  test('accountFormSaveSucceeded clears target busy flag and sets notice', () {
    final accountPatch = accountFormSaveSucceeded(
      target: AccountFormSaveTarget.account,
      savingAccount: true,
      savingProfile: false,
    );
    final profilePatch = accountFormSaveSucceeded(
      target: AccountFormSaveTarget.profile,
      savingAccount: false,
      savingProfile: true,
    );
    final preferencesPatch = accountFormSaveSucceeded(
      target: AccountFormSaveTarget.preferences,
      savingAccount: true,
      savingProfile: false,
    );

    expect(accountPatch.savingAccount, isFalse);
    expect(accountPatch.savingProfile, isFalse);
    expect(accountPatch.accountError, isNull);
    expect(accountPatch.notice, '账号绑定已保存');
    expect(profilePatch.savingAccount, isFalse);
    expect(profilePatch.savingProfile, isFalse);
    expect(profilePatch.accountError, isNull);
    expect(profilePatch.notice, '用户资料已保存');
    expect(preferencesPatch.savingAccount, isFalse);
    expect(preferencesPatch.savingProfile, isFalse);
    expect(preferencesPatch.notice, '偏好设置已保存');
  });

  test('accountPresetAvatarSelected clears pending upload state', () {
    final patch = accountPresetAvatarSelected(
      defaultAvatarKey: 'green-2',
      currentAvatarUrl: '/assets/avatar.png',
    );

    expect(patch.defaultAvatarKey, 'green-2');
    expect(patch.pendingAvatarAssetId, isNull);
    expect(patch.pendingAvatarUrl, isNull);
    expect(patch.clearUploadedAvatar, isTrue);
    expect(patch.notice, '保存用户资料后将使用预设头像');
  });

  test('accountAvatarPreparationStarted clears target error and notice', () {
    final patch = accountAvatarPreparationStarted(
      target: AccountAvatarErrorTarget.account,
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/avatar.png',
      clearUploadedAvatar: true,
      uploadingAvatar: true,
      accountError: 'account failed',
      stickerError: 'sticker failed',
    );

    expect(patch.pendingAvatarAssetId, 'asset_1');
    expect(patch.pendingAvatarUrl, '/avatar.png');
    expect(patch.clearUploadedAvatar, isTrue);
    expect(patch.uploadingAvatar, isTrue);
    expect(patch.accountError, isNull);
    expect(patch.stickerError, 'sticker failed');
    expect(patch.notice, isNull);
  });

  test('accountAvatarUploadStarted marks avatar upload busy', () {
    final patch = accountAvatarUploadStarted(
      target: AccountAvatarErrorTarget.sticker,
      pendingAvatarAssetId: null,
      pendingAvatarUrl: null,
      clearUploadedAvatar: false,
      accountError: 'account failed',
      stickerError: 'sticker failed',
    );

    expect(patch.uploadingAvatar, isTrue);
    expect(patch.accountError, 'account failed');
    expect(patch.stickerError, isNull);
    expect(patch.notice, isNull);
  });

  test('accountAvatarActionFailed routes errors by target', () {
    final accountPatch = accountAvatarActionFailed(
      target: AccountAvatarErrorTarget.account,
      pendingAvatarAssetId: null,
      pendingAvatarUrl: null,
      clearUploadedAvatar: false,
      accountError: null,
      stickerError: 'sticker failed',
      failure: 'account failed',
    );
    final stickerPatch = accountAvatarActionFailed(
      target: AccountAvatarErrorTarget.sticker,
      pendingAvatarAssetId: null,
      pendingAvatarUrl: null,
      clearUploadedAvatar: false,
      accountError: 'account failed',
      stickerError: null,
      failure: 'sticker failed',
    );

    expect(accountPatch.uploadingAvatar, isFalse);
    expect(accountPatch.accountError, 'account failed');
    expect(accountPatch.stickerError, 'sticker failed');
    expect(stickerPatch.uploadingAvatar, isFalse);
    expect(stickerPatch.accountError, 'account failed');
    expect(stickerPatch.stickerError, 'sticker failed');
  });

  test('accountAvatarActionCancelled clears target error and busy state', () {
    final patch = accountAvatarActionCancelled(
      target: AccountAvatarErrorTarget.account,
      pendingAvatarAssetId: 'asset_1',
      pendingAvatarUrl: '/avatar.png',
      clearUploadedAvatar: false,
      accountError: 'account failed',
      stickerError: 'sticker failed',
    );

    expect(patch.pendingAvatarAssetId, 'asset_1');
    expect(patch.pendingAvatarUrl, '/avatar.png');
    expect(patch.uploadingAvatar, isFalse);
    expect(patch.accountError, isNull);
    expect(patch.stickerError, 'sticker failed');
    expect(patch.notice, isNull);
  });

  test('accountAvatarPendingUploadSucceeded stores pending avatar', () {
    final patch = accountAvatarPendingUploadSucceeded(
      assetId: 'asset_1',
      assetUrl: '/avatar.png',
      stickerError: 'sticker failed',
    );

    expect(patch.pendingAvatarAssetId, 'asset_1');
    expect(patch.pendingAvatarUrl, '/avatar.png');
    expect(patch.clearUploadedAvatar, isFalse);
    expect(patch.uploadingAvatar, isFalse);
    expect(patch.accountError, isNull);
    expect(patch.stickerError, 'sticker failed');
    expect(patch.notice, '头像已上传，保存用户资料后生效');
  });

  test(
    'accountAvatarProfileUpdatedFromStickerSucceeded clears sticker state',
    () {
      final patch = accountAvatarProfileUpdatedFromStickerSucceeded(
        pendingAvatarAssetId: null,
        pendingAvatarUrl: null,
        clearUploadedAvatar: false,
        accountError: 'account failed',
      );

      expect(patch.uploadingAvatar, isFalse);
      expect(patch.accountError, 'account failed');
      expect(patch.stickerError, isNull);
      expect(patch.notice, '头像已更新');
    },
  );

  test('stickerAvatarUploadFilename stays stable for avatar uploads', () {
    expect(
      stickerAvatarUploadFilename(stickerId: 'sticker_1'),
      'avatar-sticker_1.png',
    );
  });
}

CurrentUser _user({
  String id = 'user_1',
  String username = 'logan',
  String displayName = 'Logan',
  String bio = '',
  String gender = 'secret',
  String? email,
  bool emailPublic = false,
  String? phoneNumber,
  bool phoneNumberPublic = false,
  String defaultAvatarKey = 'blue-3',
  String language = defaultUserLanguage,
}) {
  return CurrentUser(
    id: id,
    uid: '1001',
    username: username,
    displayName: displayName,
    bio: bio,
    gender: gender,
    email: email,
    emailPublic: emailPublic,
    phoneNumber: phoneNumber,
    phoneNumberPublic: phoneNumberPublic,
    avatarUrl: null,
    defaultAvatarKey: defaultAvatarKey,
    isSuperuser: false,
    language: language,
    createdAt: DateTime.utc(2026, 6, 4),
  );
}

UserSummary _summary({required String id, required String username}) {
  return UserSummary(
    id: id,
    uid: id,
    username: username,
    displayName: username,
    bio: '',
    gender: 'secret',
    email: null,
    emailPublic: false,
    phoneNumber: null,
    phoneNumberPublic: false,
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    isSuperuser: false,
    isOnline: true,
  );
}
