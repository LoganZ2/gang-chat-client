part of 'chat_pane.dart';

const double _profileCardWidth = 248;
const double _profileCardGap = 10;

/// Wraps a message avatar so hovering it reveals a floating profile card
/// anchored beside the avatar. The card itself is hoverable, and a short close
/// delay bridges the gap between avatar and card so moving the cursor across
/// the gap keeps it open.
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
  final GlobalKey _anchorKey = GlobalKey();
  final OverlayPortalController _portal = OverlayPortalController();
  final Object _tapRegionGroup = Object();

  // Hover is tracked separately for the avatar and the card; the card stays
  // open while either is hovered. The timer gives the cursor a grace period to
  // cross the gap between them.
  bool _overAnchor = false;
  bool _overCard = false;
  bool _pinned = false;
  Timer? _closeTimer;

  // Richer profile, fetched once on first open and reused afterwards.
  UserSummary? _resolved;
  bool _resolving = false;

  UserSummary get _displayUser => _resolved ?? widget.user;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _enterAnchor() {
    _overAnchor = true;
    _open();
  }

  void _exitAnchor() {
    _overAnchor = false;
    _scheduleClose();
  }

  void _enterCard() {
    _overCard = true;
    _closeTimer?.cancel();
  }

  void _exitCard() {
    _overCard = false;
    _scheduleClose();
  }

  void _open() {
    _closeTimer?.cancel();
    _resolveProfile();
    if (_portal.isShowing) return;
    _portal.show();
  }

  void _pinOpen() {
    _pinned = true;
    _open();
  }

  void _dismissPinned() {
    if (!_pinned && !_portal.isShowing) return;
    _pinned = false;
    _overAnchor = false;
    _overCard = false;
    _closeTimer?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  Future<void> _resolveProfile() async {
    final resolver = widget.onResolveProfile;
    if (resolver == null || _resolved != null || _resolving) return;
    _resolving = true;
    try {
      final profile = await resolver(widget.user);
      if (!mounted) return;
      setState(() => _resolved = profile);
    } catch (_) {
      // Keep showing the lightweight summary on failure.
    } finally {
      _resolving = false;
    }
  }

  void _scheduleClose() {
    if (_pinned) return;
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _pinned || _overAnchor || _overCard) return;
      if (_portal.isShowing) _portal.hide();
    });
  }

  Rect? _anchorRectInOverlay() {
    final anchorBox = _anchorKey.currentContext?.findRenderObject();
    final overlayBox = Overlay.maybeOf(context)?.context.findRenderObject();
    if (anchorBox is! RenderBox ||
        overlayBox is! RenderBox ||
        !anchorBox.hasSize ||
        !overlayBox.hasSize) {
      return null;
    }
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    return topLeft & anchorBox.size;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        return Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final anchorRect = _anchorRectInOverlay();
              if (anchorRect == null) return const SizedBox.shrink();
              return CustomSingleChildLayout(
                delegate: _ProfileCardLayoutDelegate(
                  anchorRect: anchorRect,
                  gap: _profileCardGap,
                  cardWidth: _profileCardWidth,
                ),
                child: TapRegion(
                  groupId: _tapRegionGroup,
                  onTapOutside: (_) => _dismissPinned(),
                  child: MouseRegion(
                    onEnter: (_) => _enterCard(),
                    onExit: (_) => _exitCard(),
                    child: AnchoredPanel(
                      width: _profileCardWidth,
                      child: _ProfileCard(user: _displayUser),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      child: TapRegion(
        groupId: _tapRegionGroup,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _pinOpen,
          child: MouseRegion(
            onEnter: (_) => _enterAnchor(),
            onExit: (_) => _exitAnchor(),
            child: KeyedSubtree(key: _anchorKey, child: widget.child),
          ),
        ),
      ),
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
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UiTypography.title.copyWith(fontSize: 16),
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
              if (gender != null) StatusBadge(label: _genderLabel(user.gender)),
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

String _genderLabel(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'male' || 'm' || 'man' => '男',
    'female' || 'f' || 'woman' => '女',
    _ => '其他',
  };
}

/// Places the profile card beside the avatar: to the right when there's room,
/// otherwise to the left. Vertically it tracks the avatar's top edge, clamped
/// so the card never spills outside the overlay.
class _ProfileCardLayoutDelegate extends SingleChildLayoutDelegate {
  const _ProfileCardLayoutDelegate({
    required this.anchorRect,
    required this.gap,
    required this.cardWidth,
  });

  final Rect anchorRect;
  final double gap;
  final double cardWidth;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      constraints.biggest,
    ).copyWith(minWidth: cardWidth, maxWidth: cardWidth);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final spaceRight = size.width - anchorRect.right - gap;
    final placeRight = spaceRight >= childSize.width;
    final rawLeft = placeRight
        ? anchorRect.right + gap
        : anchorRect.left - gap - childSize.width;
    final maxLeft = math.max(0.0, size.width - childSize.width);
    final left = rawLeft.clamp(0.0, maxLeft).toDouble();

    final maxTop = math.max(0.0, size.height - childSize.height);
    final top = anchorRect.top.clamp(0.0, maxTop).toDouble();
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_ProfileCardLayoutDelegate oldDelegate) {
    return oldDelegate.anchorRect != anchorRect ||
        oldDelegate.gap != gap ||
        oldDelegate.cardWidth != cardWidth;
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
