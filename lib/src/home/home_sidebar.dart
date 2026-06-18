import 'package:flutter/material.dart';

import '../app/room_display.dart' as room_display;
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
    required this.searchQuery,
    required this.loading,
    required this.error,
    required this.settingsActive,
    required this.createRoomActive,
    required this.notificationsActive,
    required this.logoutActive,
    required this.hasPendingNotifications,
    required this.onServerSelected,
    required this.onCreateRoom,
    required this.onOpenNotifications,
    required this.onOpenSettings,
    required this.onLogout,
    this.includeWindowChromeOffset = true,
  });

  final double width;
  final CurrentUser currentUser;
  final List<RoomCard> servers;
  final String? selectedServerId;
  final String? joinedLiveRoomId;
  final String searchQuery;
  final bool loading;
  final String? error;
  final bool settingsActive;
  final bool createRoomActive;
  final bool notificationsActive;
  final bool logoutActive;
  final bool hasPendingNotifications;
  final bool includeWindowChromeOffset;
  final ValueChanged<RoomCard> onServerSelected;
  final VoidCallback onCreateRoom;
  final VoidCallback onOpenNotifications;
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
                    _UserSummaryBar(
                      user: currentUser,
                      logoutActive: logoutActive,
                      onLogout: onLogout,
                    ),
                    SizedBox(height: showFooter ? 14 : 10),
                  ],
                  Expanded(child: _buildServerList()),
                  if (showFooter) ...[
                    const SizedBox(height: 12),
                    _SidebarFooter(
                      settingsActive: settingsActive,
                      createRoomActive: createRoomActive,
                      notificationsActive: notificationsActive,
                      hasPendingNotifications: hasPendingNotifications,
                      onCreateRoom: onCreateRoom,
                      onOpenNotifications: onOpenNotifications,
                      onOpenSettings: onOpenSettings,
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
          searchQuery: searchQuery,
          onPressed: () => onServerSelected(server),
        );
      },
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.settingsActive,
    required this.createRoomActive,
    required this.notificationsActive,
    required this.hasPendingNotifications,
    required this.onCreateRoom,
    required this.onOpenNotifications,
    required this.onOpenSettings,
  });

  final bool settingsActive;
  final bool createRoomActive;
  final bool notificationsActive;
  final bool hasPendingNotifications;
  final VoidCallback onCreateRoom;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _footerButtonOuterHeight,
      child: Row(
        children: [
          ButtonIcon(
            key: const ValueKey('home-sidebar-create-room-button'),
            tooltip: '创建房间',
            icon: const Icon(Icons.add_circle_outline),
            selected: createRoomActive,
            onPressed: onCreateRoom,
            size: _footerButtonSize,
          ),
          const SizedBox(width: _footerButtonGap),
          _NotificationFooterButton(
            selected: notificationsActive,
            hasPending: hasPendingNotifications,
            onPressed: onOpenNotifications,
          ),
          const Spacer(),
          ButtonIcon(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            selected: settingsActive,
            onPressed: onOpenSettings,
            size: _footerButtonSize,
          ),
        ],
      ),
    );
  }
}

class _NotificationFooterButton extends StatelessWidget {
  const _NotificationFooterButton({
    required this.selected,
    required this.hasPending,
    required this.onPressed,
  });

  final bool selected;
  final bool hasPending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _footerButtonSize,
      height: _footerButtonOuterHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ButtonIcon(
            key: const ValueKey('home-sidebar-notifications-button'),
            tooltip: '通知',
            icon: const Icon(Icons.notifications_none),
            selected: selected,
            onPressed: onPressed,
            size: _footerButtonSize,
          ),
          if (hasPending)
            Positioned(
              right: 2,
              top: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: UiColors.danger,
                  shape: BoxShape.circle,
                  border: Border.all(color: UiColors.surfaceLow, width: 1.4),
                ),
                child: const SizedBox.square(dimension: 9),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserSummaryBar extends StatelessWidget {
  const _UserSummaryBar({
    required this.user,
    required this.logoutActive,
    required this.onLogout,
  });

  final CurrentUser user;
  final bool logoutActive;
  final VoidCallback onLogout;

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
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PresencePill.fromLabel(_userStatus(user)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _FlatIconButton(
                tooltip: '退出登录',
                icon: Icons.logout,
                color: logoutActive ? UiColors.accent : UiColors.textMuted,
                size: 30,
                onPressed: onLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A borderless, background-free icon button — just the glyph with a hover
/// cursor and tooltip. Used for low-emphasis actions like logout that sit
/// inline next to other content.
class _FlatIconButton extends StatelessWidget {
  const _FlatIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.size,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: color, size: size * 0.54),
          ),
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.selected,
    required this.voiceJoined,
    required this.searchQuery,
    required this.onPressed,
  });

  final RoomCard server;
  final bool selected;
  final bool voiceJoined;
  final String searchQuery;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final lastMessageTime = room_display.roomSidebarLastMessageTime(server);
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
                Row(
                  children: [
                    Expanded(
                      child: HighlightedText(
                        text: server.displayName,
                        query: searchQuery,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: UiColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (lastMessageTime.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        lastMessageTime,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UiTypography.label.copyWith(
                          color: selected
                              ? UiColors.textSecondary
                              : UiColors.textMuted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                HighlightedText(
                  text: room_display.roomSidebarSubtitle(server),
                  query: searchQuery,
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
                fontWeight: FontWeight.w600,
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
