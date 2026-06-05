import 'package:flutter/material.dart';

import '../protocol/models.dart';
import '../ui/ui.dart';

const _selectedServerBackground = Color(0xFF0F3F2A);
const _selectedServerBorder = Color(0xFF4EAD76);
const _sidebarHorizontalPadding = 14.0;
const _sidebarTopPadding = 16.0;
const _sidebarBottomPadding = 16.0;
const _serverListScrollbarGutter = 15.0;
const _serverCardHeight = 68.0;
const _serverCardHoverLift = 2.0;
const _serverCardBaseDepth = 4.0;
const _serverCardOuterHeight =
    _serverCardHeight + _serverCardHoverLift + _serverCardBaseDepth;
const _serverCardGap = 10.0;

class HomeSidebar extends StatelessWidget {
  const HomeSidebar({
    super.key,
    required this.width,
    required this.currentUser,
    required this.servers,
    required this.selectedServerId,
    required this.loading,
    required this.error,
    required this.onServerSelected,
  });

  final double width;
  final CurrentUser currentUser;
  final List<RoomCard> servers;
  final String? selectedServerId;
  final bool loading;
  final String? error;
  final ValueChanged<RoomCard> onServerSelected;

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

    return _ServerList(
      servers: servers,
      selectedServerId: selectedServerId,
      onServerSelected: onServerSelected,
    );
  }
}

class _ServerList extends StatefulWidget {
  const _ServerList({
    required this.servers,
    required this.selectedServerId,
    required this.onServerSelected,
  });

  final List<RoomCard> servers;
  final String? selectedServerId;
  final ValueChanged<RoomCard> onServerSelected;

  @override
  State<_ServerList> createState() => _ServerListState();
}

class _ServerListState extends State<_ServerList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final needsScroll =
            _serverListContentHeight(widget.servers.length) >
            constraints.maxHeight;

        final list = ListView.separated(
          controller: _scrollController,
          padding: EdgeInsets.only(
            right: needsScroll ? _serverListScrollbarGutter : 0,
          ),
          itemCount: widget.servers.length,
          separatorBuilder: (context, index) =>
              const SizedBox(height: _serverCardGap),
          itemBuilder: (context, index) {
            final server = widget.servers[index];
            return _ServerCard(
              server: server,
              selected: server.id == widget.selectedServerId,
              onPressed: () => widget.onServerSelected(server),
            );
          },
        );

        if (!needsScroll) return list;
        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: list,
        );
      },
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

double _serverListContentHeight(int itemCount) {
  if (itemCount <= 0) return 0;
  return (itemCount * _serverCardOuterHeight) +
      ((itemCount - 1) * _serverCardGap);
}

String _serverMeta(RoomCard server) {
  final parts = ['${server.memberCount} members'];
  if (server.liveParticipantCount > 0) {
    parts.add('${server.liveParticipantCount} live');
  }
  return parts.join(' · ');
}
