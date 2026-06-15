import 'dart:async';

import 'package:flutter/material.dart';

import '../app/room_notifications.dart';
import '../protocol/models.dart';
import '../ui/ui.dart';
import 'room_profile_card.dart';

typedef RoomInviteReviewCallback =
    Future<void> Function(RoomInvite invite, bool accept);
typedef RoomApplicationWithdrawCallback =
    Future<void> Function(RoomApplication application);

class HomeNotificationsPane extends StatefulWidget {
  const HomeNotificationsPane({
    super.key,
    required this.invites,
    required this.applications,
    required this.loading,
    required this.error,
    required this.busyInviteId,
    required this.busyApplicationId,
    required this.onClose,
    required this.onRefresh,
    required this.onReviewInvite,
    required this.onWithdrawApplication,
    required this.currentUser,
    required this.onOpenRoom,
  });

  final List<RoomInvite> invites;
  final List<RoomApplication> applications;
  final CurrentUser currentUser;
  final bool loading;
  final String? error;
  final String? busyInviteId;
  final String? busyApplicationId;
  final VoidCallback onClose;
  final VoidCallback onRefresh;
  final RoomInviteReviewCallback onReviewInvite;
  final RoomApplicationWithdrawCallback onWithdrawApplication;
  final ValueChanged<PublicRoom> onOpenRoom;

  @override
  State<HomeNotificationsPane> createState() => _HomeNotificationsPaneState();
}

class _HomeNotificationsPaneState extends State<HomeNotificationsPane> {
  final TextEditingController _searchController = TextEditingController();
  RoomNotificationFilter _filter = RoomNotificationFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() => _query = _searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = roomNotificationsForView(
      invites: widget.invites,
      applications: widget.applications,
      query: _query,
      filter: _filter,
    );
    final rawNotificationCount =
        widget.invites.length + widget.applications.length;
    return SettingsScaffold(
      icon: Icons.notifications_none,
      title: '通知',
      onBack: widget.onClose,
      headerAction: ButtonIcon(
        tooltip: '刷新通知',
        icon: const Icon(Icons.refresh),
        onPressed: widget.loading ? null : widget.onRefresh,
        loading: widget.loading && rawNotificationCount > 0,
        size: 38,
      ),
      pinned: Column(
        children: [
          Input(
            controller: _searchController,
            hintText: '搜索通知',
            prefixIcon: Icons.search,
            showClearButton: true,
          ),
          const SizedBox(height: 12),
          SegmentedControl<RoomNotificationFilter>(
            expanded: true,
            value: _filter,
            segments: const [
              Segment(
                value: RoomNotificationFilter.all,
                label: '全部',
                icon: Icons.inbox_outlined,
              ),
              Segment(
                value: RoomNotificationFilter.invites,
                label: '邀请',
                icon: Icons.mail_outline,
              ),
              Segment(
                value: RoomNotificationFilter.applications,
                label: '申请',
                icon: Icons.assignment_turned_in_outlined,
              ),
              Segment(
                value: RoomNotificationFilter.roomNotifications,
                label: '房间通知',
                icon: Icons.meeting_room_outlined,
              ),
            ],
            onChanged: (value) => setState(() => _filter = value),
          ),
        ],
      ),
      body: _NotificationsBody(
        items: visibleItems,
        loading: widget.loading,
        error: widget.error,
        rawNotificationCount: rawNotificationCount,
        query: _query,
        filter: _filter,
        busyInviteId: widget.busyInviteId,
        busyApplicationId: widget.busyApplicationId,
        onRefresh: widget.onRefresh,
        onReviewInvite: widget.onReviewInvite,
        onWithdrawApplication: widget.onWithdrawApplication,
        currentUser: widget.currentUser,
        onOpenRoom: widget.onOpenRoom,
      ),
    );
  }
}

class _NotificationsBody extends StatelessWidget {
  const _NotificationsBody({
    required this.items,
    required this.loading,
    required this.error,
    required this.rawNotificationCount,
    required this.query,
    required this.filter,
    required this.busyInviteId,
    required this.busyApplicationId,
    required this.onRefresh,
    required this.onReviewInvite,
    required this.onWithdrawApplication,
    required this.currentUser,
    required this.onOpenRoom,
  });

  final List<RoomNotificationItem> items;
  final CurrentUser currentUser;
  final bool loading;
  final String? error;
  final int rawNotificationCount;
  final String query;
  final RoomNotificationFilter filter;
  final String? busyInviteId;
  final String? busyApplicationId;
  final VoidCallback onRefresh;
  final RoomInviteReviewCallback onReviewInvite;
  final RoomApplicationWithdrawCallback onWithdrawApplication;
  final ValueChanged<PublicRoom> onOpenRoom;

  @override
  Widget build(BuildContext context) {
    if (loading && rawNotificationCount == 0) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: UiColors.accent,
          ),
        ),
      );
    }

    if (error != null && rawNotificationCount == 0) {
      return _NotificationEmptyState(
        icon: Icons.error_outline,
        title: '通知加载失败',
        subtitle: error!,
        actionLabel: '重试',
        onAction: onRefresh,
        danger: true,
      );
    }

    if (items.isEmpty) {
      return _NotificationEmptyState(
        icon: _emptyIcon(filter),
        title: _emptyTitle(filter: filter, query: query),
      );
    }

    final itemCount = items.length + (error == null ? 0 : 1);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (error != null && index == 0) {
          return _NotificationErrorStrip(message: error!);
        }
        final item = items[index - (error == null ? 0 : 1)];
        return switch (item.type) {
          RoomNotificationItemType.invite => _RoomInviteNotificationRow(
            invite: item.invite!,
            query: query,
            busy: busyInviteId == item.invite!.id,
            busyInviteId: busyInviteId,
            onReviewInvite: onReviewInvite,
            currentUser: currentUser,
            onOpenRoom: onOpenRoom,
          ),
          RoomNotificationItemType.applicationRequested =>
            _RoomApplicationRequestNotificationRow(
              application: item.application!,
              query: query,
              busy: busyApplicationId == item.application!.id,
              busyApplicationId: busyApplicationId,
              onWithdrawApplication: onWithdrawApplication,
              currentUser: currentUser,
              onOpenRoom: onOpenRoom,
            ),
          RoomNotificationItemType.applicationReviewed =>
            _RoomApplicationReviewNotificationRow(
              application: item.application!,
              query: query,
              currentUser: currentUser,
              onOpenRoom: onOpenRoom,
            ),
        };
      },
    );
  }
}

class _RoomInviteNotificationRow extends StatelessWidget {
  const _RoomInviteNotificationRow({
    required this.invite,
    required this.query,
    required this.busy,
    required this.busyInviteId,
    required this.onReviewInvite,
    required this.currentUser,
    required this.onOpenRoom,
  });

  final RoomInvite invite;
  final String query;
  final bool busy;
  final String? busyInviteId;
  final RoomInviteReviewCallback onReviewInvite;
  final CurrentUser currentUser;
  final ValueChanged<PublicRoom> onOpenRoom;

  @override
  Widget build(BuildContext context) {
    final room = invite.room;
    final inviter = invite.inviter;
    final inviterName = _displayName(inviter);
    final role = roomInviteRoleLabel(inviter);
    final time = roomInviteTimestampLabel(invite.createdAt);
    final invalid = isInvalidPendingRoomInvite(invite);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadii.lg),
        border: Border.all(
          color: isPendingRoomInvite(invite) && !invalid
              ? UiColors.accentBorder
              : UiColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 116,
              child: HighlightedText(
                text: time,
                query: query,
                key: ValueKey('notification-time-${invite.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UiTypography.label.copyWith(color: UiColors.textMuted),
              ),
            ),
            const SizedBox(width: 10),
            Avatar(
              key: ValueKey('notification-inviter-avatar-${invite.id}'),
              label: inviterName,
              imageUrl: AppConfigScope.of(
                context,
              ).resolveAssetUrl(inviter.avatarUrl),
              defaultAvatarKey: inviter.defaultAvatarKey,
              size: 34,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    flex: 3,
                    child: HighlightedText(
                      text: inviterName,
                      query: query,
                      key: ValueKey('notification-inviter-name-${invite.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: UiColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    flex: 2,
                    child: _InviteRoleBadge(
                      key: ValueKey('notification-inviter-role-${invite.id}'),
                      label: role,
                      query: query,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '邀请您加入',
                    key: ValueKey('notification-invite-action-${invite.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UiTypography.label.copyWith(
                      color: UiColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 4,
                    child: _InlineRoomTarget(
                      room: room,
                      inviteId: invite.id,
                      query: query,
                      roomExists: invite.roomExists,
                      currentUser: currentUser,
                      onOpenRoom: onOpenRoom,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 88,
              child: Align(
                alignment: Alignment.centerRight,
                child: invalid
                    ? _InvalidInviteLabel(invite: invite, query: query)
                    : isPendingRoomInvite(invite)
                    ? _InviteDecisionActions(
                        invite: invite,
                        busy: busy,
                        enabled: canReviewNotificationInvite(
                          invite: invite,
                          busyInviteId: busyInviteId,
                        ),
                        onReviewInvite: onReviewInvite,
                      )
                    : _ProcessedInviteLabel(invite: invite, query: query),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomApplicationRequestNotificationRow extends StatelessWidget {
  const _RoomApplicationRequestNotificationRow({
    required this.application,
    required this.query,
    required this.busy,
    required this.busyApplicationId,
    required this.onWithdrawApplication,
    required this.currentUser,
    required this.onOpenRoom,
  });

  final RoomApplication application;
  final String query;
  final bool busy;
  final String? busyApplicationId;
  final RoomApplicationWithdrawCallback onWithdrawApplication;
  final CurrentUser currentUser;
  final ValueChanged<PublicRoom> onOpenRoom;

  @override
  Widget build(BuildContext context) {
    final room = application.room;
    final time = roomInviteTimestampLabel(application.createdAt);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadii.lg),
        border: Border.all(
          color: isPendingRoomApplication(application)
              ? UiColors.accentBorder
              : UiColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 116,
              child: HighlightedText(
                text: time,
                query: query,
                key: ValueKey(
                  'notification-application-time-${application.id}',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UiTypography.label.copyWith(color: UiColors.textMuted),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '您已申请加入',
              key: ValueKey(
                'notification-application-request-action-${application.id}',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.label.copyWith(
                color: UiColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _InlineRoomTarget(
                room: room,
                inviteId: 'application-${application.id}',
                query: query,
                roomExists: true,
                currentUser: currentUser,
                onOpenRoom: onOpenRoom,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 88,
              child: Align(
                alignment: Alignment.centerRight,
                child: isPendingRoomApplication(application)
                    ? _ApplicationWithdrawAction(
                        application: application,
                        busy: busy,
                        enabled: canWithdrawNotificationApplication(
                          application: application,
                          busyApplicationId: busyApplicationId,
                        ),
                        onWithdrawApplication: onWithdrawApplication,
                      )
                    : _ProcessedApplicationLabel(
                        application: application,
                        query: query,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomApplicationReviewNotificationRow extends StatelessWidget {
  const _RoomApplicationReviewNotificationRow({
    required this.application,
    required this.query,
    required this.currentUser,
    required this.onOpenRoom,
  });

  final RoomApplication application;
  final String query;
  final CurrentUser currentUser;
  final ValueChanged<PublicRoom> onOpenRoom;

  @override
  Widget build(BuildContext context) {
    final room = application.room;
    final reviewer = application.reviewer!;
    final reviewerName = _displayName(reviewer);
    final role = roomInviteRoleLabel(reviewer);
    final time = roomInviteTimestampLabel(
      application.reviewedAt ?? application.updatedAt,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadii.lg),
        border: Border.all(color: UiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 116,
              child: HighlightedText(
                text: time,
                query: query,
                key: ValueKey(
                  'notification-application-review-time-${application.id}',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UiTypography.label.copyWith(color: UiColors.textMuted),
              ),
            ),
            const SizedBox(width: 10),
            Avatar(
              key: ValueKey(
                'notification-application-reviewer-avatar-${application.id}',
              ),
              label: reviewerName,
              imageUrl: AppConfigScope.of(
                context,
              ).resolveAssetUrl(reviewer.avatarUrl),
              defaultAvatarKey: reviewer.defaultAvatarKey,
              size: 34,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    flex: 3,
                    child: HighlightedText(
                      text: reviewerName,
                      query: query,
                      key: ValueKey(
                        'notification-application-reviewer-name-${application.id}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: UiColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    flex: 2,
                    child: _InviteRoleBadge(
                      key: ValueKey(
                        'notification-application-reviewer-role-${application.id}',
                      ),
                      label: role,
                      query: query,
                    ),
                  ),
                  const SizedBox(width: 8),
                  HighlightedText(
                    text: roomApplicationReviewActionLabel(application),
                    query: query,
                    key: ValueKey(
                      'notification-application-review-action-${application.id}',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UiTypography.label.copyWith(
                      color: UiColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 4,
                    child: _InlineRoomTarget(
                      room: room,
                      inviteId: 'application-reviewed-${application.id}',
                      query: query,
                      roomExists: true,
                      currentUser: currentUser,
                      onOpenRoom: onOpenRoom,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const SizedBox(width: 88),
          ],
        ),
      ),
    );
  }
}

class _InviteRoleBadge extends StatelessWidget {
  const _InviteRoleBadge({super.key, required this.label, required this.query});

  final String label;
  final String query;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surfacePressed,
        borderRadius: BorderRadius.circular(UiRadii.sm),
        border: Border.all(color: UiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: HighlightedText(
          text: label,
          query: query,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiTypography.label.copyWith(
            color: UiColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _InlineRoomTarget extends StatelessWidget {
  const _InlineRoomTarget({
    required this.room,
    required this.inviteId,
    required this.query,
    required this.roomExists,
    required this.currentUser,
    required this.onOpenRoom,
  });

  final PublicRoom room;
  final String inviteId;
  final String query;
  final bool roomExists;
  final CurrentUser currentUser;
  final ValueChanged<PublicRoom> onOpenRoom;

  @override
  Widget build(BuildContext context) {
    final config = AppConfigScope.of(context);
    final roomLabel = roomNotificationRoomLabel(room, roomExists: roomExists);
    final avatar = Avatar(
      key: ValueKey('notification-room-avatar-$inviteId'),
      label: roomLabel,
      imageUrl: config.resolveAssetUrl(
        roomNotificationRoomAvatarUrl(room, roomExists: roomExists),
      ),
      defaultAvatarKey: roomNotificationRoomAvatarKey(
        room,
        roomExists: roomExists,
      ),
      size: 34,
    );
    final avatarTarget = roomNotificationRoomCardEnabled(roomExists: roomExists)
        ? RoomHoverCard(
            room: room,
            currentUser: currentUser,
            onEnterRoom: room.joined ? onOpenRoom : null,
            child: avatar,
          )
        : avatar;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        avatarTarget,
        const SizedBox(width: 5),
        Flexible(
          child: HighlightedText(
            text: roomLabel,
            query: query,
            key: ValueKey('notification-room-name-$inviteId'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.label.copyWith(
              color: UiColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _InviteDecisionActions extends StatelessWidget {
  const _InviteDecisionActions({
    required this.invite,
    required this.busy,
    required this.enabled,
    required this.onReviewInvite,
  });

  final RoomInvite invite;
  final bool busy;
  final bool enabled;
  final RoomInviteReviewCallback onReviewInvite;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ButtonIcon(
          tooltip: '拒绝邀请',
          icon: const Icon(Icons.close),
          tone: ButtonTone.danger,
          onPressed: enabled
              ? () => unawaited(onReviewInvite(invite, false))
              : null,
          size: 34,
        ),
        const SizedBox(width: 8),
        ButtonIcon(
          tooltip: '接受邀请',
          icon: const Icon(Icons.check),
          tone: ButtonTone.primary,
          onPressed: enabled
              ? () => unawaited(onReviewInvite(invite, true))
              : null,
          loading: busy,
          size: 34,
        ),
      ],
    );
  }
}

class _ApplicationWithdrawAction extends StatelessWidget {
  const _ApplicationWithdrawAction({
    required this.application,
    required this.busy,
    required this.enabled,
    required this.onWithdrawApplication,
  });

  final RoomApplication application;
  final bool busy;
  final bool enabled;
  final RoomApplicationWithdrawCallback onWithdrawApplication;

  @override
  Widget build(BuildContext context) {
    return Button(
      tooltip: '撤回申请',
      tone: ButtonTone.danger,
      onPressed: enabled
          ? () => unawaited(onWithdrawApplication(application))
          : null,
      loading: busy,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: const Text('撤回'),
    );
  }
}

class _InvalidInviteLabel extends StatelessWidget {
  const _InvalidInviteLabel({required this.invite, required this.query});

  final RoomInvite invite;
  final String query;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surfacePressed,
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(color: UiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: HighlightedText(
          text: roomInviteDecisionLabel(invite),
          query: query,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiTypography.label.copyWith(
            color: UiColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ProcessedInviteLabel extends StatelessWidget {
  const _ProcessedInviteLabel({required this.invite, required this.query});

  final RoomInvite invite;
  final String query;

  @override
  Widget build(BuildContext context) {
    final accepted = isAcceptedRoomInvite(invite);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accepted ? UiColors.selected : const Color(0xFF2E1F22),
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(
          color: accepted ? UiColors.accentBorder : UiColors.dangerBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: HighlightedText(
          text: roomInviteDecisionLabel(invite),
          query: query,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiTypography.label.copyWith(
            color: accepted ? UiColors.accent : UiColors.danger,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ProcessedApplicationLabel extends StatelessWidget {
  const _ProcessedApplicationLabel({
    required this.application,
    required this.query,
  });

  final RoomApplication application;
  final String query;

  @override
  Widget build(BuildContext context) {
    final approved = isApprovedRoomApplication(application);
    final rejected = isRejectedRoomApplication(application);
    final label = roomApplicationStatusLabel(application);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: approved
            ? UiColors.selected
            : rejected
            ? const Color(0xFF2E1F22)
            : UiColors.surfacePressed,
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(
          color: approved
              ? UiColors.accentBorder
              : rejected
              ? UiColors.dangerBorder
              : UiColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: HighlightedText(
          text: label,
          query: query,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: UiTypography.label.copyWith(
            color: approved
                ? UiColors.accent
                : rejected
                ? UiColors.danger
                : UiColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _NotificationErrorStrip extends StatelessWidget {
  const _NotificationErrorStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF2E1F22),
        borderRadius: BorderRadius.circular(UiRadii.lg),
        border: Border.all(color: UiColors.dangerBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: UiColors.danger, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: UiTypography.label.copyWith(color: UiColors.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: danger ? UiColors.danger : UiColors.textMuted,
              size: 30,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: UiTypography.body.copyWith(
                color: danger ? UiColors.danger : UiColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: UiTypography.label.copyWith(color: UiColors.textMuted),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              Button(
                icon: const Icon(Icons.refresh),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

IconData _emptyIcon(RoomNotificationFilter filter) {
  return switch (filter) {
    RoomNotificationFilter.all => Icons.notifications_none,
    RoomNotificationFilter.invites => Icons.mail_outline,
    RoomNotificationFilter.applications => Icons.assignment_turned_in_outlined,
    RoomNotificationFilter.roomNotifications => Icons.meeting_room_outlined,
  };
}

String _emptyTitle({
  required RoomNotificationFilter filter,
  required String query,
}) {
  if (query.trim().isNotEmpty) return '没有匹配通知';
  return switch (filter) {
    RoomNotificationFilter.all => '暂无通知',
    RoomNotificationFilter.invites => '暂无邀请',
    RoomNotificationFilter.applications => '暂无申请',
    RoomNotificationFilter.roomNotifications => '暂无房间通知',
  };
}

String _displayName(UserSummary user) {
  final roomName = user.roomDisplayName?.trim();
  if (roomName != null && roomName.isNotEmpty) return roomName;
  final displayName = user.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  return user.username;
}
