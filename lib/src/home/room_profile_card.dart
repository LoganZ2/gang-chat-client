import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/room_display.dart' as room_display;
import '../protocol/models.dart';
import '../ui/ui.dart';
import 'chat_image_preview.dart';
import 'hover_card_anchor.dart';

typedef RoomProfileResolver = Future<PublicRoom> Function(PublicRoom room);
typedef UserProfileResolver = Future<UserSummary> Function(UserSummary user);
typedef UserProfileActionBuilder =
    UserProfileAction? Function(UserSummary user);

class UserProfileAction {
  const UserProfileAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class RoomHoverCard extends StatefulWidget {
  const RoomHoverCard({
    super.key,
    required this.room,
    required this.currentUser,
    required this.child,
    this.onResolveRoom,
    this.onResolveUserProfile,
    this.onEnterRoom,
  });

  final PublicRoom room;
  final CurrentUser currentUser;
  final Widget child;
  final RoomProfileResolver? onResolveRoom;
  final UserProfileResolver? onResolveUserProfile;
  final ValueChanged<PublicRoom>? onEnterRoom;

  @override
  State<RoomHoverCard> createState() => _RoomHoverCardState();
}

class _RoomHoverCardState extends State<RoomHoverCard> {
  PublicRoom? _resolved;
  Future<void>? _resolveFuture;

  PublicRoom get _displayRoom => _resolved ?? widget.room;

  @override
  void didUpdateWidget(covariant RoomHoverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final roomChanged = oldWidget.room.id != widget.room.id;
    final resolverPresenceChanged =
        (oldWidget.onResolveRoom == null) != (widget.onResolveRoom == null);
    if (!roomChanged && !resolverPresenceChanged) return;
    _resolved = null;
    _resolveFuture = null;
  }

  Future<void> _resolveRoom() {
    final resolver = widget.onResolveRoom;
    if (resolver == null) return Future<void>.value();
    final existing = _resolveFuture;
    if (existing != null) return existing;

    final requestedRoom = widget.room;
    final future = () async {
      try {
        final room = await resolver(requestedRoom);
        if (!mounted || widget.room.id != requestedRoom.id) return;
        setState(() => _resolved = room);
      } catch (_) {
        if (!mounted || widget.room.id != requestedRoom.id) return;
        // Fall back to the current lightweight summary instead of keeping a
        // previously resolved card that may now be stale.
        setState(() => _resolved = null);
      } finally {
        if (mounted && widget.room.id == requestedRoom.id) {
          _resolveFuture = null;
        }
      }
    }();
    _resolveFuture = future;
    return future;
  }

  @override
  Widget build(BuildContext context) {
    return HoverCardAnchor(
      resetKey: Object.hash(
        widget.room.id,
        widget.onResolveRoom != null,
        widget.onResolveUserProfile != null,
      ),
      onBeforeOpen: widget.onResolveRoom == null ? null : _resolveRoom,
      cardBuilder: (context) => _RoomProfileCard(
        room: _displayRoom,
        currentUser: widget.currentUser,
        onResolveRoomProfile: widget.onResolveRoom,
        onResolveUserProfile: widget.onResolveUserProfile,
        onEnterRoom: widget.onEnterRoom,
      ),
      child: widget.child,
    );
  }
}

class UserHoverCard extends StatefulWidget {
  const UserHoverCard({
    super.key,
    required this.user,
    required this.child,
    this.currentUser,
    this.onResolveProfile,
    this.onResolveRoomProfile,
    this.onEnterCommonRoom,
    this.profileActionBuilder,
    this.inLive = false,
    this.showRoomRole = false,
  });

  final UserSummary user;
  final Widget child;
  final CurrentUser? currentUser;
  final bool inLive;
  final bool showRoomRole;

  /// Fetches a richer, up-to-date profile (gender, common rooms) before the
  /// card opens. When null the card shows only the supplied summary.
  final UserProfileResolver? onResolveProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterCommonRoom;
  final UserProfileActionBuilder? profileActionBuilder;

  @override
  State<UserHoverCard> createState() => _UserHoverCardState();
}

Future<void> showUserProfileCardAtPosition(
  BuildContext context, {
  required Offset position,
  required UserSummary user,
  CurrentUser? currentUser,
  UserProfileResolver? onResolveProfile,
  RoomProfileResolver? onResolveRoomProfile,
  ValueChanged<PublicRoom>? onEnterCommonRoom,
  UserProfileActionBuilder? profileActionBuilder,
  bool inLive = false,
  bool showRoomRole = false,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    _UserProfileCardPopupRoute(
      position: position,
      user: user,
      currentUser: currentUser,
      onResolveProfile: onResolveProfile,
      onResolveRoomProfile: onResolveRoomProfile,
      onEnterCommonRoom: onEnterCommonRoom,
      profileActionBuilder: profileActionBuilder,
      inLive: inLive,
      showRoomRole: showRoomRole,
    ),
  );
}

class _UserHoverCardState extends State<UserHoverCard> {
  UserSummary? _resolved;
  Future<void>? _resolveFuture;

  UserSummary get _displayUser => _resolved ?? widget.user;

  @override
  void didUpdateWidget(covariant UserHoverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final userChanged = oldWidget.user.id != widget.user.id;
    final currentUserChanged =
        oldWidget.currentUser?.id != widget.currentUser?.id;
    final resolverPresenceChanged =
        (oldWidget.onResolveProfile == null) !=
        (widget.onResolveProfile == null);
    final liveChanged = oldWidget.inLive != widget.inLive;
    final roleVisibilityChanged = oldWidget.showRoomRole != widget.showRoomRole;
    final actionPresenceChanged =
        (oldWidget.profileActionBuilder == null) !=
        (widget.profileActionBuilder == null);
    if (!userChanged &&
        !currentUserChanged &&
        !resolverPresenceChanged &&
        !liveChanged &&
        !roleVisibilityChanged &&
        !actionPresenceChanged) {
      return;
    }
    _resolved = null;
    _resolveFuture = null;
  }

  Future<void> _resolveProfile() {
    final resolver = widget.onResolveProfile;
    if (resolver == null) return Future<void>.value();
    final existing = _resolveFuture;
    if (existing != null) return existing;

    final requestedUser = widget.user;
    final future = () async {
      try {
        final profile = await resolver(requestedUser);
        if (!mounted || widget.user.id != requestedUser.id) return;
        setState(() => _resolved = profile);
      } catch (_) {
        if (!mounted || widget.user.id != requestedUser.id) return;
        // Keep showing the current lightweight summary on failure.
        setState(() => _resolved = null);
      } finally {
        if (mounted && widget.user.id == requestedUser.id) {
          _resolveFuture = null;
        }
      }
    }();
    _resolveFuture = future;
    return future;
  }

  @override
  Widget build(BuildContext context) {
    return HoverCardAnchor(
      resetKey: Object.hash(
        widget.user.id,
        widget.onResolveProfile != null,
        widget.onResolveRoomProfile != null,
        widget.currentUser?.id,
        widget.inLive,
        widget.showRoomRole,
        widget.profileActionBuilder != null,
      ),
      onBeforeOpen: widget.onResolveProfile == null ? null : _resolveProfile,
      cardBuilder: (context) => _UserProfileCard(
        user: _displayUser,
        currentUser: widget.currentUser,
        onResolveUserProfile: widget.onResolveProfile,
        onResolveRoomProfile: widget.onResolveRoomProfile,
        onEnterCommonRoom: widget.onEnterCommonRoom,
        inLive: widget.inLive,
        showRoomRole: widget.showRoomRole,
        action: widget.profileActionBuilder?.call(_displayUser),
      ),
      child: widget.child,
    );
  }
}

class _UserProfileCardPopupRoute extends PopupRoute<void> {
  _UserProfileCardPopupRoute({
    required this.position,
    required this.user,
    required this.currentUser,
    required this.onResolveProfile,
    required this.onResolveRoomProfile,
    required this.onEnterCommonRoom,
    required this.profileActionBuilder,
    required this.inLive,
    required this.showRoomRole,
  });

  final Offset position;
  final UserSummary user;
  final CurrentUser? currentUser;
  final UserProfileResolver? onResolveProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterCommonRoom;
  final UserProfileActionBuilder? profileActionBuilder;
  final bool inLive;
  final bool showRoomRole;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭用户名片';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 110);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return CustomSingleChildLayout(
      delegate: _UserProfileCardPopupLayoutDelegate(position),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: AnchoredPanel(
          width: hoverCardDefaultWidth,
          child: Material(
            type: MaterialType.transparency,
            child: _ResolvingUserProfileCard(
              user: user,
              currentUser: currentUser,
              onResolveProfile: onResolveProfile,
              onResolveRoomProfile: onResolveRoomProfile,
              onEnterCommonRoom: onEnterCommonRoom,
              profileActionBuilder: profileActionBuilder,
              inLive: inLive,
              showRoomRole: showRoomRole,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserProfileCardPopupLayoutDelegate extends SingleChildLayoutDelegate {
  const _UserProfileCardPopupLayoutDelegate(this.anchor);

  static const double _screenPadding = 8;
  static const double _gap = 10;

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = constraints.hasBoundedWidth
        ? math.max(0.0, constraints.maxWidth - _screenPadding * 2)
        : double.infinity;
    final maxHeight = constraints.hasBoundedHeight
        ? math.max(0.0, constraints.maxHeight - _screenPadding * 2)
        : double.infinity;
    return BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(
      _screenPadding,
      size.width - childSize.width - _screenPadding,
    );
    final x = anchor.dx.clamp(_screenPadding, maxX).toDouble();
    var y = anchor.dy + _gap;
    if (y + childSize.height + _screenPadding > size.height) {
      y = anchor.dy - childSize.height - _gap;
    }
    final maxY = math.max(
      _screenPadding,
      size.height - childSize.height - _screenPadding,
    );
    y = y.clamp(_screenPadding, maxY).toDouble();
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_UserProfileCardPopupLayoutDelegate oldDelegate) {
    return anchor != oldDelegate.anchor;
  }
}

class _ResolvingUserProfileCard extends StatefulWidget {
  const _ResolvingUserProfileCard({
    required this.user,
    required this.currentUser,
    required this.onResolveProfile,
    required this.onResolveRoomProfile,
    required this.onEnterCommonRoom,
    required this.profileActionBuilder,
    required this.inLive,
    required this.showRoomRole,
  });

  final UserSummary user;
  final CurrentUser? currentUser;
  final UserProfileResolver? onResolveProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterCommonRoom;
  final UserProfileActionBuilder? profileActionBuilder;
  final bool inLive;
  final bool showRoomRole;

  @override
  State<_ResolvingUserProfileCard> createState() =>
      _ResolvingUserProfileCardState();
}

class _ResolvingUserProfileCardState extends State<_ResolvingUserProfileCard> {
  UserSummary? _resolved;

  UserSummary get _displayUser => _resolved ?? widget.user;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final resolver = widget.onResolveProfile;
    if (resolver == null) return;
    final requestedUser = widget.user;
    try {
      final profile = await resolver(requestedUser);
      if (!mounted || widget.user.id != requestedUser.id) return;
      setState(() => _resolved = profile);
    } catch (_) {
      if (!mounted || widget.user.id != requestedUser.id) return;
      setState(() => _resolved = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _displayUser;
    return _UserProfileCard(
      user: user,
      currentUser: widget.currentUser,
      onResolveUserProfile: widget.onResolveProfile,
      onResolveRoomProfile: widget.onResolveRoomProfile,
      onEnterCommonRoom: widget.onEnterCommonRoom,
      inLive: widget.inLive,
      showRoomRole: widget.showRoomRole,
      action: widget.profileActionBuilder?.call(user),
    );
  }
}

class _UserProfileCard extends StatelessWidget {
  const _UserProfileCard({
    required this.user,
    this.currentUser,
    this.onResolveUserProfile,
    this.onResolveRoomProfile,
    this.onEnterCommonRoom,
    this.inLive = false,
    this.showRoomRole = false,
    this.action,
  });

  final UserSummary user;
  final CurrentUser? currentUser;
  final UserProfileResolver? onResolveUserProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterCommonRoom;
  final bool inLive;
  final bool showRoomRole;
  final UserProfileAction? action;

  @override
  Widget build(BuildContext context) {
    final name = room_display.userPrimaryName(user);
    final gender = genderMark(user.gender);
    final role = showRoomRole ? room_display.roomRoleLabel(user) : null;
    final isCurrentUser = currentUser?.id == user.id;
    final online = inLive || isCurrentUser || (user.isOnline ?? false);
    final presencePill = inLive
        ? PresencePill.voice()
        : online
        ? PresencePill.online()
        : PresencePill.offline();
    final bio = user.bio?.trim();
    final uid = user.uid?.trim();
    final commonRooms = user.commonRooms.where((r) => r.isUsable).toList();
    final config = AppConfigScope.of(context);
    final avatarUrl = config.resolveAssetUrl(user.avatarUrl);
    final previewAvatarUrl = _nonEmpty(user.avatarUrl) == null
        ? null
        : _nonEmpty(avatarUrl);

    return Padding(
      padding: const EdgeInsets.all(UiSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileImagePreview(
                key: const ValueKey('user-profile-card-avatar-preview'),
                imageUrl: previewAvatarUrl,
                suggestedName:
                    '${room_display.userPrimaryName(user)}-avatar.png',
                child: Avatar(
                  label: room_display.userAvatarLabel(user),
                  imageUrl: avatarUrl,
                  defaultAvatarKey: user.defaultAvatarKey,
                  size: 48,
                  active: online,
                  activeBorderWidth: 2,
                  activeBorderColor: inLive ? UiColors.presenceVoice : null,
                  paintBorderOnForeground: true,
                ),
              ),
              const SizedBox(width: UiSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: _ProfileIdentityText(
                            value: name,
                            style: UiTypography.title.copyWith(fontSize: 16),
                          ),
                        ),
                        if (gender != null) ...[
                          const SizedBox(width: 5),
                          Text(
                            gender.symbol,
                            maxLines: 1,
                            style: UiTypography.title.copyWith(
                              color: gender.color,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    _ProfileIdentityText(
                      value: '@${user.username}',
                      copyStartOffset: 1,
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
              presencePill,
              if (role != null) RoleBadge(label: role),
            ],
          ),
          if (bio != null && bio.isNotEmpty) ...[
            const SizedBox(height: UiSpacing.md),
            _ProfileIdentityText(
              value: bio,
              maxLines: 4,
              style: UiTypography.body.copyWith(color: UiColors.textSecondary),
            ),
          ],
          if (commonRooms.isNotEmpty) ...[
            const SizedBox(height: UiSpacing.md),
            Text(
              '${commonRooms.length} 个共同房间',
              style: UiTypography.label.copyWith(color: UiColors.textMuted),
            ),
            const SizedBox(height: UiSpacing.xs),
            _UserCommonRoomList(
              rooms: commonRooms,
              currentUser: currentUser,
              onResolveUserProfile: onResolveUserProfile,
              onResolveRoomProfile: onResolveRoomProfile,
              onEnterRoom: onEnterCommonRoom,
            ),
          ],
          if (uid != null && uid.isNotEmpty) ...[
            const SizedBox(height: UiSpacing.sm),
            _ProfileIdentityText(
              value: 'UID: $uid',
              copyStartOffset: 'UID: '.length,
              style: UiTypography.label.copyWith(color: UiColors.textMuted),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: UiSpacing.md),
            Center(
              child: Button(
                icon: Icon(action!.icon),
                tone: ButtonTone.primary,
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                onPressed: action!.onPressed,
                child: Text(action!.label),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileImagePreview extends StatelessWidget {
  const _ProfileImagePreview({
    super.key,
    required this.imageUrl,
    required this.child,
    required this.suggestedName,
  });

  final String? imageUrl;
  final Widget child;
  final String suggestedName;

  Future<void> _openPreview(BuildContext context, String url) async {
    final hoverScope = HoverCardTapRegionScope.maybeOf(context);
    final previewActions = ChatImagePreviewActionsScope.maybeOf(context);
    hoverScope?.onOverlayActivityChanged?.call(true);
    try {
      await showChatImagePreview(
        context,
        imageUrl: url,
        suggestedName: suggestedName,
        actions: previewActions ?? ChatImagePreviewActions.disabled(),
        showActionBar: previewActions != null,
        forceSquare: true,
      );
    } finally {
      hoverScope?.onOverlayActivityChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _nonEmpty(imageUrl);
    if (url == null) return child;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openPreview(context, url),
        child: child,
      ),
    );
  }
}

class _ProfileIdentityText extends StatelessWidget {
  const _ProfileIdentityText({
    required this.value,
    required this.style,
    this.copyStartOffset = 0,
    this.maxLines = 1,
  });

  final String value;
  final TextStyle style;
  final int copyStartOffset;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final hoverScope = HoverCardTapRegionScope.maybeOf(context);
    final start = copyStartOffset.clamp(0, value.length);
    return ReadOnlySelectableText(
      value: value,
      style: style,
      maxLines: maxLines,
      secondaryClickSelection: TextSelection(
        baseOffset: start,
        extentOffset: value.length,
      ),
      showSelectAllInContextMenu: false,
      contextMenuTapRegionGroupId: hoverScope?.tapRegionGroup,
      onContextMenuOpenChanged: hoverScope?.onOverlayActivityChanged,
    );
  }
}

class _UserCommonRoomList extends StatefulWidget {
  const _UserCommonRoomList({
    required this.rooms,
    required this.currentUser,
    required this.onResolveUserProfile,
    required this.onResolveRoomProfile,
    required this.onEnterRoom,
  });

  final List<UserCommonRoom> rooms;
  final CurrentUser? currentUser;
  final UserProfileResolver? onResolveUserProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterRoom;

  @override
  State<_UserCommonRoomList> createState() => _UserCommonRoomListState();
}

class _UserCommonRoomListState extends State<_UserCommonRoomList> {
  static const double _maxHeight = 116;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final room in widget.rooms)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _UserCommonRoomRow(
              room: room,
              currentUser: widget.currentUser,
              onResolveUserProfile: widget.onResolveUserProfile,
              onResolveRoomProfile: widget.onResolveRoomProfile,
              onEnterRoom: widget.onEnterRoom,
            ),
          ),
      ],
    );

    if (widget.rooms.length <= 4) return list;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.only(right: UiSpacing.sm),
          child: list,
        ),
      ),
    );
  }
}

class _UserCommonRoomRow extends StatelessWidget {
  const _UserCommonRoomRow({
    required this.room,
    required this.currentUser,
    required this.onResolveUserProfile,
    required this.onResolveRoomProfile,
    required this.onEnterRoom,
  });

  final UserCommonRoom room;
  final CurrentUser? currentUser;
  final UserProfileResolver? onResolveUserProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterRoom;

  @override
  Widget build(BuildContext context) {
    final avatar = Avatar(
      label: room_display.commonRoomAvatarLabel(room),
      imageUrl: AppConfigScope.of(context).resolveAssetUrl(room.avatarUrl),
      defaultAvatarKey: room.defaultAvatarKey,
      size: 20,
      activeBorderWidth: 1,
    );
    final publicRoom = _publicRoomFromCommonRoom(room);
    final avatarTarget = currentUser == null
        ? avatar
        : RoomHoverCard(
            room: publicRoom,
            currentUser: currentUser!,
            onResolveRoom: onResolveRoomProfile,
            onResolveUserProfile: onResolveUserProfile,
            onEnterRoom: onEnterRoom,
            child: avatar,
          );

    return Row(
      children: [
        avatarTarget,
        const SizedBox(width: UiSpacing.sm),
        Expanded(
          child: Text(
            room_display.commonRoomDisplayName(room),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: UiTypography.body.copyWith(
              color: UiColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomProfileCard extends StatelessWidget {
  const _RoomProfileCard({
    required this.room,
    required this.currentUser,
    this.onResolveRoomProfile,
    this.onResolveUserProfile,
    this.onEnterRoom,
  });

  final PublicRoom room;
  final CurrentUser currentUser;
  final RoomProfileResolver? onResolveRoomProfile;
  final UserProfileResolver? onResolveUserProfile;
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
    final roomAvatarUrl = config.resolveAssetUrl(room.avatarUrl);
    final previewRoomAvatarUrl = _nonEmpty(room.avatarUrl) == null
        ? null
        : _nonEmpty(roomAvatarUrl);

    return Padding(
      padding: const EdgeInsets.all(UiSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileImagePreview(
                key: const ValueKey('room-profile-card-icon-preview'),
                imageUrl: previewRoomAvatarUrl,
                suggestedName: '${room.name}-icon.png',
                child: Avatar(
                  label: room_display.publicRoomAvatarLabel(room),
                  imageUrl: roomAvatarUrl,
                  defaultAvatarKey: room.defaultAvatarKey,
                  size: 48,
                  activeBorderWidth: 2,
                ),
              ),
              const SizedBox(width: UiSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ProfileIdentityText(
                      value: room.name,
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
              StatusBadge(
                label: room_display.roomJoinPolicyLabel(room.joinPolicy),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: UiSpacing.md),
            _ProfileIdentityText(
              value: description,
              maxLines: 4,
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
              avatarLabel: room_display.userAvatarLabel(creator),
              avatarUrl: creator.avatarUrl,
              defaultAvatarKey: creator.defaultAvatarKey,
              name: room_display.userPrimaryName(creator),
              profileUser: creator,
              currentUser: currentUser,
              onResolveUserProfile: onResolveUserProfile,
              onResolveRoomProfile: onResolveRoomProfile,
              onEnterCommonRoom: onEnterRoom,
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
              avatarLabel: _currentUserAvatarLabel(currentUser),
              avatarUrl: myAvatarUrl,
              defaultAvatarKey: myDefaultAvatarKey,
              name: myName,
              trailing: RoleBadge(label: myRole),
            ),
          ],
          const SizedBox(height: UiSpacing.sm),
          _ProfileIdentityText(
            value: 'RID: $rid',
            copyStartOffset: 'RID: '.length,
            style: UiTypography.label.copyWith(color: UiColors.textMuted),
          ),
          if (joined) ...[
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
    this.profileUser,
    this.currentUser,
    this.onResolveUserProfile,
    this.onResolveRoomProfile,
    this.onEnterCommonRoom,
    this.trailing,
  });

  final String avatarLabel;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final String name;
  final UserSummary? profileUser;
  final CurrentUser? currentUser;
  final UserProfileResolver? onResolveUserProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterCommonRoom;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final avatar = Avatar(
      label: avatarLabel,
      imageUrl: AppConfigScope.of(context).resolveAssetUrl(avatarUrl),
      defaultAvatarKey: defaultAvatarKey,
      size: 20,
      activeBorderWidth: 1,
    );
    final avatarTarget = profileUser == null || currentUser == null
        ? avatar
        : UserHoverCard(
            user: profileUser!,
            currentUser: currentUser,
            onResolveProfile: onResolveUserProfile,
            onResolveRoomProfile: onResolveRoomProfile,
            onEnterCommonRoom: onEnterCommonRoom,
            child: avatar,
          );

    return Row(
      children: [
        avatarTarget,
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
  return currentUser.avatarUrl;
}

String _myRoomDefaultAvatarKey(PublicRoom room, CurrentUser currentUser) {
  return currentUser.defaultAvatarKey;
}

String _currentUserAvatarLabel(CurrentUser currentUser) {
  final displayName = currentUser.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  final username = currentUser.username.trim();
  if (username.isNotEmpty) return username;
  return currentUser.id;
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

PublicRoom _publicRoomFromCommonRoom(UserCommonRoom room) {
  return PublicRoom(
    id: room.id,
    rid: room.rid,
    name: room_display.commonRoomDisplayName(room),
    avatarLabel: room_display.commonRoomAvatarLabel(room),
    avatarUrl: room.avatarUrl,
    defaultAvatarKey: room.defaultAvatarKey,
    visibility: room.visibility,
    joinPolicy: 'closed',
    memberCount: 0,
    onlineMemberCount: 0,
    liveParticipantCount: 0,
    joined: true,
    joinState: 'joined',
  );
}

@visibleForTesting
class RoomHoverCardForTest extends StatelessWidget {
  const RoomHoverCardForTest({
    super.key,
    required this.room,
    required this.currentUser,
    this.onResolveRoom,
    this.onResolveUserProfile,
    this.onEnterRoom,
  });

  final PublicRoom room;
  final CurrentUser currentUser;
  final RoomProfileResolver? onResolveRoom;
  final UserProfileResolver? onResolveUserProfile;
  final ValueChanged<PublicRoom>? onEnterRoom;

  @override
  Widget build(BuildContext context) {
    return RoomHoverCard(
      room: room,
      currentUser: currentUser,
      onResolveRoom: onResolveRoom,
      onResolveUserProfile: onResolveUserProfile,
      onEnterRoom: onEnterRoom,
      child: Avatar(label: room_display.publicRoomAvatarLabel(room), size: 34),
    );
  }
}
