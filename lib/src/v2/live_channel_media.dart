part of 'live_channel_pane.dart';

enum _LiveMediaKind { camera, screenShare }

class _LiveMediaStage extends StatelessWidget {
  const _LiveMediaStage({
    required this.track,
    required this.label,
    required this.onExit,
    required this.onFullScreen,
  });

  final LiveVideoTrack track;
  final String label;
  final VoidCallback onExit;
  final VoidCallback onFullScreen;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(UiRadii.lg),
      child: ColoredBox(
        color: UiColors.surfacePressed,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LiveVideoTrackView(
              track: track,
              fit: track.isScreenShare
                  ? LiveVideoTrackFit.contain
                  : LiveVideoTrackFit.cover,
              mirrorLocal: true,
            ),
            Positioned(
              left: 0,
              top: 0,
              child: _LiveStageBadge(
                label: label,
                kind: track.isScreenShare
                    ? _LiveMediaKind.screenShare
                    : _LiveMediaKind.camera,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StageOverlayIconButton(
                    tooltip: '退出观看',
                    icon: Icons.close_fullscreen,
                    onPressed: onExit,
                  ),
                  const SizedBox(width: 6),
                  _StageOverlayIconButton(
                    tooltip: '全屏',
                    icon: Icons.fullscreen,
                    onPressed: onFullScreen,
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

class LiveFullScreenStage extends StatelessWidget {
  const LiveFullScreenStage({
    super.key,
    required this.track,
    required this.label,
    required this.onExit,
  });

  final LiveVideoTrack track;
  final String label;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LiveVideoTrackView(
            track: track,
            fit: track.isScreenShare
                ? LiveVideoTrackFit.contain
                : LiveVideoTrackFit.cover,
            mirrorLocal: true,
          ),
          Positioned(
            left: 14,
            top: 14,
            child: _LiveStageBadge(
              label: label,
              kind: track.isScreenShare
                  ? _LiveMediaKind.screenShare
                  : _LiveMediaKind.camera,
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: _StageOverlayIconButton(
              tooltip: '退出全屏',
              icon: Icons.fullscreen_exit,
              onPressed: onExit,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageOverlayIconButton extends StatefulWidget {
  const _StageOverlayIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_StageOverlayIconButton> createState() =>
      _StageOverlayIconButtonState();
}

class _StageOverlayIconButtonState extends State<_StageOverlayIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _hovered ? UiColors.accent : UiColors.textSecondary;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _hovered
                  ? UiColors.surface.withValues(alpha: 0.92)
                  : UiColors.surface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(UiRadii.md),
            ),
            child: Icon(widget.icon, size: 19, color: color),
          ),
        ),
      ),
    );
  }
}

class _LiveStageBadge extends StatelessWidget {
  const _LiveStageBadge({required this.label, required this.kind});

  final String label;
  final _LiveMediaKind kind;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surface.withValues(alpha: 0.86),
        border: const Border(
          right: BorderSide(color: UiColors.border),
          bottom: BorderSide(color: UiColors.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_mediaIcon(kind), color: UiColors.accent, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.label.copyWith(color: UiColors.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveVideoFooter extends StatelessWidget {
  const _LiveVideoFooter({
    required this.name,
    required this.micMuted,
    required this.speaking,
    required this.mediaKind,
  });

  final String name;
  final bool micMuted;
  final bool speaking;
  final _LiveMediaKind mediaKind;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            UiColors.surfacePressed.withValues(alpha: 0.9),
            UiColors.surfacePressed.withValues(alpha: 0),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 16, 9, 8),
        child: Row(
          children: [
            Icon(
              micMuted ? Icons.mic_off : Icons.mic,
              size: 14,
              color: micMuted
                  ? UiColors.textMuted
                  : speaking
                  ? UiColors.accent
                  : UiColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UiTypography.label.copyWith(color: UiColors.text),
              ),
            ),
            const SizedBox(width: 6),
            Icon(_mediaIcon(mediaKind), size: 14, color: UiColors.accent),
          ],
        ),
      ),
    );
  }
}

IconData _mediaIcon(_LiveMediaKind kind) {
  return switch (kind) {
    _LiveMediaKind.camera => Icons.videocam,
    _LiveMediaKind.screenShare => Icons.screen_share,
  };
}

String liveStageTrackLabel(LiveState? live, LiveVideoTrack track) {
  final name = live_display.liveParticipantDisplayName(live, track.identity);
  if (track.isScreenShare) return live_display.liveScreenShareStageLabel(name);
  return name.isEmpty ? '摄像头' : '$name 的摄像头';
}

LiveVideoTrack? _trackForSelection(
  List<LiveVideoTrack> tracks,
  LiveStageSelection selection,
) {
  if (selection.mode != LiveStageSelectionMode.track) return null;
  for (final track in tracks) {
    if (track.identity == selection.identity &&
        track.isScreenShare == selection.isScreenShare) {
      return track;
    }
  }
  return null;
}

@visibleForTesting
LiveVideoTrack? resolveLiveStageTrackForTest({
  required List<LiveVideoTrack> tracks,
  required LiveStageSelection? selection,
}) {
  return _resolveLiveStageTrack(tracks: tracks, selection: selection);
}

LiveVideoTrack? _resolveLiveStageTrack({
  required List<LiveVideoTrack> tracks,
  required LiveStageSelection? selection,
}) {
  if (selection != null) {
    if (selection.mode == LiveStageSelectionMode.none) return null;
    final track = _trackForSelection(tracks, selection);
    if (track != null) return track;
    return _localScreenShare(tracks);
  }

  return _localScreenShare(tracks);
}

LiveVideoTrack? _localScreenShare(List<LiveVideoTrack> tracks) {
  for (final track in tracks) {
    if (track.isLocal && track.isScreenShare) return track;
  }
  return null;
}

LiveVideoTrack? _memberPreviewTrack({
  required List<LiveVideoTrack> tracks,
  required String userId,
  required LiveVideoTrack? stageTrack,
}) {
  final camera = _cameraFor(tracks, userId);
  final share = _screenShareFor(tracks, userId);
  if (stageTrack?.identity == userId) {
    if (stageTrack!.isScreenShare) return camera;
    return share;
  }
  return camera ?? share;
}

LiveVideoTrack? _selectableTrack({
  required List<LiveVideoTrack> tracks,
  required String userId,
  required LiveVideoTrack? stageTrack,
}) {
  final preview = _memberPreviewTrack(
    tracks: tracks,
    userId: userId,
    stageTrack: stageTrack,
  );
  if (preview != null) return preview;

  return null;
}

LiveVideoTrack? _screenShareFor(List<LiveVideoTrack> tracks, String userId) {
  for (final track in tracks) {
    if (track.isScreenShare && track.identity == userId) return track;
  }
  return null;
}

LiveVideoTrack? _cameraFor(List<LiveVideoTrack> tracks, String userId) {
  for (final track in tracks) {
    if (!track.isScreenShare && track.identity == userId) return track;
  }
  return null;
}
