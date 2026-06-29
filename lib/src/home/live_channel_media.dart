part of 'live_channel_pane.dart';

enum _LiveMediaKind { camera, screenShare }

class _LiveMediaVideo extends StatelessWidget {
  const _LiveMediaVideo({required this.track});

  final LiveVideoTrack track;

  @override
  Widget build(BuildContext context) {
    return LiveVideoTrackView(
      track: track,
      fit: track.isScreenShare
          ? LiveVideoTrackFit.contain
          : LiveVideoTrackFit.cover,
      mirrorLocal: true,
    );
  }
}

class _LiveMediaStage extends StatelessWidget {
  const _LiveMediaStage({
    required this.track,
    required this.label,
    required this.screenShareVolume,
    required this.onExit,
    required this.onFullScreen,
    required this.onScreenShareVolumeChanged,
    required this.onScreenShareMuteToggled,
  });

  final LiveVideoTrack track;
  final String label;
  final double screenShareVolume;
  final VoidCallback onExit;
  final VoidCallback onFullScreen;
  final ValueChanged<double> onScreenShareVolumeChanged;
  final VoidCallback onScreenShareMuteToggled;

  @override
  Widget build(BuildContext context) {
    final isLocalScreenShare = track.isScreenShare && track.isLocal;
    final isRemoteScreenShare = track.isScreenShare && !track.isLocal;
    final content = ColoredBox(
      color: UiColors.surfacePressed,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _LiveMediaVideo(track: track),
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
                  key: const ValueKey<String>('live-stage:exit'),
                  icon: Icons.close_fullscreen,
                  infoMessage: '退出焦点画面',
                  onPressed: onExit,
                ),
                if (!isLocalScreenShare) ...[
                  const SizedBox(width: 6),
                  _StageOverlayIconButton(
                    key: const ValueKey<String>('live-stage:fullscreen'),
                    icon: Icons.fullscreen,
                    infoMessage: '全屏查看',
                    onPressed: onFullScreen,
                  ),
                ],
              ],
            ),
          ),
          if (isRemoteScreenShare)
            Positioned(
              right: 8,
              bottom: 8,
              child: _StageScreenShareVolumeButton(
                value: screenShareVolume,
                onChanged: onScreenShareVolumeChanged,
                onPressed: onScreenShareMuteToggled,
              ),
            ),
        ],
      ),
    );
    if (track.isScreenShare) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(UiRadii.lg),
      child: content,
    );
  }
}

class _StageScreenShareVolumeButton extends StatelessWidget {
  const _StageScreenShareVolumeButton({
    required this.value,
    required this.onChanged,
    required this.onPressed,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizedAudioVolume(value);
    final message = normalized <= 0 ? '取消静音共享屏幕' : '静音共享屏幕';
    return _HoverVolumeButton(
      key: const ValueKey<String>('live-stage:screen-share-volume'),
      value: normalized,
      semanticLabel: '共享屏幕输出音量',
      infoMessage: message,
      onChanged: onChanged,
      panelWidth: 34,
      panelHeight: _hoverVolumePanelHeight * 34 / _controlButtonSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Semantics(
          button: true,
          label: message,
          child: _StageOverlayIconSurface(
            icon: _screenShareVolumeIcon(normalized),
          ),
        ),
      ),
    );
  }
}

class LiveFullScreenStage extends StatefulWidget {
  const LiveFullScreenStage({
    super.key,
    required this.track,
    required this.label,
    required this.screenShareVolume,
    required this.onScreenShareVolumeChanged,
    required this.onScreenShareMuteToggled,
    required this.onExit,
  });

  final LiveVideoTrack track;
  final String label;
  final double screenShareVolume;
  final ValueChanged<double> onScreenShareVolumeChanged;
  final VoidCallback onScreenShareMuteToggled;
  final VoidCallback onExit;

  @override
  State<LiveFullScreenStage> createState() => _LiveFullScreenStageState();
}

class _LiveFullScreenStageState extends State<LiveFullScreenStage> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'LiveFullScreenStage');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onExit();
        }
      },
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _LiveMediaVideo(track: widget.track),
            Positioned(
              left: 14,
              top: 14,
              child: _LiveStageBadge(
                label: widget.label,
                kind: widget.track.isScreenShare
                    ? _LiveMediaKind.screenShare
                    : _LiveMediaKind.camera,
              ),
            ),
            Positioned(
              top: 14,
              right: 14,
              child: _StageOverlayIconButton(
                key: const ValueKey<String>('live-fullscreen-stage:exit'),
                icon: Icons.fullscreen_exit,
                infoMessage: '退出全屏',
                onPressed: widget.onExit,
              ),
            ),
            if (widget.track.isScreenShare && !widget.track.isLocal)
              Positioned(
                right: 14,
                bottom: 14,
                child: _StageScreenShareVolumeButton(
                  value: widget.screenShareVolume,
                  onChanged: widget.onScreenShareVolumeChanged,
                  onPressed: widget.onScreenShareMuteToggled,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StageOverlayIconButton extends StatefulWidget {
  const _StageOverlayIconButton({
    super.key,
    required this.icon,
    required this.infoMessage,
    required this.onPressed,
  });

  final IconData icon;
  final String infoMessage;
  final VoidCallback onPressed;

  @override
  State<_StageOverlayIconButton> createState() =>
      _StageOverlayIconButtonState();
}

class _StageOverlayIconButtonState extends State<_StageOverlayIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return _HoverInfo(
      message: widget.infoMessage,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: _StageOverlayIconSurface(icon: widget.icon, hovered: _hovered),
        ),
      ),
    );
  }
}

class _StageOverlayIconSurface extends StatefulWidget {
  const _StageOverlayIconSurface({required this.icon, this.hovered});

  final IconData icon;
  final bool? hovered;

  @override
  State<_StageOverlayIconSurface> createState() =>
      _StageOverlayIconSurfaceState();
}

class _StageOverlayIconSurfaceState extends State<_StageOverlayIconSurface> {
  bool _hovered = false;

  bool get _effectiveHovered => widget.hovered ?? _hovered;

  @override
  Widget build(BuildContext context) {
    final color = _effectiveHovered ? UiColors.accent : UiColors.textSecondary;
    final surface = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: _effectiveHovered
            ? UiColors.surface.withValues(alpha: 0.92)
            : UiColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(UiRadii.md),
      ),
      child: Icon(widget.icon, size: 19, color: color),
    );
    if (widget.hovered != null) return surface;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: surface,
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

IconData _mediaIcon(_LiveMediaKind kind) {
  return switch (kind) {
    _LiveMediaKind.camera => Icons.videocam,
    _LiveMediaKind.screenShare => Icons.screen_share,
  };
}

IconData _screenShareVolumeIcon(double value) {
  final normalized = normalizedAudioVolume(value);
  if (normalized <= 0) return Icons.volume_off;
  if (normalized < 0.5) return Icons.volume_down;
  return Icons.volume_up;
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
    return null;
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
