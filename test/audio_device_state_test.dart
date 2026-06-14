import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/audio_device_state.dart';

void main() {
  test('audioDeviceListLoadStarted preserves devices and clears error', () {
    const input = _Device('mic_1', 'Mic', 'audioinput');
    const output = _Device('speaker_1', 'Speaker', 'audiooutput');
    final patch = audioDeviceListLoadStarted(
      inputs: const [input],
      outputs: const [output],
      selectedInput: input,
      selectedOutput: output,
    );

    expect(patch.inputs, [input]);
    expect(patch.outputs, [output]);
    expect(patch.selectedInput, input);
    expect(patch.selectedOutput, output);
    expect(patch.loading, isTrue);
    expect(patch.error, isNull);
  });

  test(
    'audioDeviceListLoadFailed preserves device state and reports error',
    () {
      const input = _Device('mic_1', 'Mic', 'audioinput');
      final patch = audioDeviceListLoadFailed(
        inputs: const [input],
        outputs: const [],
        selectedInput: input,
        selectedOutput: null,
        failure: 'device denied',
      );

      expect(patch.inputs, [input]);
      expect(patch.outputs, isEmpty);
      expect(patch.selectedInput, input);
      expect(patch.selectedOutput, isNull);
      expect(patch.loading, isFalse);
      expect(patch.error, 'device denied');
    },
  );

  test(
    'audioDeviceListApplied filters and selects from priority candidates',
    () {
      const inputOne = _Device('mic_1', 'Mic 1', 'audioinput');
      const inputTwo = _Device('mic_2', 'Mic 2', 'audioinput');
      const outputOne = _Device('speaker_1', 'Speaker 1', 'audiooutput');
      const outputTwo = _Device('speaker_2', 'Speaker 2', 'audiooutput');

      final patch = audioDeviceListApplied<_Device>(
        devices: const [inputOne, inputTwo, outputOne, outputTwo],
        restoredInput: inputTwo,
        restoredOutput: null,
        hardwareInput: inputOne,
        hardwareOutput: outputTwo,
        currentInput: null,
        currentOutput: outputOne,
        kindOf: _kindOf,
        deviceIdOf: _deviceIdOf,
        error: 'previous warning',
      );

      expect(patch.inputs, [inputOne, inputTwo]);
      expect(patch.outputs, [outputOne, outputTwo]);
      expect(patch.selectedInput, inputTwo);
      expect(patch.selectedOutput, outputTwo);
      expect(patch.loading, isFalse);
      expect(patch.error, 'previous warning');
    },
  );

  test(
    'audioDeviceListApplied follows system default input when none restored',
    () {
      const inputOne = _Device('mic_1', 'Mic 1', 'audioinput');
      const inputTwo = _Device('mic_2', 'Mic 2', 'audioinput');

      final patch = audioDeviceListApplied<_Device>(
        devices: const [inputOne, inputTwo],
        restoredInput: null,
        restoredOutput: null,
        hardwareInput: inputOne,
        hardwareOutput: null,
        currentInput: null,
        currentOutput: null,
        kindOf: _kindOf,
        deviceIdOf: _deviceIdOf,
        error: null,
        systemDefaultInput: inputTwo,
      );

      // The system default sits ahead of the hardware/current device, so it is
      // chosen even though the hardware reports mic_1.
      expect(patch.selectedInput, inputTwo);
    },
  );

  test('audioDeviceListApplied keeps restored input over system default', () {
    const inputOne = _Device('mic_1', 'Mic 1', 'audioinput');
    const inputTwo = _Device('mic_2', 'Mic 2', 'audioinput');

    final patch = audioDeviceListApplied<_Device>(
      devices: const [inputOne, inputTwo],
      restoredInput: inputOne,
      restoredOutput: null,
      hardwareInput: null,
      hardwareOutput: null,
      currentInput: null,
      currentOutput: null,
      kindOf: _kindOf,
      deviceIdOf: _deviceIdOf,
      error: null,
      systemDefaultInput: inputTwo,
    );

    // An explicit saved preference still wins over the OS default.
    expect(patch.selectedInput, inputOne);
  });

  test('audioDeviceSelectionStarted marks selected device busy', () {
    const input = _Device('mic_1', 'Mic', 'audioinput');
    const output = _Device('speaker_1', 'Speaker', 'audiooutput');
    final patch = audioDeviceSelectionStarted(
      device: input,
      selectedInput: input,
      selectedOutput: output,
      kindOf: _kindOf,
      deviceIdOf: _deviceIdOf,
    );

    expect(patch.selectedInput, input);
    expect(patch.selectedOutput, output);
    expect(patch.busyDeviceId, 'audioinput:mic_1');
    expect(patch.error, isNull);
  });

  test('audioDeviceSelectionSucceeded updates only matching kind', () {
    const oldInput = _Device('mic_1', 'Mic 1', 'audioinput');
    const newOutput = _Device('speaker_2', 'Speaker 2', 'audiooutput');

    final patch = audioDeviceSelectionSucceeded<_Device>(
      device: newOutput,
      selectedInput: oldInput,
      selectedOutput: null,
      kindOf: _kindOf,
      storageFailure: 'storage denied',
    );

    expect(patch.selectedInput, oldInput);
    expect(patch.selectedOutput, newOutput);
    expect(patch.busyDeviceId, isNull);
    expect(
      patch.error,
      'Could not save audio device preference: storage denied',
    );
  });

  test('audioDeviceSelectionFailed preserves selection and clears busy', () {
    const input = _Device('mic_1', 'Mic', 'audioinput');
    final patch = audioDeviceSelectionFailed(
      selectedInput: input,
      selectedOutput: null,
      failure: 'select failed',
    );

    expect(patch.selectedInput, input);
    expect(patch.selectedOutput, isNull);
    expect(patch.busyDeviceId, isNull);
    expect(patch.error, 'select failed');
  });

  test('audio device selection effects describe follow-up test work', () {
    var effects = audioInputDeviceSelectedEffects(
      wasTestingInput: true,
      wasTestingOutput: false,
    );
    expect(effects.restartInputTest, isTrue);
    expect(effects.restartOutputTest, isFalse);
    expect(effects.routeOutputTest, isFalse);

    effects = audioInputDeviceSelectedEffects(
      wasTestingInput: false,
      wasTestingOutput: true,
    );
    expect(effects.restartInputTest, isFalse);
    expect(effects.restartOutputTest, isTrue);
    expect(effects.routeOutputTest, isFalse);

    effects = audioOutputDeviceSelectedEffects(testingOutput: true);
    expect(effects.restartInputTest, isFalse);
    expect(effects.restartOutputTest, isFalse);
    expect(effects.routeOutputTest, isTrue);
  });

  test('audioStoredVolumesApplied normalizes stored volumes', () {
    final patch = audioStoredVolumesApplied(
      inputVolume: 1.2,
      outputVolume: -0.2,
    );

    expect(patch.inputVolume, 1);
    expect(patch.outputVolume, 0);
  });

  test('audio volume changes update only target value', () {
    final inputPatch = audioInputVolumeChanged(
      inputVolume: 0.42,
      outputVolume: 0.8,
    );
    final outputPatch = audioOutputVolumeChanged(
      inputVolume: 0.42,
      outputVolume: 1.4,
    );

    expect(inputPatch.inputVolume, 0.42);
    expect(inputPatch.outputVolume, 0.8);
    expect(outputPatch.inputVolume, 0.42);
    expect(outputPatch.outputVolume, 1);
  });

  test('audio volume effects describe persistence and local test updates', () {
    var effects = audioInputVolumeChangedEffects(
      inputVolume: 1.2,
      hasInputTestTrack: true,
    );
    expect(effects.deviceKind, 'audioinput');
    expect(effects.volume, 1);
    expect(effects.updateInputTestTrack, isTrue);
    expect(effects.updateOutputRenderer, isFalse);

    effects = audioOutputVolumeChangedEffects(
      outputVolume: -0.2,
      hasOutputRenderer: true,
    );
    expect(effects.deviceKind, 'audiooutput');
    expect(effects.volume, 0);
    expect(effects.updateInputTestTrack, isFalse);
    expect(effects.updateOutputRenderer, isTrue);
  });

  test('audioInputTestStarted resets input level and clears error', () {
    final patch = audioInputTestStarted(testingOutput: true, outputLevel: 0.6);

    expect(patch.testingInput, isTrue);
    expect(patch.testingOutput, isTrue);
    expect(patch.inputLevel, 0);
    expect(patch.outputLevel, 0.6);
    expect(patch.error, isNull);
  });

  test('audioInputTestStopped and failed clear input test state', () {
    final stopped = audioInputTestStopped(
      testingOutput: true,
      outputLevel: 0.6,
      error: 'previous warning',
    );
    final failed = audioInputTestFailed(
      testingOutput: false,
      outputLevel: 0.2,
      failure: 'input failed',
    );

    expect(stopped.testingInput, isFalse);
    expect(stopped.testingOutput, isTrue);
    expect(stopped.inputLevel, 0);
    expect(stopped.outputLevel, 0.6);
    expect(stopped.error, 'previous warning');
    expect(failed.testingInput, isFalse);
    expect(failed.testingOutput, isFalse);
    expect(failed.inputLevel, 0);
    expect(failed.outputLevel, 0.2);
    expect(failed.error, 'input failed');
  });

  test('audioOutputTestStarted resets output level and clears error', () {
    final patch = audioOutputTestStarted(testingInput: true, inputLevel: 0.5);

    expect(patch.testingInput, isTrue);
    expect(patch.testingOutput, isTrue);
    expect(patch.inputLevel, 0.5);
    expect(patch.outputLevel, 0);
    expect(patch.error, isNull);
  });

  test('audioOutputTestStopped and failed clear output test state', () {
    final stopped = audioOutputTestStopped(
      testingInput: true,
      inputLevel: 0.7,
      error: 'previous warning',
    );
    final failed = audioOutputTestFailed(
      testingInput: false,
      inputLevel: 0.1,
      failure: 'output failed',
    );

    expect(stopped.testingInput, isTrue);
    expect(stopped.testingOutput, isFalse);
    expect(stopped.inputLevel, 0.7);
    expect(stopped.outputLevel, 0);
    expect(stopped.error, 'previous warning');
    expect(failed.testingInput, isFalse);
    expect(failed.testingOutput, isFalse);
    expect(failed.inputLevel, 0.1);
    expect(failed.outputLevel, 0);
    expect(failed.error, 'output failed');
  });

  test('audio test level changes apply current volume', () {
    final inputPatch = audioInputLevelChanged(
      level: 0.8,
      inputVolume: 0.5,
      testingOutput: true,
      outputLevel: 0.3,
      error: null,
    );
    final outputPatch = audioOutputLevelChanged(
      level: 0.8,
      outputVolume: 1.5,
      testingInput: true,
      inputLevel: 0.4,
      error: 'previous warning',
    );

    expect(inputPatch.testingInput, isTrue);
    expect(inputPatch.testingOutput, isTrue);
    expect(inputPatch.inputLevel, 0.4);
    expect(inputPatch.outputLevel, 0.3);
    expect(inputPatch.error, isNull);
    expect(outputPatch.testingInput, isTrue);
    expect(outputPatch.testingOutput, isTrue);
    expect(outputPatch.inputLevel, 0.4);
    expect(outputPatch.outputLevel, 1);
    expect(outputPatch.error, 'previous warning');
  });
}

class _Device {
  const _Device(this.deviceId, this.label, this.kind);

  final String deviceId;
  final String label;
  final String kind;
}

String _kindOf(_Device device) => device.kind;
String _deviceIdOf(_Device device) => device.deviceId;
