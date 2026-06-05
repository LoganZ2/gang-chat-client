part of 'home_page.dart';

class _BadgeAnchor extends StatelessWidget {
  const _BadgeAnchor({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (show) const Positioned(top: -3, right: -3, child: _BadgeDot()),
      ],
    );
  }
}

class _BadgeDot extends StatelessWidget {
  const _BadgeDot();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _danger,
        shape: BoxShape.circle,
        border: Border.all(color: _primaryDarkLow, width: 2),
      ),
      child: const SizedBox.square(dimension: 10),
    );
  }
}

class _RoomListPane extends StatelessWidget {
  const _RoomListPane({
    required this.rooms,
    required this.selectedRoomId,
    required this.loading,
    required this.currentUser,
    required this.collapsed,
    required this.settingsActive,
    required this.hasPendingRoomInvites,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onOpenSettings,
    required this.onLogout,
    required this.onOpenCurrentUser,
    required this.onOpenRoom,
    required this.onJoinLive,
  });

  final List<RoomCard> rooms;
  final String? selectedRoomId;
  final bool loading;
  final CurrentUser currentUser;
  final bool collapsed;
  final bool settingsActive;
  final bool hasPendingRoomInvites;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onLogout;
  final VoidCallback onOpenCurrentUser;
  final ValueChanged<RoomCard> onOpenRoom;
  final ValueChanged<RoomCard> onJoinLive;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDarkLow,
      child: Column(
        children: [
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Tooltip(
                message: '查看我的用户信息',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpenCurrentUser,
                    child: Row(
                      children: [
                        _Avatar(
                          label: currentUser.displayName,
                          imageUrl: AppConfigScope.of(
                            context,
                          ).resolveAssetUrl(currentUser.avatarUrl),
                          defaultAvatarKey: currentUser.defaultAvatarKey,
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currentUser.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              _UserStatusLabel(
                                label: currentUser.status ?? '在线',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Button(
                      width: double.infinity,
                      onPressed: onCreateRoom,
                      icon: const Icon(Icons.add),
                      tone: ButtonTone.primary,
                      child: const Text('创建房间'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BadgeAnchor(
                      show: hasPendingRoomInvites,
                      child: Button(
                        width: double.infinity,
                        onPressed: onJoinRoom,
                        icon: const Icon(Icons.group_add),
                        child: const Text('加入房间'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (rooms.isEmpty && !loading)
                  Center(
                    child: collapsed
                        ? const SizedBox.shrink()
                        : const Text(
                            '选择一个房间开始聊天',
                            style: TextStyle(color: _textMuted),
                          ),
                  )
                else
                  ListView.builder(
                    padding: collapsed
                        ? const EdgeInsets.fromLTRB(0, 12, 0, 4)
                        : const EdgeInsets.fromLTRB(12, 0, 12, 18),
                    itemCount: rooms.length,
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      return _RoomCardTile(
                        room: room,
                        selected: room.id == selectedRoomId,
                        collapsed: collapsed,
                        onOpenRoom: () => onOpenRoom(room),
                        onJoinLive: () => onJoinLive(room),
                      );
                    },
                  ),
                if (loading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: _cyan,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
              ],
            ),
          ),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SidebarIconButton(
                      tooltip: 'Settings',
                      onPressed: onOpenSettings,
                      selected: settingsActive,
                      icon: const Icon(Icons.settings),
                    ),
                    const SizedBox(width: 8),
                    _SidebarIconButton(
                      tooltip: 'Logout',
                      onPressed: () => onLogout(),
                      icon: const Icon(Icons.logout),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: _SidebarIconButton(
                tooltip: 'Settings',
                onPressed: onOpenSettings,
                selected: settingsActive,
                icon: const Icon(Icons.settings),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarIconButton extends StatelessWidget {
  const _SidebarIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.selected = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    return SizedBox(
      width: size,
      child: PressableSurface(
        tooltip: tooltip,
        onPressed: onPressed,
        selected: selected,
        height: size,
        padding: EdgeInsets.zero,
        backgroundColor: _primaryDarkLow,
        selectedBackgroundColor: _selectedSurface,
        pressedBackgroundColor: _primaryDark,
        borderColor: _primaryDarkLow,
        selectedBorderColor: _cyan,
        child: IconTheme.merge(
          data: IconThemeData(color: selected ? _cyan : _textPrimary, size: 17),
          child: Center(child: icon),
        ),
      ),
    );
  }
}

class _UserStatusLabel extends StatelessWidget {
  const _UserStatusLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(color: _cyan, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomCardTile extends StatelessWidget {
  const _RoomCardTile({
    required this.room,
    required this.selected,
    required this.collapsed,
    required this.onOpenRoom,
    required this.onJoinLive,
  });

  final RoomCard room;
  final bool selected;
  final bool collapsed;
  final VoidCallback onOpenRoom;
  final VoidCallback onJoinLive;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return _CollapsedRoomTile(
        room: room,
        selected: selected,
        onOpenRoom: onOpenRoom,
        onJoinLive: onJoinLive,
      );
    }
    return _ExpandedRoomTile(
      room: room,
      selected: selected,
      onOpenRoom: onOpenRoom,
      onJoinLive: onJoinLive,
    );
  }
}

class _ExpandedRoomTile extends StatelessWidget {
  const _ExpandedRoomTile({
    required this.room,
    required this.selected,
    required this.onOpenRoom,
    required this.onJoinLive,
  });

  final RoomCard room;
  final bool selected;
  final VoidCallback onOpenRoom;
  final VoidCallback onJoinLive;

  @override
  Widget build(BuildContext context) {
    final liveActive = room.liveParticipantCount > 0;
    return PressableSurface(
      height: 112,
      margin: const EdgeInsets.only(bottom: 2),
      interactive: true,
      pressRequiresHover: true,
      selected: selected,
      backgroundColor: _primaryDarkRaised,
      selectedBackgroundColor: _selectedSurface,
      borderColor: _borderColor,
      selectedBorderColor: _cyan,
      hoverLift: 3,
      pressDepth: 3,
      baseDepth: 5,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenRoom,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _Avatar(
                      label: room.name,
                      imageUrl: AppConfigScope.of(
                        context,
                      ).resolveAssetUrl(room.avatarUrl),
                      defaultAvatarKey: room.defaultAvatarKey,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            room.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            room_display.roomSubtitle(room),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _AvatarStack(users: room.liveAvatarPreview),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, color: _borderColor),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onJoinLive,
              child: SizedBox.expand(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.volume_up,
                      color: liveActive ? _cyan : _textMuted,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${room.liveParticipantCount}',
                      style: TextStyle(
                        color: liveActive ? _cyan : _textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedRoomTile extends StatefulWidget {
  const _CollapsedRoomTile({
    required this.room,
    required this.selected,
    required this.onOpenRoom,
    required this.onJoinLive,
  });

  final RoomCard room;
  final bool selected;
  final VoidCallback onOpenRoom;
  final VoidCallback onJoinLive;

  @override
  State<_CollapsedRoomTile> createState() => _CollapsedRoomTileState();
}

class _CollapsedRoomTileState extends State<_CollapsedRoomTile> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  bool _overSlot = false;
  bool _overOverlay = false;

  bool get _expanded => _overSlot || _overOverlay;

  void _setOverSlot(bool v) {
    if (_overSlot == v) return;
    setState(() {
      _overSlot = v;
      _syncPortal();
    });
  }

  void _setOverOverlay(bool v) {
    if (_overOverlay == v) return;
    setState(() {
      _overOverlay = v;
      _syncPortal();
    });
  }

  void _syncPortal() {
    final shouldShow = _expanded;
    if (shouldShow && !_portal.isShowing) {
      _portal.show();
    } else if (!shouldShow && _portal.isShowing) {
      _portal.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = _ExpandedRoomTile(
      room: widget.room,
      selected: widget.selected,
      onOpenRoom: widget.onOpenRoom,
      onJoinLive: widget.onJoinLive,
    );

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) {
          return Positioned(
            width: 320,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.topLeft,
              child: MouseRegion(
                onEnter: (_) => _setOverOverlay(true),
                onExit: (_) => _setOverOverlay(false),
                child: Material(
                  color: Colors.transparent,
                  child: _ExpandedRoomTile(
                    room: widget.room,
                    selected: widget.selected,
                    onOpenRoom: widget.onOpenRoom,
                    onJoinLive: widget.onJoinLive,
                  ),
                ),
              ),
            ),
          );
        },
        child: MouseRegion(
          onEnter: (_) => _setOverSlot(true),
          onExit: (_) => _setOverSlot(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpenRoom,
            child: _expanded
                ? Visibility(
                    visible: false,
                    maintainState: true,
                    maintainSize: true,
                    maintainAnimation: true,
                    child: placeholder,
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Center(
                      child: _Avatar(
                        label: widget.room.name,
                        imageUrl: AppConfigScope.of(
                          context,
                        ).resolveAssetUrl(widget.room.avatarUrl),
                        defaultAvatarKey: widget.room.defaultAvatarKey,
                        size: 44,
                        borderColor: widget.selected ? _cyan : _borderColor,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
