part of 'room_management.dart';

class _MemberFilters extends StatelessWidget {
  const _MemberFilters({
    required this.controller,
    required this.filterCounts,
    required this.presenceFilter,
    required this.roleFilter,
    required this.onPresenceChanged,
    required this.onRoleChanged,
  });

  final TextEditingController controller;
  final member_filter.RoomMemberFilterCounts filterCounts;
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
          showClearButton: true,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SegmentedControl<member_filter.RoomMemberPresenceFilter>(
                expanded: true,
                value: presenceFilter,
                onChanged: onPresenceChanged,
                segments: [
                  Segment(
                    value: member_filter.RoomMemberPresenceFilter.all,
                    label: member_filter.roomMemberPresenceFilterLabel(
                      member_filter.RoomMemberPresenceFilter.all,
                      filterCounts,
                    ),
                  ),
                  Segment(
                    value: member_filter.RoomMemberPresenceFilter.online,
                    label: member_filter.roomMemberPresenceFilterLabel(
                      member_filter.RoomMemberPresenceFilter.online,
                      filterCounts,
                    ),
                  ),
                  Segment(
                    value: member_filter.RoomMemberPresenceFilter.offline,
                    label: member_filter.roomMemberPresenceFilterLabel(
                      member_filter.RoomMemberPresenceFilter.offline,
                      filterCounts,
                    ),
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
                segments: [
                  Segment(
                    value: member_filter.RoomMemberRoleFilter.all,
                    label: member_filter.roomMemberRoleFilterLabel(
                      member_filter.RoomMemberRoleFilter.all,
                      filterCounts,
                    ),
                  ),
                  Segment(
                    value: member_filter.RoomMemberRoleFilter.member,
                    label: member_filter.roomMemberRoleFilterLabel(
                      member_filter.RoomMemberRoleFilter.member,
                      filterCounts,
                    ),
                  ),
                  Segment(
                    value: member_filter.RoomMemberRoleFilter.admin,
                    label: member_filter.roomMemberRoleFilterLabel(
                      member_filter.RoomMemberRoleFilter.admin,
                      filterCounts,
                    ),
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
    required this.currentUser,
    required this.live,
    required this.permission,
    required this.ownerUserId,
    required this.query,
    required this.busy,
    required this.onResolveProfile,
    required this.onResolveRoomProfile,
    required this.onOpenRoom,
    required this.onSetAdmin,
    required this.onUnsetAdmin,
    required this.onRemoveMember,
    required this.onTransferCreator,
  });

  final RoomMember member;
  final CurrentUser currentUser;
  final LiveState live;
  final member_filter.RoomMemberPermissionState permission;
  final String? ownerUserId;
  final String query;
  final bool busy;
  final Future<UserSummary> Function(UserSummary user) onResolveProfile;
  final RoomProfileResolver onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onOpenRoom;
  final VoidCallback onSetAdmin;
  final VoidCallback onUnsetAdmin;
  final VoidCallback onRemoveMember;
  final VoidCallback onTransferCreator;

  @override
  Widget build(BuildContext context) {
    final presence = member_filter.roomMemberPresence(member, live: live);
    final role = room_display.roomRoleLabel(
      member.user,
      ownerUserId: ownerUserId,
    );
    final avatar = Avatar(
      label: member_filter.roomMemberDisplayName(member),
      imageUrl: AppConfigScope.of(
        context,
      ).resolveAssetUrl(member.user.avatarUrl),
      defaultAvatarKey: member.user.defaultAvatarKey,
      size: 38,
    );
    return _RowSurface(
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            UserHoverCard(
              user: member.user,
              currentUser: currentUser,
              onResolveProfile: onResolveProfile,
              onResolveRoomProfile: onResolveRoomProfile,
              onEnterCommonRoom: onOpenRoom,
              child: avatar,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: HighlightedText(
                text: member_filter.roomMemberDisplayName(member),
                query: query,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UiTypography.body.copyWith(fontWeight: FontWeight.w600),
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
            ] else if (permission.canRoleEdit ||
                permission.canRemoveMember) ...[
              const SizedBox(width: 8),
              if (permission.canRoleEdit) ...[
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
              ],
              if (permission.canRemoveMember) ...[
                ButtonIcon(
                  tooltip: '踢出此用户',
                  icon: const Icon(Icons.person_remove_outlined),
                  tone: ButtonTone.danger,
                  onPressed: onRemoveMember,
                  size: 34,
                ),
                if (permission.canRoleEdit) const SizedBox(width: 6),
              ],
              if (permission.canRoleEdit)
                ButtonIcon(
                  tooltip: '转让创建者',
                  icon: const Icon(Icons.swap_horiz),
                  tone: ButtonTone.danger,
                  onPressed: onTransferCreator,
                  size: 34,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InviteSection extends StatelessWidget {
  const _InviteSection({
    required this.controller,
    required this.currentUser,
    required this.query,
    required this.searching,
    required this.results,
    required this.members,
    required this.pendingInviteUserIds,
    required this.busyUserIds,
    required this.error,
    required this.enabled,
    required this.onResolveProfile,
    required this.onResolveRoomProfile,
    required this.onOpenRoom,
    required this.onInvite,
  });

  final TextEditingController controller;
  final CurrentUser currentUser;
  final String query;
  final bool searching;
  final List<UserSummary> results;
  final List<RoomMember> members;
  final Set<String> pendingInviteUserIds;
  final Set<String> busyUserIds;
  final String? error;
  final bool enabled;
  final Future<UserSummary> Function(UserSummary user) onResolveProfile;
  final RoomProfileResolver onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onOpenRoom;
  final ValueChanged<UserSummary> onInvite;

  @override
  Widget build(BuildContext context) {
    final candidates = room_invites.roomInviteCandidates(
      searchResults: results,
      members: members,
      query: query,
      pendingInviteUserIds: pendingInviteUserIds,
      busyUserIds: busyUserIds,
      invitesEnabled: enabled,
    );
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
              enabled: enabled,
              showClearButton: true,
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
            ] else if (enabled && query.length >= 2) ...[
              const SizedBox(height: 8),
              if (candidates.isEmpty)
                Text(
                  '未找到用户',
                  style: UiTypography.label.copyWith(color: UiColors.textMuted),
                )
              else
                for (final candidate in candidates.take(4)) ...[
                  _InviteUserRow(
                    user: candidate.user,
                    currentUser: currentUser,
                    query: query,
                    alreadyMember: candidate.existing,
                    pending: candidate.pending,
                    busy: candidate.busy,
                    enabled: enabled,
                    onResolveProfile: onResolveProfile,
                    onResolveRoomProfile: onResolveRoomProfile,
                    onOpenRoom: onOpenRoom,
                    onInvite: () => onInvite(candidate.user),
                  ),
                  if (candidate != candidates.take(4).last)
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
    required this.currentUser,
    required this.query,
    required this.alreadyMember,
    required this.pending,
    required this.busy,
    required this.enabled,
    required this.onResolveProfile,
    required this.onResolveRoomProfile,
    required this.onOpenRoom,
    required this.onInvite,
  });

  final UserSummary user;
  final CurrentUser currentUser;
  final String query;
  final bool alreadyMember;
  final bool pending;
  final bool busy;
  final bool enabled;
  final Future<UserSummary> Function(UserSummary user) onResolveProfile;
  final RoomProfileResolver onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onOpenRoom;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final actionLabel = alreadyMember ? '在房间内' : (pending ? '已邀请' : '邀请');
    return _RowSurface(
      compact: true,
      child: Row(
        children: [
          UserHoverCard(
            user: user,
            currentUser: currentUser,
            onResolveProfile: onResolveProfile,
            onResolveRoomProfile: onResolveRoomProfile,
            onEnterCommonRoom: onOpenRoom,
            child: Avatar(
              label: room_display.userPrimaryName(user),
              imageUrl: AppConfigScope.of(
                context,
              ).resolveAssetUrl(user.avatarUrl),
              defaultAvatarKey: user.defaultAvatarKey,
              size: 32,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: HighlightedText(
              text: room_display.userPrimaryName(user),
              query: query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.label.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Button(
            height: 34,
            loading: busy,
            onPressed: !enabled || alreadyMember || pending ? null : onInvite,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _JoinRequestsSection extends StatelessWidget {
  const _JoinRequestsSection({
    required this.requests,
    required this.currentUser,
    required this.busyRequestIds,
    required this.activeDetailRequestId,
    required this.error,
    required this.onResolveProfile,
    required this.onResolveRoomProfile,
    required this.onOpenRoom,
    required this.onDetail,
    required this.onApprove,
    required this.onReject,
  });

  final List<JoinRequest> requests;
  final CurrentUser currentUser;
  final Set<String> busyRequestIds;
  final String? activeDetailRequestId;
  final String? error;
  final Future<UserSummary> Function(UserSummary user) onResolveProfile;
  final RoomProfileResolver onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onOpenRoom;
  final ValueChanged<JoinRequest> onDetail;
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
                    currentUser: currentUser,
                    busy: busyRequestIds.contains(request.id),
                    detailActive: activeDetailRequestId == request.id,
                    onResolveProfile: onResolveProfile,
                    onResolveRoomProfile: onResolveRoomProfile,
                    onOpenRoom: onOpenRoom,
                    onDetail: () => onDetail(request),
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
    required this.currentUser,
    required this.busy,
    required this.detailActive,
    required this.onResolveProfile,
    required this.onResolveRoomProfile,
    required this.onOpenRoom,
    required this.onDetail,
    required this.onApprove,
    required this.onReject,
  });

  final JoinRequest request;
  final CurrentUser currentUser;
  final bool busy;
  final bool detailActive;
  final Future<UserSummary> Function(UserSummary user) onResolveProfile;
  final RoomProfileResolver onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onOpenRoom;
  final VoidCallback onDetail;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return _RowSurface(
      compact: true,
      child: Row(
        children: [
          UserHoverCard(
            user: request.user,
            currentUser: currentUser,
            onResolveProfile: onResolveProfile,
            onResolveRoomProfile: onResolveRoomProfile,
            onEnterCommonRoom: onOpenRoom,
            child: Avatar(
              label: room_display.userPrimaryName(request.user),
              imageUrl: AppConfigScope.of(
                context,
              ).resolveAssetUrl(request.user.avatarUrl),
              defaultAvatarKey: request.user.defaultAvatarKey,
              size: 32,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              room_display.userPrimaryName(request.user),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.label.copyWith(fontWeight: FontWeight.w600),
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
              tooltip: '详情',
              icon: const Icon(Icons.info_outline),
              selected: detailActive,
              onPressed: onDetail,
              size: 32,
            ),
            const SizedBox(width: 6),
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

class _JoinRequestDetailsDialog extends StatelessWidget {
  const _JoinRequestDetailsDialog({
    required this.request,
    required this.currentUser,
    required this.onResolveProfile,
    required this.onResolveRoomProfile,
    required this.onOpenRoom,
  });

  final JoinRequest request;
  final CurrentUser currentUser;
  final Future<UserSummary> Function(UserSummary user) onResolveProfile;
  final RoomProfileResolver onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onOpenRoom;

  @override
  Widget build(BuildContext context) {
    return DialogFrame(
      title: '申请详情',
      icon: Icons.fact_check_outlined,
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _JoinRequestDetailBlock(
            label: '来源',
            child: _JoinRequestSourceContent(
              request: request,
              currentUser: currentUser,
              onResolveProfile: onResolveProfile,
              onResolveRoomProfile: onResolveRoomProfile,
              onOpenRoom: onOpenRoom,
            ),
          ),
          const SizedBox(height: 14),
          _JoinRequestDetailBlock(
            label: '申请理由',
            child: Text(
              room_join_requests.joinRequestDetailReasonText(request),
              style: UiTypography.body,
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinRequestDetailBlock extends StatelessWidget {
  const _JoinRequestDetailBlock({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: UiTypography.label.copyWith(
            color: UiColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _JoinRequestSourceContent extends StatelessWidget {
  const _JoinRequestSourceContent({
    required this.request,
    required this.currentUser,
    required this.onResolveProfile,
    required this.onResolveRoomProfile,
    required this.onOpenRoom,
  });

  final JoinRequest request;
  final CurrentUser currentUser;
  final Future<UserSummary> Function(UserSummary user) onResolveProfile;
  final RoomProfileResolver onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onOpenRoom;

  @override
  Widget build(BuildContext context) {
    if (!room_join_requests.joinRequestFromInvitation(request) ||
        request.inviters.isEmpty) {
      return Text(
        room_join_requests.joinRequestSourceText(request),
        style: UiTypography.body.copyWith(fontWeight: FontWeight.w600),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final inviter in request.inviters) ...[
          _JoinRequestInviterSourceLine(
            user: inviter,
            currentUser: currentUser,
            onResolveProfile: onResolveProfile,
            onResolveRoomProfile: onResolveRoomProfile,
            onOpenRoom: onOpenRoom,
          ),
          if (inviter != request.inviters.last) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _JoinRequestInviterSourceLine extends StatelessWidget {
  const _JoinRequestInviterSourceLine({
    required this.user,
    required this.currentUser,
    required this.onResolveProfile,
    required this.onResolveRoomProfile,
    required this.onOpenRoom,
  });

  final UserSummary user;
  final CurrentUser currentUser;
  final Future<UserSummary> Function(UserSummary user) onResolveProfile;
  final RoomProfileResolver onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onOpenRoom;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        UserHoverCard(
          user: user,
          currentUser: currentUser,
          onResolveProfile: onResolveProfile,
          onResolveRoomProfile: onResolveRoomProfile,
          onEnterCommonRoom: onOpenRoom,
          child: Avatar(
            label: room_display.userPrimaryName(user),
            imageUrl: AppConfigScope.of(
              context,
            ).resolveAssetUrl(user.avatarUrl),
            defaultAvatarKey: user.defaultAvatarKey,
            size: 28,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${room_display.userPrimaryName(user)} 的邀请',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
