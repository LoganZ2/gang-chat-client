part of 'home_shell.dart';

class _RoomMessageHistoryPane extends StatefulWidget {
  const _RoomMessageHistoryPane({
    required this.room,
    required this.currentUser,
    required this.roomsController,
    required this.messagesController,
    required this.clipboardService,
    required this.onJumpToMessage,
  });

  final RoomDetail room;
  final CurrentUser currentUser;
  final RoomsController roomsController;
  final MessagesController messagesController;
  final ClipboardService clipboardService;
  final ValueChanged<String> onJumpToMessage;

  @override
  State<_RoomMessageHistoryPane> createState() =>
      _RoomMessageHistoryPaneState();
}

class _RoomMessageHistoryPaneState extends State<_RoomMessageHistoryPane> {
  static const _pageSize = 50;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  late room_notifications.RoomNotificationDateRange _defaultDateRange;
  late room_notifications.RoomNotificationDateRange _dateRange;
  room_message_history.RoomMessageHistoryCategory _category =
      room_message_history.RoomMessageHistoryCategory.all;
  List<RoomMember> _members = const [];
  RoomMember? _selectedMember;
  List<Message> _messages = const [];
  Set<String> _selectedMessageIds = const {};
  bool _selectionMode = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _membersLoading = true;
  String? _nextBefore;
  String? _error;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    _defaultDateRange = _makeDefaultDateRange();
    _dateRange = _defaultDateRange;
    _scrollController.addListener(_handleScroll);
    unawaited(_loadMembers());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  room_notifications.RoomNotificationDateRange _makeDefaultDateRange() {
    return room_notifications.RoomNotificationDateRange.defaultFor(
      accountCreatedAt: widget.currentUser.createdAt,
      today: DateTime.now(),
    );
  }

  Future<void> _loadMembers() async {
    try {
      final members = await widget.roomsController.loadAllRoomMembers(
        widget.room.id,
      );
      if (!mounted) return;
      setState(() {
        _members = members;
        _membersLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _membersLoading = false);
      showFloatingErrorNotice(context, '加载房间成员失败：$error');
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 240) {
      return;
    }
    unawaited(_loadMore());
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _clearSelection();
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    final serial = ++_loadSerial;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _messages = const [];
      _hasMore = false;
      _nextBefore = null;
    });
    try {
      final page = await _requestPage();
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _messages = page.messages;
        _hasMore = page.hasMore;
        _nextBefore = page.nextBefore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _nextBefore == null) return;
    final serial = _loadSerial;
    setState(() => _loadingMore = true);
    try {
      final page = await _requestPage(before: _nextBefore);
      if (!mounted || serial != _loadSerial) return;
      final knownIds = _messages.map((message) => message.id).toSet();
      setState(() {
        _messages = [
          ..._messages,
          ...page.messages.where((message) => knownIds.add(message.id)),
        ];
        _hasMore = page.hasMore;
        _nextBefore = page.nextBefore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || serial != _loadSerial) return;
      setState(() => _loadingMore = false);
      showFloatingErrorNotice(context, '加载更多消息记录失败：$error');
    }
  }

  Future<MessagePage> _requestPage({String? before}) {
    return widget.messagesController.loadMessageHistory(
      roomId: widget.room.id,
      query: _searchController.text,
      category: _category.apiValue,
      senderUserId: _selectedMember?.user.id,
      startAt: room_message_history.roomMessageHistoryDayStart(
        _dateRange.startDate,
      ),
      endAt: room_message_history.roomMessageHistoryDayEndExclusive(
        _dateRange.endDate,
      ),
      limit: _pageSize,
      before: before,
    );
  }

  Future<void> _showDateFilter() async {
    final result = await showDateRangeFilterDialog(
      context,
      initialRange: _dateRange,
      defaultRange: _defaultDateRange,
      title: '筛选消息日期',
      description: '选择包含首尾日期的消息时间区间。',
    );
    if (!mounted || result == null || result == _dateRange) return;
    setState(() => _dateRange = result);
    _clearSelection();
    await _reload();
  }

  Future<void> _showMemberFilter() async {
    if (_membersLoading) return;
    final result = await showDialog<_HistoryMemberFilterResult>(
      context: context,
      builder: (context) => _HistoryMemberFilterDialog(
        members: _members,
        selectedMember: _selectedMember,
      ),
    );
    if (!mounted || result == null) return;
    if (result.member?.user.id == _selectedMember?.user.id) return;
    setState(() => _selectedMember = result.member);
    _clearSelection();
    await _reload();
  }

  void _changeCategory(
    room_message_history.RoomMessageHistoryCategory category,
  ) {
    if (_category == category) return;
    setState(() => _category = category);
    _clearSelection();
    unawaited(_reload());
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedMessageIds = const {};
    });
  }

  void _clearSelection() {
    if (_selectedMessageIds.isEmpty) return;
    setState(() => _selectedMessageIds = const {});
  }

  void _toggleMessage(String messageId) {
    setState(() {
      final ids = {..._selectedMessageIds};
      if (!ids.add(messageId)) ids.remove(messageId);
      _selectedMessageIds = ids;
    });
  }

  void _toggleAllMessages() {
    if (_messages.isEmpty) return;
    final visibleIds = _messages.map((message) => message.id).toSet();
    setState(() {
      if (visibleIds.every(_selectedMessageIds.contains)) {
        _selectedMessageIds = {..._selectedMessageIds}..removeAll(visibleIds);
      } else {
        _selectedMessageIds = {..._selectedMessageIds, ...visibleIds};
      }
    });
  }

  List<Message> get _selectedMessages => _messages
      .where((message) => _selectedMessageIds.contains(message.id))
      .toList(growable: false);

  Future<void> _copyMessage(Message message) async {
    await widget.clipboardService.writeText(
      room_message_history.roomMessageHistoryCopyText(message),
    );
    if (mounted) showFloatingSuccessNotice(context, '已复制');
  }

  Future<void> _deleteMessages(List<Message> messages) async {
    if (messages.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _HistoryDeleteConfirmDialog(messageCount: messages.length),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.messagesController.hideMessageHistory(
        roomId: widget.room.id,
        messageIds: messages.map((message) => message.id),
      );
      if (!mounted) return;
      final deletedIds = messages.map((message) => message.id).toSet();
      setState(() {
        _messages = _messages
            .where((message) => !deletedIds.contains(message.id))
            .toList(growable: false);
        _selectedMessageIds = {..._selectedMessageIds}..removeAll(deletedIds);
      });
      showFloatingSuccessNotice(
        context,
        messages.length == 1 ? '已删除消息记录' : '已删除 ${messages.length} 条消息记录',
      );
    } catch (error) {
      if (mounted) showFloatingErrorNotice(context, '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _messages.isNotEmpty &&
        _messages.every((message) => _selectedMessageIds.contains(message.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Input(
                  key: const ValueKey('room-message-history-search'),
                  controller: _searchController,
                  hintText: '搜索消息记录',
                  prefixIcon: Icons.search,
                  showClearButton: true,
                  onChanged: _handleSearchChanged,
                ),
              ),
              const SizedBox(width: 10),
              ButtonIcon(
                key: const ValueKey('room-message-history-date-filter'),
                tooltip: '筛选消息日期',
                icon: const Icon(Icons.calendar_month_outlined),
                selected: _dateRange != _defaultDateRange,
                onPressed: _showDateFilter,
                size: Input.defaultHeight,
              ),
              const SizedBox(width: 8),
              ButtonIcon(
                key: const ValueKey('room-message-history-member-filter'),
                tooltip: _selectedMember == null
                    ? '筛选成员（所有人）'
                    : '筛选成员：${member_filter.roomMemberDisplayName(_selectedMember!)}',
                icon: const Icon(Icons.person_search_outlined),
                selected: _selectedMember != null,
                loading: _membersLoading,
                onPressed: _membersLoading ? null : _showMemberFilter,
                size: Input.defaultHeight,
              ),
              const SizedBox(width: 8),
              ButtonIcon(
                key: const ValueKey('room-message-history-batch-manage'),
                tooltip: _selectionMode ? '退出批量管理' : '批量管理',
                icon: const Icon(Icons.checklist_outlined),
                selected: _selectionMode,
                onPressed: _toggleSelectionMode,
                size: Input.defaultHeight,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_selectionMode) ...[
                UiCheckbox(
                  key: const ValueKey('room-message-history-select-all'),
                  value: allSelected,
                  onChanged: _messages.isEmpty
                      ? null
                      : (_) => _toggleAllMessages(),
                  tooltip: allSelected ? '取消全选当前消息记录' : '全选当前消息记录',
                  semanticLabel: '全选当前消息记录',
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child:
                    SegmentedControl<
                      room_message_history.RoomMessageHistoryCategory
                    >(
                      expanded: true,
                      value: _category,
                      onChanged: _changeCategory,
                      segments: const [
                        Segment(
                          value: room_message_history
                              .RoomMessageHistoryCategory
                              .all,
                          label: '全部',
                          icon: Icons.inbox_outlined,
                        ),
                        Segment(
                          value: room_message_history
                              .RoomMessageHistoryCategory
                              .links,
                          label: '链接',
                          icon: Icons.link,
                        ),
                        Segment(
                          value: room_message_history
                              .RoomMessageHistoryCategory
                              .stickers,
                          label: '表情',
                          icon: Icons.emoji_emotions_outlined,
                        ),
                        Segment(
                          value: room_message_history
                              .RoomMessageHistoryCategory
                              .images,
                          label: '图片',
                          icon: Icons.image_outlined,
                        ),
                        Segment(
                          value: room_message_history
                              .RoomMessageHistoryCategory
                              .files,
                          label: '文件',
                          icon: Icons.attach_file,
                        ),
                        Segment(
                          value: room_message_history
                              .RoomMessageHistoryCategory
                              .system,
                          label: '系统',
                          icon: Icons.info_outline,
                        ),
                      ],
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: UiTypography.body.copyWith(color: UiColors.danger),
            ),
            const SizedBox(height: 12),
            Button(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          '没有符合条件的消息记录',
          style: UiTypography.body.copyWith(color: UiColors.textMuted),
        ),
      );
    }
    return ListView.separated(
      controller: _scrollController,
      itemCount: _messages.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final message = _messages[index];
        return _HistoryMessageRow(
          message: message,
          selectionMode: _selectionMode,
          selected: _selectedMessageIds.contains(message.id),
          selectedMessages: _selectedMessages,
          onToggleSelection: () => _toggleMessage(message.id),
          onCopy: _copyMessage,
          onDelete: _deleteMessages,
          onJump: () => widget.onJumpToMessage(message.id),
        );
      },
    );
  }
}

class _HistoryMessageRow extends StatefulWidget {
  const _HistoryMessageRow({
    required this.message,
    required this.selectionMode,
    required this.selected,
    required this.selectedMessages,
    required this.onToggleSelection,
    required this.onCopy,
    required this.onDelete,
    required this.onJump,
  });

  final Message message;
  final bool selectionMode;
  final bool selected;
  final List<Message> selectedMessages;
  final VoidCallback onToggleSelection;
  final Future<void> Function(Message message) onCopy;
  final Future<void> Function(List<Message> messages) onDelete;
  final VoidCallback onJump;

  @override
  State<_HistoryMessageRow> createState() => _HistoryMessageRowState();
}

class _HistoryMessageRowState extends State<_HistoryMessageRow> {
  bool _contextMenuActive = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final senderName = _historySenderName(message.sender);
    final content = room_message_history.roomMessageHistoryCopyText(message);
    final highlighted = widget.selected || _contextMenuActive;
    final surface = AnimatedContainer(
      key: ValueKey('room-message-history-row-${message.id}'),
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadii.lg),
        border: Border.all(
          color: highlighted ? UiColors.selectedBorder : UiColors.border,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Avatar(
            label: senderName,
            imageUrl: AppConfigScope.of(
              context,
            ).resolveAssetUrl(message.sender.avatarUrl),
            defaultAvatarKey: message.sender.defaultAvatarKey,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: UiTypography.label.copyWith(
                    color: UiColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                IgnorePointer(
                  ignoring: widget.selectionMode,
                  child: ReadOnlySelectableText(
                    value: content,
                    maxLines: 6,
                    style: UiTypography.body.copyWith(
                      color: UiColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _HistoryInteractiveTarget(
            child: ButtonIcon(
              key: ValueKey('room-message-history-jump-${message.id}'),
              tooltip: '跳转到消息',
              icon: const Icon(Icons.location_on_rounded),
              tone: ButtonTone.primary,
              onPressed: widget.onJump,
              size: 34,
            ),
          ),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (widget.selectionMode) ...[
          UiCheckbox(
            key: ValueKey('room-message-history-select-${message.id}'),
            value: widget.selected,
            onChanged: (_) => widget.onToggleSelection(),
            semanticLabel: '选择这条消息记录',
          ),
          const SizedBox(width: 8),
        ],
        SizedBox(
          width: 82,
          child: Text(
            room_notifications.roomInviteTimestampLabel(message.createdAt),
            textAlign: TextAlign.center,
            style: UiTypography.label.copyWith(color: UiColors.textMuted),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.selectionMode ? widget.onToggleSelection : null,
            onSecondaryTapDown: _showContextMenu,
            child: surface,
          ),
        ),
      ],
    );
  }

  void _showContextMenu(TapDownDetails details) {
    if (widget.selectionMode && !widget.selected) return;
    final items = widget.selectionMode
        ? widget.selectedMessages
        : <Message>[widget.message];
    if (items.isEmpty) return;
    setState(() => _contextMenuActive = true);
    unawaited(
      showUiContextMenu(
        context,
        position: details.globalPosition,
        sections: [
          if (items.length == 1)
            UiContextMenuSection([
              UiContextMenuItem(
                label: '复制',
                shortcut: 'Ctrl+C',
                onPressed: () => unawaited(widget.onCopy(items.single)),
              ),
            ]),
          UiContextMenuSection([
            UiContextMenuItem(
              label: '删除',
              onPressed: () => unawaited(widget.onDelete(items)),
            ),
          ]),
        ],
      ).whenComplete(() {
        if (mounted) setState(() => _contextMenuActive = false);
      }),
    );
  }
}

class _HistoryInteractiveTarget extends StatelessWidget {
  const _HistoryInteractiveTarget({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onTap: () {},
      child: child,
    );
  }
}

String _historySenderName(UserSummary user) {
  final roomName = user.roomDisplayName?.trim();
  if (roomName != null && roomName.isNotEmpty) return roomName;
  final displayName = user.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  return user.username;
}

class _HistoryMemberFilterResult {
  const _HistoryMemberFilterResult(this.member);

  final RoomMember? member;
}

class _HistoryMemberFilterDialog extends StatefulWidget {
  const _HistoryMemberFilterDialog({
    required this.members,
    required this.selectedMember,
  });

  final List<RoomMember> members;
  final RoomMember? selectedMember;

  @override
  State<_HistoryMemberFilterDialog> createState() =>
      _HistoryMemberFilterDialogState();
}

class _HistoryMemberFilterDialogState
    extends State<_HistoryMemberFilterDialog> {
  final TextEditingController _controller = TextEditingController();
  RoomMember? _selectedMember;

  @override
  void initState() {
    super.initState();
    _selectedMember = widget.selectedMember;
    _controller.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() => setState(() {});

  List<RoomMember> get _visibleMembers {
    final query = _controller.text.trim();
    final members = widget.members
        .where(
          (member) => member_filter.roomMemberSearchRank(member, query) < 99,
        )
        .toList(growable: false);
    members.sort((a, b) {
      final rank = member_filter
          .roomMemberSearchRank(a, query)
          .compareTo(member_filter.roomMemberSearchRank(b, query));
      if (rank != 0) return rank;
      return member_filter
          .roomMemberDisplayName(a)
          .toLowerCase()
          .compareTo(member_filter.roomMemberDisplayName(b).toLowerCase());
    });
    return members;
  }

  @override
  Widget build(BuildContext context) {
    final visibleMembers = _visibleMembers;
    return DialogFrame(
      title: '筛选消息成员',
      icon: Icons.person_search_outlined,
      maxWidth: 440,
      actions: [
        Button(
          key: const ValueKey('message-history-member-reset'),
          icon: const Icon(Icons.restart_alt),
          onPressed: () =>
              Navigator.of(context).pop(const _HistoryMemberFilterResult(null)),
          child: const Text('重置'),
        ),
        const Spacer(),
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        Button(
          key: const ValueKey('message-history-member-apply'),
          tone: ButtonTone.primary,
          icon: const Icon(Icons.check),
          onPressed: () => Navigator.of(
            context,
          ).pop(_HistoryMemberFilterResult(_selectedMember)),
          child: const Text('应用'),
        ),
      ],
      child: SizedBox(
        height: 360,
        child: Column(
          children: [
            Input(
              key: const ValueKey('message-history-member-search'),
              controller: _controller,
              hintText: '搜索成员',
              prefixIcon: Icons.search,
              showClearButton: true,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  _HistoryMemberOption(
                    label: '所有人',
                    selected: _selectedMember == null,
                    icon: Icons.groups_outlined,
                    onPressed: () => setState(() => _selectedMember = null),
                  ),
                  for (final member in visibleMembers)
                    _HistoryMemberOption(
                      label: member_filter.roomMemberDisplayName(member),
                      meta: member_filter.roomMemberMeta(member),
                      selected: _selectedMember?.user.id == member.user.id,
                      user: member.user,
                      onPressed: () => setState(() => _selectedMember = member),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryMemberOption extends StatelessWidget {
  const _HistoryMemberOption({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.meta,
    this.user,
    this.icon,
  });

  final String label;
  final String? meta;
  final UserSummary? user;
  final IconData? icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: PressableSurface(
        onPressed: onPressed,
        selected: selected,
        height: meta == null ? 46 : 54,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            if (user != null)
              Avatar(
                label: label,
                imageUrl: AppConfigScope.of(
                  context,
                ).resolveAssetUrl(user!.avatarUrl),
                defaultAvatarKey: user!.defaultAvatarKey,
                size: 30,
              )
            else
              SizedBox.square(
                dimension: 30,
                child: Icon(icon, color: UiColors.textSecondary, size: 19),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UiTypography.body.copyWith(color: UiColors.text),
                  ),
                  if (meta != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UiTypography.label.copyWith(
                        color: UiColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, color: UiColors.accent, size: 18),
          ],
        ),
      ),
    );
  }
}

class _HistoryDeleteConfirmDialog extends StatelessWidget {
  const _HistoryDeleteConfirmDialog({required this.messageCount});

  final int messageCount;

  @override
  Widget build(BuildContext context) {
    return DialogFrame(
      title: messageCount == 1 ? '删除消息记录' : '删除选中的消息记录',
      icon: Icons.warning_amber_outlined,
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        Button(
          tone: ButtonTone.danger,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除'),
        ),
      ],
      child: Text(
        messageCount == 1
            ? '删除后仅会从当前账号看到的消息记录中移除，不会撤回或删除房间消息'
            : '确定删除所有选中的 $messageCount 条消息记录吗？删除只对当前账号生效',
        style: UiTypography.body,
      ),
    );
  }
}
