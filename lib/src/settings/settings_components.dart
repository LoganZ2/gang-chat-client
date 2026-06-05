part of 'settings_page.dart';

class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation({required this.selected, required this.onChanged});

  final SettingsSection selected;
  final ValueChanged<SettingsSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 188,
      child: ColoredBox(
        color: _primaryDarkLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NavItem(
                title: '用户资料',
                icon: Icons.badge_outlined,
                selected: selected == SettingsSection.profile,
                onPressed: () => onChanged(SettingsSection.profile),
              ),
              const SizedBox(height: 8),
              _NavItem(
                title: '隐私和安全',
                icon: Icons.shield_outlined,
                selected: selected == SettingsSection.security,
                onPressed: () => onChanged(SettingsSection.security),
              ),
              const SizedBox(height: 8),
              _NavItem(
                title: '默认语音源',
                icon: Icons.graphic_eq,
                selected: selected == SettingsSection.voice,
                onPressed: () => onChanged(SettingsSection.voice),
              ),
              const SizedBox(height: 8),
              _NavItem(
                title: '我的表情包',
                icon: Icons.emoji_emotions_outlined,
                selected: selected == SettingsSection.stickers,
                onPressed: () => onChanged(SettingsSection.stickers),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableSurface(
      onPressed: onPressed,
      selected: selected,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      backgroundColor: _primaryDarkLow,
      selectedBackgroundColor: const Color(0xFF1F2D27),
      pressedBackgroundColor: _primaryDark,
      borderColor: selected ? _cyan : _borderColor,
      selectedBorderColor: _cyan,
      hoverLift: 2,
      pressDepth: 2,
      baseDepth: 4,
      child: Row(
        children: [
          Icon(icon, color: selected ? _cyan : _textMuted, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? _textPrimary : _textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentTitle extends StatelessWidget {
  const _ContentTitle({required this.title, required this.loading});

  final String title;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (loading)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
          ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.children,
    this.trailing,
    this.danger = false,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _primaryDarkLow,
        border: Border.all(
          color: danger ? const Color(0xFF3A2A2E) : _borderColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: danger ? _danger : _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsSubPanel extends StatelessWidget {
  const _SettingsSubPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _primaryDark,
        border: Border.all(color: _borderColor),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.controller,
    this.enabled = true,
    this.maxLines = 1,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.helperText,
    this.onTogglePasswordVisibility,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final int maxLines;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? helperText;
  final VoidCallback? onTogglePasswordVisibility;

  @override
  Widget build(BuildContext context) {
    final effectiveSuffixIcon = onTogglePasswordVisibility == null
        ? suffixIcon
        : _PasswordVisibilityToggle(
            obscure: obscureText,
            enabled: enabled,
            onPressed: onTogglePasswordVisibility!,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: obscureText ? 1 : maxLines,
          obscureText: obscureText,
          keyboardType: keyboardType,
          cursorColor: _textSecondary,
          style: TextStyle(
            color: enabled ? _textPrimary : _textMuted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            isDense: true,
            suffixIcon: effectiveSuffixIcon,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 38,
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText!,
            style: const TextStyle(color: _textMuted, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _CopyableField extends StatelessWidget {
  const _CopyableField({
    required this.label,
    required this.value,
    required this.tooltip,
    required this.onCopy,
  });

  final String label;
  final String value;
  final String tooltip;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _primaryDark,
            border: Border.all(color: _borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 7, 8, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ButtonIcon(
                  tooltip: tooltip,
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy),
                  size: 30,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyLine extends StatelessWidget {
  const _ReadOnlyLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 110, child: _FieldLabel(label)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleSetting extends StatelessWidget {
  const _ToggleSetting({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _FieldLabel(label)),
        Switch(
          value: value,
          activeThumbColor: _cyan,
          activeTrackColor: _cyan.withValues(alpha: 0.26),
          inactiveThumbColor: _textMuted,
          inactiveTrackColor: _borderColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SegmentOption {
  const _SegmentOption({required this.value, required this.label});

  final String value;
  final String label;
}

class _SegmentedSetting extends StatelessWidget {
  const _SegmentedSetting({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<_SegmentOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final option in options) ...[
              Expanded(
                child: PressableSurface(
                  onPressed: () => onChanged(option.value),
                  selected: value == option.value,
                  height: 36,
                  backgroundColor: _primaryDark,
                  selectedBackgroundColor: const Color(0xFF1F2D27),
                  pressedBackgroundColor: _primaryDarkLow,
                  borderColor: _borderColor,
                  selectedBorderColor: _cyan,
                  hoverLift: 2,
                  pressDepth: 2,
                  baseDepth: 4,
                  child: Center(
                    child: Text(
                      option.label,
                      style: TextStyle(
                        color: value == option.value ? _cyan : _textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              if (option != options.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _AvatarKeyPicker extends StatelessWidget {
  const _AvatarKeyPicker({
    required this.value,
    required this.displayName,
    required this.avatarUrl,
    required this.uploading,
    required this.onChanged,
    required this.onUpload,
    required this.onUsePreset,
  });

  static const _keys = [
    'blue-3',
    'sky-2',
    'cyan-2',
    'mint-2',
    'green-2',
    'lime-2',
    'amber-2',
    'orange-2',
    'coral-2',
    'pink-2',
    'violet-2',
    'indigo-2',
    'rose-2',
    'teal-2',
    'olive-2',
    'slate-2',
    'steel-2',
    'graphite-2',
  ];

  final String value;
  final String displayName;
  final String? avatarUrl;
  final bool uploading;
  final ValueChanged<String> onChanged;
  final VoidCallback onUpload;
  final VoidCallback onUsePreset;

  @override
  Widget build(BuildContext context) {
    final uploadedSelected = avatarUrl != null;
    final presetSelected = !uploadedSelected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel('头像'),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Center(
                child: _AvatarPreview(
                  label: displayName,
                  imageUrl: avatarUrl,
                  defaultAvatarKey: value,
                  size: 88,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final key in _keys)
                    Tooltip(
                      message: key,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(key),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: avatarFallbackColor(key),
                            border: Border.all(
                              color: presetSelected && value == key
                                  ? _cyan
                                  : _borderColor,
                              width: presetSelected && value == key ? 2 : 1,
                            ),
                          ),
                          child: const SizedBox.square(dimension: 30),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Button(
                onPressed: uploading ? null : onUpload,
                loading: uploading,
                icon: const Icon(Icons.upload_file),
                tone: uploadedSelected
                    ? ButtonTone.primary
                    : ButtonTone.neutral,
                selected: uploadedSelected,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                width: double.infinity,
                child: const Text('上传头像'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Button(
                onPressed: uploading ? null : onUsePreset,
                icon: const Icon(Icons.restart_alt),
                tone: presetSelected ? ButtonTone.primary : ButtonTone.neutral,
                selected: presetSelected,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                width: double.infinity,
                child: const Text('预设头像'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.label,
    required this.imageUrl,
    required this.defaultAvatarKey,
    required this.size,
  });

  final String label;
  final String? imageUrl;
  final String defaultAvatarKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: avatarFallbackColor(defaultAvatarKey),
      child: Center(
        child: Text(
          account_display.initials(label),
          style: TextStyle(
            color: _textPrimary,
            fontSize: (size * 0.36).clamp(12, 28).toDouble(),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
    final imageUrl = this.imageUrl;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: _borderColor)),
        child: ClipRect(
          child: imageUrl == null
              ? fallback
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.sessions, required this.loading});

  final List<UserSession> sessions;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bodyState = account_display.sessionListBodyState(
      loading: loading,
      sessions: sessions,
    );
    return switch (bodyState) {
      account_display.SessionListBodyState.loading => const SizedBox(
        height: 82,
        child: Center(child: CircularProgressIndicator(color: _cyan)),
      ),
      account_display.SessionListBodyState.empty => const _SettingsEmptyState(
        text: '暂无近期账号活动',
      ),
      account_display.SessionListBodyState.results => Column(
        children: [
          for (final session in sessions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _primaryDark,
                  border: Border.all(color: _borderColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            session.isCurrent
                                ? Icons.radio_button_checked
                                : Icons.devices_other,
                            color: session.isCurrent ? _cyan : _textMuted,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              account_display.sessionDeviceLabel(session),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            account_display.sessionStateText(session),
                            style: TextStyle(
                              color: session.isActive ? _cyan : _textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        account_display.sessionDetailText(session),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    };
  }
}
