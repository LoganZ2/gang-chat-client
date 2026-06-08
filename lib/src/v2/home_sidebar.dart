import 'package:flutter/material.dart';

import '../protocol/models.dart';
import '../ui/ui.dart';

const _sidebarHorizontalPadding = 14.0;
const _sidebarTopPadding = 16.0;
const _sidebarBottomPadding = 16.0;
const _serverCardHeight = 68.0;
const _serverCardHoverLift = 2.0;
const _serverCardBaseDepth = 4.0;
const _serverCardGap = 10.0;
const _footerButtonSize = 38.0;
const _footerButtonGap = 8.0;
const _footerButtonOuterHeight = _footerButtonSize + 3.0 + 5.0;
const _compactFooterBreakpoint = 130.0;
const _compactSummaryBreakpoint = 88.0;

class HomeSidebar extends StatelessWidget {
  const HomeSidebar({
    super.key,
    required this.width,
    required this.currentUser,
    required this.servers,
    required this.selectedServerId,
    required this.joinedLiveRoomId,
    required this.loading,
    required this.error,
    required this.settingsActive,
    required this.onServerSelected,
    required this.onOpenSettings,
    required this.onLogout,
    this.includeWindowChromeOffset = true,
  });

  final double width;
  final CurrentUser currentUser;
  final List<RoomCard> servers;
  final String? selectedServerId;
  final String? joinedLiveRoomId;
  final bool loading;
  final String? error;
  final bool settingsActive;
  final bool includeWindowChromeOffset;
  final ValueChanged<RoomCard> onServerSelected;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final chrome = WindowChromeInsets.of(context);
    final topChromeOffset = includeWindowChromeOffset
        ? chrome.sidebarTopOffset
        : 0.0;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: UiColors.surfaceLow,
          border: Border(right: BorderSide(color: UiColors.border)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _sidebarHorizontalPadding,
            _sidebarTopPadding + topChromeOffset,
            _sidebarHorizontalPadding,
            _sidebarBottomPadding,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showSummary =
                  constraints.maxHeight >= _compactSummaryBreakpoint;
              final showFooter =
                  constraints.maxHeight >= _compactFooterBreakpoint;
              return Column(
                children: [
                  if (showSummary) ...[
                    _UserSummaryBar(user: currentUser),
                    SizedBox(height: showFooter ? 14 : 10),
                  ],
                  Expanded(child: _buildServerList()),
                  if (showFooter) ...[
                    const SizedBox(height: 12),
                    _SidebarFooter(
                      settingsActive: settingsActive,
                      onOpenSettings: onOpenSettings,
                      onLogout: onLogout,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildServerList() {
    if (servers.isEmpty && loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: UiColors.accent,
          ),
        ),
      );
    }

    if (servers.isEmpty && error != null) {
      return Center(
        child: Icon(Icons.error_outline, color: UiColors.danger, size: 22),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: servers.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: _serverCardGap),
      itemBuilder: (context, index) {
        final server = servers[index];
        return _ServerCard(
          server: server,
          selected: server.id == selectedServerId,
          voiceJoined: server.id == joinedLiveRoomId,
          onPressed: () => onServerSelected(server),
        );
      },
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.settingsActive,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final bool settingsActive;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _footerButtonOuterHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ButtonIcon(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            selected: settingsActive,
            onPressed: onOpenSettings,
            size: _footerButtonSize,
          ),
          const SizedBox(width: _footerButtonGap),
          ButtonIcon(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
            onPressed: onLogout,
            size: _footerButtonSize,
          ),
        ],
      ),
    );
  }
}

class _UserSummaryBar extends StatelessWidget {
  const _UserSummaryBar({required this.user});

  final CurrentUser user;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('home-sidebar-user-summary'),
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(color: UiColors.border),
      ),
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Avatar(
                label: user.displayName,
                imageUrl: AppConfigScope.of(
                  context,
                ).resolveAssetUrl(user.avatarUrl),
                defaultAvatarKey: user.defaultAvatarKey,
                size: 38,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: UiColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _UserPresenceLabel(label: _userStatus(user)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserPresenceLabel extends StatelessWidget {
  const _UserPresenceLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            color: UiColors.accent,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(dimension: 7),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.label.copyWith(color: UiColors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.selected,
    required this.voiceJoined,
    required this.onPressed,
  });

  final RoomCard server;
  final bool selected;
  final bool voiceJoined;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableSurface(
      width: double.infinity,
      height: _serverCardHeight,
      hoverLift: _serverCardHoverLift,
      baseDepth: _serverCardBaseDepth,
      selected: selected,
      backgroundColor: UiColors.surfaceLow,
      selectedBackgroundColor: UiColors.selected,
      pressedBackgroundColor: UiColors.surfacePressed,
      borderColor: UiColors.border,
      selectedBorderColor: UiColors.selectedBorder,
      borderRadius: UiRadii.md,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      onPressed: onPressed,
      child: Row(
        children: [
          _ServerAvatar(server: server, selected: selected),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UiColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _serverMeta(server),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: UiTypography.label.copyWith(
                    color: selected
                        ? UiColors.textSecondary
                        : UiColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (voiceJoined) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: '已加入语音',
              child: Icon(Icons.volume_up, color: UiColors.accent, size: 17),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServerAvatar extends StatelessWidget {
  const _ServerAvatar({required this.server, required this.selected});

  final RoomCard server;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Avatar(
              label: server.displayName,
              imageUrl: server.avatarUrl,
              defaultAvatarKey: server.defaultAvatarKey,
              size: 40,
              active: selected,
              activeBorderWidth: 1.2,
            ),
          ),
          if (server.unreadCount > 0)
            Positioned(
              top: 0,
              right: 0,
              child: _UnreadBadge(count: server.unreadCount),
            ),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE14747),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF35191D), width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _userStatus(CurrentUser user) {
  final status = user.status?.trim();
  if (status != null && status.isNotEmpty) return status;
  return '在线';
}

String _serverMeta(RoomCard server) {
  final parts = ['${server.memberCount} 名成员'];
  if (server.liveParticipantCount > 0) {
    parts.add('${server.liveParticipantCount} 直播中');
  }
  return parts.join(' · ');
}
