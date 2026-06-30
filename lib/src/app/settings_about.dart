const gangChatClientVersion = String.fromEnvironment(
  'GANG_CHAT_VERSION',
  defaultValue: '0.4.0',
);

const gangChatClientReleaseDate = '2026/06/30';
const gangChatClientLastUpdateDate = '2026/06/30';
const gangChatSupportEmail = 'gang-chat@outlook.com';
const defaultAutoUpdatePromptEnabled = true;

String appVersionLabel(String version) {
  final normalized = version.trim();
  if (normalized.isEmpty) return 'v0.0.0';
  return normalized.startsWith('v') ? normalized : 'v$normalized';
}

String appVersionNumberLabel(String version) {
  final normalized = version.trim();
  if (normalized.isEmpty) return '0.0.0';
  return normalized.startsWith('v') ? normalized.substring(1) : normalized;
}

String updateCheckSucceededText({
  required String currentVersion,
  required String latestVersion,
}) {
  final comparison = compareAppVersions(currentVersion, latestVersion);
  if (comparison >= 0) return '当前已是最新版本';
  return '发现新版本 ${appVersionLabel(latestVersion)}';
}

String feedbackMailSubject(String version) {
  return 'Gang Chat 意见反馈 (${appVersionLabel(version)})';
}

String feedbackMailBody({
  required String senderEmail,
  required String currentVersion,
}) {
  return [
    '发件人（绑定邮箱）：$senderEmail',
    '当前版本：${appVersionLabel(currentVersion)}',
    '',
    '请在这里填写你的意见反馈：',
  ].join('\n');
}

String? boundEmailForFeedback(String? email) {
  final trimmed = email?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

class AutoUpdatePromptStore {
  const AutoUpdatePromptStore();

  Future<bool> read() {
    throw UnimplementedError('AutoUpdatePromptStore.read must be implemented.');
  }

  Future<void> write(bool enabled) {
    throw UnimplementedError(
      'AutoUpdatePromptStore.write must be implemented.',
    );
  }
}

int compareAppVersions(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index++) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) return leftValue.compareTo(rightValue);
  }
  return 0;
}

List<int> _versionParts(String version) {
  final withoutBuild = version.trim().split('+').first;
  final withoutPrefix = withoutBuild.startsWith('v')
      ? withoutBuild.substring(1)
      : withoutBuild;
  return withoutPrefix
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9].*$'), '')))
      .map((part) => part ?? 0)
      .toList(growable: false);
}
