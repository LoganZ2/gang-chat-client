import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'audio_device_store.dart';
import '../ui/key_button.dart';
import '../ui/title_bar.dart';

const _primaryDark = Color(0xFF14171D);
const _primaryDarkLow = Color(0xFF181C24);
const _borderColor = Color(0xFF2A2F38);
const _cyan = Color(0xFF6FCFA6);
const _textPrimary = Color(0xFFECEFF1);
const _textSecondary = Color(0xFFB0B8C0);
const _textMuted = Color(0xFF6F7785);
const _danger = Color(0xFFE58383);

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.isSubWindow = false,
    this.audioDeviceStore = const AudioDeviceStore(),
    this.onDeviceSelected,
    this.onVolumeChanged,
    this.onClose,
  });

  final bool isSubWindow;
  final AudioDeviceStore audioDeviceStore;
  final void Function(String kind, String deviceId)? onDeviceSelected;
  final void Function(String kind, double volume)? onVolumeChanged;
  final VoidCallback? onClose;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  StreamSubscription<List<lk.MediaDevice>>? _deviceSubscription;
  List<lk.MediaDevice> _audioInputs = const [];
  List<lk.MediaDevice> _audioOutputs = const [];
  lk.MediaDevice? _selectedInput;
  lk.MediaDevice? _selectedOutput;
  String? _busyDeviceId;
  double _inputVolume = 1.0;
  double _outputVolume = 1.0;
  double _inputLevel = 0.0;
  double _outputLevel = 0.0;
  bool _testingInput = false;
  bool _testingOutput = false;
  bool _requestedDeviceAccess = false;
  String? _error;
  bool _loading = true;
  lk.LocalAudioTrack? _inputTestTrack;
  lk.AudioVisualizer? _inputVisualizer;
  lk.EventsListener<lk.AudioVisualizerEvent>? _inputVisualizerListener;
  lk.LocalAudioTrack? _outputTestTrack;
  lk.AudioVisualizer? _outputVisualizer;
  lk.EventsListener<lk.AudioVisualizerEvent>? _outputVisualizerListener;
  rtc.RTCVideoRenderer? _outputRenderer;

  @override
  void initState() {
    super.initState();
    _deviceSubscription = lk.Hardware.instance.onDeviceChange.stream.listen((
      devices,
    ) {
      unawaited(_applyDevices(devices));
    });
    unawaited(_loadStoredAudioSettings());
    unawaited(_loadDevices());
  }

  @override
  void dispose() {
    unawaited(_stopInputTest(updateState: false));
    unawaited(_stopOutputTest(updateState: false));
    unawaited(_deviceSubscription?.cancel());
    super.dispose();
  }

  Future<void> _loadStoredAudioSettings() async {
    try {
      final stored = await widget.audioDeviceStore.read();
      if (!mounted) return;
      setState(() {
        _inputVolume = stored.inputVolume;
        _outputVolume = stored.outputVolume;
      });
      widget.onVolumeChanged?.call('audioinput', stored.inputVolume);
      widget.onVolumeChanged?.call('audiooutput', stored.outputVolume);
    } catch (_) {}
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _ensureDeviceAccess();
      final devices = await lk.Hardware.instance.enumerateDevices();
      await _applyDevices(devices);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _ensureDeviceAccess() async {
    if (_requestedDeviceAccess) return;
    _requestedDeviceAccess = true;
    try {
      final track = await lk.LocalAudioTrack.create();
      await track.start();
      await track.stop();
    } catch (_) {
      // Device enumeration below will surface the usable state. This call is
      // only here to trigger OS media permission before enumerateDevices().
    }
  }

  Future<void> _applyDevices(List<lk.MediaDevice> devices) async {
    if (!mounted) return;
    final inputs = devices
        .where((device) => device.kind == 'audioinput')
        .toList();
    final outputs = devices
        .where((device) => device.kind == 'audiooutput')
        .toList();
    RestoredAudioDevices restored = const RestoredAudioDevices();
    try {
      restored = await restoreStoredAudioDevices(
        widget.audioDeviceStore,
        devices: devices,
      );
    } catch (_) {
      // Device choices are a local convenience. If storage or OS routing fails,
      // keep rendering the current device list and let the user re-select.
    }
    if (!mounted) return;
    setState(() {
      _audioInputs = inputs;
      _audioOutputs = outputs;
      _selectedInput = _selectedFrom(inputs, [
        restored.input,
        lk.Hardware.instance.selectedAudioInput,
        _selectedInput,
      ]);
      _selectedOutput = _selectedFrom(outputs, [
        restored.output,
        lk.Hardware.instance.selectedAudioOutput,
        _selectedOutput,
      ]);
      _loading = false;
    });
  }

  lk.MediaDevice? _selectedFrom(
    List<lk.MediaDevice> devices,
    Iterable<lk.MediaDevice?> candidates,
  ) {
    if (devices.isEmpty) return null;
    for (final candidate in candidates) {
      if (candidate == null) continue;
      for (final device in devices) {
        if (device.deviceId == candidate.deviceId &&
            device.kind == candidate.kind) {
          return device;
        }
      }
    }
    return devices.first;
  }

  Future<void> _selectInput(lk.MediaDevice device) async {
    final wasTestingInput = _testingInput;
    final wasTestingOutput = _testingOutput;
    final didSelect = await _selectDevice(
      device,
      () => lk.Hardware.instance.selectAudioInput(device),
      () => widget.audioDeviceStore.writeInputDeviceId(device.deviceId),
      () => _selectedInput = device,
    );
    if (!didSelect) return;
    if (wasTestingInput) await _restartInputTest();
    if (wasTestingOutput) await _restartOutputTest();
  }

  Future<void> _selectOutput(lk.MediaDevice device) async {
    final didSelect = await _selectDevice(
      device,
      () => lk.Hardware.instance.selectAudioOutput(device),
      () => widget.audioDeviceStore.writeOutputDeviceId(device.deviceId),
      () => _selectedOutput = device,
    );
    if (didSelect && _testingOutput) await _routeOutputTest();
  }

  Future<bool> _selectDevice(
    lk.MediaDevice device,
    Future<void> Function() select,
    Future<void> Function() rememberSelection,
    VoidCallback applySelection,
  ) async {
    if (_busyDeviceId != null) return false;
    setState(() {
      _busyDeviceId = '${device.kind}:${device.deviceId}';
      _error = null;
    });
    var didSelect = false;
    try {
      await select();
      Object? storageError;
      try {
        await rememberSelection();
      } catch (e) {
        storageError = e;
      }
      if (!mounted) return false;
      setState(() {
        applySelection();
        if (storageError != null) {
          _error = 'Could not save audio device preference: $storageError';
        }
      });
      widget.onDeviceSelected?.call(device.kind, device.deviceId);
      didSelect = true;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyDeviceId = null);
    }
    return didSelect;
  }

  Future<void> _setInputVolume(double volume) async {
    final next = _normalizedVolume(volume);
    setState(() => _inputVolume = next);
    widget.onVolumeChanged?.call('audioinput', next);
    unawaited(widget.audioDeviceStore.writeInputVolume(next));
    final track = _inputTestTrack;
    if (track != null) {
      try {
        await rtc.Helper.setVolume(next, track.mediaStreamTrack);
      } catch (_) {}
    }
  }

  Future<void> _setOutputVolume(double volume) async {
    final next = _normalizedVolume(volume);
    setState(() => _outputVolume = next);
    widget.onVolumeChanged?.call('audiooutput', next);
    unawaited(widget.audioDeviceStore.writeOutputVolume(next));
    final renderer = _outputRenderer;
    if (renderer != null) {
      try {
        await renderer.setVolume(next);
      } catch (_) {}
    }
  }

  Future<void> _toggleInputTest() async {
    if (_testingInput) {
      await _stopInputTest();
    } else {
      await _startInputTest();
    }
  }

  Future<void> _toggleOutputTest() async {
    if (_testingOutput) {
      await _stopOutputTest();
    } else {
      await _startOutputTest();
    }
  }

  Future<void> _restartInputTest() async {
    await _stopInputTest();
    if (mounted) await _startInputTest();
  }

  Future<void> _restartOutputTest() async {
    await _stopOutputTest();
    if (mounted) await _startOutputTest();
  }

  Future<void> _startInputTest() async {
    if (_testingInput) return;
    setState(() {
      _testingInput = true;
      _inputLevel = 0;
      _error = null;
    });
    lk.LocalAudioTrack? track;
    try {
      track = await _createTestAudioTrack();
      await rtc.Helper.setVolume(_inputVolume, track.mediaStreamTrack);
      final visualizer = await _startVisualizer(
        track,
        (level) => _inputLevel = level * _inputVolume,
      );
      if (!mounted) {
        await _disposeTestTrack(track);
        return;
      }
      _inputTestTrack = track;
      _inputVisualizer = visualizer.visualizer;
      _inputVisualizerListener = visualizer.listener;
    } catch (e) {
      await _disposeTestTrack(track);
      if (!mounted) return;
      setState(() {
        _testingInput = false;
        _inputLevel = 0;
        _error = e.toString();
      });
    }
  }

  Future<void> _stopInputTest({bool updateState = true}) async {
    final track = _inputTestTrack;
    final visualizer = _inputVisualizer;
    final listener = _inputVisualizerListener;
    _inputTestTrack = null;
    _inputVisualizer = null;
    _inputVisualizerListener = null;
    await _stopVisualizer(visualizer, listener);
    await _disposeTestTrack(track);
    if (updateState && mounted) {
      setState(() {
        _testingInput = false;
        _inputLevel = 0;
      });
    }
  }

  Future<void> _startOutputTest() async {
    if (_testingOutput) return;
    setState(() {
      _testingOutput = true;
      _outputLevel = 0;
      _error = null;
    });
    lk.LocalAudioTrack? track;
    rtc.RTCVideoRenderer? renderer;
    try {
      track = await _createTestAudioTrack();
      renderer = rtc.RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = track.mediaStream;
      await renderer.setVolume(_outputVolume);
      _outputRenderer = renderer;
      await _routeOutputTest();
      final visualizer = await _startVisualizer(
        track,
        (level) => _outputLevel = level * _outputVolume,
      );
      if (!mounted) {
        await _disposeRenderer(renderer);
        await _disposeTestTrack(track);
        return;
      }
      _outputTestTrack = track;
      _outputVisualizer = visualizer.visualizer;
      _outputVisualizerListener = visualizer.listener;
    } catch (e) {
      if (_outputRenderer == renderer) _outputRenderer = null;
      await _disposeRenderer(renderer);
      await _disposeTestTrack(track);
      if (!mounted) return;
      setState(() {
        _testingOutput = false;
        _outputLevel = 0;
        _error = e.toString();
      });
    }
  }

  Future<void> _stopOutputTest({bool updateState = true}) async {
    final track = _outputTestTrack;
    final visualizer = _outputVisualizer;
    final listener = _outputVisualizerListener;
    final renderer = _outputRenderer;
    _outputTestTrack = null;
    _outputVisualizer = null;
    _outputVisualizerListener = null;
    _outputRenderer = null;
    await _stopVisualizer(visualizer, listener);
    await _disposeRenderer(renderer);
    await _disposeTestTrack(track);
    if (updateState && mounted) {
      setState(() {
        _testingOutput = false;
        _outputLevel = 0;
      });
    }
  }

  Future<lk.LocalAudioTrack> _createTestAudioTrack() async {
    await _ensureDeviceAccess();
    final track = await lk.LocalAudioTrack.create(
      lk.AudioCaptureOptions(deviceId: _selectedInput?.deviceId),
    );
    await track.start();
    return track;
  }

  Future<void> _routeOutputTest() async {
    final renderer = _outputRenderer;
    final device = _selectedOutput;
    if (renderer == null || device == null) return;
    try {
      await renderer.audioOutput(device.deviceId);
    } catch (_) {}
  }

  Future<_StartedVisualizer> _startVisualizer(
    lk.LocalAudioTrack track,
    void Function(double level) applyLevel,
  ) async {
    final visualizer = lk.createVisualizer(
      track,
      options: const lk.AudioVisualizerOptions(
        barCount: 14,
        centeredBands: false,
      ),
    );
    final listener = visualizer.createListener();
    listener.on<lk.AudioVisualizerEvent>((event) {
      if (!mounted) return;
      setState(() => applyLevel(_levelFromVisualizerEvent(event)));
    });
    try {
      await visualizer.start();
    } catch (_) {
      await _stopVisualizer(visualizer, listener);
      rethrow;
    }
    return _StartedVisualizer(visualizer, listener);
  }

  Future<void> _stopVisualizer(
    lk.AudioVisualizer? visualizer,
    lk.EventsListener<lk.AudioVisualizerEvent>? listener,
  ) async {
    try {
      await visualizer?.stop();
    } catch (_) {}
    try {
      await visualizer?.dispose();
    } catch (_) {}
    try {
      await listener?.dispose();
    } catch (_) {}
  }

  Future<void> _disposeTestTrack(lk.LocalAudioTrack? track) async {
    if (track == null) return;
    try {
      await track.stop();
    } catch (_) {}
    try {
      await track.dispose();
    } catch (_) {}
  }

  Future<void> _disposeRenderer(rtc.RTCVideoRenderer? renderer) async {
    if (renderer == null) return;
    try {
      renderer.srcObject = null;
    } catch (_) {}
    try {
      await renderer.dispose();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _primaryDarkLow,
      body: Column(
        children: [
          Container(
            // Drop the header below the window-controls strip so the title and
            // refresh button clear the drag band and window buttons.
            height: 48 + titleBarHeight,
            padding: const EdgeInsets.fromLTRB(22, titleBarHeight, 22, 0),
            color: _primaryDarkLow,
            child: Row(
              children: [
                if (!widget.isSubWindow) ...[
                  KeyIconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    size: 38,
                  ),
                  const SizedBox(width: 14),
                ],
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 14),
                    child: Text(
                      'Settings',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: KeySurface(
                    onPressed: _loading ? null : _loadDevices,
                    tooltip: 'Refresh devices',
                    enabled: !_loading,
                    height: 34,
                    padding: EdgeInsets.zero,
                    backgroundColor: _primaryDarkLow,
                    selectedBackgroundColor: _primaryDarkLow,
                    pressedBackgroundColor: _primaryDark,
                    borderColor: _primaryDarkLow,
                    selectedBorderColor: _primaryDarkLow,
                    hoverLift: 3,
                    pressDepth: 3,
                    baseDepth: 5,
                    child: IconTheme.merge(
                      data: const IconThemeData(
                        color: _textSecondary,
                        size: 16,
                      ),
                      child: const Center(child: Icon(Icons.refresh)),
                    ),
                  ),
                ),
                if (widget.onClose != null) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 34,
                    child: KeySurface(
                      onPressed: widget.onClose,
                      tooltip: 'Close settings',
                      height: 34,
                      padding: EdgeInsets.zero,
                      backgroundColor: _primaryDarkLow,
                      selectedBackgroundColor: _primaryDarkLow,
                      pressedBackgroundColor: _primaryDark,
                      borderColor: _primaryDarkLow,
                      selectedBorderColor: _primaryDarkLow,
                      hoverLift: 3,
                      pressDepth: 3,
                      baseDepth: 5,
                      child: IconTheme.merge(
                        data: const IconThemeData(
                          color: _textSecondary,
                          size: 16,
                        ),
                        child: const Center(child: Icon(Icons.close)),
                      ),
                    ),
                  ),
                ],
                // Pull the refresh button further inward from the edge.
                const SizedBox(width: 16),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 32),
              children: [
                _DeviceSection(
                  title: 'Input source',
                  icon: Icons.mic,
                  devices: _audioInputs,
                  selectedDevice: _selectedInput,
                  busyDeviceId: _busyDeviceId,
                  emptyText: _loading
                      ? 'Loading input sources'
                      : 'No input sources found',
                  fallbackLabel: 'Microphone',
                  onSelect: _selectInput,
                ),
                const SizedBox(height: 16),
                _AudioControlPanel(
                  title: 'Input volume',
                  icon: Icons.graphic_eq,
                  volume: _inputVolume,
                  level: _inputLevel,
                  testing: _testingInput,
                  testTooltip: _testingInput
                      ? 'Stop input test'
                      : 'Test input volume',
                  disabled: _audioInputs.isEmpty,
                  onVolumeChanged: (value) => unawaited(_setInputVolume(value)),
                  onToggleTest: _toggleInputTest,
                ),
                const SizedBox(height: 30),
                _DeviceSection(
                  title: 'Output source',
                  icon: Icons.headphones,
                  devices: _audioOutputs,
                  selectedDevice: _selectedOutput,
                  busyDeviceId: _busyDeviceId,
                  emptyText: _loading
                      ? 'Loading output sources'
                      : 'No output sources found',
                  fallbackLabel: 'Output',
                  onSelect: _selectOutput,
                ),
                const SizedBox(height: 16),
                _AudioControlPanel(
                  title: 'Output volume',
                  icon: Icons.volume_up,
                  volume: _outputVolume,
                  level: _outputLevel,
                  testing: _testingOutput,
                  testTooltip: _testingOutput
                      ? 'Stop output test'
                      : 'Test output volume',
                  disabled: _audioOutputs.isEmpty,
                  onVolumeChanged: (value) =>
                      unawaited(_setOutputVolume(value)),
                  onToggleTest: _toggleOutputTest,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 28),
                  _SettingsError(message: _error!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StartedVisualizer {
  const _StartedVisualizer(this.visualizer, this.listener);

  final lk.AudioVisualizer visualizer;
  final lk.EventsListener<lk.AudioVisualizerEvent> listener;
}

double _levelFromVisualizerEvent(lk.AudioVisualizerEvent event) {
  var peak = 0.0;
  for (final value in event.event) {
    if (value is! num) continue;
    final sample = value.toDouble();
    if (sample > peak) peak = sample;
  }
  return peak.clamp(0.0, 1.0).toDouble();
}

double _normalizedVolume(double volume) {
  return volume.clamp(0.0, 1.0).toDouble();
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({
    required this.title,
    required this.icon,
    required this.devices,
    required this.selectedDevice,
    required this.busyDeviceId,
    required this.emptyText,
    required this.fallbackLabel,
    required this.onSelect,
  });

  final String title;
  final IconData icon;
  final List<lk.MediaDevice> devices;
  final lk.MediaDevice? selectedDevice;
  final String? busyDeviceId;
  final String emptyText;
  final String fallbackLabel;
  final ValueChanged<lk.MediaDevice> onSelect;

  @override
  Widget build(BuildContext context) {
    final labels = _deviceLabels();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _cyan, size: 18),
            const SizedBox(width: 9),
            Text(
              title,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        devices.isEmpty
            ? _EmptyDeviceRow(text: emptyText)
            : Column(
                children: [
                  for (final entry in devices.asMap().entries)
                    _DeviceRow(
                      device: entry.value,
                      label: labels[entry.key],
                      selected:
                          selectedDevice?.deviceId == entry.value.deviceId &&
                          selectedDevice?.kind == entry.value.kind,
                      busy:
                          busyDeviceId ==
                          '${entry.value.kind}:${entry.value.deviceId}',
                      onTap: () => onSelect(entry.value),
                    ),
                ],
              ),
      ],
    );
  }

  List<String> _deviceLabels() {
    final baseLabels = [
      for (final entry in devices.asMap().entries)
        _deviceLabel(entry.value, entry.key, fallbackLabel),
    ];
    final totals = <String, int>{};
    for (final label in baseLabels) {
      totals[label] = (totals[label] ?? 0) + 1;
    }
    final seen = <String, int>{};
    return [
      for (final label in baseLabels)
        if (totals[label] == 1)
          label
        else
          _labelWithDuplicateSuffix(label, seen),
    ];
  }

  String _labelWithDuplicateSuffix(String label, Map<String, int> seen) {
    final count = (seen[label] ?? 0) + 1;
    seen[label] = count;
    if (count == 1) return label;
    return '$label #$count';
  }

  String _deviceLabel(lk.MediaDevice device, int index, String fallbackLabel) {
    final label = device.label.trim();
    if (label.isNotEmpty) return label;
    if (device.deviceId == 'default') return 'System default';
    if (device.deviceId == 'communications') return 'Communications';
    return '$fallbackLabel ${index + 1}';
  }
}

class _AudioControlPanel extends StatelessWidget {
  const _AudioControlPanel({
    required this.title,
    required this.icon,
    required this.volume,
    required this.level,
    required this.testing,
    required this.testTooltip,
    required this.disabled,
    required this.onVolumeChanged,
    required this.onToggleTest,
  });

  final String title;
  final IconData icon;
  final double volume;
  final double level;
  final bool testing;
  final String testTooltip;
  final bool disabled;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleTest;

  @override
  Widget build(BuildContext context) {
    final percent = (volume * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _cyan, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _cyan,
                  inactiveTrackColor: _borderColor,
                  thumbColor: _textPrimary,
                  overlayColor: _cyan.withValues(alpha: 0.14),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: volume,
                  min: 0,
                  max: 1,
                  onChanged: disabled ? null : onVolumeChanged,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 96,
              child: KeySurface(
                onPressed: disabled ? null : onToggleTest,
                tooltip: testTooltip,
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                backgroundColor: const Color(0xFF5B6397),
                selectedBackgroundColor: const Color(0xFF5B6397),
                pressedBackgroundColor: const Color(0xFF454C7A),
                disabledBackgroundColor: const Color(0xFF303542),
                borderColor: const Color(0xFF5B6397),
                selectedBorderColor: const Color(0xFF5B6397),
                disabledBorderColor: _borderColor,
                borderRadius: 2,
                hoverLift: 0,
                pressDepth: 0,
                baseDepth: 0,
                child: Center(
                  child: Text(
                    testing ? '停止测试' : '测试',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: disabled ? _textMuted : _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LevelMeter(level: level, active: testing),
            ),
          ],
        ),
      ],
    );
  }
}

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level, required this.active});

  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final normalized = level.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _primaryDark),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentCount = (constraints.maxWidth / 12).floor().clamp(
                24,
                56,
              );
              final activeCount = active
                  ? (normalized * segmentCount).ceil().clamp(0, segmentCount)
                  : 0;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < segmentCount; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      width: 5,
                      height: 22,
                      decoration: BoxDecoration(
                        color: i < activeCount
                            ? _cyan
                            : const Color(0xFFE8EBEE),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.label,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final lk.MediaDevice device;
  final String label;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KeySurface(
      onPressed: busy ? null : onTap,
      height: 50,
      width: double.infinity,
      selected: selected,
      backgroundColor: _primaryDarkLow,
      selectedBackgroundColor: _primaryDarkLow,
      pressedBackgroundColor: _primaryDark,
      borderColor: _borderColor,
      selectedBorderColor: selected ? _cyan : _borderColor,
      hoverLift: 3,
      pressDepth: 3,
      baseDepth: 5,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? _textPrimary : _textSecondary,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (busy)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
            )
          else if (selected)
            const Icon(Icons.check, color: _cyan, size: 18)
          else
            Icon(
              device.kind == 'audioinput' ? Icons.mic_none : Icons.volume_up,
              color: _textMuted,
              size: 18,
            ),
        ],
      ),
    );
  }
}

class _EmptyDeviceRow extends StatelessWidget {
  const _EmptyDeviceRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            text,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsError extends StatelessWidget {
  const _SettingsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF2E1F22),
        border: Border.fromBorderSide(BorderSide(color: Color(0xFF3A2A2E))),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber, color: _danger, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: _danger, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
