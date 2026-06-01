import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

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
    this.onDeviceSelected,
    this.onClose,
  });

  final bool isSubWindow;
  final void Function(String kind, String deviceId)? onDeviceSelected;
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
  bool _requestedDeviceAccess = false;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _deviceSubscription = lk.Hardware.instance.onDeviceChange.stream.listen((
      devices,
    ) {
      _applyDevices(devices);
    });
    unawaited(_loadDevices());
  }

  @override
  void dispose() {
    unawaited(_deviceSubscription?.cancel());
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _ensureDeviceAccess();
      final devices = await lk.Hardware.instance.enumerateDevices();
      _applyDevices(devices);
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

  void _applyDevices(List<lk.MediaDevice> devices) {
    if (!mounted) return;
    final inputs = devices
        .where((device) => device.kind == 'audioinput')
        .toList();
    final outputs = devices
        .where((device) => device.kind == 'audiooutput')
        .toList();
    setState(() {
      _audioInputs = inputs;
      _audioOutputs = outputs;
      _selectedInput = _selectedFrom(
        inputs,
        lk.Hardware.instance.selectedAudioInput,
        _selectedInput,
      );
      _selectedOutput = _selectedFrom(
        outputs,
        lk.Hardware.instance.selectedAudioOutput,
        _selectedOutput,
      );
      _loading = false;
    });
  }

  lk.MediaDevice? _selectedFrom(
    List<lk.MediaDevice> devices,
    lk.MediaDevice? hardwareSelected,
    lk.MediaDevice? currentSelected,
  ) {
    if (devices.isEmpty) return null;
    for (final candidate in [hardwareSelected, currentSelected]) {
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
    await _selectDevice(
      device,
      () => lk.Hardware.instance.selectAudioInput(device),
      () => _selectedInput = device,
    );
  }

  Future<void> _selectOutput(lk.MediaDevice device) async {
    await _selectDevice(
      device,
      () => lk.Hardware.instance.selectAudioOutput(device),
      () => _selectedOutput = device,
    );
  }

  Future<void> _selectDevice(
    lk.MediaDevice device,
    Future<void> Function() select,
    VoidCallback applySelection,
  ) async {
    if (_busyDeviceId != null) return;
    setState(() {
      _busyDeviceId = '${device.kind}:${device.deviceId}';
      _error = null;
    });
    try {
      await select();
      if (!mounted) return;
      setState(applySelection);
      widget.onDeviceSelected?.call(device.kind, device.deviceId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyDeviceId = null);
    }
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
