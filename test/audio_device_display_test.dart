import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/audio_device_display.dart';

void main() {
  test('audioDeviceKey is stable from kind and id', () {
    expect(
      audioDeviceKey(kind: 'audioinput', deviceId: 'mic_1'),
      'audioinput:mic_1',
    );
    expect(
      audioDeviceKeyOf(
        const _Device('mic_1', 'Mic', 'audioinput'),
        kindOf: _kindOf,
        deviceIdOf: _deviceIdOf,
      ),
      'audioinput:mic_1',
    );
  });

  test('audio device selection helpers expose busy state', () {
    const device = _Device('mic_1', 'Mic', 'audioinput');

    expect(canStartAudioDeviceSelection(null), isTrue);
    expect(canStartAudioDeviceSelection('audioinput:mic_1'), isFalse);
    expect(
      audioDeviceBusy(
        device,
        'audioinput:mic_1',
        kindOf: _kindOf,
        deviceIdOf: _deviceIdOf,
      ),
      isTrue,
    );
    expect(
      audioDeviceBusy(
        device,
        'audiooutput:mic_1',
        kindOf: _kindOf,
        deviceIdOf: _deviceIdOf,
      ),
      isFalse,
    );
    expect(
      audioDevicePreferenceSaveFailureMessage('denied'),
      'Could not save audio device preference: denied',
    );
  });

  test('isSameAudioDevice compares kind and device id', () {
    const device = _Device('mic_1', 'Mic', 'audioinput');
    expect(
      isSameAudioDevice(
        device,
        device,
        kindOf: _kindOf,
        deviceIdOf: _deviceIdOf,
      ),
      isTrue,
    );
    expect(
      isSameAudioDevice(
        const _Device('mic_1', 'Speaker', 'audiooutput'),
        device,
        kindOf: _kindOf,
        deviceIdOf: _deviceIdOf,
      ),
      isFalse,
    );
  });

  test('audioDeviceLabels normalizes empty and duplicate labels', () {
    final labels = audioDeviceLabels(
      const [
        _Device('default', '', 'audioinput'),
        _Device('communications', '', 'audioinput'),
        _Device('mic_1', '', 'audioinput'),
        _Device('mic_2', 'Desk Mic', 'audioinput'),
        _Device('mic_3', 'Desk Mic', 'audioinput'),
      ],
      fallbackLabel: '麦克风',
      labelOf: _labelOf,
      deviceIdOf: _deviceIdOf,
    );

    expect(labels, [
      'System default',
      'Communications',
      '麦克风 3',
      'Desk Mic',
      'Desk Mic #2',
    ]);
  });

  test('audioDevicesByKind filters devices by WebRTC kind', () {
    final inputs = audioDevicesByKind(
      const [
        _Device('mic_1', 'Mic', 'audioinput'),
        _Device('speaker_1', 'Speaker', 'audiooutput'),
      ],
      'audioinput',
      kindOf: _kindOf,
    );

    expect(inputs.map((device) => device.deviceId), ['mic_1']);
  });

  test(
    'selectedAudioDeviceFrom picks first matching candidate then fallback',
    () {
      const devices = [
        _Device('mic_1', 'Mic 1', 'audioinput'),
        _Device('mic_2', 'Mic 2', 'audioinput'),
      ];

      expect(
        selectedAudioDeviceFrom(
          devices,
          [
            const _Device('missing', 'Missing', 'audioinput'),
            const _Device('mic_2', 'Mic 2', 'audioinput'),
          ],
          kindOf: _kindOf,
          deviceIdOf: _deviceIdOf,
        )?.deviceId,
        'mic_2',
      );
      expect(
        selectedAudioDeviceFrom<_Device>(
          devices,
          const [],
          kindOf: _kindOf,
          deviceIdOf: _deviceIdOf,
        )?.deviceId,
        'mic_1',
      );
      expect(
        selectedAudioDeviceFrom(
          const <_Device>[],
          devices,
          kindOf: _kindOf,
          deviceIdOf: _deviceIdOf,
        ),
        isNull,
      );
    },
  );

  test('audio test tooltips reflect active state', () {
    expect(audioInputTestTooltip(false), '测试输入音量');
    expect(audioInputTestTooltip(true), '停止输入测试');
    expect(audioOutputTestTooltip(false), '测试输出音量');
    expect(audioOutputTestTooltip(true), '停止输出测试');
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
String _labelOf(_Device device) => device.label;
