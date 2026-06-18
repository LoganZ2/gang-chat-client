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
        Text(
          'Live Channel',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiTypography.label.copyWith(color: UiColors.textMuted),
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
    required this.onToggleCamera,
    required this.onToggleShare,
  });

  final List<LiveParticipant> participants;
  final CurrentUser currentUser;
  final Set<String> speakingUserIds;
  final List<LiveVideoTrack> videoTracks;
  final LiveVideoTrack? stageTrack;
  final ValueChanged<LiveVideoTrack> onSelectStage;
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleShare;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (participants.isEmpty) {
          return Center(
            child: Text(
              'No one is in live channel',
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
                      onToggleCamera: onToggleCamera,
                      onToggleShare: onToggleShare,
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
    required this.onToggleCamera,
    required this.onToggleShare,
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
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleShare;

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
    if (previewTrack != null) {
      if (previewTrack.isScreenShare) {
        return _LiveMemberScreenShareCard(
          track: previewTrack,
          name: name,
          nameColor: nameColor,
          micMuted: state.micMutedForDisplay,
          speaking: speaking,
          highlighted: state.highlighted,
          borderColor: borderColor,
          onPressed: () => onSelectPreview(previewTrack),
        );
      }
      return SizedBox(
        width: _memberCardWidth,
        child: PressableSurface(
          height: _memberCardHeight,
          hoverLift: 3,
          baseDepth: 5,
          borderRadius: UiRadii.lg,
          backgroundColor: _memberIdleBackground,
          selectedBackgroundColor: _memberSpeakingBackground,
          borderColor: borderColor,
          selectedBorderColor: UiColors.borderStrong,
          selected: state.highlighted,
          padding: EdgeInsets.zero,
          onPressed: () => onSelectPreview(previewTrack),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _LiveMemberVideo(track: previewTrack),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _LiveVideoFooter(
                  name: name,
                  nameColor: nameColor,
                  micMuted: state.micMutedForDisplay,
                  speaking: speaking,
                  mediaKind: previewTrack.isScreenShare
                      ? _LiveMediaKind.screenShare
                      : _LiveMediaKind.camera,
                ),
              ),
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
            Positioned(
              top: 8,
              right: 9,
              child: _LiveMemberActivityTag(
                label: _participantMeta(participant, speaking: speaking),
                color: _participantMetaColor(participant, speaking: speaking),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 27, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Avatar(
                      label: name,
                      imageUrl: AppConfigScope.of(
                        context,
                      ).resolveAssetUrl(participant.user.avatarUrl),
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
                  _LiveMemberStatusRow(
                    participant: participant,
                    micMutedForDisplay: state.micMutedForDisplay,
                    onToggleMic: local && !participant.voiceBlocked
                        ? onToggleMic
                        : null,
                    onToggleHeadphones: local ? onToggleHeadphones : null,
                    onToggleCamera: local ? onToggleCamera : null,
                    onToggleShare: local ? onToggleShare : null,
                  ),
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
  const _LiveMemberActivityTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 84),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: UiColors.surfacePressed.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.36)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.label.copyWith(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveMemberStatusRow extends StatelessWidget {
  const _LiveMemberStatusRow({
    required this.participant,
    required this.micMutedForDisplay,
    this.onToggleMic,
    this.onToggleHeadphones,
    this.onToggleCamera,
    this.onToggleShare,
  });

  final LiveParticipant participant;
  final bool micMutedForDisplay;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleHeadphones;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onToggleShare;

  @override
  Widget build(BuildContext context) {
    final listening =
        participant.headphonesListening && !participant.headphonesMuted;
    final buttons = [
      _LiveMemberStatusButton(
        key: ValueKey<String>('live-member-status:mic:${participant.user.id}'),
        icon: micMutedForDisplay ? Icons.mic_off : Icons.mic,
        active: !micMutedForDisplay,
        danger: participant.voiceBlocked,
        onPressed: onToggleMic,
        tooltip: participant.voiceBlocked
            ? '已被禁言'
            : micMutedForDisplay
            ? '麦克风关闭'
            : '麦克风开启',
      ),
      _LiveMemberStatusButton(
        key: ValueKey<String>(
          'live-member-status:headphones:${participant.user.id}',
        ),
        icon: listening ? Icons.headphones : Icons.headset_off,
        active: listening,
        onPressed: onToggleHeadphones,
        tooltip: listening ? '正在收听' : '已关闭收听',
      ),
      _LiveMemberStatusButton(
        key: ValueKey<String>(
          'live-member-status:camera:${participant.user.id}',
        ),
        icon: participant.cameraOn ? Icons.videocam : Icons.videocam_outlined,
        active: participant.cameraOn,
        onPressed: onToggleCamera,
        tooltip: participant.cameraOn ? '摄像头已开启' : '摄像头关闭',
      ),
      _LiveMemberStatusButton(
        key: ValueKey<String>(
          'live-member-status:screen-share:${participant.user.id}',
        ),
        icon: participant.screenSharing
            ? Icons.stop_screen_share
            : Icons.screen_share_outlined,
        active: participant.screenSharing,
        onPressed: onToggleShare,
        tooltip: participant.screenSharing ? '正在共享屏幕' : '未共享屏幕',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final dimension = constraints.maxWidth / buttons.length;
        return SizedBox(
          height: dimension,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final button in buttons)
                SizedBox.square(dimension: dimension, child: button),
            ],
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
  });

  final IconData icon;
  final bool active;
  final bool danger;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = danger
        ? UiColors.danger
        : active
        ? UiColors.accent
        : UiColors.textMuted;
    final background = active
        ? UiColors.selected
        : UiColors.surfacePressed.withValues(alpha: 0.72);
    final border = danger
        ? UiColors.dangerBorder
        : active
        ? UiColors.selectedBorder
        : UiColors.border;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Semantics(
            button: true,
            enabled: enabled,
            selected: active,
            label: tooltip,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(UiRadii.sm),
                border: Border.all(color: border),
              ),
              child: Center(child: Icon(icon, color: foreground, size: 13)),
            ),
          ),
        ),
      ),
    );
  }
}

Color _liveMemberNameColor(UserSummary user, {required bool local}) {
  if (local) return UiColors.accent;
  return roleBadgeForegroundColorForLabel(room_display.roomRoleLabel(user));
}

Color _participantMetaColor(
  LiveParticipant participant, {
  required bool speaking,
}) {
  if (participant.voiceBlocked) return UiColors.danger;
  if (participant.screenSharing || participant.cameraOn || speaking) {
    return UiColors.accent;
  }
  if (participant.micMuted) return UiColors.textMuted;
  return UiColors.textSecondary;
}

class _LiveMemberScreenShareCard extends StatelessWidget {
  const _LiveMemberScreenShareCard({
    required this.track,
    required this.name,
    required this.nameColor,
    required this.micMuted,
    required this.speaking,
    required this.highlighted,
    required this.borderColor,
    required this.onPressed,
  });

  final LiveVideoTrack track;
  final String name;
  final Color nameColor;
  final bool micMuted;
  final bool speaking;
  final bool highlighted;
  final Color borderColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final background = highlighted
        ? _memberSpeakingBackground
        : _memberIdleBackground;
    return SizedBox(
      width: _memberCardWidth,
      height: _memberCardHeight + 8,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 8,
                height: _memberCardHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: UiColors.surfacePressed,
                    borderRadius: BorderRadius.circular(UiRadii.lg),
                    border: Border.all(color: borderColor),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 3,
                height: _memberCardHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(UiRadii.lg),
                    border: Border.all(color: borderColor),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _LiveMediaVideo(track: track),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _LiveVideoFooter(
                          name: name,
                          nameColor: nameColor,
                          micMuted: micMuted,
                          speaking: speaking,
                          mediaKind: _LiveMediaKind.screenShare,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  if (participant.voiceBlocked) return '已被禁言';
  if (participant.screenSharing) return '正在共享屏幕';
  if (participant.cameraOn) return '摄像头已开启';
  if (participant.micMuted) return '已静音';
  if (speaking) return '正在说话';
  return '正在收听';
}
