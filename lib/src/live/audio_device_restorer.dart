import '../app/audio_device_info.dart';
import '../app/audio_device_store.dart';
import 'audio_device_service.dart';

Future<RestoredAudioDevices<AudioDeviceInfo>> restoreStoredAudioDevices(
  AudioDeviceStore store, {
  LiveAudioDeviceService audioDevices = const LiveAudioDeviceService(),
  List<AudioDeviceInfo>? devices,
}) async {
  final stored = await store.read();
  final availableDevices = devices ?? await audioDevices.enumerateDevices();
  final input = preferredStoredAudioDeviceFrom(
    availableDevices,
    kind: 'audioinput',
    storedDeviceId: stored.inputDeviceId,
    kindOf: audioDeviceInfoKind,
    deviceIdOf: audioDeviceInfoId,
  );
  final output = preferredStoredAudioDeviceFrom(
    availableDevices,
    kind: 'audiooutput',
    storedDeviceId: stored.outputDeviceId,
    kindOf: audioDeviceInfoKind,
    deviceIdOf: audioDeviceInfoId,
  );

  final restoredInput = input == null
      ? null
      : await selectStoredAudioDeviceIfChanged(
          selected: audioDevices.selectedAudioInput,
          device: input,
          select: audioDevices.selectAudioInput,
          kindOf: audioDeviceInfoKind,
          deviceIdOf: audioDeviceInfoId,
        );
  final restoredOutput = output == null
      ? null
      : await selectStoredAudioDeviceIfChanged(
          selected: audioDevices.selectedAudioOutput,
          device: output,
          select: audioDevices.selectAudioOutput,
          kindOf: audioDeviceInfoKind,
          deviceIdOf: audioDeviceInfoId,
        );

  return RestoredAudioDevices(input: restoredInput, output: restoredOutput);
}
