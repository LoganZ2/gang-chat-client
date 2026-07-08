part of 'home_shell.dart';

const _homeTitleBarHeight = 44.0;
const _homeTitleBarSearchWidth = 520.0;
const _homeTitleBarSearchHeight = 30.0;
const _homeTitleBarMinSearchWidth = 122.0;
const _homeTitleBarControlsWidth = appWindowControlsWidth;
const _homeTitleBarLiveRoomWidth = 250.0;
const _homeTitleBarLiveRoomHeight = 30.0;
const _homeTitleBarLiveRoomHorizontalInset = 10.0;
const _homeTitleBarLiveRoomSearchGap = 14.0;
const _homeTitleBarLiveRoomActionSize = 28.0;
const _homeTitleBarWindowsSearchMinWidth =
    _homeTitleBarSearchWidth +
    _homeTitleBarControlsWidth * 2 +
    appWindowControlGap * 2;
const _homeTitleBarLiveRoomMinWidth =
    _homeTitleBarSearchWidth +
    (_homeTitleBarLiveRoomWidth +
            _homeTitleBarLiveRoomHorizontalInset +
            _homeTitleBarLiveRoomSearchGap) *
        2;

double _homeTitleBarBrandWidth(BuildContext context, double maxWidth) {
  final nativeMacControls = Theme.of(context).platform == TargetPlatform.macOS;
  final wide = maxWidth >= narrowBreakpoint;
  final compactBrandWidth =
      (maxWidth -
              (nativeMacControls ? 0 : _homeTitleBarControlsWidth) -
              _homeTitleBarMinSearchWidth)
          .clamp(118.0, 168.0)
          .toDouble();
  return wide ? sidebarWidth : compactBrandWidth;
}

bool _homeTitleBarCanShowSearch(BuildContext context, double maxWidth) {
  final nativeMacControls = Theme.of(context).platform == TargetPlatform.macOS;
  if (nativeMacControls) {
    return maxWidth >= _homeTitleBarSearchWidth;
  }
  return maxWidth >= _homeTitleBarWindowsSearchMinWidth;
}

class _HomeTitleBar extends StatefulWidget {
  const _HomeTitleBar({
    required this.windowController,
    required this.searchController,
    required this.searchTapRegionGroup,
    required this.liveRoom,
    required this.micMuted,
    required this.headphonesMuted,
    required this.voiceBlocked,
    required this.onActivateSearch,
    required this.onSearchTapOutside,
    required this.onSearchContextMenuOpenChanged,
    required this.onClearSearchQuery,
    required this.onOpenLiveRoom,
    required this.onToggleMic,
    required this.onToggleHeadphones,
    required this.onLeaveLive,
  });

  final DesktopWindowController windowController;
  final TextEditingController searchController;
  final Object searchTapRegionGroup;
  final live_display.JoinedLiveRoomSummary? liveRoom;
  final bool micMuted;
  final bool headphonesMuted;
  final bool voiceBlocked;
  final VoidCallback onActivateSearch;
  final VoidCallback onSearchTapOutside;
  final ValueChanged<bool> onSearchContextMenuOpenChanged;
  final VoidCallback onClearSearchQuery;
  final VoidCallback onOpenLiveRoom;
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onLeaveLive;

  @override
  State<_HomeTitleBar> createState() => _HomeTitleBarState();
}

class _HomeTitleBarState extends State<_HomeTitleBar> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    unawaited(_syncMaximized());
  }

  @override
  void didUpdateWidget(_HomeTitleBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowController != widget.windowController) {
      unawaited(_syncMaximized());
    }
  }

  Future<void> _syncMaximized() async {
    final maximized = await widget.windowController.isMaximizedWindow();
    if (!mounted) return;
    setState(() => _maximized = maximized);
  }

  void _minimize() {
    unawaited(widget.windowController.minimizeWindow());
  }

  void _toggleMaximize() {
    unawaited(() async {
      await widget.windowController.toggleMaximizeWindow();
      await _syncMaximized();
    }());
  }

  void _close() {
    unawaited(widget.windowController.closeWindow());
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _homeTitleBarHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: UiColors.surfaceLow,
          border: Border(bottom: BorderSide(color: UiColors.border)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // mac 使用系统原生红绿灯,其它平台用自定义窗口按钮。
            final nativeMacControls =
                Theme.of(context).platform == TargetPlatform.macOS;
            final brandWidth = _homeTitleBarBrandWidth(
              context,
              constraints.maxWidth,
            );
            final showSearch = _homeTitleBarCanShowSearch(
              context,
              constraints.maxWidth,
            );
            final showLiveRoom =
                widget.liveRoom != null &&
                constraints.maxWidth >= _homeTitleBarLiveRoomMinWidth;

            return Stack(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: brandWidth,
                      child: AppWindowDragRegion(
                        windowController: widget.windowController,
                        onDoubleTap: _toggleMaximize,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      child: AppWindowDragRegion(
                        windowController: widget.windowController,
                        onDoubleTap: _toggleMaximize,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    if (!nativeMacControls)
                      SelectionContainer.disabled(
                        child: AppWindowControls(
                          maximized: _maximized,
                          onMinimize: _minimize,
                          onToggleMaximize: _toggleMaximize,
                          onClose: _close,
                        ),
                      ),
                  ],
                ),
                if (showLiveRoom)
                  Positioned(
                    top:
                        (_homeTitleBarHeight - _homeTitleBarLiveRoomHeight) / 2,
                    left: nativeMacControls
                        ? null
                        : _homeTitleBarLiveRoomHorizontalInset,
                    right: nativeMacControls
                        ? _homeTitleBarLiveRoomHorizontalInset
                        : null,
                    child: _TitleLiveRoomDock(
                      room: widget.liveRoom!,
                      micMuted: widget.micMuted,
                      headphonesMuted: widget.headphonesMuted,
                      voiceBlocked: widget.voiceBlocked,
                      onOpen: widget.onOpenLiveRoom,
                      onToggleMic: widget.onToggleMic,
                      onToggleHeadphones: widget.onToggleHeadphones,
                      onLeave: widget.onLeaveLive,
                    ),
                  ),
                if (showSearch)
                  Align(
                    alignment: Alignment.center,
                    child: TapRegion(
                      groupId: widget.searchTapRegionGroup,
                      onTapOutside: (_) => widget.onSearchTapOutside(),
                      child: SizedBox(
                        key: const ValueKey('home-title-search'),
                        width: _homeTitleBarSearchWidth,
                        height: _homeTitleBarSearchHeight,
                        child: _TitleSearchField(
                          controller: widget.searchController,
                          tapRegionGroup: widget.searchTapRegionGroup,
                          onContextMenuOpenChanged:
                              widget.onSearchContextMenuOpenChanged,
                          onActivated: widget.onActivateSearch,
                          onClearQuery: widget.onClearSearchQuery,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TitleLiveRoomDock extends StatelessWidget {
  const _TitleLiveRoomDock({
    required this.room,
    required this.micMuted,
    required this.headphonesMuted,
    required this.voiceBlocked,
    required this.onOpen,
    required this.onToggleMic,
    required this.onToggleHeadphones,
    required this.onLeave,
  });

  final live_display.JoinedLiveRoomSummary room;
  final bool micMuted;
  final bool headphonesMuted;
  final bool voiceBlocked;
  final VoidCallback onOpen;
  final VoidCallback? onToggleMic;
  final VoidCallback onToggleHeadphones;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final micControl = live_display.liveMicControlState(
      micMuted: micMuted,
      voiceBlocked: voiceBlocked,
    );
    final resolvedAvatar = AppConfigScope.of(
      context,
    ).resolveAssetUrl(room.avatarUrl);
    return Tooltip(
      message: '打开语音频道',
      preferBelow: true,
      verticalOffset: 22,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey<String>('home-title-live-room'),
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: SizedBox(
            width: _homeTitleBarLiveRoomWidth,
            height: _homeTitleBarLiveRoomHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: UiColors.surface,
                borderRadius: BorderRadius.circular(UiRadii.md),
                border: Border.all(color: UiColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Row(
                  children: [
                    Icon(Icons.volume_up, size: 16, color: UiColors.accent),
                    const SizedBox(width: 7),
                    Avatar(
                      label: room.avatarLabel,
                      imageUrl: resolvedAvatar,
                      defaultAvatarKey: room.defaultAvatarKey,
                      size: 20,
                      showBorder: false,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        room.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: UiTypography.label.copyWith(
                          color: UiColors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TitleLiveActionButton(
                      key: const ValueKey<String>('home-title-live-room:mic'),
                      tooltip: micControl.mutedForDisplay ? '打开麦克风' : '关闭麦克风',
                      icon: micControl.mutedForDisplay
                          ? Icons.mic_off
                          : Icons.mic,
                      color: !micControl.enabled
                          ? UiColors.danger
                          : micControl.active
                          ? UiColors.accent
                          : UiColors.textMuted,
                      onPressed: micControl.enabled ? onToggleMic : null,
                    ),
                    _TitleLiveActionButton(
                      key: const ValueKey<String>(
                        'home-title-live-room:headphones',
                      ),
                      tooltip: headphonesMuted ? '打开耳机' : '关闭耳机',
                      icon: headphonesMuted
                          ? Icons.headset_off
                          : Icons.headphones,
                      color: headphonesMuted
                          ? UiColors.textMuted
                          : UiColors.accent,
                      onPressed: onToggleHeadphones,
                    ),
                    _TitleLiveActionButton(
                      key: const ValueKey<String>('home-title-live-room:leave'),
                      tooltip: '离开语音频道',
                      icon: Icons.call_end,
                      color: UiColors.danger,
                      onPressed: onLeave,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleLiveActionButton extends StatelessWidget {
  const _TitleLiveActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      preferBelow: true,
      verticalOffset: 22,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (enabled) onPressed!();
          },
          child: SizedBox.square(
            dimension: _homeTitleBarLiveRoomActionSize,
            child: Center(
              child: Icon(
                icon,
                size: 16,
                color: enabled ? color : color.withValues(alpha: 0.56),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 标题栏中央的搜索框。不复用通用 [Input] 封装,而是一个普通的圆角矩形,
/// 获得焦点时会像按钮一样显示绿色边框与底色。
class _TitleSearchField extends StatefulWidget {
  const _TitleSearchField({
    required this.controller,
    required this.tapRegionGroup,
    required this.onContextMenuOpenChanged,
    required this.onActivated,
    required this.onClearQuery,
  });

  final TextEditingController controller;
  final Object tapRegionGroup;
  final ValueChanged<bool> onContextMenuOpenChanged;
  final VoidCallback onActivated;
  final VoidCallback onClearQuery;

  @override
  State<_TitleSearchField> createState() => _TitleSearchFieldState();
}

class _TitleSearchFieldState extends State<_TitleSearchField> {
  final FocusNode _focusNode = FocusNode();
  final UndoHistoryController _undoController = UndoHistoryController();
  bool _focused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(_TitleSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleTextChanged);
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _undoController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) widget.onActivated();
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  void _handleTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (_hasText == hasText) return;
    setState(() => _hasText = hasText);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _focused ? UiColors.accent : UiColors.textMuted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
      height: _homeTitleBarSearchHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _focused ? UiColors.selected : UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(
          color: _focused ? UiColors.selectedBorder : UiColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: TextFieldEditingShortcuts(
              controller: widget.controller,
              focusNode: _focusNode,
              undoController: _undoController,
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                maxLines: 1,
                textInputAction: TextInputAction.search,
                undoController: _undoController,
                onTap: widget.onActivated,
                cursorColor: UiColors.accent,
                cursorWidth: 1.5,
                style: UiTypography.body.copyWith(fontSize: 13, height: 1.2),
                contextMenuBuilder: (context, editableTextState) =>
                    buildTextFieldContextMenu(
                      context,
                      editableTextState,
                      undoController: _undoController,
                      tapRegionGroupId: widget.tapRegionGroup,
                      onOpenChanged: widget.onContextMenuOpenChanged,
                    ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: '搜索',
                  hintStyle: UiTypography.body.copyWith(
                    fontSize: 13,
                    height: 1.2,
                    color: UiColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
          if (_hasText) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: '清空搜索',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClearQuery,
                child: Icon(Icons.close, size: 15, color: UiColors.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TitleSearchResultsPanel extends StatelessWidget {
  const _TitleSearchResultsPanel({
    required this.query,
    required this.results,
    required this.loading,
    required this.loadingMore,
    required this.error,
    required this.timestampNow,
    required this.currentUser,
    required this.activeCategory,
    required this.visibleCategories,
    required this.busyPublicRoomId,
    required this.pendingPublicRoomIds,
    required this.onCategorySelected,
    required this.onLoadMore,
    required this.onMyRoomSelected,
    required this.onProfileRoomSelected,
    required this.onResolveRoomProfile,
    required this.onResolveRoomUserProfile,
    required this.onPublicRoomAction,
    required this.onMessageSelected,
    required this.onFileSelected,
  });

  final String query;
  final GlobalSearchResults? results;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final DateTime timestampNow;
  final CurrentUser currentUser;
  final search_display.GlobalSearchCategory? activeCategory;
  final List<search_display.GlobalSearchCategory> visibleCategories;
  final String? busyPublicRoomId;
  final Set<String> pendingPublicRoomIds;
  final ValueChanged<search_display.GlobalSearchCategory> onCategorySelected;
  final VoidCallback onLoadMore;
  final ValueChanged<RoomCard> onMyRoomSelected;
  final ValueChanged<PublicRoom> onProfileRoomSelected;
  final RoomProfileResolver onResolveRoomProfile;
  final Future<UserSummary> Function(String roomId, UserSummary user)
  onResolveRoomUserProfile;
  final ValueChanged<PublicRoom> onPublicRoomAction;
  final ValueChanged<MessageSearchResult> onMessageSelected;
  final ValueChanged<MessageSearchResult> onFileSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surfaceLow,
        borderRadius: BorderRadius.circular(UiRadii.lg),
        border: Border.all(color: UiColors.borderStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(UiRadii.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SearchCategoryTabs(
                results: results,
                activeCategory: activeCategory,
                onCategorySelected: onCategorySelected,
              ),
              const Divider(height: 1, color: UiColors.border),
              Flexible(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final failure = error;
    if (failure != null) {
      return _SearchPanelState(
        icon: Icons.error_outline,
        title: '搜索失败',
        detail: failure,
      );
    }

    final snapshot = results;
    if (snapshot == null && loading) {
      return const SizedBox(
        height: 104,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: UiColors.accent,
            ),
          ),
        ),
      );
    }

    if (!search_display.globalSearchHasResults(snapshot)) {
      return _SearchPanelState(
        icon: Icons.search,
        title: '没有找到结果',
        detail: query.trim(),
      );
    }

    final sections = <Widget>[];
    for (final category in visibleCategories) {
      final section = _sectionFor(context, snapshot!, category);
      if (section != null) {
        if (sections.isNotEmpty) sections.add(const SizedBox(height: 10));
        sections.add(section);
      }
    }

    if (sections.isEmpty) {
      return _SearchPanelState(
        icon: Icons.filter_alt_outlined,
        title: '该分类没有结果',
        detail: activeCategory == null
            ? query.trim()
            : search_display.globalSearchCategoryLabel(activeCategory!),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        children: [
          ...sections,
          if (loadingMore) const _SearchLoadingMoreIndicator(),
        ],
      ),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (loadingMore || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification.metrics.maxScrollExtent <= 0) return false;
    if (notification.metrics.extentAfter <= 96) onLoadMore();
    return false;
  }

  Widget? _sectionFor(
    BuildContext context,
    GlobalSearchResults snapshot,
    search_display.GlobalSearchCategory category,
  ) {
    final count = search_display.globalSearchCategoryCount(snapshot, category);
    if (count == 0) return null;

    final children = switch (category) {
      search_display.GlobalSearchCategory.myRooms => snapshot.myRooms.map((
        room,
      ) {
        final time = room_display.roomSidebarLastMessageTime(
          room,
          now: timestampNow,
        );
        return _RoomSearchResultTile(
          title: room.displayName,
          subtitle: room_display.roomSidebarSubtitle(room),
          query: query,
          leading: RoomHoverCard(
            room: _publicRoomFromRoomCard(room),
            currentUser: currentUser,
            onResolveRoom: onResolveRoomProfile,
            onResolveUserProfile: (user) =>
                onResolveRoomUserProfile(room.id, user),
            onEnterRoom: onProfileRoomSelected,
            child: Avatar(
              label: room_display.roomCardAvatarLabel(room),
              imageUrl: AppConfigScope.of(
                context,
              ).resolveAssetUrl(room.avatarUrl),
              defaultAvatarKey: room.defaultAvatarKey,
              size: 30,
            ),
          ),
          titleTrailing: time.isEmpty
              ? null
              : Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: UiTypography.label.copyWith(
                    color: UiColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
          trailing: _MyRoomEnterActivity(
            room: room,
            onPressed: onMyRoomSelected,
          ),
        );
      }).toList(),
      search_display.GlobalSearchCategory.publicRooms =>
        room_join
            .publicRoomJoinCandidates(
              rooms: snapshot.publicRooms,
              pendingRoomIds: pendingPublicRoomIds,
              busyRoomId: busyPublicRoomId,
            )
            .map(
              (candidate) => _RoomSearchResultTile(
                title: candidate.room.name,
                subtitle: _publicRoomSearchMeta(candidate.room),
                query: query,
                leading: RoomHoverCard(
                  room: candidate.room,
                  currentUser: currentUser,
                  onResolveRoom: onResolveRoomProfile,
                  onResolveUserProfile: (user) =>
                      onResolveRoomUserProfile(candidate.room.id, user),
                  onEnterRoom: candidate.room.joined
                      ? onProfileRoomSelected
                      : null,
                  child: Avatar(
                    label: candidate.room.name,
                    imageUrl: AppConfigScope.of(
                      context,
                    ).resolveAssetUrl(candidate.room.avatarUrl),
                    defaultAvatarKey: candidate.room.defaultAvatarKey,
                    size: 30,
                  ),
                ),
                trailing: _PublicRoomJoinActivity(
                  candidate: candidate,
                  onPressed: onPublicRoomAction,
                ),
              ),
            )
            .toList(),
      search_display.GlobalSearchCategory.messages =>
        snapshot.messages
            .map(
              (result) => _MessageSearchResultTile(
                result: result,
                title: search_display.globalSearchMessageTitle(result),
                subtitle: search_display.globalSearchMessageSubtitle(result),
                query: query,
                onPressed: () => onMessageSelected(result),
              ),
            )
            .toList(),
      search_display.GlobalSearchCategory.files =>
        snapshot.files
            .map(
              (result) => _MessageSearchResultTile(
                result: result,
                title: search_display.globalSearchFileTitle(result),
                subtitle: search_display.globalSearchFileSubtitle(result),
                query: query,
                onPressed: () => onFileSelected(result),
              ),
            )
            .toList(),
    };

    return _SearchResultSection(
      title: search_display.globalSearchCategoryLabel(category),
      count: count,
      children: children,
    );
  }
}

class _SearchCategoryTabs extends StatelessWidget {
  const _SearchCategoryTabs({
    required this.results,
    required this.activeCategory,
    required this.onCategorySelected,
  });

  final GlobalSearchResults? results;
  final search_display.GlobalSearchCategory? activeCategory;
  final ValueChanged<search_display.GlobalSearchCategory> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 380;
          final columns = compact ? 2 : 4;
          final itemWidth =
              ((constraints.maxWidth - (columns - 1) * 6) / columns)
                  .clamp(0.0, constraints.maxWidth)
                  .toDouble();
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final category in search_display.globalSearchCategories)
                SizedBox(
                  width: itemWidth,
                  child: _SearchCategoryButton(
                    key: ValueKey('search-category-${category.name}'),
                    label: search_display.globalSearchCategoryLabel(category),
                    count: search_display.globalSearchCategoryCount(
                      results,
                      category,
                    ),
                    selected: activeCategory == category,
                    onPressed: () => onCategorySelected(category),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchCategoryButton extends StatefulWidget {
  const _SearchCategoryButton({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_SearchCategoryButton> createState() => _SearchCategoryButtonState();
}

class _SearchCategoryButtonState extends State<_SearchCategoryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 29,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? UiColors.selected
                : active
                ? UiColors.surface
                : UiColors.surfaceLow,
            borderRadius: BorderRadius.circular(UiRadii.sm),
            border: Border.all(
              color: widget.selected
                  ? UiColors.selectedBorder
                  : UiColors.border,
            ),
          ),
          child: Center(
            child: Text(
              '${widget.label} ${widget.count}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.label.copyWith(
                color: widget.selected ? UiColors.accent : UiColors.text,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultSection extends StatelessWidget {
  const _SearchResultSection({
    required this.title,
    required this.count,
    required this.children,
  });

  final String title;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 7),
          child: Text(
            '$title $count',
            style: UiTypography.label.copyWith(color: UiColors.textMuted),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _SearchLoadingMoreIndicator extends StatelessWidget {
  const _SearchLoadingMoreIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 34,
      child: Center(
        child: SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: UiColors.accent,
          ),
        ),
      ),
    );
  }
}

class _RoomSearchResultTile extends StatelessWidget {
  const _RoomSearchResultTile({
    required this.title,
    required this.subtitle,
    required this.query,
    required this.leading,
    this.titleTrailing,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String query;
  final Widget leading;
  final Widget? titleTrailing;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _SearchResultTile(
      leading: leading,
      title: title,
      titleTrailing: titleTrailing,
      subtitle: subtitle,
      query: query,
      trailing: trailing,
    );
  }
}

class _MyRoomEnterActivity extends StatelessWidget {
  const _MyRoomEnterActivity({required this.room, required this.onPressed});

  final RoomCard room;
  final ValueChanged<RoomCard> onPressed;

  @override
  Widget build(BuildContext context) {
    return Button(
      key: ValueKey('my-room-action-${room.id}'),
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tone: ButtonTone.primary,
      onPressed: () => onPressed(room),
      child: const Text('进入房间'),
    );
  }
}

class _PublicRoomJoinActivity extends StatelessWidget {
  const _PublicRoomJoinActivity({
    required this.candidate,
    required this.onPressed,
  });

  final room_join.PublicRoomJoinCandidate candidate;
  final ValueChanged<PublicRoom> onPressed;

  @override
  Widget build(BuildContext context) {
    final room = candidate.room;
    return Button(
      key: ValueKey('public-room-action-${room.id}'),
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tone: candidate.actionable ? ButtonTone.primary : ButtonTone.neutral,
      loading: candidate.busy,
      onPressed: candidate.actionEnabled ? () => onPressed(room) : null,
      child: Text(_publicRoomSearchActionLabel(candidate)),
    );
  }
}

class _MessageSearchResultTile extends StatelessWidget {
  const _MessageSearchResultTile({
    required this.result,
    required this.title,
    required this.subtitle,
    required this.query,
    required this.onPressed,
  });

  final MessageSearchResult result;
  final String title;
  final String subtitle;
  final String query;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _SearchResultTile(
      onPressed: onPressed,
      leading: Avatar(
        label: result.room.name,
        imageUrl: AppConfigScope.of(
          context,
        ).resolveAssetUrl(result.room.avatarUrl),
        defaultAvatarKey: result.room.defaultAvatarKey,
        size: 30,
      ),
      title: title,
      subtitle: subtitle,
      query: query,
      trailing: Text(
        search_display.globalSearchResultTimeLabel(result),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: UiTypography.label.copyWith(color: UiColors.textMuted),
      ),
    );
  }
}

class _SearchResultTile extends StatefulWidget {
  const _SearchResultTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.query,
    this.titleTrailing,
    this.trailing,
    this.onPressed,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String query;
  final Widget? titleTrailing;
  final Widget? trailing;
  final VoidCallback? onPressed;

  @override
  State<_SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<_SearchResultTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onPressed != null;
    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered && interactive
                ? UiColors.surface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(UiRadii.sm),
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 30,
                child: Center(child: widget.leading),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: HighlightedText(
                            text: widget.title,
                            query: widget.query,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: UiTypography.body.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.titleTrailing != null) ...[
                          const SizedBox(width: 8),
                          widget.titleTrailing!,
                        ],
                      ],
                    ),
                    if (widget.subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: HighlightedText(
                              text: widget.subtitle,
                              query: widget.query,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: UiTypography.label.copyWith(
                                color: UiColors.textMuted,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 126),
                  child: widget.trailing!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchPanelState extends StatelessWidget {
  const _SearchPanelState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: UiColors.textMuted, size: 22),
              const SizedBox(height: 8),
              Text(title, style: UiTypography.body),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UiTypography.label.copyWith(color: UiColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _publicRoomSearchMeta(PublicRoom room) {
  return '${room.memberCount} 名成员';
}

String _publicRoomSearchActionLabel(
  room_join.PublicRoomJoinCandidate candidate,
) {
  final room = candidate.room;
  if (room.joined) return '进入房间';
  if (candidate.pending) return '待审批';
  if (room.joinPolicy == 'closed') return '不可加入';
  return '加入房间';
}

PublicRoom _publicRoomFromRoomCard(RoomCard room) {
  return PublicRoom(
    id: room.id,
    rid: room.rid,
    name: room.displayName,
    avatarLabel: room_display.roomCardAvatarLabel(room),
    avatarUrl: room.avatarUrl,
    defaultAvatarKey: room.defaultAvatarKey,
    visibility: room.visibility,
    joinPolicy: room.visibility == 'public' ? 'open' : 'closed',
    description: room.description,
    memberCount: room.memberCount,
    onlineMemberCount: room.onlineMemberCount,
    liveParticipantCount: room.liveParticipantCount,
    joined: true,
    joinState: 'joined',
    myMembership: RoomMembership(
      joinedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      role: 'member',
    ),
  );
}
