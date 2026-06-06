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
  });

  final List<LiveParticipant> participants;
  final CurrentUser currentUser;
  final Set<String> speakingUserIds;
  final List<LiveVideoTrack> videoTracks;
  final LiveVideoTrack? stageTrack;
  final ValueChanged<LiveVideoTrack> onSelectStage;

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
    this.selectableTrack,
    this.previewTrack,
  });

  final LiveParticipant participant;
  final bool local;
  final bool speaking;
  final LiveVideoTrack? previewTrack;
  final LiveVideoTrack? selectableTrack;
  final ValueChanged<LiveVideoTrack> onSelectPreview;

  @override
  Widget build(BuildContext context) {
    final state = live_display.liveParticipantTileState(
      participant,
      speaking: speaking,
    );
    final name = participant.user.displayName;
    final previewTrack = this.previewTrack;
    final borderColor = state.highlighted
        ? UiColors.borderStrong
        : UiColors.border;
    if (previewTrack != null) {
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
              ClipRRect(
                borderRadius: BorderRadius.circular(UiRadii.lg),
                child: LiveVideoTrackView(
                  track: previewTrack,
                  fit: LiveVideoTrackFit.cover,
                  mirrorLocal: true,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _LiveVideoFooter(
                  name: local ? '$name (you)' : name,
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
        padding: const EdgeInsets.all(12),
        onPressed: selectableTrack == null
            ? () {}
            : () => onSelectPreview(selectableTrack!),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(
                  label: name,
                  imageUrl: AppConfigScope.of(
                    context,
                  ).resolveAssetUrl(participant.user.avatarUrl),
                  size: 42,
                  active: state.micActive,
                  activeBorderWidth: 1.2,
                ),
                const Spacer(),
                Icon(
                  state.micMutedForDisplay ? Icons.mic_off : Icons.mic,
                  color: state.micMutedForDisplay
                      ? UiColors.textMuted
                      : UiColors.textSecondary,
                  size: 17,
                ),
              ],
            ),
            const Spacer(),
            Text(
              local ? '$name (you)' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.body.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              _participantMeta(participant, speaking: speaking),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.label.copyWith(color: UiColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

String _participantMeta(LiveParticipant participant, {required bool speaking}) {
  if (participant.voiceBlocked) return 'Voice blocked';
  if (participant.screenSharing) return 'Sharing screen';
  if (participant.cameraOn) return 'Camera on';
  if (participant.micMuted) return 'Muted';
  if (speaking) return 'Speaking';
  return 'Listening';
}
