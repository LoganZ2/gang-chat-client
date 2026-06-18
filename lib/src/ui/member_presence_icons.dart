import 'package:flutter/material.dart';

import '../app/room_members_filter.dart';
import 'tokens.dart';

enum PresencePillTone { voice, online, offline }

IconData roomMemberPresenceIcon(RoomMemberPresence presence) {
  return switch (presence) {
    RoomMemberPresence.live => Icons.call,
    RoomMemberPresence.online => Icons.circle,
    RoomMemberPresence.offline => Icons.circle_outlined,
  };
}

PresencePillTone roomMemberPresencePillTone(RoomMemberPresence presence) {
  return switch (presence) {
    RoomMemberPresence.live => PresencePillTone.voice,
    RoomMemberPresence.online => PresencePillTone.online,
    RoomMemberPresence.offline => PresencePillTone.offline,
  };
}

class PresencePill extends StatelessWidget {
  const PresencePill({super.key, required this.label, required this.tone});

  factory PresencePill.member(RoomMemberPresence presence, {Key? key}) {
    return PresencePill(
      key: key,
      label: roomMemberPresenceLabel(presence),
      tone: roomMemberPresencePillTone(presence),
    );
  }

  factory PresencePill.online({Key? key, String label = '在线'}) {
    return PresencePill(key: key, label: label, tone: PresencePillTone.online);
  }

  factory PresencePill.offline({Key? key, String label = '离线'}) {
    return PresencePill(key: key, label: label, tone: PresencePillTone.offline);
  }

  factory PresencePill.voice({Key? key, String label = '语音'}) {
    return PresencePill(key: key, label: label, tone: PresencePillTone.voice);
  }

  factory PresencePill.fromLabel(String label, {Key? key}) {
    final tone = switch (label.trim()) {
      '语音' => PresencePillTone.voice,
      '离线' => PresencePillTone.offline,
      _ => PresencePillTone.online,
    };
    return PresencePill(key: key, label: label, tone: tone);
  }

  final String label;
  final PresencePillTone tone;

  @override
  Widget build(BuildContext context) {
    final style = _presencePillStyle(tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PresenceDot(color: style.foreground, filled: style.dotFilled),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.label.copyWith(
                color: style.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? color : Colors.transparent,
        shape: BoxShape.circle,
        border: filled ? null : Border.all(color: color, width: 1.4),
      ),
      child: const SizedBox.square(dimension: 10),
    );
  }
}

class _PresencePillStyle {
  const _PresencePillStyle({
    required this.foreground,
    required this.surface,
    required this.border,
    required this.dotFilled,
  });

  final Color foreground;
  final Color surface;
  final Color border;
  final bool dotFilled;
}

_PresencePillStyle _presencePillStyle(PresencePillTone tone) {
  return switch (tone) {
    PresencePillTone.voice => const _PresencePillStyle(
      foreground: UiColors.presenceVoice,
      surface: UiColors.presenceVoiceSurface,
      border: UiColors.presenceVoiceBorder,
      dotFilled: true,
    ),
    PresencePillTone.online => const _PresencePillStyle(
      foreground: UiColors.presenceOnline,
      surface: UiColors.presenceOnlineSurface,
      border: UiColors.presenceOnlineBorder,
      dotFilled: true,
    ),
    PresencePillTone.offline => const _PresencePillStyle(
      foreground: UiColors.presenceOffline,
      surface: UiColors.presenceOfflineSurface,
      border: UiColors.presenceOfflineBorder,
      dotFilled: false,
    ),
  };
}
