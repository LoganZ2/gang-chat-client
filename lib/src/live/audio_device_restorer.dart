import '../app/audio_device_info.dart';
import '../app/audio_device_store.dart';
import 'audio_device_service.dart';

Future<RestoredAudioDevices<AudioDeviceInfo>> restoreStoredAudioDevices(
  AudioDeviceStore store, {
  LiveAudioDeviceService audioDevices = const LiveAudioDeviceService(),
  List<AudioDeviceInfo>? devices,
  String? systemDefaultInputId,
  String? systemDefaultOutputId,
}) async {
  final stored = await store.read();
  final availableDevices = devices ?? await audioDevices.enumerateDevices();
  final storedInputPreference = storedPreferredAudioDeviceFrom(
    availableDevices,
    kind: 'audioinput',
    storedDeviceId: stored.inputDeviceId,
    storedDeviceLabel: stored.inputDeviceLabel,
    storedDeviceGroupId: stored.inputDeviceGroupId,
    kindOf: audioDeviceInfoKind,
    deviceIdOf: audioDeviceInfoId,
    labelOf: audioDeviceInfoLabel,
    groupIdOf: audioDeviceInfoGroupId,
  );
  final storedOutputPreference = storedPreferredAudioDeviceFrom(
    availableDevices,
    kind: 'audiooutput',
    storedDeviceId: stored.outputDeviceId,
    storedDeviceLabel: stored.outputDeviceLabel,
    storedDeviceGroupId: stored.outputDeviceGroupId,
    kindOf: audioDeviceInfoKind,
    deviceIdOf: audioDeviceInfoId,
    labelOf: audioDeviceInfoLabel,
    groupIdOf: audioDeviceInfoGroupId,
  );
  final input = preferredStoredAudioDeviceFrom(
    availableDevices,
    kind: 'audioinput',
    storedDeviceId: stored.inputDeviceId,
    storedDeviceLabel: stored.inputDeviceLabel,
    storedDeviceGroupId: stored.inputDeviceGroupId,
    kindOf: audioDeviceInfoKind,
    deviceIdOf: audioDeviceInfoId,
    labelOf: audioDeviceInfoLabel,
    groupIdOf: audioDeviceInfoGroupId,
    systemDefaultDeviceId: systemDefaultInputId,
  );
  final output = preferredStoredAudioDeviceFrom(
    availableDevices,
    kind: 'audiooutput',
    storedDeviceId: stored.outputDeviceId,
    storedDeviceLabel: stored.outputDeviceLabel,
    storedDeviceGroupId: stored.outputDeviceGroupId,
    kindOf: audioDeviceInfoKind,
    deviceIdOf: audioDeviceInfoId,
    labelOf: audioDeviceInfoLabel,
    groupIdOf: audioDeviceInfoGroupId,
    systemDefaultDeviceId: systemDefaultOutputId,
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

  await _rememberRestoredPreferences(
    store,
    input: storedInputPreference == null ? null : restoredInput,
    output: storedOutputPreference == null ? null : restoredOutput,
  );

  return RestoredAudioDevices(input: restoredInput, output: restoredOutput);
}

Future<void> _rememberRestoredPreferences(
  AudioDeviceStore store, {
  required AudioDeviceInfo? input,
  required AudioDeviceInfo? output,
}) async {
  try {
    if (input != null) {
      await store.writeInputDevicePreference(
        deviceId: input.deviceId,
        label: input.label,
        groupId: input.groupId,
      );
    }
    if (output != null) {
      await store.writeOutputDevicePreference(
        deviceId: output.deviceId,
        label: output.label,
        groupId: output.groupId,
      );
    }
  } catch (_) {
    // Signature backfill is a convenience; routing already succeeded.
  }
}
