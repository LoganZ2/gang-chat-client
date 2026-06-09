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
    required this.onJoin,
    required this.onLeave,
    required this.onToggleMic,
    required this.onToggleHeadphones,
    required this.onToggleCamera,
    required this.onToggleShare,
    required this.onCollapse,
  });

  final bool joined;
  final bool joining;
  final bool micMuted;
  final bool headphonesMuted;
  final bool voiceBlocked;
  final bool cameraOn;
  final bool screenSharing;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleShare;
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

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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

        return Center(
          child: Row(
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
          ),
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
