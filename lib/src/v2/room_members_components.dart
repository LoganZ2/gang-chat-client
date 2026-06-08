part of 'room_management.dart';

class _MemberFilters extends StatelessWidget {
  const _MemberFilters({
    required this.controller,
    required this.presenceFilter,
    required this.roleFilter,
    required this.onPresenceChanged,
    required this.onRoleChanged,
  });

  final TextEditingController controller;
  final member_filter.RoomMemberPresenceFilter presenceFilter;
  final member_filter.RoomMemberRoleFilter roleFilter;
  final ValueChanged<member_filter.RoomMemberPresenceFilter> onPresenceChanged;
  final ValueChanged<member_filter.RoomMemberRoleFilter> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Input(
          controller: controller,
          hintText: '搜索成员',
          prefixIcon: Icons.search,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SegmentedControl<member_filter.RoomMemberPresenceFilter>(
                expanded: true,
                value: presenceFilter,
                onChanged: onPresenceChanged,
                segments: const [
                  Segment(
                    value: member_filter.RoomMemberPresenceFilter.all,
                    label: '全部',
                  ),
                  Segment(
                    value: member_filter.RoomMemberPresenceFilter.online,
                    label: '在线',
                  ),
                  Segment(
                    value: member_filter.RoomMemberPresenceFilter.offline,
                    label: '离线',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SegmentedControl<member_filter.RoomMemberRoleFilter>(
                expanded: true,
                value: roleFilter,
                onChanged: onRoleChanged,
                segments: const [
                  Segment(
                    value: member_filter.RoomMemberRoleFilter.all,
                    label: '所有身份',
                  ),
                  Segment(
                    value: member_filter.RoomMemberRoleFilter.member,
                    label: '成员',
                  ),
                  Segment(
                    value: member_filter.RoomMemberRoleFilter.admin,
                    label: '管理员',
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.live,
    required this.permission,
    required this.ownerUserId,
    required this.busy,
    required this.onSetAdmin,
    required this.onUnsetAdmin,
    required this.onTransferCreator,
  });

  final RoomMember member;
  final LiveState live;
  final member_filter.RoomMemberPermissionState permission;
  final String? ownerUserId;
  final bool busy;
  final VoidCallback onSetAdmin;
  final VoidCallback onUnsetAdmin;
  final VoidCallback onTransferCreator;

  @override
  Widget build(BuildContext context) {
    final presence = member_filter.roomMemberPresence(member, live: live);
    final role = room_display.roomRoleLabel(
      member.user,
      ownerUserId: ownerUserId,
    );
    return _RowSurface(
      child: Row(
        children: [
          Avatar(
            label: member_filter.roomMemberDisplayName(member),
            imageUrl: AppConfigScope.of(
              context,
            ).resolveAssetUrl(member.user.avatarUrl),
            active: presence != member_filter.RoomMemberPresence.offline,
            activeBorderWidth: 1.1,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  member_filter.roomMemberDisplayName(member),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: UiTypography.body.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  member_filter.roomMemberMeta(member),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: UiTypography.label.copyWith(color: UiColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _Pill(
            label: member_filter.roomMemberPresenceLabel(presence),
            active: presence == member_filter.RoomMemberPresence.live,
          ),
          const SizedBox(width: 6),
          _Pill(label: role),
          if (busy) ...[
            const SizedBox(width: 10),
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                color: UiColors.accent,
                strokeWidth: 2,
              ),
            ),
          ] else if (permission.canRoleEdit) ...[
            const SizedBox(width: 8),
            ButtonIcon(
              tooltip: permission.isAdmin ? '移除管理员' : '设为管理员',
              icon: Icon(
                permission.isAdmin
                    ? Icons.admin_panel_settings_outlined
                    : Icons.admin_panel_settings,
              ),
              selected: permission.isAdmin,
              onPressed: permission.isAdmin ? onUnsetAdmin : onSetAdmin,
              size: 34,
            ),
            const SizedBox(width: 6),
            ButtonIcon(
              tooltip: '转让群主',
              icon: const Icon(Icons.swap_horiz),
              tone: ButtonTone.danger,
              onPressed: onTransferCreator,
              size: 34,
            ),
          ],
        ],
      ),
    );
  }
}

class _InviteSection extends StatelessWidget {
  const _InviteSection({
    required this.controller,
    required this.query,
    required this.searching,
    required this.results,
    required this.members,
    required this.busyUserIds,
    required this.error,
    required this.onInvite,
  });

  final TextEditingController controller;
  final String query;
  final bool searching;
  final List<UserSummary> results;
  final List<RoomMember> members;
  final Set<String> busyUserIds;
  final String? error;
  final ValueChanged<UserSummary> onInvite;

  @override
  Widget build(BuildContext context) {
    final memberIds = members.map((member) => member.user.id).toSet();
    return SettingsCard(
      title: '邀请成员',
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Input(
              controller: controller,
              hintText: '按用户名、昵称或 UID 搜索',
              prefixIcon: Icons.person_add_alt_1,
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              _NoticeStrip(message: error!, danger: true),
            ],
            if (searching) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(
                minHeight: 2,
                color: UiColors.accent,
                backgroundColor: UiColors.surfacePressed,
              ),
            ] else if (query.length >= 2) ...[
              const SizedBox(height: 8),
              if (results.isEmpty)
                Text(
                  '未找到用户',
                  style: UiTypography.label.copyWith(color: UiColors.textMuted),
                )
              else
                for (final user in results.take(4)) ...[
                  _InviteUserRow(
                    user: user,
                    alreadyMember: memberIds.contains(user.id),
                    busy: busyUserIds.contains(user.id),
                    onInvite: () => onInvite(user),
                  ),
                  if (user != results.take(4).last)
                    const SizedBox(height: 6),
                ],
            ],
          ],
        ),
      ],
    );
  }
}

class _InviteUserRow extends StatelessWidget {
  const _InviteUserRow({
    required this.user,
    required this.alreadyMember,
    required this.busy,
    required this.onInvite,
  });

  final UserSummary user;
  final bool alreadyMember;
  final bool busy;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return _RowSurface(
      compact: true,
      child: Row(
        children: [
          Avatar(
            label: room_display.userPrimaryName(user),
            imageUrl: AppConfigScope.of(
              context,
            ).resolveAssetUrl(user.avatarUrl),
            size: 32,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${room_display.userPrimaryName(user)} · @${user.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.label.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          Button(
            height: 34,
            loading: busy,
            onPressed: alreadyMember ? null : onInvite,
            child: Text(alreadyMember ? '成员' : '邀请'),
          ),
        ],
      ),
    );
  }
}

class _JoinRequestsSection extends StatelessWidget {
  const _JoinRequestsSection({
    required this.requests,
    required this.busyRequestIds,
    required this.error,
    required this.onApprove,
    required this.onReject,
  });

  final List<JoinRequest> requests;
  final Set<String> busyRequestIds;
  final String? error;
  final ValueChanged<JoinRequest> onApprove;
  final ValueChanged<JoinRequest> onReject;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: '加入申请',
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) _NoticeStrip(message: error!, danger: true),
              if (requests.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(
                    '暂无待处理申请',
                    style: UiTypography.label.copyWith(
                      color: UiColors.textMuted,
                    ),
                  ),
                )
              else
                for (final request in requests) ...[
                  _JoinRequestRow(
                    request: request,
                    busy: busyRequestIds.contains(request.id),
                    onApprove: () => onApprove(request),
                    onReject: () => onReject(request),
                  ),
                  if (request != requests.last) const SizedBox(height: 6),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _JoinRequestRow extends StatelessWidget {
  const _JoinRequestRow({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final JoinRequest request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return _RowSurface(
      compact: true,
      child: Row(
        children: [
          Avatar(
            label: room_display.userPrimaryName(request.user),
            imageUrl: AppConfigScope.of(
              context,
            ).resolveAssetUrl(request.user.avatarUrl),
            size: 32,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${room_display.userPrimaryName(request.user)} · @${request.user.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.label.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          if (busy)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                color: UiColors.accent,
                strokeWidth: 2,
              ),
            )
          else ...[
            ButtonIcon(
              tooltip: '拒绝',
              icon: const Icon(Icons.close),
              tone: ButtonTone.danger,
              onPressed: onReject,
              size: 32,
            ),
            const SizedBox(width: 6),
            ButtonIcon(
              tooltip: '通过',
              icon: const Icon(Icons.check),
              tone: ButtonTone.primary,
              onPressed: onApprove,
              size: 32,
            ),
          ],
        ],
      ),
    );
  }
}
