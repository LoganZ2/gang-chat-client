part of 'live_channel_pane.dart';

class _LiveRoomHeader extends StatelessWidget {
  const _LiveRoomHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.graphic_eq, color: UiColors.textSecondary, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.title.copyWith(fontSize: 16),
          ),
        ),
      ],
    );
  }
}

class _LiveMemberStage extends StatelessWidget {
  const _LiveMemberStage({
    required this.participants,
    required this.currentUser,
    required this.speakingUserIds,
    required this.videoTracks,
    required this.stageTrack,
    required this.onSelectStage,
    required this.onToggleMic,
    required this.onToggleHeadphones,
    required this.participantVoiceVolume,
    required this.onParticipantVoiceVolumeChanged,
    required this.onParticipantVoiceMuteToggled,
    required this.canModerateParticipant,
    required this.onToggleParticipantMicModeration,
    required this.onToggleParticipantHeadphonesModeration,
    required this.canRemoveParticipant,
    required this.onRemoveParticipant,
  });

  final List<LiveParticipant> participants;
  final CurrentUser currentUser;
  final Set<String> speakingUserIds;
  final List<LiveVideoTrack> videoTracks;
  final LiveVideoTrack? stageTrack;
  final ValueChanged<LiveVideoTrack> onSelectStage;
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final double Function(String userId) participantVoiceVolume;
  final void Function(String userId, double volume)
  onParticipantVoiceVolumeChanged;
  final ValueChanged<String> onParticipantVoiceMuteToggled;
  final bool Function(LiveParticipant participant) canModerateParticipant;
  final ValueChanged<LiveParticipant> onToggleParticipantMicModeration;
  final ValueChanged<LiveParticipant> onToggleParticipantHeadphonesModeration;
  final bool Function(LiveParticipant participant) canRemoveParticipant;
  final ValueChanged<LiveParticipant> onRemoveParticipant;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (participants.isEmpty) {
          return Center(
            child: Text(
              '语音频道里还没有人',
              style: UiTypography.body.copyWith(color: UiColors.textMuted),
            ),
          );
        }

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.topLeft,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final participant in participants)
                    _LiveMemberCard(
                      participant: participant,
                      local: participant.user.id == currentUser.id,
                      speaking: speakingUserIds.contains(participant.user.id),
                      previewTrack: _memberPreviewTrack(
                        tracks: videoTracks,
                        userId: participant.user.id,
                        stageTrack: stageTrack,
                      ),
                      selectableTrack: _selectableTrack(
                        tracks: videoTracks,
                        userId: participant.user.id,
                        stageTrack: stageTrack,
                      ),
                      onSelectPreview: onSelectStage,
                      onToggleMic: onToggleMic,
                      onToggleHeadphones: onToggleHeadphones,
                      participantVoiceVolume: participantVoiceVolume,
                      onParticipantVoiceVolumeChanged:
                          onParticipantVoiceVolumeChanged,
                      onParticipantVoiceMuteToggled:
                          onParticipantVoiceMuteToggled,
                      canModerateParticipant: canModerateParticipant,
                      onToggleParticipantMicModeration:
                          onToggleParticipantMicModeration,
                      onToggleParticipantHeadphonesModeration:
                          onToggleParticipantHeadphonesModeration,
                      canRemoveParticipant: canRemoveParticipant,
                      onRemoveParticipant: onRemoveParticipant,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LiveMemberCard extends StatelessWidget {
  const _LiveMemberCard({
    required this.participant,
    required this.local,
    required this.speaking,
    required this.onSelectPreview,
    required this.onToggleMic,
    required this.onToggleHeadphones,
    required this.participantVoiceVolume,
    required this.onParticipantVoiceVolumeChanged,
    required this.onParticipantVoiceMuteToggled,
    required this.canModerateParticipant,
    required this.onToggleParticipantMicModeration,
    required this.onToggleParticipantHeadphonesModeration,
    required this.canRemoveParticipant,
    required this.onRemoveParticipant,
    this.selectableTrack,
    this.previewTrack,
  });

  final LiveParticipant participant;
  final bool local;
  final bool speaking;
  final LiveVideoTrack? previewTrack;
  final LiveVideoTrack? selectableTrack;
  final ValueChanged<LiveVideoTrack> onSelectPreview;
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final double Function(String userId) participantVoiceVolume;
  final void Function(String userId, double volume)
  onParticipantVoiceVolumeChanged;
  final ValueChanged<String> onParticipantVoiceMuteToggled;
  final bool Function(LiveParticipant participant) canModerateParticipant;
  final ValueChanged<LiveParticipant> onToggleParticipantMicModeration;
  final ValueChanged<LiveParticipant> onToggleParticipantHeadphonesModeration;
  final bool Function(LiveParticipant participant) canRemoveParticipant;
  final ValueChanged<LiveParticipant> onRemoveParticipant;

  @override
  Widget build(BuildContext context) {
    final state = live_display.liveParticipantTileState(
      participant,
      speaking: speaking,
    );
    final name = room_display.userPrimaryName(participant.user);
    final nameColor = _liveMemberNameColor(participant.user, local: local);
    final previewTrack = this.previewTrack;
    final borderColor = state.highlighted
        ? UiColors.borderStrong
        : UiColors.border;
    final activityIcon = _participantMetaIcon(participant, speaking: speaking);
    final canModerate = !local && canModerateParticipant(participant);
    final activityTag = activityIcon == null
        ? null
        : _LiveMemberActivityTag(
            key: ValueKey<String>(
              'live-member-activity:${participant.user.id}',
            ),
            label: _participantMeta(participant, speaking: speaking),
            icon: activityIcon,
            color: _participantMetaColor(participant, speaking: speaking),
          );
    final statusRow = _LiveMemberStatusRow(
      participant: participant,
      participantName: name,
      micMutedForDisplay: state.micMutedForDisplay,
      moderationControls: canModerate,
      onToggleMic: local
          ? onToggleMic
          : canModerate
          ? () => onToggleParticipantMicModeration(participant)
          : null,
      onToggleHeadphones: local
          ? onToggleHeadphones
          : canModerate
          ? () => onToggleParticipantHeadphonesModeration(participant)
          : null,
      voiceVolume: local ? null : participantVoiceVolume(participant.user.id),
      onVoiceVolumeChanged: local
          ? null
          : (volume) =>
                onParticipantVoiceVolumeChanged(participant.user.id, volume),
      onVoiceVolumeToggle: local
          ? null
          : () => onParticipantVoiceMuteToggled(participant.user.id),
      onRemoveMember: !local && canRemoveParticipant(participant)
          ? () => onRemoveParticipant(participant)
          : null,
    );
    if (previewTrack != null) {
      return SizedBox(
        width: _memberCardWidth,
        child: PressableSurface(
          height: _memberCardHeight,
          hoverLift: 3,
          baseDepth: 5,
          borderRadius: UiRadii.lg,
          backgroundColor: state.highlighted
              ? _memberSpeakingBackground
              : _memberIdleBackground,
          selectedBackgroundColor: _memberSpeakingBackground,
          borderColor: borderColor,
          selectedBorderColor: UiColors.borderStrong,
          selected: state.highlighted,
          padding: EdgeInsets.zero,
          interactive: true,
          pressEffect: false,
          mouseCursor: SystemMouseCursors.basic,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 8,
                right: 8,
                top: 30,
                bottom: 46,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelectPreview(previewTrack),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(UiRadii.md),
                      child: ColoredBox(
                        color: UiColors.surfacePressed,
                        child: _LiveMemberVideo(track: previewTrack),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 9,
                right: 9,
                top: 8,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UiTypography.label.copyWith(
                          color: nameColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (activityTag != null) ...[
                      const SizedBox(width: 6),
                      activityTag,
                    ],
                  ],
                ),
              ),
              Positioned(left: 12, right: 12, bottom: 8, child: statusRow),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(UiRadii.lg),
                      border: Border.all(color: borderColor),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      width: _memberCardWidth,
      child: PressableSurface(
        height: _memberCardHeight,
        hoverLift: 3,
        baseDepth: 5,
        borderRadius: UiRadii.lg,
        backgroundColor: state.highlighted
            ? _memberSpeakingBackground
            : _memberIdleBackground,
        selectedBackgroundColor: _memberSpeakingBackground,
        borderColor: borderColor,
        selectedBorderColor: UiColors.borderStrong,
        selected: state.highlighted,
        padding: EdgeInsets.zero,
        onPressed: selectableTrack == null
            ? () {}
            : () => onSelectPreview(selectableTrack!),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (activityTag != null)
              Positioned(top: 8, right: 9, child: activityTag),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 33, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Avatar(
                      label: name,
                      imageUrl: AppConfigScope.of(
                        context,
                      ).resolveAssetUrl(participant.user.avatarUrl),
                      defaultAvatarKey: participant.user.defaultAvatarKey,
                      size: 42,
                      showBorder: false,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: UiTypography.body.copyWith(
                      color: nameColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  statusRow,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveMemberActivityTag extends StatelessWidget {
  const _LiveMemberActivityTag({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: SizedBox.square(
          dimension: 24,
          child: Center(child: Icon(icon, color: color, size: 15)),
        ),
      ),
    );
  }
}

class _LiveMemberStatusRow extends StatelessWidget {
  const _LiveMemberStatusRow({
    required this.participant,
    required this.participantName,
    required this.micMutedForDisplay,
    required this.moderationControls,
    this.onToggleMic,
    this.onToggleHeadphones,
    this.voiceVolume,
    this.onVoiceVolumeChanged,
    this.onVoiceVolumeToggle,
    this.onRemoveMember,
  });

  final LiveParticipant participant;
  final String participantName;
  final bool micMutedForDisplay;
  final bool moderationControls;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleHeadphones;
  final double? voiceVolume;
  final ValueChanged<double>? onVoiceVolumeChanged;
  final VoidCallback? onVoiceVolumeToggle;
  final VoidCallback? onRemoveMember;

  @override
  Widget build(BuildContext context) {
    final listening =
        participant.headphonesListening &&
        !participant.headphonesMuted &&
        !participant.headphonesBlocked;
    final micModerated = participant.micBlocked || participant.voiceBlocked;
    final headphonesModerated = participant.headphonesBlocked;
    final voiceVolume = this.voiceVolume;
    final onVoiceVolumeChanged = this.onVoiceVolumeChanged;
    final buttons = <Widget>[
      _LiveMemberStatusButton(
        key: ValueKey<String>('live-member-status:mic:${participant.user.id}'),
        icon: micMutedForDisplay ? Icons.mic_off : Icons.mic,
        active: !micMutedForDisplay,
        danger: micModerated,
        onPressed: onToggleMic,
        tooltip: _liveMemberMicTooltip(
          micMutedForDisplay: micMutedForDisplay,
          micModerated: micModerated,
          headphonesModerated: headphonesModerated,
          moderationControls: moderationControls,
        ),
      ),
      _LiveMemberStatusButton(
        key: ValueKey<String>(
          'live-member-status:headphones:${participant.user.id}',
        ),
        icon: listening ? Icons.headphones : Icons.headset_off,
        active: listening,
        danger: headphonesModerated,
        onPressed: onToggleHeadphones,
        tooltip: _liveMemberHeadphonesTooltip(
          listening: listening,
          headphonesModerated: headphonesModerated,
          moderationControls: moderationControls,
        ),
      ),
      if (voiceVolume != null && onVoiceVolumeChanged != null)
        _HoverVolumeButton(
          key: ValueKey<String>(
            'live-member-status:voice-volume:${participant.user.id}',
          ),
          value: voiceVolume,
          semanticLabel: '$participantName语音音量',
          infoMessage: _memberVoiceVolumeToggleLabel(
            participantName: participantName,
            voiceVolume: voiceVolume,
          ),
          onChanged: onVoiceVolumeChanged,
          maxValue: maxParticipantVoiceVolume,
          valueFormatter: participantVoiceVolumePercentText,
          panelWidth: _memberStatusButtonDimension,
          panelHeight: _memberVoiceVolumePanelHeight(
            _memberStatusButtonDimension,
          ),
          child: _LiveMemberStatusButton(
            icon: _memberVoiceVolumeIcon(voiceVolume),
            active: voiceVolume > 0,
            tooltip: _memberVoiceVolumeToggleLabel(
              participantName: participantName,
              voiceVolume: voiceVolume,
            ),
            onPressed: onVoiceVolumeToggle,
            showHoverInfo: false,
          ),
        ),
      if (onRemoveMember != null)
        _LiveMemberStatusButton(
          key: ValueKey<String>(
            'live-member-status:kick:${participant.user.id}',
          ),
          icon: Icons.exit_to_app,
          active: false,
          danger: true,
          tooltip: '踢出语音频道',
          onPressed: onRemoveMember,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final dimension = constraints.maxWidth / 4;
        final rowWidth = dimension * buttons.length;
        return Center(
          child: SizedBox(
            width: rowWidth,
            height: dimension,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final button in buttons)
                  SizedBox.square(dimension: dimension, child: button),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LiveMemberStatusButton extends StatelessWidget {
  const _LiveMemberStatusButton({
    super.key,
    required this.icon,
    required this.active,
    required this.tooltip,
    this.onPressed,
    this.danger = false,
    this.showHoverInfo = true,
  });

  final IconData icon;
  final bool active;
  final bool danger;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool showHoverInfo;

  @override
  Widget build(BuildContext context) {
    final foreground = danger
        ? UiColors.danger
        : active
        ? UiColors.accent
        : UiColors.textMuted;
    final enabled = onPressed != null;
    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Semantics(
          button: true,
          enabled: enabled,
          selected: active,
          label: tooltip,
          child: Center(child: Icon(icon, color: foreground, size: 13)),
        ),
      ),
    );
    if (!showHoverInfo) return button;
    return _HoverInfo(message: tooltip, child: button);
  }
}

IconData _memberVoiceVolumeIcon(double volume) {
  final normalized = normalizedParticipantVoiceVolume(volume);
  if (normalized <= 0) return Icons.volume_off;
  if (normalized < defaultParticipantVoiceVolume) return Icons.volume_down;
  return Icons.volume_up;
}

String _memberVoiceVolumeToggleLabel({
  required String participantName,
  required double voiceVolume,
}) {
  return voiceVolume <= 0 ? '取消静音$participantName' : '静音$participantName';
}

const _memberStatusButtonDimension = (_memberCardWidth - 24.0) / 4;

double _memberVoiceVolumePanelHeight(double buttonDimension) {
  return _hoverVolumePanelHeight * buttonDimension / _controlButtonSize;
}

String _liveMemberMicTooltip({
  required bool micMutedForDisplay,
  required bool micModerated,
  required bool headphonesModerated,
  required bool moderationControls,
}) {
  if (moderationControls) {
    if (micModerated && headphonesModerated) return '解除隔离';
    if (micModerated) return '取消禁言';
    return '禁言';
  }
  if (micModerated) return '已被禁言';
  return micMutedForDisplay ? '麦克风关闭' : '麦克风开启';
}

String _liveMemberHeadphonesTooltip({
  required bool listening,
  required bool headphonesModerated,
  required bool moderationControls,
}) {
  if (moderationControls) {
    return headphonesModerated ? '恢复耳机' : '隔离';
  }
  if (headphonesModerated) return '已被隔离';
  return listening ? '正在收听' : '已关闭收听';
}

Color _liveMemberNameColor(UserSummary user, {required bool local}) {
  if (local) return UiColors.accent;
  return roleBadgeForegroundColorForLabel(room_display.roomRoleLabel(user));
}

Color _participantMetaColor(
  LiveParticipant participant, {
  required bool speaking,
}) {
  if (participant.screenSharing || participant.cameraOn || speaking) {
    return UiColors.accent;
  }
  if (participant.micMuted) return UiColors.textMuted;
  return UiColors.textSecondary;
}

IconData? _participantMetaIcon(
  LiveParticipant participant, {
  required bool speaking,
}) {
  if (participant.screenSharing) return Icons.screen_share_outlined;
  if (participant.cameraOn) return Icons.videocam;
  if (speaking) return Icons.mic;
  return null;
}

class _LiveMemberVideo extends StatelessWidget {
  const _LiveMemberVideo({required this.track});

  final LiveVideoTrack track;

  @override
  Widget build(BuildContext context) {
    final video = _LiveMediaVideo(track: track);
    if (track.isScreenShare) return video;
    return ClipRRect(
      borderRadius: BorderRadius.circular(UiRadii.lg),
      child: video,
    );
  }
}

String _participantMeta(LiveParticipant participant, {required bool speaking}) {
  if (participant.screenSharing) return '正在共享屏幕';
  if (participant.cameraOn) return '摄像头已开启';
  if (participant.micMuted) return '已静音';
  if (speaking) return '正在说话';
  return '正在收听';
}
