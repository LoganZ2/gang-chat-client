import 'package:flutter/material.dart';

import '../protocol/models.dart';
import '../ui/ui.dart';

const _selectedServerBackground = Color(0xFF0F3F2A);
const _selectedServerBorder = Color(0xFF4EAD76);

class HomeSidebar extends StatelessWidget {
  const HomeSidebar({
    super.key,
    required this.width,
    required this.servers,
    required this.selectedServerId,
    required this.loading,
    required this.error,
    required this.onServerSelected,
  });

  final double width;
  final List<RoomCard> servers;
  final String? selectedServerId;
  final bool loading;
  final String? error;
  final ValueChanged<RoomCard> onServerSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: UiColors.surfaceLow,
          border: Border(right: BorderSide(color: UiColors.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
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
      separatorBuilder: (context, index) => const SizedBox(height: 10),
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
      height: 68,
      hoverLift: 2,
      baseDepth: 4,
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

String _serverMeta(RoomCard server) {
  final parts = ['${server.memberCount} members'];
  if (server.liveParticipantCount > 0) {
    parts.add('${server.liveParticipantCount} live');
  }
  return parts.join(' · ');
}
