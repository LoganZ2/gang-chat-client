import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/audio_device_info.dart';
import 'package:client/src/app/audio_device_store.dart';
import 'package:client/src/live/audio_device_restorer.dart';
import 'package:client/src/live/audio_device_service.dart';

void main() {
  test(
    'restoreStoredAudioDevices uses injected audio device service',
    () async {
      const defaultInput = AudioDeviceInfo(
        deviceId: 'default',
        label: 'System Default',
        kind: 'audioinput',
        groupId: 'group_default',
      );
      const speaker = AudioDeviceInfo(
        deviceId: 'speaker_1',
        label: 'Speaker',
        kind: 'audiooutput',
        groupId: 'group_speaker',
      );
      final service = _FakeLiveAudioDeviceService(
        devices: const [defaultInput, speaker],
        selectedInput: defaultInput,
      );

      final restored = await restoreStoredAudioDevices(
        const _FakeAudioDeviceStore(),
        audioDevices: service,
      );

      expect(restored.input, defaultInput);
      expect(restored.output, speaker);
      expect(service.enumerateCalls, 1);
      expect(service.inputSelects, 0);
      expect(service.outputSelects, 1);
      expect(service.selectedOutput, speaker);
    },
  );
}

class _FakeAudioDeviceStore extends AudioDeviceStore {
  const _FakeAudioDeviceStore();

  @override
  Future<StoredAudioDevices> read() async {
    return const StoredAudioDevices(
      inputDeviceId: 'missing_input',
      outputDeviceId: 'speaker_1',
    );
  }
}

class _FakeLiveAudioDeviceService extends LiveAudioDeviceService {
  _FakeLiveAudioDeviceService({
    required this.devices,
    AudioDeviceInfo? selectedInput,
    AudioDeviceInfo? selectedOutput,
  }) : _selectedInput = selectedInput,
       _selectedOutput = selectedOutput;

  final List<AudioDeviceInfo> devices;
  AudioDeviceInfo? _selectedInput;
  AudioDeviceInfo? _selectedOutput;
  int enumerateCalls = 0;
  int inputSelects = 0;
  int outputSelects = 0;

  @override
  Future<List<AudioDeviceInfo>> enumerateDevices() async {
    enumerateCalls += 1;
    return devices;
  }

  @override
  AudioDeviceInfo? get selectedAudioInput => _selectedInput;

  @override
  AudioDeviceInfo? get selectedAudioOutput => _selectedOutput;

  AudioDeviceInfo? get selectedOutput => _selectedOutput;

  @override
  Future<void> selectAudioInput(AudioDeviceInfo device) async {
    inputSelects += 1;
    _selectedInput = device;
  }

  @override
  Future<void> selectAudioOutput(AudioDeviceInfo device) async {
    outputSelects += 1;
    _selectedOutput = device;
  }
}
