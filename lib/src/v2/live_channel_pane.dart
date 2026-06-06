import 'package:flutter/material.dart';

import '../app/live_display.dart' as live_display;
import '../live/live_session.dart';
import '../live/live_video_track_view.dart';
import '../protocol/models.dart';
import '../ui/ui.dart';

part 'live_channel_members.dart';
part 'live_channel_media.dart';
part 'live_channel_controls.dart';

const _paneEdgeInset = 14.0;
const _paneTopInset = _paneEdgeInset;
const _liveRoomRadius = UiRadii.md;
const _liveRoomPadding = 18.0;
const _memberCardWidth = 154.0;
const _memberCardHeight = 126.0;
const _controlButtonSize = 44.0;
const _liveRoomBackground = UiColors.surfaceLow;
const _liveRoomBorder = UiColors.border;
const _memberSpeakingBackground = Color(0xFF252A34);
const _memberIdleBackground = Color(0xFF1D2328);

enum LiveStageSelectionMode { none, track }

class LiveStageSelection {
  const LiveStageSelection.track({
    required String this.identity,
    required bool this.isScreenShare,
  }) : mode = LiveStageSelectionMode.track;

  const LiveStageSelection.none()
    : mode = LiveStageSelectionMode.none,
      identity = null,
      isScreenShare = null;

  factory LiveStageSelection.fromTrack(LiveVideoTrack track) {
    return LiveStageSelection.track(
      identity: track.identity,
      isScreenShare: track.isScreenShare,
    );
  }

  final LiveStageSelectionMode mode;
  final String? identity;
  final bool? isScreenShare;
}

class LiveChannelPane extends StatefulWidget {
  const LiveChannelPane({
    super.key,
    required this.title,
    required this.avatarUrl,
    required this.live,
    required this.currentUser,
    required this.loading,
    required this.joined,
    required this.joining,
    required this.micMuted,
    required this.headphonesMuted,
    required this.voiceBlocked,
    required this.cameraOn,
    required this.screenSharing,
    required this.speakingUserIds,
    required this.videoTracks,
    required this.stageSelection,
    required this.onStageSelectionChanged,
    required this.onEnterFullScreen,
    required this.onBackToChat,
    required this.onJoin,
    required this.onLeave,
    required this.onToggleMic,
    required this.onToggleHeadphones,
    required this.onToggleCamera,
    required this.onToggleShare,
  });

  final String title;
  final String? avatarUrl;
  final LiveState? live;
  final CurrentUser currentUser;
  final bool loading;
  final bool joined;
  final bool joining;
  final bool micMuted;
  final bool headphonesMuted;
  final bool voiceBlocked;
  final bool cameraOn;
  final bool screenSharing;
  final Set<String> speakingUserIds;
  final List<LiveVideoTrack> videoTracks;
  final LiveStageSelection? stageSelection;
  final ValueChanged<LiveStageSelection?> onStageSelectionChanged;
  final ValueChanged<LiveVideoTrack> onEnterFullScreen;
  final VoidCallback onBackToChat;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleShare;

  @override
  State<LiveChannelPane> createState() => _LiveChannelPaneState();
}

class _LiveChannelPaneState extends State<LiveChannelPane> {
  LiveVideoTrack? _resolveStageTrack() {
    return _resolveLiveStageTrack(
      tracks: widget.videoTracks,
      selection: widget.stageSelection,
    );
  }

  void _selectStage(LiveVideoTrack track) {
    widget.onStageSelectionChanged(LiveStageSelection.fromTrack(track));
  }

  void _exitStage() {
    widget.onStageSelectionChanged(const LiveStageSelection.none());
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.live?.participants ?? const <LiveParticipant>[];
    final stageTrack = _resolveStageTrack();

    return ColoredBox(
      color: UiColors.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _paneEdgeInset,
          _paneTopInset,
          _paneEdgeInset,
          _paneEdgeInset,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _liveRoomBackground,
            borderRadius: BorderRadius.circular(_liveRoomRadius),
            border: Border.all(color: _liveRoomBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66080A0D),
                offset: Offset(0, 10),
                blurRadius: 22,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(_liveRoomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LiveRoomHeader(title: widget.title),
                const SizedBox(height: 16),
                Expanded(
                  child: Column(
                    children: [
                      if (stageTrack != null) ...[
                        Expanded(
                          flex: 3,
                          child: _LiveMediaStage(
                            track: stageTrack,
                            label: liveStageTrackLabel(widget.live, stageTrack),
                            onExit: _exitStage,
                            onFullScreen: () =>
                                widget.onEnterFullScreen(stageTrack),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Expanded(
                        flex: stageTrack == null ? 1 : 2,
                        child: _LiveMemberStage(
                          participants: participants,
                          currentUser: widget.currentUser,
                          speakingUserIds: widget.speakingUserIds,
                          videoTracks: widget.videoTracks,
                          stageTrack: stageTrack,
                          onSelectStage: _selectStage,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _LiveControlBar(
                  joined: widget.joined,
                  joining: widget.joining || widget.loading,
                  micMuted: widget.micMuted,
                  headphonesMuted: widget.headphonesMuted,
                  voiceBlocked: widget.voiceBlocked,
                  cameraOn: widget.cameraOn,
                  screenSharing: widget.screenSharing,
                  onJoin: widget.onJoin,
                  onLeave: widget.onLeave,
                  onToggleMic: widget.onToggleMic,
                  onToggleHeadphones: widget.onToggleHeadphones,
                  onToggleCamera: widget.onToggleCamera,
                  onToggleShare: widget.onToggleShare,
                  onCollapse: widget.onBackToChat,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
