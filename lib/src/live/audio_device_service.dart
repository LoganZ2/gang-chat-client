import 'package:livekit_client/livekit_client.dart' as lk;

import '../app/audio_device_info.dart';

class LiveAudioDeviceService {
  const LiveAudioDeviceService();

  Stream<List<AudioDeviceInfo>> get devicesChanged {
    return lk.Hardware.instance.onDeviceChange.stream.map(_audioDeviceInfos);
  }

  Future<List<AudioDeviceInfo>> enumerateDevices() async {
    return _audioDeviceInfos(await lk.Hardware.instance.enumerateDevices());
  }

  AudioDeviceInfo? get selectedAudioInput {
    return _audioDeviceInfoOrNull(lk.Hardware.instance.selectedAudioInput);
  }

  AudioDeviceInfo? get selectedAudioOutput {
    return _audioDeviceInfoOrNull(lk.Hardware.instance.selectedAudioOutput);
  }

  Future<void> selectAudioInput(AudioDeviceInfo device) {
    return lk.Hardware.instance.selectAudioInput(_mediaDevice(device));
  }

  Future<void> selectAudioOutput(AudioDeviceInfo device) {
    return lk.Hardware.instance.selectAudioOutput(_mediaDevice(device));
  }
}

List<AudioDeviceInfo> _audioDeviceInfos(List<lk.MediaDevice> devices) {
  return devices.map(_audioDeviceInfo).toList();
}

AudioDeviceInfo? _audioDeviceInfoOrNull(lk.MediaDevice? device) {
  return device == null ? null : _audioDeviceInfo(device);
}

AudioDeviceInfo _audioDeviceInfo(lk.MediaDevice device) {
  return AudioDeviceInfo(
    deviceId: device.deviceId,
    label: device.label,
    kind: device.kind,
    groupId: device.groupId ?? '',
  );
}

lk.MediaDevice _mediaDevice(AudioDeviceInfo device) {
  return lk.MediaDevice(
    device.deviceId,
    device.label,
    device.kind,
    device.groupId,
  );
}
