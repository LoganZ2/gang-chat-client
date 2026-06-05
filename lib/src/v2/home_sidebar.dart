import 'package:flutter/material.dart';

import '../protocol/models.dart';
import '../ui/ui.dart';

const _selectedServerBackground = Color(0xFF0F3F2A);
const _selectedServerBorder = Color(0xFF4EAD76);
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

class HomeSidebar extends StatelessWidget {
  const HomeSidebar({
    super.key,
    required this.width,
    required this.currentUser,
    required this.servers,
    required this.selectedServerId,
    required this.loading,
    required this.error,
    required this.settingsActive,
    required this.onServerSelected,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final double width;
  final CurrentUser currentUser;
  final List<RoomCard> servers;
  final String? selectedServerId;
  final bool loading;
  final String? error;
  final bool settingsActive;
  final ValueChanged<RoomCard> onServerSelected;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final chrome = WindowChromeInsets.of(context);
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
            _sidebarTopPadding + chrome.sidebarTopOffset,
            _sidebarHorizontalPadding,
            _sidebarBottomPadding,
          ),
          child: Column(
            children: [
              _UserSummaryBar(user: currentUser),
              const SizedBox(height: 14),
              Expanded(child: _buildServerList()),
              const SizedBox(height: 12),
              _SidebarFooter(
                settingsActive: settingsActive,
                onOpenSettings: onOpenSettings,
                onLogout: onLogout,
              ),
            ],
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
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            selected: settingsActive,
            onPressed: onOpenSettings,
            size: _footerButtonSize,
          ),
          const SizedBox(width: _footerButtonGap),
          ButtonIcon(
            tooltip: 'Logout',
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
                size: 38,
                active: true,
                activeBorderWidth: 1.2,
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
    required this.onPressed,
  });

  final RoomCard server;
  final bool selected;
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
      selectedBackgroundColor: _selectedServerBackground,
      pressedBackgroundColor: UiColors.surfacePressed,
      borderColor: UiColors.border,
      selectedBorderColor: _selectedServerBorder,
      borderRadius: UiRadii.md,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      onPressed: onPressed,
      child: Row(
        children: [
          Avatar(
            label: server.displayName,
            imageUrl: server.avatarUrl,
            size: 40,
            active: selected,
            activeBorderWidth: 1.2,
          ),
          const SizedBox(width: 11),
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
          if (server.unreadCount > 0) ...[
            const SizedBox(width: 8),
            StatusBadge(label: '${server.unreadCount}', active: true),
          ],
        ],
      ),
    );
  }
}

String _userStatus(CurrentUser user) {
  final status = user.status?.trim();
  if (status != null && status.isNotEmpty) return status;
  return 'Online';
}

String _serverMeta(RoomCard server) {
  final parts = ['${server.memberCount} members'];
  if (server.liveParticipantCount > 0) {
    parts.add('${server.liveParticipantCount} live');
  }
  return parts.join(' · ');
}
