import 'audio_device_display.dart';
import 'audio_levels.dart';

class AudioDeviceListPatch<T> {
  const AudioDeviceListPatch({
    required this.inputs,
    required this.outputs,
    required this.selectedInput,
    required this.selectedOutput,
    required this.loading,
    required this.error,
  });

  final List<T> inputs;
  final List<T> outputs;
  final T? selectedInput;
  final T? selectedOutput;
  final bool loading;
  final String? error;
}

class AudioDeviceSelectionPatch<T> {
  const AudioDeviceSelectionPatch({
    required this.selectedInput,
    required this.selectedOutput,
    required this.busyDeviceId,
    required this.error,
  });

  final T? selectedInput;
  final T? selectedOutput;
  final String? busyDeviceId;
  final String? error;
}

class AudioDeviceSelectionEffects {
  const AudioDeviceSelectionEffects({
    required this.restartInputTest,
    required this.restartOutputTest,
    required this.routeOutputTest,
  });

  final bool restartInputTest;
  final bool restartOutputTest;
  final bool routeOutputTest;
}

class AudioVolumePatch {
  const AudioVolumePatch({
    required this.inputVolume,
    required this.outputVolume,
  });

  final double inputVolume;
  final double outputVolume;
}

class AudioVolumeEffects {
  const AudioVolumeEffects({
    required this.deviceKind,
    required this.volume,
    required this.updateInputTestTrack,
    required this.updateOutputRenderer,
  });

  final String deviceKind;
  final double volume;
  final bool updateInputTestTrack;
  final bool updateOutputRenderer;
}

class AudioTestStatePatch {
  const AudioTestStatePatch({
    required this.testingInput,
    required this.testingOutput,
    required this.inputLevel,
    required this.outputLevel,
    required this.error,
  });

  final bool testingInput;
  final bool testingOutput;
  final double inputLevel;
  final double outputLevel;
  final String? error;
}

AudioDeviceListPatch<T> audioDeviceListLoadStarted<T>({
  required List<T> inputs,
  required List<T> outputs,
  required T? selectedInput,
  required T? selectedOutput,
}) {
  return AudioDeviceListPatch(
    inputs: inputs,
    outputs: outputs,
    selectedInput: selectedInput,
    selectedOutput: selectedOutput,
    loading: true,
    error: null,
  );
}

AudioDeviceListPatch<T> audioDeviceListLoadFailed<T>({
  required List<T> inputs,
  required List<T> outputs,
  required T? selectedInput,
  required T? selectedOutput,
  required Object failure,
}) {
  return AudioDeviceListPatch(
    inputs: inputs,
    outputs: outputs,
    selectedInput: selectedInput,
    selectedOutput: selectedOutput,
    loading: false,
    error: failure.toString(),
  );
}

AudioDeviceListPatch<T> audioDeviceListApplied<T>({
  required List<T> devices,
  required T? restoredInput,
  required T? restoredOutput,
  required T? hardwareInput,
  required T? hardwareOutput,
  required T? currentInput,
  required T? currentOutput,
  required AudioDeviceKindOf<T> kindOf,
  required AudioDeviceIdOf<T> deviceIdOf,
  required String? error,
  T? systemDefaultInput,
}) {
  final inputs = audioDevicesByKind(devices, 'audioinput', kindOf: kindOf);
  final outputs = audioDevicesByKind(devices, 'audiooutput', kindOf: kindOf);
  return AudioDeviceListPatch(
    inputs: inputs,
    outputs: outputs,
    // [systemDefaultInput] sits between the saved preference and the hardware/
    // current device so that, absent an explicit choice, the picker follows the
    // OS default. On Windows this is null (the synthetic "default" device is
    // already captured by [restoredInput]); on macOS, where no such device is
    // enumerated, it carries the OS default reported by the native channel.
    selectedInput: selectedAudioDeviceFrom(
      inputs,
      [restoredInput, systemDefaultInput, hardwareInput, currentInput],
      kindOf: kindOf,
      deviceIdOf: deviceIdOf,
    ),
    selectedOutput: selectedAudioDeviceFrom(
      outputs,
      [restoredOutput, hardwareOutput, currentOutput],
      kindOf: kindOf,
      deviceIdOf: deviceIdOf,
    ),
    loading: false,
    error: error,
  );
}

AudioDeviceSelectionPatch<T> audioDeviceSelectionStarted<T>({
  required T device,
  required T? selectedInput,
  required T? selectedOutput,
  required AudioDeviceKindOf<T> kindOf,
  required AudioDeviceIdOf<T> deviceIdOf,
}) {
  return AudioDeviceSelectionPatch(
    selectedInput: selectedInput,
    selectedOutput: selectedOutput,
    busyDeviceId: audioDeviceKeyOf(
      device,
      kindOf: kindOf,
      deviceIdOf: deviceIdOf,
    ),
    error: null,
  );
}

AudioDeviceSelectionPatch<T> audioDeviceSelectionSucceeded<T>({
  required T device,
  required T? selectedInput,
  required T? selectedOutput,
  required AudioDeviceKindOf<T> kindOf,
  required Object? storageFailure,
}) {
  return AudioDeviceSelectionPatch(
    selectedInput: kindOf(device) == 'audioinput' ? device : selectedInput,
    selectedOutput: kindOf(device) == 'audiooutput' ? device : selectedOutput,
    busyDeviceId: null,
    error: storageFailure == null
        ? null
        : audioDevicePreferenceSaveFailureMessage(storageFailure),
  );
}

AudioDeviceSelectionPatch<T> audioDeviceSelectionFailed<T>({
  required T? selectedInput,
  required T? selectedOutput,
  required Object failure,
}) {
  return AudioDeviceSelectionPatch(
    selectedInput: selectedInput,
    selectedOutput: selectedOutput,
    busyDeviceId: null,
    error: failure.toString(),
  );
}

AudioDeviceSelectionEffects audioInputDeviceSelectedEffects({
  required bool wasTestingInput,
  required bool wasTestingOutput,
}) {
  return AudioDeviceSelectionEffects(
    restartInputTest: wasTestingInput,
    restartOutputTest: wasTestingOutput,
    routeOutputTest: false,
  );
}

AudioDeviceSelectionEffects audioOutputDeviceSelectedEffects({
  required bool testingOutput,
}) {
  return AudioDeviceSelectionEffects(
    restartInputTest: false,
    restartOutputTest: false,
    routeOutputTest: testingOutput,
  );
}

AudioVolumePatch audioStoredVolumesApplied({
  required double inputVolume,
  required double outputVolume,
}) {
  return AudioVolumePatch(
    inputVolume: normalizedAudioVolume(inputVolume),
    outputVolume: normalizedAudioVolume(outputVolume),
  );
}

AudioVolumePatch audioInputVolumeChanged({
  required double inputVolume,
  required double outputVolume,
}) {
  return AudioVolumePatch(
    inputVolume: normalizedAudioVolume(inputVolume),
    outputVolume: normalizedAudioVolume(outputVolume),
  );
}

AudioVolumePatch audioOutputVolumeChanged({
  required double inputVolume,
  required double outputVolume,
}) {
  return AudioVolumePatch(
    inputVolume: normalizedAudioVolume(inputVolume),
    outputVolume: normalizedAudioVolume(outputVolume),
  );
}

AudioVolumeEffects audioInputVolumeChangedEffects({
  required double inputVolume,
  required bool hasInputTestTrack,
}) {
  return AudioVolumeEffects(
    deviceKind: 'audioinput',
    volume: normalizedAudioVolume(inputVolume),
    updateInputTestTrack: hasInputTestTrack,
    updateOutputRenderer: false,
  );
}

AudioVolumeEffects audioOutputVolumeChangedEffects({
  required double outputVolume,
  required bool hasOutputRenderer,
}) {
  return AudioVolumeEffects(
    deviceKind: 'audiooutput',
    volume: normalizedAudioVolume(outputVolume),
    updateInputTestTrack: false,
    updateOutputRenderer: hasOutputRenderer,
  );
}

AudioTestStatePatch audioInputTestStarted({
  required bool testingOutput,
  required double outputLevel,
}) {
  return AudioTestStatePatch(
    testingInput: true,
    testingOutput: testingOutput,
    inputLevel: 0,
    outputLevel: outputLevel,
    error: null,
  );
}

AudioTestStatePatch audioInputTestStopped({
  required bool testingOutput,
  required double outputLevel,
  required String? error,
}) {
  return AudioTestStatePatch(
    testingInput: false,
    testingOutput: testingOutput,
    inputLevel: 0,
    outputLevel: outputLevel,
    error: error,
  );
}

AudioTestStatePatch audioInputTestFailed({
  required bool testingOutput,
  required double outputLevel,
  required Object failure,
}) {
  return AudioTestStatePatch(
    testingInput: false,
    testingOutput: testingOutput,
    inputLevel: 0,
    outputLevel: outputLevel,
    error: failure.toString(),
  );
}

AudioTestStatePatch audioOutputTestStarted({
  required bool testingInput,
  required double inputLevel,
}) {
  return AudioTestStatePatch(
    testingInput: testingInput,
    testingOutput: true,
    inputLevel: inputLevel,
    outputLevel: 0,
    error: null,
  );
}

AudioTestStatePatch audioOutputTestStopped({
  required bool testingInput,
  required double inputLevel,
  required String? error,
}) {
  return AudioTestStatePatch(
    testingInput: testingInput,
    testingOutput: false,
    inputLevel: inputLevel,
    outputLevel: 0,
    error: error,
  );
}

AudioTestStatePatch audioOutputTestFailed({
  required bool testingInput,
  required double inputLevel,
  required Object failure,
}) {
  return AudioTestStatePatch(
    testingInput: testingInput,
    testingOutput: false,
    inputLevel: inputLevel,
    outputLevel: 0,
    error: failure.toString(),
  );
}

AudioTestStatePatch audioInputLevelChanged({
  required double level,
  required double inputVolume,
  required bool testingOutput,
  required double outputLevel,
  required String? error,
}) {
  return AudioTestStatePatch(
    testingInput: true,
    testingOutput: testingOutput,
    inputLevel: normalizedAudioVolume(level * inputVolume),
    outputLevel: outputLevel,
    error: error,
  );
}

AudioTestStatePatch audioOutputLevelChanged({
  required double level,
  required double outputVolume,
  required bool testingInput,
  required double inputLevel,
  required String? error,
}) {
  return AudioTestStatePatch(
    testingInput: testingInput,
    testingOutput: true,
    inputLevel: inputLevel,
    outputLevel: normalizedAudioVolume(level * outputVolume),
    error: error,
  );
}
