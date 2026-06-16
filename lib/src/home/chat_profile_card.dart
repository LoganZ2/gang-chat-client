part of 'chat_pane.dart';

/// Wraps a message avatar so hovering it reveals a floating profile card.
class _AvatarHoverCard extends StatelessWidget {
  const _AvatarHoverCard({
    required this.user,
    required this.currentUser,
    required this.child,
    this.onResolveProfile,
    this.onResolveRoomProfile,
    this.onEnterCommonRoom,
    this.profileActionBuilder,
  });

  final UserSummary user;
  final CurrentUser currentUser;
  final Widget child;

  /// Lazily fetches a richer profile (gender, common rooms) the first time the
  /// card opens. When null the card shows only the message summary.
  final Future<UserSummary> Function(UserSummary sender)? onResolveProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterCommonRoom;
  final UserProfileActionBuilder? profileActionBuilder;

  @override
  Widget build(BuildContext context) {
    return UserHoverCard(
      user: user,
      currentUser: currentUser,
      onResolveProfile: onResolveProfile,
      onResolveRoomProfile: onResolveRoomProfile,
      onEnterCommonRoom: onEnterCommonRoom,
      profileActionBuilder: profileActionBuilder,
      child: child,
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
    this.currentUser = _avatarHoverCardTestCurrentUser,
    this.onResolveProfile,
    this.onResolveRoomProfile,
    this.onEnterCommonRoom,
    this.profileActionBuilder,
  });

  final UserSummary user;
  final CurrentUser currentUser;
  final Future<UserSummary> Function(UserSummary sender)? onResolveProfile;
  final RoomProfileResolver? onResolveRoomProfile;
  final ValueChanged<PublicRoom>? onEnterCommonRoom;
  final UserProfileActionBuilder? profileActionBuilder;

  @override
  Widget build(BuildContext context) {
    return _AvatarHoverCard(
      user: user,
      currentUser: currentUser,
      onResolveProfile: onResolveProfile,
      onResolveRoomProfile: onResolveRoomProfile,
      onEnterCommonRoom: onEnterCommonRoom,
      profileActionBuilder: profileActionBuilder,
      child: Avatar(label: _senderName(user), size: 32),
    );
  }
}

const _avatarHoverCardTestCurrentUser = CurrentUser(
  id: 'avatar-hover-card-test-user',
  uid: '',
  username: 'viewer',
  displayName: 'Viewer',
  bio: '',
  gender: 'secret',
  email: null,
  emailPublic: false,
  phoneNumber: null,
  phoneNumberPublic: false,
  avatarUrl: null,
  defaultAvatarKey: 'green-2',
  isSuperuser: false,
  createdAt: null,
);
