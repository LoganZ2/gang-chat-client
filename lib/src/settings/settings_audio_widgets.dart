part of 'settings_page.dart';

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
  final List<AudioDeviceInfo> devices;
  final AudioDeviceInfo? selectedDevice;
  final String? busyDeviceId;
  final String emptyText;
  final String fallbackLabel;
  final ValueChanged<AudioDeviceInfo> onSelect;

  @override
  Widget build(BuildContext context) {
    final labels = audioDeviceLabels(
      devices,
      fallbackLabel: fallbackLabel,
      labelOf: audioDeviceInfoLabel,
      deviceIdOf: audioDeviceInfoId,
    );
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
                      selected: isSameAudioDevice(
                        selectedDevice,
                        entry.value,
                        kindOf: audioDeviceInfoKind,
                        deviceIdOf: audioDeviceInfoId,
                      ),
                      busy: audioDeviceBusy(
                        entry.value,
                        busyDeviceId,
                        kindOf: audioDeviceInfoKind,
                        deviceIdOf: audioDeviceInfoId,
                      ),
                      onTap: () => onSelect(entry.value),
                    ),
                ],
              ),
      ],
    );
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
              audioVolumePercentText(volume),
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
              child: Button(
                onPressed: disabled ? null : onToggleTest,
                tooltip: testTooltip,
                height: 42,
                width: double.infinity,
                tone: testing ? ButtonTone.primary : ButtonTone.neutral,
                selected: testing,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  testing ? '停止测试' : '测试',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _primaryDark),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentCount = audioLevelSegmentCount(constraints.maxWidth);
              final activeCount = activeAudioLevelSegmentCount(
                level: level,
                active: active,
                segmentCount: segmentCount,
              );
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
                            : const Color(0xFF2A2F38),
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

  final AudioDeviceInfo device;
  final String label;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableSurface(
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
