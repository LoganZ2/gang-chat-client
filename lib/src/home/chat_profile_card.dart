part of 'chat_pane.dart';

/// Wraps a message avatar so hovering it reveals a floating profile card.
class _AvatarHoverCard extends StatefulWidget {
  const _AvatarHoverCard({
    required this.user,
    required this.child,
    this.onResolveProfile,
  });

  final UserSummary user;
  final Widget child;

  /// Lazily fetches a richer profile (gender, common rooms) the first time the
  /// card opens. When null the card shows only the message summary.
  final Future<UserSummary> Function(UserSummary sender)? onResolveProfile;

  @override
  State<_AvatarHoverCard> createState() => _AvatarHoverCardState();
}

class _AvatarHoverCardState extends State<_AvatarHoverCard> {
  // Richer profile, fetched once on first open and reused afterwards.
  UserSummary? _resolved;
  Future<void>? _resolveFuture;
  bool _profileResolveCompleted = false;

  UserSummary get _displayUser => _resolved ?? widget.user;
  bool get _profileReady =>
      widget.onResolveProfile == null ||
      _resolved != null ||
      _profileResolveCompleted;

  @override
  void didUpdateWidget(covariant _AvatarHoverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final userChanged = oldWidget.user.id != widget.user.id;
    final resolverAdded =
        oldWidget.onResolveProfile == null && widget.onResolveProfile != null;
    if (!userChanged && !resolverAdded) {
      return;
    }
    _resolved = null;
    _resolveFuture = null;
    _profileResolveCompleted = false;
  }

  Future<void> _resolveProfile() {
    final resolver = widget.onResolveProfile;
    if (resolver == null || _profileResolveCompleted) {
      return Future<void>.value();
    }
    final existing = _resolveFuture;
    if (existing != null) return existing;

    final requestedUser = widget.user;
    final future = () async {
      try {
        final profile = await resolver(requestedUser);
        if (!mounted || widget.user.id != requestedUser.id) return;
        setState(() {
          _resolved = profile;
          _profileResolveCompleted = true;
        });
      } catch (_) {
        if (!mounted || widget.user.id != requestedUser.id) return;
        // Keep showing the lightweight summary on failure.
        setState(() => _profileResolveCompleted = true);
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
      resetKey: Object.hash(widget.user.id, widget.onResolveProfile != null),
      onBeforeOpen: _profileReady ? null : _resolveProfile,
      cardBuilder: (context) => _ProfileCard(user: _displayUser),
      child: widget.child,
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user});

  final UserSummary user;

  @override
  Widget build(BuildContext context) {
    final name = _senderName(user);
    final gender = genderMark(user.gender);
    final role = room_display.roomRoleLabel(user);
    final online = user.isOnline ?? false;
    final bio = user.bio?.trim();
    final uid = user.uid?.trim();
    final commonRooms = user.commonRooms.where((r) => r.isUsable).toList();

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
                label: name,
                imageUrl: AppConfigScope.of(
                  context,
                ).resolveAssetUrl(user.avatarUrl),
                defaultAvatarKey: user.defaultAvatarKey,
                size: 48,
                active: online,
                activeBorderWidth: 2,
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
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                    Text(
                      '@${user.username}',
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
                label: online ? '在线' : '离线',
                icon: online ? Icons.circle : Icons.circle_outlined,
                active: online,
              ),
              StatusBadge(label: role),
            ],
          ),
          if (bio != null && bio.isNotEmpty) ...[
            const SizedBox(height: UiSpacing.md),
            Text(
              bio,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
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
            ...commonRooms
                .take(4)
                .map(
                  (room) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Avatar(
                          label: room_display.commonRoomAvatarLabel(room),
                          imageUrl: AppConfigScope.of(
                            context,
                          ).resolveAssetUrl(room.avatarUrl),
                          defaultAvatarKey: room.defaultAvatarKey,
                          size: 20,
                          activeBorderWidth: 1,
                        ),
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
                    ),
                  ),
                ),
            if (commonRooms.length > 4) ...[
              const SizedBox(height: 4),
              Text(
                '等 ${commonRooms.length} 个房间',
                style: UiTypography.label.copyWith(color: UiColors.textMuted),
              ),
            ],
          ],
          if (uid != null && uid.isNotEmpty) ...[
            const SizedBox(height: UiSpacing.sm),
            Text(
              'UID: $uid',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UiTypography.label.copyWith(color: UiColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Test-only entry point for the otherwise-private avatar hover card, so widget
/// tests can pump it directly without standing up the whole message list.
@visibleForTesting
class AvatarHoverCardForTest extends StatelessWidget {
  const AvatarHoverCardForTest({
    super.key,
    required this.user,
    this.onResolveProfile,
  });

  final UserSummary user;
  final Future<UserSummary> Function(UserSummary sender)? onResolveProfile;

  @override
  Widget build(BuildContext context) {
    return _AvatarHoverCard(
      user: user,
      onResolveProfile: onResolveProfile,
      child: Avatar(label: _senderName(user), size: 32),
    );
  }
}
