import 'package:livekit_client/livekit_client.dart' as lk;

import '../app/audio_device_info.dart';
import 'mac_audio_devices.dart';

class LiveAudioDeviceService {
  const LiveAudioDeviceService();

  // macOS-only CoreAudio access. flutter_webrtc enumerates zero audio inputs
  // until WebRTC is recording in a room, so on macOS we merge the native input
  // list in here; off macOS this is a no-op (returns empty) and the WebRTC list
  // is used verbatim. Static so the const constructor and all call sites share
  // one instance.
  static final MacAudioDevices _mac = MacAudioDevices();

  Stream<List<AudioDeviceInfo>> get devicesChanged {
    // Re-merge native devices on every hardware change so a hotplug doesn't wipe
    // the CoreAudio-sourced devices that WebRTC can't see outside a room.
    return lk.Hardware.instance.onDeviceChange.stream.asyncMap((devices) async {
      return _mergeNativeDevices(_audioDeviceInfos(devices));
    });
  }

  Future<List<AudioDeviceInfo>> enumerateDevices() async {
    final webrtc = _audioDeviceInfos(
      await lk.Hardware.instance.enumerateDevices(),
    );
    return _mergeNativeDevices(webrtc);
  }

  // Adds CoreAudio input and output devices that WebRTC didn't report (matched
  // by deviceId, which is the same stringified AudioDeviceID on both sides).
  // When WebRTC already lists devices (i.e. inside a room) the native list
  // usually overlaps and nothing new is added.
  Future<List<AudioDeviceInfo>> _mergeNativeDevices(
    List<AudioDeviceInfo> webrtc,
  ) async {
    final native = [
      ...await _mac.enumerateInputs(),
      ...await _mac.enumerateOutputs(),
    ];
    if (native.isEmpty) return webrtc;
    final seen = webrtc.map((d) => '${d.kind}:${d.deviceId}').toSet();
    final merged = [...webrtc];
    for (final device in native) {
      if (seen.add('${device.kind}:${device.deviceId}')) merged.add(device);
    }
    return merged;
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
