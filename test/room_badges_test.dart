import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/room_badges.dart';

void main() {
  test('room navigation badge reset is a no-op when already clear', () {
    expect(
      roomNavigationBadgesReset(
        currentHasPendingRoomInvites: false,
        currentSelectedRoomHasPendingJoinRequests: false,
      ),
      isNull,
    );

    final patch = roomNavigationBadgesReset(
      currentHasPendingRoomInvites: true,
      currentSelectedRoomHasPendingJoinRequests: true,
    );

    expect(patch?.hasPendingRoomInvites, isFalse);
    expect(patch?.selectedRoomHasPendingJoinRequests, isFalse);
  });

  test('room invite badge update preserves selected join request badge', () {
    expect(
      roomInviteBadgeUpdated(
        currentHasPendingRoomInvites: true,
        currentSelectedRoomHasPendingJoinRequests: false,
        hasPending: true,
      ),
      isNull,
    );

    final patch = roomInviteBadgeUpdated(
      currentHasPendingRoomInvites: false,
      currentSelectedRoomHasPendingJoinRequests: true,
      hasPending: true,
    );

    expect(patch?.hasPendingRoomInvites, isTrue);
    expect(patch?.selectedRoomHasPendingJoinRequests, isTrue);
  });

  test('selected join request badge update preserves room invite badge', () {
    expect(
      selectedJoinRequestBadgeUpdated(
        currentHasPendingRoomInvites: true,
        currentSelectedRoomHasPendingJoinRequests: false,
        hasPending: false,
      ),
      isNull,
    );

    final patch = selectedJoinRequestBadgeUpdated(
      currentHasPendingRoomInvites: true,
      currentSelectedRoomHasPendingJoinRequests: false,
      hasPending: true,
    );

    expect(patch?.hasPendingRoomInvites, isTrue);
    expect(patch?.selectedRoomHasPendingJoinRequests, isTrue);
  });
}
