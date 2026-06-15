import 'package:flutter/material.dart';

import '../app/room_display.dart' as room_display;
import '../protocol/models.dart';
import '../ui/ui.dart';
import 'hover_card_anchor.dart';

class RoomHoverCard extends StatelessWidget {
  const RoomHoverCard({
    super.key,
    required this.room,
    required this.currentUser,
    required this.child,
    this.onEnterRoom,
  });

  final PublicRoom room;
  final CurrentUser currentUser;
  final Widget child;
  final ValueChanged<PublicRoom>? onEnterRoom;

  @override
  Widget build(BuildContext context) {
    return HoverCardAnchor(
      resetKey: room.id,
      cardBuilder: (context) => _RoomProfileCard(
        room: room,
        currentUser: currentUser,
        onEnterRoom: onEnterRoom,
      ),
      child: child,
    );
  }
}

class _RoomProfileCard extends StatelessWidget {
  const _RoomProfileCard({
    required this.room,
    required this.currentUser,
    this.onEnterRoom,
  });

  final PublicRoom room;
  final CurrentUser currentUser;
  final ValueChanged<PublicRoom>? onEnterRoom;

  @override
  Widget build(BuildContext context) {
    final config = AppConfigScope.of(context);
    final description = _nonEmpty(room.description);
    final rid = _nonEmpty(room.rid) ?? room.id;
    final creator = room.createdBy;
    final joined = room.joined;
    final myName = _myRoomDisplayName(room, currentUser);
    final myAvatarUrl = _myRoomAvatarUrl(room, currentUser);
    final myDefaultAvatarKey = _myRoomDefaultAvatarKey(room, currentUser);
    final myRole = _myRoomRoleLabel(room, currentUser);

    return Padding(
      padding: const EdgeInsets.all(UiSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(
                label: room.name,
                imageUrl: config.resolveAssetUrl(room.avatarUrl),
                defaultAvatarKey: room.defaultAvatarKey,
                size: 48,
                activeBorderWidth: 2,
              ),
              const SizedBox(width: UiSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      room.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UiTypography.title.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${room.memberCount} 名成员',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UiTypography.label.copyWith(
                        color: UiColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: UiSpacing.md),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusBadge(
                label: room.joined ? '已加入' : '未加入',
                icon: room.joined ? Icons.check_circle : Icons.circle_outlined,
                active: room.joined,
              ),
              StatusBadge(label: room_display.visibilityLabel(room.visibility)),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: UiSpacing.md),
            Text(
              description,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.body.copyWith(color: UiColors.textSecondary),
            ),
          ],
          if (creator != null) ...[
            const SizedBox(height: UiSpacing.md),
            Text(
              '创建者',
              style: UiTypography.label.copyWith(color: UiColors.textMuted),
            ),
            const SizedBox(height: UiSpacing.xs),
            _RoomCardPersonRow(
              avatarLabel: room_display.userPrimaryName(creator),
              avatarUrl: creator.avatarUrl,
              defaultAvatarKey: creator.defaultAvatarKey,
              name: room_display.userPrimaryName(creator),
            ),
          ],
          if (joined) ...[
            const SizedBox(height: UiSpacing.md),
            Text(
              '我的房间内信息',
              style: UiTypography.label.copyWith(color: UiColors.textMuted),
            ),
            const SizedBox(height: UiSpacing.xs),
            _RoomCardPersonRow(
              avatarLabel: myName,
              avatarUrl: myAvatarUrl,
              defaultAvatarKey: myDefaultAvatarKey,
              name: myName,
              trailing: StatusBadge(label: myRole),
            ),
            const SizedBox(height: UiSpacing.md),
            Center(
              child: Button(
                icon: const Icon(Icons.login_rounded),
                tone: ButtonTone.primary,
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                onPressed: onEnterRoom == null
                    ? null
                    : () => onEnterRoom!(room),
                child: const Text('进入房间'),
              ),
            ),
          ],
          const SizedBox(height: UiSpacing.sm),
          Text(
            'RID: $rid',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.label.copyWith(color: UiColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _RoomCardPersonRow extends StatelessWidget {
  const _RoomCardPersonRow({
    required this.avatarLabel,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    required this.name,
    this.trailing,
  });

  final String avatarLabel;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final String name;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Avatar(
          label: avatarLabel,
          imageUrl: AppConfigScope.of(context).resolveAssetUrl(avatarUrl),
          defaultAvatarKey: defaultAvatarKey,
          size: 20,
          activeBorderWidth: 1,
        ),
        const SizedBox(width: UiSpacing.sm),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.body.copyWith(
              color: UiColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: UiSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

String _myRoomDisplayName(PublicRoom room, CurrentUser currentUser) {
  return _nonEmpty(room.personalProfile.displayName) ?? currentUser.displayName;
}

String? _myRoomAvatarUrl(PublicRoom room, CurrentUser currentUser) {
  return _nonEmpty(room.personalProfile.avatarUrl) ?? currentUser.avatarUrl;
}

String _myRoomDefaultAvatarKey(PublicRoom room, CurrentUser currentUser) {
  return _nonEmpty(room.personalProfile.defaultAvatarKey) ??
      currentUser.defaultAvatarKey;
}

String _myRoomRoleLabel(PublicRoom room, CurrentUser currentUser) {
  final role = room_display.roomRoleLabelFromValue(room.myMembership?.role);
  if (role != null) return role;
  return currentUser.isSuperuser ? '超级用户' : '成员';
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

@visibleForTesting
class RoomHoverCardForTest extends StatelessWidget {
  const RoomHoverCardForTest({
    super.key,
    required this.room,
    required this.currentUser,
    this.onEnterRoom,
  });

  final PublicRoom room;
  final CurrentUser currentUser;
  final ValueChanged<PublicRoom>? onEnterRoom;

  @override
  Widget build(BuildContext context) {
    return RoomHoverCard(
      room: room,
      currentUser: currentUser,
      onEnterRoom: onEnterRoom,
      child: Avatar(label: room.name, size: 34),
    );
  }
}
