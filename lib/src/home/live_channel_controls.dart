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
    required this.musicBox,
    required this.musicBoxEnabled,
    required this.musicBoxOpen,
    required this.onJoin,
    required this.onLeave,
    required this.onToggleMic,
    required this.onToggleHeadphones,
    required this.onToggleCamera,
    required this.onToggleShare,
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
  final MusicBoxState? musicBox;
  final bool musicBoxEnabled;
  final bool musicBoxOpen;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleShare;
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
          ButtonIcon(
            tooltip: micControl.tooltip,
            icon: Icon(micControl.mutedForDisplay ? Icons.mic_off : Icons.mic),
            selected: micControl.active,
            onPressed: micControl.enabled ? onToggleMic : null,
            size: _controlButtonSize,
          ),
          ButtonIcon(
            tooltip: live_display.liveHeadphonesControlTooltip(headphonesMuted),
            icon: Icon(headphonesMuted ? Icons.headset_off : Icons.headphones),
            selected: !headphonesMuted,
            onPressed: onToggleHeadphones,
            size: _controlButtonSize,
          ),
          ButtonIcon(
            tooltip: live_display.liveCameraControlTooltip(cameraOn),
            icon: Icon(cameraOn ? Icons.videocam : Icons.videocam_outlined),
            selected: cameraOn,
            onPressed: onToggleCamera,
            size: _controlButtonSize,
          ),
          ButtonIcon(
            tooltip: live_display.liveScreenShareControlTooltip(screenSharing),
            icon: Icon(
              screenSharing
                  ? Icons.stop_screen_share
                  : Icons.screen_share_outlined,
            ),
            selected: screenSharing,
            onPressed: onToggleShare,
            size: _controlButtonSize,
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
                    tooltip: '收起直播频道',
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
              tooltip: '收起直播频道',
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
