part of 'chat_pane.dart';

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.title,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    required this.memberCount,
    required this.onlineMemberCount,
    required this.liveParticipantCount,
    required this.loading,
    required this.onLivePressed,
    required this.onMembersPressed,
    required this.onSettingsPressed,
  });

  final String title;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final int? memberCount;
  final int? onlineMemberCount;
  final int? liveParticipantCount;
  final bool loading;
  final VoidCallback onLivePressed;
  final VoidCallback onMembersPressed;
  final VoidCallback onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    const headerTopInset = _chatHeaderVisualTopInset - _headerSurfaceHoverLift;
    return SizedBox(
      height: _chatHeaderHeight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _chatHeaderHorizontalInset,
          headerTopInset,
          _chatHeaderHorizontalInset,
          _chatHeaderBottomInset,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _LiveChannelHeaderCard(
                title: title,
                avatarUrl: avatarUrl,
                defaultAvatarKey: defaultAvatarKey,
                memberCount: memberCount,
                onlineMemberCount: onlineMemberCount,
                liveParticipantCount: liveParticipantCount,
                onPressed: onLivePressed,
              ),
            ),
            const SizedBox(width: 10),
            _RoomHeaderActions(
              loading: loading,
              onMembersPressed: onMembersPressed,
              onSettingsPressed: onSettingsPressed,
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveChannelHeaderCard extends StatelessWidget {
  const _LiveChannelHeaderCard({
    required this.title,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    required this.memberCount,
    required this.onlineMemberCount,
    required this.liveParticipantCount,
    required this.onPressed,
  });

  final String title;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final int? memberCount;
  final int? onlineMemberCount;
  final int? liveParticipantCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final liveActive = (liveParticipantCount ?? 0) > 0;
    return PressableSurface(
      width: double.infinity,
      height: _liveHeaderCardHeight,
      hoverLift: _headerSurfaceHoverLift,
      baseDepth: _headerSurfaceBaseDepth,
      borderRadius: UiRadii.md,
      backgroundColor: UiColors.surface,
      selectedBackgroundColor: UiColors.selected,
      borderColor: UiColors.border,
      selectedBorderColor: UiColors.selectedBorder,
      selected: liveActive,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tooltip: '进入直播频道',
      onPressed: onPressed,
      child: Row(
        children: [
          Avatar(
            label: title,
            imageUrl: AppConfigScope.of(context).resolveAssetUrl(avatarUrl),
            defaultAvatarKey: defaultAvatarKey,
            size: 34,
            active: liveActive,
            activeBorderWidth: 1.1,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      liveActive ? Icons.volume_up : Icons.volume_up_outlined,
                      color: liveActive ? UiColors.accent : UiColors.text,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '进入直播频道',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UiTypography.label.copyWith(
                          color: liveActive ? UiColors.accent : UiColors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$title - ${_roomMeta(memberCount: memberCount, onlineMemberCount: onlineMemberCount, liveParticipantCount: liveParticipantCount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: UiTypography.label.copyWith(color: UiColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomHeaderActions extends StatelessWidget {
  const _RoomHeaderActions({
    required this.loading,
    required this.onMembersPressed,
    required this.onSettingsPressed,
  });

  final bool loading;
  final VoidCallback onMembersPressed;
  final VoidCallback onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _headerActionButtonSize,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderIconButton(
                tooltip: '房间成员',
                icon: Icons.groups_outlined,
                onPressed: onMembersPressed,
              ),
              const SizedBox(height: _headerActionGap),
              _HeaderIconButton(
                tooltip: '房间操作',
                icon: Icons.more_horiz,
                onPressed: onSettingsPressed,
              ),
            ],
          ),
          if (loading)
            const Positioned(
              top: 0,
              right: 0,
              child: SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: UiColors.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableSurface(
      width: _headerActionButtonSize,
      height: _headerActionButtonSize,
      hoverLift: _headerSurfaceHoverLift,
      baseDepth: _headerSurfaceBaseDepth,
      borderRadius: UiRadii.sm,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      backgroundColor: UiColors.surface,
      borderColor: UiColors.border,
      child: Center(child: Icon(icon, size: 16, color: UiColors.textSecondary)),
    );
  }
}

String _roomMeta({
  required int? memberCount,
  required int? onlineMemberCount,
  required int? liveParticipantCount,
}) {
  final parts = <String>[];
  final members = memberCount ?? 0;
  if (members > 0) parts.add('$members 名成员');
  final online = onlineMemberCount ?? 0;
  if (online > 0) parts.add('$online 人在线');
  final live = liveParticipantCount ?? 0;
  if (live > 0) parts.add('$live 语音');
  return parts.isEmpty ? '就绪' : parts.join(' - ');
}
