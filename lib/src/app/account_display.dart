import '../protocol/models.dart';
import 'file_display.dart';

enum SessionListBodyState { loading, empty, results }

class AccountDeletionConfirmationSpec {
  const AccountDeletionConfirmationSpec({
    required this.title,
    required this.body,
    required this.expectedText,
    required this.inputHint,
    required this.confirmLabel,
  });

  final String title;
  final String body;
  final String expectedText;
  final String inputHint;
  final String confirmLabel;
}

String normalizeGender(String value) {
  return switch (value) {
    'male' || 'female' || 'secret' => value,
    _ => 'secret',
  };
}

String formatDateTime(DateTime? value) {
  if (value == null) return '未知';
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

bool canEditUsername(CurrentUser user, {DateTime? now}) {
  final canAt = user.canChangeUsernameAt;
  return canAt == null || !canAt.isAfter(now ?? DateTime.now());
}

String usernameHelperText(CurrentUser user, {DateTime? now}) {
  if (canEditUsername(user, now: now)) {
    return '用于登录和账号识别；同一账号一天只能修改一次。';
  }
  return '下次可修改时间：${formatDateTime(user.canChangeUsernameAt)}';
}

String avatarUploadFilename(String originalName, {DateTime? now}) {
  final cleaned = basename(originalName)
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
  final stem = cleaned.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
  final safeStem = stem.isEmpty ? 'avatar' : stem;
  final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return '$safeStem-$timestamp.png';
}

String? accountAvatarPreviewPath({
  required bool clearUploadedAvatar,
  String? pendingAvatarUrl,
  String? currentAvatarUrl,
}) {
  if (clearUploadedAvatar) return null;
  return pendingAvatarUrl ?? currentAvatarUrl;
}

bool shouldClearUploadedAvatarForPreset(String? currentAvatarUrl) {
  return currentAvatarUrl != null;
}

String? accountPresetAvatarNotice({required bool clearUploadedAvatar}) {
  return clearUploadedAvatar ? '保存用户资料后将使用预设头像' : null;
}

String accountNoBindingChangesNotice() {
  return '没有账号绑定变更';
}

String accountBindingsSavedNotice() {
  return '账号绑定已保存';
}

String preferencesNoChangesNotice() {
  return '没有偏好设置变更';
}

String preferencesSavedNotice() {
  return '偏好设置已保存';
}

String profileNoChangesNotice() {
  return '没有用户资料变更';
}

String profileSavedNotice() {
  return '用户资料已保存';
}

String avatarPickerOpenFailureMessage(Object error) {
  return '无法打开文件选择器';
}

String avatarReadFailureMessage(Object error) {
  return '无法读取图片';
}

String avatarEmptyFileMessage() {
  return '图片文件为空';
}

String avatarUploadedPendingProfileNotice() {
  return '头像已上传，保存用户资料后生效';
}

String avatarUpdatedNotice() {
  return '头像已更新';
}

String passwordUpdatedNotice() {
  return '密码已更新';
}

bool canDeleteAccount(CurrentUser user) {
  return !user.isSuperuser;
}

bool canStartAccountDeletion({
  required bool hasApi,
  required CurrentUser? user,
  required bool deletingAccount,
}) {
  return hasApi && user != null && canDeleteAccount(user) && !deletingAccount;
}

String accountDeletionDescription(CurrentUser user) {
  if (!canDeleteAccount(user)) return '超级用户账号不能被注销。';
  return '注销后账号不能继续登录，当前会话会失效，服务端将删除和该账号有关的信息。';
}

AccountDeletionConfirmationSpec accountDeletionConfirmationSpec(
  CurrentUser user,
) {
  return AccountDeletionConfirmationSpec(
    title: '确认注销账号',
    body: accountDeletionDescription(user),
    expectedText: user.username,
    inputHint: '输入 ${user.username} 确认',
    confirmLabel: '确认注销',
  );
}

bool canStartPasswordChange({
  required bool hasApi,
  required bool changingPassword,
}) {
  return hasApi && !changingPassword;
}

String sessionStateText(UserSession session, {DateTime? now}) {
  if (session.isCurrent) return '当前会话';
  if (session.revokedAt != null) return '已失效';
  if (!session.expiresAt.isAfter(now ?? DateTime.now())) return '已过期';
  return '有效';
}

String sessionDeviceLabel(UserSession session) {
  final userAgent = session.userAgent?.trim();
  if (userAgent == null || userAgent.isEmpty) return '未知设备';
  return userAgent;
}

String sessionIpAddressLabel(UserSession session) {
  final ipAddress = session.ipAddress?.trim();
  if (ipAddress == null || ipAddress.isEmpty) return '未知 IP';
  return ipAddress;
}

String sessionLocationLabel(UserSession session) {
  final location = session.location.trim();
  if (location.isEmpty) return '未知地点';
  return location;
}

String sessionDetailText(UserSession session) {
  return '位置：${sessionLocationLabel(session)} · IP：${sessionIpAddressLabel(session)} · 最近活动：${formatDateTime(session.lastUsedAt)}';
}

SessionListBodyState sessionListBodyState({
  required bool loading,
  required Iterable<UserSession> sessions,
}) {
  if (sessions.isNotEmpty) return SessionListBodyState.results;
  if (loading) return SessionListBodyState.loading;
  return SessionListBodyState.empty;
}

String initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts
      .take(2)
      .map((part) => String.fromCharCode(part.runes.first))
      .join();
  return initials.toUpperCase();
}
