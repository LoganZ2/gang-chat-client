import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/account_display.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('normalizeGender keeps known values and falls back to secret', () {
    expect(normalizeGender('male'), 'male');
    expect(normalizeGender('female'), 'female');
    expect(normalizeGender('secret'), 'secret');
    expect(normalizeGender('unknown'), 'secret');
  });

  test('formatDateTime uses a compact local timestamp and handles null', () {
    expect(formatDateTime(null), '未知');
    expect(formatDateTime(DateTime(2026, 6, 4, 9, 5)), '2026-06-04 09:05');
  });

  test('username edit helper respects can-change time', () {
    final now = DateTime(2026, 6, 4, 12);
    final editable = _user(canChangeUsernameAt: now);
    final locked = _user(
      canChangeUsernameAt: now.add(const Duration(hours: 2)),
    );

    expect(canEditUsername(editable, now: now), isTrue);
    expect(usernameHelperText(editable, now: now), contains('一天只能修改一次'));
    expect(canEditUsername(locked, now: now), isFalse);
    expect(usernameHelperText(locked, now: now), contains('下次可修改时间'));
  });

  test('avatarUploadFilename sanitizes basename and appends timestamp', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1234567890);

    expect(
      avatarUploadFilename('/tmp/My Avatar.jpg', now: now),
      'My-Avatar-1234567890.png',
    );
    expect(avatarUploadFilename(' .jpg ', now: now), 'avatar-1234567890.png');
  });

  test('account avatar preview helpers handle pending and preset states', () {
    expect(
      accountAvatarPreviewPath(
        clearUploadedAvatar: false,
        pendingAvatarUrl: '/pending.png',
        currentAvatarUrl: '/current.png',
      ),
      '/pending.png',
    );
    expect(
      accountAvatarPreviewPath(
        clearUploadedAvatar: false,
        pendingAvatarUrl: null,
        currentAvatarUrl: '/current.png',
      ),
      '/current.png',
    );
    expect(
      accountAvatarPreviewPath(
        clearUploadedAvatar: true,
        pendingAvatarUrl: '/pending.png',
        currentAvatarUrl: '/current.png',
      ),
      isNull,
    );
    expect(shouldClearUploadedAvatarForPreset('/current.png'), isTrue);
    expect(shouldClearUploadedAvatarForPreset(null), isFalse);
    expect(
      accountPresetAvatarNotice(clearUploadedAvatar: true),
      '保存用户资料后将使用预设头像',
    );
    expect(accountPresetAvatarNotice(clearUploadedAvatar: false), isNull);
  });

  test('account profile and avatar notices stay outside UI', () {
    expect(accountNoBindingChangesNotice(), '没有账号绑定变更');
    expect(accountBindingsSavedNotice(), '账号绑定已保存');
    expect(profileNoChangesNotice(), '没有用户资料变更');
    expect(profileSavedNotice(), '用户资料已保存');
    expect(avatarPickerOpenFailureMessage('denied'), '无法打开文件选择器：denied');
    expect(avatarReadFailureMessage('bad file'), '无法读取图片：bad file');
    expect(avatarEmptyFileMessage(), '图片文件为空');
    expect(avatarUploadedPendingProfileNotice(), '头像已上传，保存用户资料后生效');
    expect(avatarUpdatedNotice(), '头像已更新');
    expect(passwordUpdatedNotice(), '密码已更新');
  });

  test('account security action helpers gate dangerous actions', () {
    final user = _user();
    final superuser = _user(isSuperuser: true);

    expect(canDeleteAccount(user), isTrue);
    expect(canDeleteAccount(superuser), isFalse);
    expect(
      canStartAccountDeletion(hasApi: true, user: user, deletingAccount: false),
      isTrue,
    );
    expect(
      canStartAccountDeletion(
        hasApi: false,
        user: user,
        deletingAccount: false,
      ),
      isFalse,
    );
    expect(
      canStartAccountDeletion(
        hasApi: true,
        user: superuser,
        deletingAccount: false,
      ),
      isFalse,
    );
    expect(accountDeletionDescription(superuser), '超级用户账号不能被注销。');
    expect(accountDeletionDescription(user), contains('注销后账号不能继续登录'));

    final spec = accountDeletionConfirmationSpec(user);
    expect(spec.title, '确认注销账号');
    expect(spec.body, accountDeletionDescription(user));
    expect(spec.expectedText, 'logan');
    expect(spec.inputHint, '输入 logan 确认');
    expect(spec.confirmLabel, '确认注销');
  });

  test('password change guard follows api and busy state', () {
    expect(
      canStartPasswordChange(hasApi: true, changingPassword: false),
      isTrue,
    );
    expect(
      canStartPasswordChange(hasApi: false, changingPassword: false),
      isFalse,
    );
    expect(
      canStartPasswordChange(hasApi: true, changingPassword: true),
      isFalse,
    );
  });

  test(
    'sessionStateText prioritizes current revoked expired and active state',
    () {
      final now = DateTime(2026, 6, 4, 12);

      expect(sessionStateText(_session(isCurrent: true), now: now), '当前会话');
      expect(
        sessionStateText(
          _session(revokedAt: now.subtract(const Duration(days: 1))),
          now: now,
        ),
        '已失效',
      );
      expect(
        sessionStateText(
          _session(expiresAt: now.subtract(const Duration(minutes: 1))),
          now: now,
        ),
        '已过期',
      );
      expect(
        sessionStateText(
          _session(expiresAt: now.add(const Duration(minutes: 1))),
          now: now,
        ),
        '有效',
      );
    },
  );

  test('session display helpers provide fallback device and detail text', () {
    final session = _session(userAgent: '  ', ipAddress: '');

    expect(sessionDeviceLabel(session), 'Unknown device');
    expect(sessionIpAddressLabel(session), 'Unknown IP');
    expect(sessionDetailText(session), 'Local · Unknown IP · 2026-06-04 00:00');
  });

  test('sessionListBodyState separates loading empty and result states', () {
    expect(
      sessionListBodyState(loading: true, sessions: const []),
      SessionListBodyState.loading,
    );
    expect(
      sessionListBodyState(loading: false, sessions: const []),
      SessionListBodyState.empty,
    );
    expect(
      sessionListBodyState(loading: true, sessions: [_session()]),
      SessionListBodyState.results,
    );
  });

  test('initials uses first characters from up to two words', () {
    expect(initials(''), '?');
    expect(initials('Logan'), 'L');
    expect(initials('Logan Zhang'), 'LZ');
  });
}

CurrentUser _user({DateTime? canChangeUsernameAt, bool isSuperuser = false}) {
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
    createdAt: DateTime(2026, 6, 4),
    canChangeUsernameAt: canChangeUsernameAt,
  );
}

UserSession _session({
  bool isCurrent = false,
  String? userAgent = 'Test Browser',
  String? ipAddress = '127.0.0.1',
  DateTime? expiresAt,
  DateTime? revokedAt,
}) {
  return UserSession(
    id: 'session_1',
    userAgent: userAgent,
    ipAddress: ipAddress,
    location: 'Local',
    createdAt: DateTime(2026, 6, 1),
    lastUsedAt: DateTime(2026, 6, 4),
    expiresAt: expiresAt ?? DateTime(2026, 6, 5),
    revokedAt: revokedAt,
    isCurrent: isCurrent,
  );
}
