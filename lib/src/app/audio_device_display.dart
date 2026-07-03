typedef AudioDeviceKindOf<T> = String Function(T device);
typedef AudioDeviceIdOf<T> = String Function(T device);
typedef AudioDeviceLabelOf<T> = String Function(T device);
typedef AudioDeviceGroupIdOf<T> = String Function(T device);

String audioDeviceKey({required String kind, required String deviceId}) {
  return '$kind:$deviceId';
}

String audioDeviceKeyOf<T>(
  T device, {
  required AudioDeviceKindOf<T> kindOf,
  required AudioDeviceIdOf<T> deviceIdOf,
}) {
  return audioDeviceKey(kind: kindOf(device), deviceId: deviceIdOf(device));
}

bool canStartAudioDeviceSelection(String? busyDeviceId) {
  return busyDeviceId == null;
}

bool audioDeviceBusy<T>(
  T device,
  String? busyDeviceId, {
  required AudioDeviceKindOf<T> kindOf,
  required AudioDeviceIdOf<T> deviceIdOf,
}) {
  return busyDeviceId ==
      audioDeviceKeyOf(device, kindOf: kindOf, deviceIdOf: deviceIdOf);
}

String audioDevicePreferenceSaveFailureMessage(Object error) {
  return 'Could not save audio device preference: $error';
}

bool isSameAudioDevice<T>(
  T? left,
  T right, {
  required AudioDeviceKindOf<T> kindOf,
  required AudioDeviceIdOf<T> deviceIdOf,
}) {
  return left != null &&
      deviceIdOf(left) == deviceIdOf(right) &&
      kindOf(left) == kindOf(right);
}

List<T> audioDevicesByKind<T>(
  List<T> devices,
  String kind, {
  required AudioDeviceKindOf<T> kindOf,
}) {
  return devices.where((device) => kindOf(device) == kind).toList();
}

T? selectedAudioDeviceFrom<T>(
  List<T> devices,
  Iterable<T?> candidates, {
  required AudioDeviceKindOf<T> kindOf,
  required AudioDeviceIdOf<T> deviceIdOf,
}) {
  if (devices.isEmpty) return null;
  for (final candidate in candidates) {
    if (candidate == null) continue;
    for (final device in devices) {
      if (isSameAudioDevice(
        candidate,
        device,
        kindOf: kindOf,
        deviceIdOf: deviceIdOf,
      )) {
        return device;
      }
    }
  }
  return devices.first;
}

List<String> audioDeviceLabels<T>(
  List<T> devices, {
  required String fallbackLabel,
  required AudioDeviceLabelOf<T> labelOf,
  required AudioDeviceIdOf<T> deviceIdOf,
}) {
  final baseLabels = [
    for (final entry in devices.asMap().entries)
      audioDeviceLabel(
        label: labelOf(entry.value),
        deviceId: deviceIdOf(entry.value),
        index: entry.key,
        fallbackLabel: fallbackLabel,
      ),
  ];
  final totals = <String, int>{};
  for (final label in baseLabels) {
    totals[label] = (totals[label] ?? 0) + 1;
  }
  final seen = <String, int>{};
  return [
    for (final label in baseLabels)
      if (totals[label] == 1) label else _labelWithDuplicateSuffix(label, seen),
  ];
}

String audioDeviceLabel({
  required String label,
  required String deviceId,
  required int index,
  required String fallbackLabel,
}) {
  final trimmed = label.trim();
  if (trimmed.isNotEmpty) return trimmed;
  if (deviceId == 'default') return 'System default';
  if (deviceId == 'communications') return 'Communications';
  return '$fallbackLabel ${index + 1}';
}

String audioInputTestTooltip(bool testing) {
  return testing ? '停止输入测试' : '测试输入音量';
}

String audioOutputTestTooltip(bool testing) {
  return testing ? '停止输出测试' : '测试输出音量';
}

String _labelWithDuplicateSuffix(String label, Map<String, int> seen) {
  final count = (seen[label] ?? 0) + 1;
  seen[label] = count;
  if (count == 1) return label;
  return '$label #$count';
}
