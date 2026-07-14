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
        _FakeAudioDeviceStore(),
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

  test(
    'restoreStoredAudioDevices falls back to system default output',
    () async {
      const speakerOne = AudioDeviceInfo(
        deviceId: 'speaker_1',
        label: 'Speaker 1',
        kind: 'audiooutput',
        groupId: 'group_speaker_1',
      );
      const speakerTwo = AudioDeviceInfo(
        deviceId: 'speaker_2',
        label: 'Speaker 2',
        kind: 'audiooutput',
        groupId: 'group_speaker_2',
      );
      final service = _FakeLiveAudioDeviceService(
        devices: const [speakerOne, speakerTwo],
        selectedOutput: speakerOne,
      );

      final restored = await restoreStoredAudioDevices(
        _FakeAudioDeviceStore(outputDeviceId: 'missing_output'),
        audioDevices: service,
        systemDefaultOutputId: 'speaker_2',
      );

      expect(restored.output, speakerTwo);
      expect(service.outputSelects, 1);
      expect(service.selectedOutput, speakerTwo);
    },
  );

  test(
    'restoreStoredAudioDevices restores output by signature after hotplug',
    () async {
      const speaker = AudioDeviceInfo(
        deviceId: 'speaker_2',
        label: 'Desk Speaker',
        kind: 'audiooutput',
        groupId: 'group_speaker',
      );
      const repluggedHeadset = AudioDeviceInfo(
        deviceId: 'headset_new',
        label: 'USB Headset',
        kind: 'audiooutput',
        groupId: 'group_headset',
      );
      final service = _FakeLiveAudioDeviceService(
        devices: const [speaker, repluggedHeadset],
        selectedOutput: speaker,
      );

      final store = _FakeAudioDeviceStore(
        outputDeviceId: 'headset_old',
        outputDeviceLabel: 'USB Headset',
        outputDeviceGroupId: 'group_headset',
      );

      final restored = await restoreStoredAudioDevices(
        store,
        audioDevices: service,
        systemDefaultOutputId: 'speaker_2',
      );

      expect(restored.output, repluggedHeadset);
      expect(service.outputSelects, 1);
      expect(service.selectedOutput, repluggedHeadset);
      expect(store.writtenOutputDeviceId, 'headset_new');
      expect(store.writtenOutputDeviceLabel, 'USB Headset');
      expect(store.writtenOutputDeviceGroupId, 'group_headset');
    },
  );
}

class _FakeAudioDeviceStore extends AudioDeviceStore {
  _FakeAudioDeviceStore({
    this.outputDeviceId = 'speaker_1',
    this.outputDeviceLabel,
    this.outputDeviceGroupId,
  });

  final String? outputDeviceId;
  final String? outputDeviceLabel;
  final String? outputDeviceGroupId;
  String? writtenOutputDeviceId;
  String? writtenOutputDeviceLabel;
  String? writtenOutputDeviceGroupId;

  @override
  Future<StoredAudioDevices> read() async {
    return StoredAudioDevices(
      inputDeviceId: 'missing_input',
      outputDeviceId: outputDeviceId,
      outputDeviceLabel: outputDeviceLabel,
      outputDeviceGroupId: outputDeviceGroupId,
    );
  }

  @override
  Future<void> writeOutputDevicePreference({
    required String deviceId,
    String? label,
    String? groupId,
  }) async {
    writtenOutputDeviceId = deviceId;
    writtenOutputDeviceLabel = label;
    writtenOutputDeviceGroupId = groupId;
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
