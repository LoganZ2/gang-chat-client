class AudioDeviceInfo {
  const AudioDeviceInfo({
    required this.deviceId,
    required this.label,
    required this.kind,
    this.groupId = '',
  });

  final String deviceId;
  final String label;
  final String kind;
  final String groupId;

  @override
  bool operator ==(Object other) {
    return other is AudioDeviceInfo &&
        other.deviceId == deviceId &&
        other.label == label &&
        other.kind == kind &&
        other.groupId == groupId;
  }

  @override
  int get hashCode => Object.hash(deviceId, label, kind, groupId);

  @override
  String toString() {
    return 'AudioDeviceInfo(deviceId: $deviceId, label: $label, kind: $kind)';
  }
}

String audioDeviceInfoKind(AudioDeviceInfo device) => device.kind;
String audioDeviceInfoId(AudioDeviceInfo device) => device.deviceId;
String audioDeviceInfoLabel(AudioDeviceInfo device) => device.label;
String audioDeviceInfoGroupId(AudioDeviceInfo device) => device.groupId;
