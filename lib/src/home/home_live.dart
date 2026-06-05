part of 'home_page.dart';

class _LiveHeader extends StatelessWidget {
  const _LiveHeader({
    required this.room,
    required this.live,
    required this.joined,
    required this.joining,
    required this.onExpand,
    required this.onJoin,
    required this.onOpenRoomManagement,
    required this.onOpenRoomInfo,
    required this.onOpenMembers,
    required this.showManagementButton,
    required this.showMemberRequestBadge,
  });

  final RoomDetail room;
  final LiveState live;
  final bool joined;
  final bool joining;
  final VoidCallback onExpand;
  final VoidCallback onJoin;
  final VoidCallback onOpenRoomManagement;
  final VoidCallback onOpenRoomInfo;
  final VoidCallback onOpenMembers;
  final bool showManagementButton;
  final bool showMemberRequestBadge;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        final tight = constraints.maxWidth < 300;
        return PressableSurface(
          height: 72,
          onPressed: onExpand,
          backgroundColor: _primaryDarkRaised,
          borderColor: _borderColor,
          elevateOnHover: true,
          // Notch is shortened by the drop so its bottom still lines up with
          // the bottom of the window-control buttons.
          cornerCut: const Size(
            windowControlsWidth,
            titleBarHeight - windowDragHeight,
          ),
          cutCorner: SurfaceCorner.topRight,
          // Drop the whole header surface down so the top band stays free to
          // grab-and-drag the window, and inset its right edge so its right
          // shadow shows and the notch lines up with the inset buttons.
          margin: const EdgeInsets.only(
            top: windowDragHeight,
            right: windowControlsInset,
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: compact ? 16 : 22,
                    right: compact ? 8 : 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Flexible(
                        child: Text(
                          '${room.memberCount} members',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showManagementButton) ...[
                      ButtonIcon(
                        tooltip: '房间管理',
                        onPressed: onOpenRoomManagement,
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        size: 36,
                      ),
                      const SizedBox(width: 8),
                    ],
                    ButtonIcon(
                      tooltip: '房间信息',
                      onPressed: onOpenRoomInfo,
                      icon: const Icon(Icons.info_outline),
                      size: 36,
                    ),
                    const SizedBox(width: 8),
                    _BadgeAnchor(
                      show: showMemberRequestBadge,
                      child: ButtonIcon(
                        tooltip: '成员列表',
                        onPressed: onOpenMembers,
                        icon: const Icon(Icons.groups_2_outlined),
                        size: 36,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _LiveHeaderActions(
                live: live,
                joined: joined,
                joining: joining,
                onJoin: onJoin,
                showAvatars: !compact,
                showCount: !tight,
                compactButton: compact,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LiveHeaderActions extends StatelessWidget {
  const _LiveHeaderActions({
    required this.live,
    required this.joined,
    required this.joining,
    required this.onJoin,
    required this.showAvatars,
    required this.showCount,
    required this.compactButton,
  });

  final LiveState live;
  final bool joined;
  final bool joining;
  final VoidCallback onJoin;
  final bool showAvatars;
  final bool showCount;
  final bool compactButton;

  @override
  Widget build(BuildContext context) {
    final Widget joinControl = !joined
        ? (compactButton
              ? ButtonIcon(
                  tooltip: 'Join live',
                  onPressed: onJoin,
                  loading: joining,
                  icon: joining
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _cyan,
                          ),
                        )
                      : const Icon(Icons.call),
                  tone: ButtonTone.primary,
                  size: 36,
                )
              : Button(
                  onPressed: onJoin,
                  loading: joining,
                  width: double.infinity,
                  icon: joining
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _cyan,
                          ),
                        )
                      : const Icon(Icons.call),
                  tone: ButtonTone.primary,
                  height: 38,
                  child: const Text('Join'),
                ))
        : const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showAvatars) ...[
          _AvatarStack(users: live.participants.map((p) => p.user).toList()),
          const SizedBox(width: 10),
        ],
        if (showCount) ...[
          _LiveCount(count: live.participantCount),
          const SizedBox(width: 10),
        ],
        // Push the avatars/count further left of the cut column.
        const SizedBox(width: 16),
        // Join control nests under the cut: a full-width slot flush to the
        // right edge (aligned with the window buttons), dropped so it clears
        // the notch, with left/right padding inside the column. The
        // avatars/count above stay outside this column.
        SizedBox(
          width: windowControlsWidth,
          height: 72,
          child: Align(
            alignment: const Alignment(0, 0.7),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: joinControl,
            ),
          ),
        ),
      ],
    );
  }
}

class _LivePanel extends StatelessWidget {
  const _LivePanel({
    required this.room,
    required this.live,
    required this.liveSessionController,
    required this.joined,
    required this.joining,
    required this.micMuted,
    required this.headphonesMuted,
    required this.voiceBlocked,
    required this.cameraOn,
    required this.screenSharing,
    required this.speakingUserIds,
    required this.onJoin,
    required this.onLeave,
    required this.onToggleMic,
    required this.onToggleHeadphones,
    required this.onToggleCamera,
    required this.onToggleShare,
    required this.onCollapse,
    required this.onEnterFullScreen,
    required this.onOpenUserInfo,
    required this.localUserId,
  });

  final RoomDetail room;
  final LiveState live;
  final LiveSessionController liveSessionController;
  final bool joined;
  final bool joining;
  final bool micMuted;
  final bool headphonesMuted;
  final bool voiceBlocked;
  final bool cameraOn;
  final bool screenSharing;
  final Set<String> speakingUserIds;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  // Null when the local user is voice-blocked: the mic can't be toggled.
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleShare;
  final VoidCallback onCollapse;
  // Invoked with the share track to enter immersive full-screen.
  final void Function(LiveVideoTrack track) onEnterFullScreen;
  final ValueChanged<UserSummary> onOpenUserInfo;
  // The local user's id. Used to decide whether the staged share belongs to us:
  // a sharer can't full-screen their own share (a local screen-capture track
  // can attach to only one renderer at a time), so the button is hidden for it.
  final String localUserId;

  @override
  Widget build(BuildContext context) {
    final stageShare = live_display.pickLiveStageShare(
      liveSessionController.videoTracks,
      isScreenShare: (track) => track.isScreenShare,
      isLocal: (track) => track.isLocal,
    );
    final canFullScreen =
        stageShare != null &&
        live_display.canOpenLiveStageShareFullScreen(
          stageShareIdentity: stageShare.identity,
          localUserId: localUserId,
        );
    return ColoredBox(
      color: _primaryDarkLow,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
              child: Column(
                children: [
                  Text(
                    room.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (stageShare != null) ...[
                    Expanded(
                      flex: 3,
                      child: _ScreenShareStage(
                        track: stageShare,
                        label: live_display.liveScreenShareStageLabel(
                          live_display.liveParticipantDisplayName(
                            live,
                            stageShare.identity,
                          ),
                        ),
                        onToggleFullScreen: canFullScreen
                            ? () => onEnterFullScreen(stageShare)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: live.participants.isEmpty
                        ? const SizedBox.shrink()
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 220,
                                  mainAxisExtent: 156,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemCount: live.participants.length,
                            itemBuilder: (context, index) {
                              final participant = live.participants[index];
                              return _LiveParticipantCard(
                                participant: participant,
                                speaking: speakingUserIds.contains(
                                  participant.user.id,
                                ),
                                cameraTrack: liveSessionController.cameraFor(
                                  participant.user.id,
                                ),
                                onOpenUserInfo: () =>
                                    onOpenUserInfo(participant.user),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          _LiveControls(
            joined: joined,
            joining: joining,
            micMuted: micMuted,
            headphonesMuted: headphonesMuted,
            voiceBlocked: voiceBlocked,
            cameraOn: cameraOn,
            screenSharing: screenSharing,
            onJoin: onJoin,
            onLeave: onLeave,
            onToggleMic: onToggleMic,
            onToggleHeadphones: onToggleHeadphones,
            onToggleCamera: onToggleCamera,
            onToggleShare: onToggleShare,
            onCollapse: onCollapse,
          ),
        ],
      ),
    );
  }
}

class _LiveParticipantCard extends StatelessWidget {
  const _LiveParticipantCard({
    required this.participant,
    required this.speaking,
    required this.onOpenUserInfo,
    this.cameraTrack,
  });

  final LiveParticipant participant;
  final bool speaking;
  final VoidCallback onOpenUserInfo;
  final LiveVideoTrack? cameraTrack;

  @override
  Widget build(BuildContext context) {
    final state = live_display.liveParticipantTileState(
      participant,
      speaking: speaking,
    );
    final cameraTrack = this.cameraTrack;
    // When a live camera track is available, fill the tile with the video and
    // overlay the name + status; otherwise fall back to the avatar layout.
    if (cameraTrack != null) {
      return PressableSurface(
        height: 148,
        interactive: true,
        pressRequiresHover: true,
        onPressed: onOpenUserInfo,
        tooltip: '查看用户信息',
        backgroundColor: _primaryDark,
        selectedBackgroundColor: _primaryDark,
        borderColor: state.highlighted ? _cyan : _borderColor,
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LiveVideoTrackView(
              track: cameraTrack,
              fit: LiveVideoTrackFit.cover,
              mirrorLocal: true,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _VideoTileFooter(
                name: participant.user.displayName,
                micMuted: state.micMutedForDisplay,
                speaking: speaking,
                screenSharing: participant.screenSharing,
              ),
            ),
          ],
        ),
      );
    }
    return PressableSurface(
      height: 148,
      interactive: true,
      pressRequiresHover: true,
      onPressed: onOpenUserInfo,
      tooltip: '查看用户信息',
      backgroundColor: _primaryDarkRaised,
      selectedBackgroundColor: _primaryDarkRaised,
      borderColor: _borderColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _UserInfoTapTarget(
            tooltip: '查看用户信息',
            onTap: onOpenUserInfo,
            child: _Avatar(
              label: participant.user.displayName,
              imageUrl: AppConfigScope.of(
                context,
              ).resolveAssetUrl(participant.user.avatarUrl),
              defaultAvatarKey: participant.user.defaultAvatarKey,
              size: 54,
              borderColor: state.highlighted ? _cyan : _borderColor,
              borderWidth: state.highlighted ? 2.4 : 1,
            ),
          ),
          const SizedBox(height: 12),
          _UserInfoTapTarget(
            tooltip: '查看用户信息',
            onTap: onOpenUserInfo,
            child: Text(
              participant.user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: state.highlighted ? _textPrimary : _textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              _StatusIcon(
                icon: state.micMutedForDisplay ? Icons.mic_off : Icons.mic,
                active: state.micActive,
              ),
              _StatusIcon(icon: Icons.videocam, active: participant.cameraOn),
              _StatusIcon(
                icon: Icons.screen_share,
                active: participant.screenSharing,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Large video stage for the active screen share, shown above the participant
/// grid in the live panel.
class _ScreenShareStage extends StatelessWidget {
  const _ScreenShareStage({
    required this.track,
    required this.label,
    this.onToggleFullScreen,
  });

  final LiveVideoTrack track;
  final String label;
  // When non-null, a fullscreen-enter button is shown in the top-right corner.
  final VoidCallback? onToggleFullScreen;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDark,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LiveVideoTrackView(track: track),
          Positioned(left: 0, top: 0, child: _StageBadge(label: label)),
          if (onToggleFullScreen != null)
            Positioned(
              right: 8,
              top: 8,
              child: _StageIconButton(
                tooltip: '全屏',
                icon: Icons.fullscreen,
                onPressed: onToggleFullScreen!,
              ),
            ),
        ],
      ),
    );
  }
}

/// Translucent square icon button overlaid on the screen-share video (e.g. the
/// fullscreen toggle). Kept lightweight so it reads as an overlay control.
class _StageIconButton extends StatefulWidget {
  const _StageIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_StageIconButton> createState() => _StageIconButtonState();
}

class _StageIconButtonState extends State<_StageIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _primaryDark.withValues(alpha: _hover ? 0.92 : 0.7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _hover ? _cyan : _borderColor),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 20,
              color: _hover ? _cyan : _textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Immersive full-screen view of a single screen share. Fills the window over a
/// black backdrop with the video letterboxed inside. A floating control bar
/// (label + exit) auto-hides after a few seconds of mouse inactivity and
/// reappears on movement. Esc exits. The caller drives real OS full-screen and
/// hides the rest of the app chrome; this widget owns only the in-content UI.
class _FullScreenShare extends StatefulWidget {
  const _FullScreenShare({
    required this.track,
    required this.label,
    required this.onExit,
  });

  final LiveVideoTrack track;
  final String label;
  final VoidCallback onExit;

  @override
  State<_FullScreenShare> createState() => _FullScreenShareState();
}

class _FullScreenShareState extends State<_FullScreenShare> {
  final FocusNode _focusNode = FocusNode();
  Timer? _hideTimer;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    // Grab focus so Esc is delivered here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _wake() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        onHover: (_) => _wake(),
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LiveVideoTrackView(track: widget.track),
              // Top control bar: label on the left, exit on the right.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.screen_share,
                            size: 16,
                            color: _cyan,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _StageIconButton(
                            tooltip: '退出全屏 (Esc)',
                            icon: Icons.fullscreen_exit,
                            onPressed: widget.onExit,
                          ),
                        ],
                      ),
                    ),
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

class _StageBadge extends StatelessWidget {
  const _StageBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: _primaryDark.withValues(alpha: 0.82),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.screen_share, size: 14, color: _cyan),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Name + status overlay shown along the bottom of a participant's camera tile.
class _VideoTileFooter extends StatelessWidget {
  const _VideoTileFooter({
    required this.name,
    required this.micMuted,
    required this.speaking,
    required this.screenSharing,
  });

  final String name;
  final bool micMuted;
  final bool speaking;
  final bool screenSharing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_primaryDark.withValues(alpha: 0.85), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          Icon(
            micMuted ? Icons.mic_off : Icons.mic,
            size: 14,
            color: micMuted ? _textMuted : (speaking ? _cyan : _textSecondary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (screenSharing) ...[
            const SizedBox(width: 6),
            const Icon(Icons.screen_share, size: 14, color: _cyan),
          ],
        ],
      ),
    );
  }
}

/// Desktop screen-share source picker. Lists screens and windows with live
/// thumbnails and returns the chosen [ScreenSource], styled to match the app.
class _ScreenShareDialog extends StatefulWidget {
  const _ScreenShareDialog({
    required this.loadSources,
    required this.refreshThumbnails,
  });

  final Future<List<ScreenSource>> Function() loadSources;
  final Future<void> Function() refreshThumbnails;

  @override
  State<_ScreenShareDialog> createState() => _ScreenShareDialogState();
}

class _ScreenShareDialogState extends State<_ScreenShareDialog> {
  live_display.LiveScreenSourcePickerState<ScreenSource> _pickerState =
      const live_display.LiveScreenSourcePickerState();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(widget.refreshThumbnails());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!live_display.canLoadLiveScreenSources(_pickerState)) return;
    _pickerState = live_display.liveScreenSourceLoadStarted(_pickerState);
    try {
      final sources = await widget.loadSources();
      if (!mounted) return;
      setState(
        () => _pickerState = live_display.liveScreenSourceLoadSucceeded(
          state: _pickerState,
          sources: sources,
          sourceId: (source) => source.id,
        ),
      );
      unawaited(widget.refreshThumbnails());
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _pickerState = live_display.liveScreenSourceLoadFailed(
          state: _pickerState,
          failure: e,
        ),
      );
    }
  }

  void _confirm() {
    final source = _selectedSource;
    if (source == null) return;
    Navigator.of(context).pop(source);
  }

  ScreenSource? get _selectedSource {
    return live_display.liveScreenSourceById(
      _pickerState.sources,
      selectedId: _pickerState.selectedId,
      sourceId: (source) => source.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = _pickerState.sources;
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '选择共享内容',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(child: _buildBody(sources)),
              if (_pickerState.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _pickerState.error!,
                  style: const TextStyle(color: _danger),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    onPressed: () => Navigator.of(context).pop(),
                    height: 38,
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  Button(
                    onPressed:
                        live_display.canConfirmLiveScreenSourceSelection(
                          _pickerState.selectedId,
                        )
                        ? _confirm
                        : null,
                    tone: ButtonTone.primary,
                    height: 38,
                    child: const Text('共享'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(List<ScreenSource>? sources) {
    final bodyState = live_display.liveScreenSourceListBodyState(sources);
    return switch (bodyState) {
      live_display.LiveScreenSourceListBodyState.loading => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(color: _cyan)),
      ),
      live_display.LiveScreenSourceListBodyState.empty => const SizedBox(
        height: 200,
        child: Center(
          child: Text('没有可共享的屏幕或窗口', style: TextStyle(color: _textMuted)),
        ),
      ),
      live_display.LiveScreenSourceListBodyState.results => GridView.builder(
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 158,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: sources!.length,
        itemBuilder: (context, index) {
          final source = sources[index];
          final selected = live_display.liveScreenSourceSelected(
            source,
            selectedId: _pickerState.selectedId,
            sourceId: (source) => source.id,
          );
          return _ScreenSourceTile(
            source: source,
            selected: selected,
            onTap: () => setState(
              () => _pickerState = live_display.liveScreenSourceSelectedChanged(
                _pickerState,
                source.id,
              ),
            ),
          );
        },
      ),
    };
  }
}

class _ScreenSourceThumbnail extends StatefulWidget {
  const _ScreenSourceThumbnail({
    required this.source,
    required this.fit,
    required this.iconSize,
  });

  final ScreenSource source;
  final BoxFit fit;
  final double iconSize;

  @override
  State<_ScreenSourceThumbnail> createState() => _ScreenSourceThumbnailState();
}

class _ScreenSourceThumbnailState extends State<_ScreenSourceThumbnail> {
  Uint8List? _thumbnail;
  Object? _imageError;
  StreamSubscription<Uint8List>? _thumbnailSubscription;

  @override
  void initState() {
    super.initState();
    _bindSource(widget.source);
  }

  @override
  void didUpdateWidget(_ScreenSourceThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) _bindSource(widget.source);
  }

  @override
  void dispose() {
    unawaited(_thumbnailSubscription?.cancel());
    super.dispose();
  }

  void _bindSource(ScreenSource source) {
    unawaited(_thumbnailSubscription?.cancel());
    _thumbnail = source.thumbnail;
    _imageError = null;
    _thumbnailSubscription = source.thumbnailUpdates?.listen((thumbnail) {
      if (!mounted) return;
      setState(() {
        _thumbnail = thumbnail;
        _imageError = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final thumbnail = live_display.visibleLiveScreenSourceThumbnail(
      thumbnail: _thumbnail,
      imageError: _imageError,
    );
    if (thumbnail == null) {
      return _ScreenSourceThumbnailFallback(iconSize: widget.iconSize);
    }

    return ClipRect(
      child: ColoredBox(
        color: _primaryDarkLow,
        child: Image.memory(
          thumbnail,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _imageError = error);
            });
            return _ScreenSourceThumbnailFallback(iconSize: widget.iconSize);
          },
        ),
      ),
    );
  }
}

class _ScreenSourceThumbnailFallback extends StatelessWidget {
  const _ScreenSourceThumbnailFallback({required this.iconSize});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDarkLow,
      child: Center(
        child: Icon(Icons.desktop_windows, color: _textMuted, size: iconSize),
      ),
    );
  }
}

class _ScreenSourceTile extends StatelessWidget {
  const _ScreenSourceTile({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final ScreenSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableSurface(
      height: 158,
      interactive: true,
      pressRequiresHover: true,
      selected: selected,
      onPressed: onTap,
      backgroundColor: _primaryDark,
      selectedBackgroundColor: _primaryDark,
      borderColor: _borderColor,
      selectedBorderColor: _cyan,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ScreenSourceThumbnail(
              source: source,
              fit: BoxFit.contain,
              iconSize: 32,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.desktop_windows,
                size: 13,
                color: selected ? _cyan : _textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _textPrimary : _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveControls extends StatelessWidget {
  const _LiveControls({
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
  // Null disables the mic button (the local user is voice-blocked).
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleShare;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final micControl = live_display.liveMicControlState(
      micMuted: micMuted,
      voiceBlocked: voiceBlocked,
    );
    return Container(
      height: 86,
      color: _primaryDarkLow,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!joined)
            _LiveControlKey(
              tooltip: 'Join',
              icon: Icons.call,
              active: true,
              busy: joining,
              onPressed: onJoin,
            )
          else ...[
            _LiveControlKey(
              tooltip: micControl.tooltip,
              icon: micControl.mutedForDisplay ? Icons.mic_off : Icons.mic,
              active: micControl.active,
              onPressed: micControl.enabled ? onToggleMic : null,
            ),
            _LiveControlKey(
              tooltip: live_display.liveHeadphonesControlTooltip(
                headphonesMuted,
              ),
              icon: headphonesMuted ? Icons.headset_off : Icons.headset,
              active: !headphonesMuted,
              onPressed: onToggleHeadphones,
            ),
            _LiveControlKey(
              tooltip: live_display.liveCameraControlTooltip(cameraOn),
              icon: Icons.videocam,
              active: cameraOn,
              onPressed: onToggleCamera,
            ),
            _LiveControlKey(
              tooltip: live_display.liveScreenShareControlTooltip(
                screenSharing,
              ),
              icon: Icons.screen_share,
              active: screenSharing,
              onPressed: onToggleShare,
            ),
            _LiveControlKey(
              tooltip: 'Leave',
              icon: Icons.call_end,
              active: true,
              danger: true,
              busy: joining,
              onPressed: onLeave,
            ),
          ],
          _LiveControlKey(
            tooltip: 'Collapse',
            icon: Icons.keyboard_arrow_up,
            active: false,
            onPressed: onCollapse,
          ),
        ],
      ),
    );
  }
}

class _LiveControlKey extends StatelessWidget {
  const _LiveControlKey({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
    this.danger = false,
    this.busy = false,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tone = danger
        ? ButtonTone.danger
        : active
        ? ButtonTone.primary
        : ButtonTone.neutral;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ButtonIcon(
        tooltip: tooltip,
        onPressed: onPressed,
        loading: busy,
        tone: tone,
        size: 48,
        icon: busy
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: danger ? _danger : _cyan,
                ),
              )
            : Icon(icon),
      ),
    );
  }
}
