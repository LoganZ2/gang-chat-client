part of 'live_channel_pane.dart';

class _LiveControlBar extends StatelessWidget {
  const _LiveControlBar({
    required this.joined,
    required this.joining,
    required this.micMuted,
    required this.headphonesMuted,
    required this.voiceBlocked,
    required this.cameraOn,
    required this.screenSharing,
    required this.watchingRemoteScreenShare,
    required this.inputVolume,
    required this.outputVolume,
    required this.screenShareVolume,
    required this.musicBox,
    required this.musicBoxEnabled,
    required this.musicBoxOpen,
    required this.onJoin,
    required this.onLeave,
    required this.onToggleMic,
    required this.onToggleHeadphones,
    required this.onToggleCamera,
    required this.onToggleShare,
    required this.onInputVolumeChanged,
    required this.onOutputVolumeChanged,
    required this.onScreenShareVolumeChanged,
    required this.onToggleMusicBox,
    required this.onMusicBoxTogglePlayback,
    required this.onMusicBoxSkip,
    required this.onCollapse,
  });

  final bool joined;
  final bool joining;
  final bool micMuted;
  final bool headphonesMuted;
  final bool voiceBlocked;
  final bool cameraOn;
  final bool screenSharing;
  final bool watchingRemoteScreenShare;
  final double inputVolume;
  final double outputVolume;
  final double screenShareVolume;
  final MusicBoxState? musicBox;
  final bool musicBoxEnabled;
  final bool musicBoxOpen;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleShare;
  final ValueChanged<double> onInputVolumeChanged;
  final ValueChanged<double> onOutputVolumeChanged;
  final ValueChanged<double> onScreenShareVolumeChanged;
  final VoidCallback onToggleMusicBox;
  final VoidCallback onMusicBoxTogglePlayback;
  final VoidCallback onMusicBoxSkip;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final micControl = live_display.liveMicControlState(
          micMuted: micMuted,
          voiceBlocked: voiceBlocked,
        );
        final controls = [
          _HoverVolumeButton(
            value: inputVolume,
            semanticLabel: '麦克风输入音量',
            onChanged: onInputVolumeChanged,
            child: ButtonIcon(
              tooltip: micControl.tooltip,
              icon: Icon(
                micControl.mutedForDisplay ? Icons.mic_off : Icons.mic,
              ),
              selected: micControl.active,
              onPressed: micControl.enabled ? onToggleMic : null,
              size: _controlButtonSize,
            ),
          ),
          _HoverVolumeButton(
            value: outputVolume,
            semanticLabel: '语音输出音量',
            onChanged: onOutputVolumeChanged,
            child: ButtonIcon(
              tooltip: live_display.liveHeadphonesControlTooltip(
                headphonesMuted,
              ),
              icon: Icon(
                headphonesMuted ? Icons.headset_off : Icons.headphones,
              ),
              selected: !headphonesMuted,
              onPressed: onToggleHeadphones,
              size: _controlButtonSize,
            ),
          ),
          ButtonIcon(
            tooltip: live_display.liveCameraControlTooltip(cameraOn),
            icon: Icon(cameraOn ? Icons.videocam : Icons.videocam_outlined),
            selected: cameraOn,
            onPressed: onToggleCamera,
            size: _controlButtonSize,
          ),
          _HoverVolumeButton(
            value: screenShareVolume,
            semanticLabel: '共享屏幕输出音量',
            onChanged: onScreenShareVolumeChanged,
            enabled: watchingRemoteScreenShare,
            child: ButtonIcon(
              tooltip: live_display.liveScreenShareControlTooltip(
                screenSharing,
              ),
              icon: Icon(
                screenSharing
                    ? Icons.stop_screen_share
                    : Icons.screen_share_outlined,
              ),
              selected: screenSharing,
              onPressed: onToggleShare,
              size: _controlButtonSize,
            ),
          ),
          ButtonIcon(
            tooltip: '离开',
            icon: const Icon(Icons.call_end),
            tone: ButtonTone.danger,
            onPressed: joining ? null : onLeave,
            size: _controlButtonSize,
          ),
        ];

        final musicBoxStrip = (joined && musicBoxEnabled && musicBox != null)
            ? _InlineMusicBox(
                state: musicBox!,
                expanded: musicBoxOpen,
                onTogglePlayback: onMusicBoxTogglePlayback,
                onSkip: onMusicBoxSkip,
                onToggleExpand: onToggleMusicBox,
              )
            : null;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (musicBoxStrip != null) ...[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: musicBoxStrip,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (!joined)
                    Button(
                      height: _controlButtonSize,
                      loading: joining,
                      icon: const Icon(Icons.call),
                      onPressed: onJoin,
                      child: const Text('加入'),
                    )
                  else
                    ...controls,
                  ButtonIcon(
                    tooltip: '收起语音频道',
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: onCollapse,
                    size: _controlButtonSize,
                  ),
                ],
              ),
            ],
          );
        }

        // The inline music box sits on its own centered row above the
        // transport buttons, so it never competes with them for horizontal
        // space — it just ellipsizes its title/artist within the 280 cap.
        final buttonRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!joined) ...[
              Button(
                height: _controlButtonSize,
                loading: joining,
                icon: const Icon(Icons.call),
                onPressed: onJoin,
                child: const Text('加入'),
              ),
              const SizedBox(width: 12),
            ] else ...[
              ..._withControlGaps(controls),
              const SizedBox(width: 10),
            ],
            ButtonIcon(
              tooltip: '收起语音频道',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: onCollapse,
              size: _controlButtonSize,
            ),
          ],
        );

        if (musicBoxStrip == null) return Center(child: buttonRow);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: musicBoxStrip,
              ),
            ),
            const SizedBox(height: 10),
            Center(child: buttonRow),
          ],
        );
      },
    );
  }
}

List<Widget> _withControlGaps(List<Widget> children) {
  return [
    for (var index = 0; index < children.length; index++) ...[
      if (index > 0) const SizedBox(width: 10),
      children[index],
    ],
  ];
}

const _hoverVolumePanelHeight = 144.0;
const _hoverVolumeTrackThickness = 7.0;
const _hoverVolumeThumbWidth = 26.0;
const _hoverVolumeThumbHeight = 7.0;
const _hoverVolumePercentWidth = 40.0;
const _hoverVolumePercentHeight = 18.0;
const _hoverVolumePercentGap = 6.0;

class _HoverVolumeButton extends StatefulWidget {
  const _HoverVolumeButton({
    required this.child,
    required this.value,
    required this.semanticLabel,
    required this.onChanged,
    this.enabled = true,
  });

  final Widget child;
  final double value;
  final String semanticLabel;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<_HoverVolumeButton> createState() => _HoverVolumeButtonState();
}

class _HoverVolumeButtonState extends State<_HoverVolumeButton> {
  static _HoverVolumeButtonState? _active;

  OverlayEntry? _overlayEntry;
  Timer? _hideTimer;
  bool _targetHovered = false;
  bool _overlayHovered = false;
  bool _dragging = false;
  late double _value = normalizedAudioVolume(widget.value);

  @override
  void didUpdateWidget(_HoverVolumeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = normalizedAudioVolume(widget.value);
      _markOverlayNeedsBuild();
    }
    if (!widget.enabled) _hideOverlay();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hideOverlay();
    super.dispose();
  }

  void _showOverlay() {
    if (!widget.enabled) return;
    _hideTimer?.cancel();
    if (_active != null && _active != this) {
      _active!._hideOverlay();
    }
    _active = this;
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.of(context);
    final targetBox = context.findRenderObject();
    final overlayBox = overlay.context.findRenderObject();
    if (targetBox is! RenderBox || overlayBox is! RenderBox) return;
    final targetOffset = targetBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final targetSize = targetBox.size;
    final overlaySize = overlayBox.size;
    final maxPanelLeft = (overlaySize.width - _controlButtonSize).clamp(
      0.0,
      double.infinity,
    );
    final maxPanelTop = (overlaySize.height - _hoverVolumePanelHeight).clamp(
      0.0,
      double.infinity,
    );
    final panelLeft =
        (targetOffset.dx + (targetSize.width - _controlButtonSize) / 2)
            .clamp(0.0, maxPanelLeft)
            .toDouble();
    final panelTop = (targetOffset.dy - _hoverVolumePanelHeight - 8)
        .clamp(0.0, maxPanelTop)
        .toDouble();
    _overlayEntry = OverlayEntry(
      builder: (context) =>
          _buildOverlay(context, left: panelLeft, top: panelTop),
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (_active == this) _active = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 90), () {
      if (!_targetHovered && !_overlayHovered && !_dragging) {
        _hideOverlay();
      }
    });
  }

  void _markOverlayNeedsBuild() {
    if (_overlayEntry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _overlayEntry?.markNeedsBuild();
    });
  }

  void _setValue(double value) {
    final normalized = normalizedAudioVolume(value);
    setState(() => _value = normalized);
    _overlayEntry?.markNeedsBuild();
    widget.onChanged(normalized);
  }

  Widget _buildOverlay(
    BuildContext context, {
    required double left,
    required double top,
  }) {
    return Positioned(
      left: left,
      top: top,
      width: _controlButtonSize,
      height: _hoverVolumePanelHeight,
      child: MouseRegion(
        onEnter: (_) {
          _overlayHovered = true;
          _showOverlay();
        },
        onExit: (_) {
          _overlayHovered = false;
          _scheduleHide();
        },
        child: _HoverVolumePanel(
          value: _value,
          semanticLabel: widget.semanticLabel,
          onChanged: _setValue,
          onChangeStart: (_) {
            _dragging = true;
            _showOverlay();
          },
          onChangeEnd: (_) {
            _dragging = false;
            _scheduleHide();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _targetHovered = true;
        _showOverlay();
      },
      onExit: (_) {
        _targetHovered = false;
        _scheduleHide();
      },
      child: widget.child,
    );
  }
}

class _HoverVolumePanel extends StatelessWidget {
  const _HoverVolumePanel({
    required this.value,
    required this.semanticLabel,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
  });

  final double value;
  final String semanticLabel;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizedAudioVolume(value);
    return Semantics(
      label: semanticLabel,
      value: audioVolumePercentText(normalized),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: UiColors.surface,
          borderRadius: BorderRadius.circular(UiRadii.md),
          border: Border.all(color: UiColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66080A0D),
              offset: Offset(0, 8),
              blurRadius: 18,
            ),
          ],
        ),
        child: SizedBox(
          key: ValueKey<String>('live-volume-panel:$semanticLabel'),
          width: _controlButtonSize,
          height: _hoverVolumePanelHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _HoverVolumeSlider(
                value: normalized,
                semanticLabel: semanticLabel,
                onChanged: onChanged,
                onChangeStart: onChangeStart,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverVolumeSlider extends StatefulWidget {
  const _HoverVolumeSlider({
    required this.value,
    required this.semanticLabel,
    required this.onChanged,
    required this.onChangeStart,
    required this.onChangeEnd,
  });

  final double value;
  final String semanticLabel;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_HoverVolumeSlider> createState() => _HoverVolumeSliderState();
}

class _HoverVolumeSliderState extends State<_HoverVolumeSlider> {
  int? _pointer;
  bool _thumbHovered = false;
  bool _dragging = false;
  late double _interactionValue = normalizedAudioVolume(widget.value);

  double get _value => normalizedAudioVolume(widget.value);

  double _fractionFromPosition(Offset localPosition, Size size) {
    final travel = size.height - _hoverVolumeThumbHeight;
    if (travel <= 0) return 0;
    return (1 - (localPosition.dy - _hoverVolumeThumbHeight / 2) / travel)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _emitFromPosition(Offset localPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final fraction = _fractionFromPosition(localPosition, renderObject.size);
    _interactionValue = fraction;
    widget.onChanged(fraction);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _interactionValue = _value;
    setState(() => _dragging = true);
    widget.onChangeStart(_interactionValue);
    _emitFromPosition(event.localPosition);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _emitFromPosition(event.localPosition);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    setState(() => _dragging = false);
    widget.onChangeEnd(_interactionValue);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    setState(() => _dragging = false);
    widget.onChangeEnd(_interactionValue);
  }

  @override
  void didUpdateWidget(_HoverVolumeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) _interactionValue = _value;
  }

  @override
  Widget build(BuildContext context) {
    final percentText = audioVolumePercentText(_value);
    final showPercent = _thumbHovered || _dragging;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: SizedBox(
          key: ValueKey<String>('live-volume-slider:${widget.semanticLabel}'),
          width: _hoverVolumeThumbWidth,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              final travel = (height - _hoverVolumeThumbHeight).clamp(
                0.0,
                double.infinity,
              );
              final thumbBottom = travel * _value;
              final labelBottom = _sidePercentBottom(
                height: height,
                thumbBottom: thumbBottom,
              );
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  _HoverVolumeTrack(),
                  Positioned(
                    left:
                        (_hoverVolumeThumbWidth - _hoverVolumeTrackThickness) /
                        2,
                    bottom: 0,
                    width: _hoverVolumeTrackThickness,
                    height: thumbBottom,
                    child: DecoratedBox(
                      key: ValueKey<String>(
                        'live-volume-fill:${widget.semanticLabel}',
                      ),
                      decoration: BoxDecoration(
                        color: UiColors.accent,
                        borderRadius: BorderRadius.all(
                          Radius.circular(_hoverVolumeTrackThickness / 2),
                        ),
                      ),
                    ),
                  ),
                  if (showPercent)
                    Positioned(
                      left: _hoverVolumeThumbWidth + _hoverVolumePercentGap,
                      bottom: labelBottom,
                      width: _hoverVolumePercentWidth,
                      height: _hoverVolumePercentHeight,
                      child: DecoratedBox(
                        key: ValueKey<String>(
                          'live-volume-percent:${widget.semanticLabel}',
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(UiRadii.sm),
                        ),
                        child: Center(
                          child: Text(
                            percentText,
                            style: UiTypography.label.copyWith(
                              color: Colors.black87,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    bottom: thumbBottom,
                    width: _hoverVolumeThumbWidth,
                    height: _hoverVolumeThumbHeight,
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _thumbHovered = true),
                      onExit: (_) => setState(() => _thumbHovered = false),
                      child: DecoratedBox(
                        key: ValueKey<String>(
                          'live-volume-thumb:${widget.semanticLabel}',
                        ),
                        decoration: const BoxDecoration(
                          color: UiColors.text,
                          borderRadius: BorderRadius.all(
                            Radius.circular(_hoverVolumeThumbHeight / 2),
                          ),
                        ),
                      ),
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

  double _sidePercentBottom({
    required double height,
    required double thumbBottom,
  }) {
    return (thumbBottom +
            (_hoverVolumeThumbHeight - _hoverVolumePercentHeight) / 2)
        .clamp(0.0, height - _hoverVolumePercentHeight)
        .toDouble();
  }
}

class _HoverVolumeTrack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: (_hoverVolumeThumbWidth - _hoverVolumeTrackThickness) / 2,
      top: 0,
      bottom: 0,
      width: _hoverVolumeTrackThickness,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: UiColors.surfacePressed,
          borderRadius: BorderRadius.circular(_hoverVolumeTrackThickness / 2),
        ),
      ),
    );
  }
}

/// The now-playing strip embedded inline at the right of the live control bar:
/// a small spinning vinyl, the current track, transport controls, and a button
/// that expands the full search + queue panel. Replaces the old standalone
/// music box button so the player no longer claims its own content column.
class _InlineMusicBox extends StatelessWidget {
  const _InlineMusicBox({
    required this.state,
    required this.expanded,
    required this.onTogglePlayback,
    required this.onSkip,
    required this.onToggleExpand,
  });

  final MusicBoxState state;
  final bool expanded;
  final VoidCallback onTogglePlayback;
  final VoidCallback onSkip;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final current = state.currentItem;
    final spinning = music_box_display.musicBoxRecordSpinning(state);
    final transport = music_box_display.musicBoxPrimaryTransport(state);
    final hasQueue = state.queue.isNotEmpty;
    final isPause =
        transport == music_box_display.MusicBoxTransportAction.pause;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: SizedBox(
        height: _controlButtonSize,
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                // Drop the skip button once the strip narrows so the title/artist
                // can keep shrinking instead of the whole strip bottoming out at
                // the full button-row width.
                final showSkip = constraints.maxWidth >= 175;
                return Row(
                  children: [
                    _VinylRecord(
                      spinning: spinning,
                      label: current?.title,
                      size: 26,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            current?.title ?? '未在播放',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: current == null
                                  ? UiColors.textMuted
                                  : UiColors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            current?.artist.isNotEmpty == true
                                ? current!.artist
                                : '点一首歌开始播放',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: UiColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    ButtonIcon(
                      tooltip: isPause ? '暂停' : '播放',
                      icon: Icon(isPause ? Icons.pause : Icons.play_arrow),
                      tone: ButtonTone.primary,
                      onPressed: hasQueue ? onTogglePlayback : null,
                      size: 30,
                    ),
                    if (showSkip) ...[
                      const SizedBox(width: 4),
                      ButtonIcon(
                        tooltip: '下一首',
                        icon: const Icon(Icons.skip_next),
                        onPressed: hasQueue ? onSkip : null,
                        size: 30,
                      ),
                    ],
                    const SizedBox(width: 4),
                    ButtonIcon(
                      tooltip: expanded ? '收起音乐盒' : '搜索 / 播放列表',
                      icon: const Icon(Icons.queue_music),
                      selected: expanded,
                      onPressed: onToggleExpand,
                      size: 30,
                    ),
                  ],
                );
              },
            ),
            // A hairline progress track pinned to the bottom edge of the strip,
            // spanning its full width — keeps the title/artist lines intact
            // while still reading playback position at a glance.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _InlineProgress(state: state),
            ),
          ],
        ),
      ),
    );
  }
}

/// A hairline server-authoritative progress track that hugs the bottom edge of
/// the inline music box. No time labels — just a 2px bar reflecting the
/// snapshot's reported position, set on a subtly darker groove so the unplayed
/// remainder still reads against the control bar.
class _InlineProgress extends StatelessWidget {
  const _InlineProgress({required this.state});

  final MusicBoxState state;

  @override
  Widget build(BuildContext context) {
    final progress = music_box_display.musicBoxProgress(state);
    return LinearProgressIndicator(
      value: progress.fraction,
      minHeight: 3,
      backgroundColor: UiColors.surfacePressed,
      valueColor: const AlwaysStoppedAnimation(UiColors.accent),
    );
  }
}
