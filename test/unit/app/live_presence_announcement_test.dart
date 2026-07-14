import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/live_presence_announcement.dart';
import 'package:client/src/app/room_display.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('presence speech excludes self and obeys the room switch', () {
    expect(
      shouldSpeakLivePresenceAnnouncement(
        enabled: true,
        participantIdentity: 'user-1',
        currentUserIdentity: 'user-1',
      ),
      isFalse,
    );
    expect(
      shouldSpeakLivePresenceAnnouncement(
        enabled: false,
        participantIdentity: 'user-2',
        currentUserIdentity: 'user-1',
      ),
      isFalse,
    );
    expect(
      shouldSpeakLivePresenceAnnouncement(
        enabled: true,
        participantIdentity: 'user-2',
        currentUserIdentity: 'user-1',
      ),
      isTrue,
    );
  });

  test('presence announcement uses role and room display name as segments', () {
    final announcement = livePresenceAnnouncementForUser(
      user: const UserSummary(
        id: 'user-2',
        username: 'morgan',
        displayName: 'Morgan Account',
        roomDisplayName: '房间里的 Morgan',
        roomRole: 'admin',
        avatarUrl: null,
        defaultAvatarKey: 'blue-1',
      ),
      action: LivePresenceAnnouncementAction.joined,
    );

    expect(announcement.segments, ['管理员', '房间里的 Morgan', '进入了语音频道']);
  });

  test('presence announcement distinguishes leave from removal', () {
    const left = LivePresenceAnnouncement(
      roleLabel: '成员',
      roomDisplayName: '小林',
      action: LivePresenceAnnouncementAction.left,
    );
    const removed = LivePresenceAnnouncement(
      roleLabel: '成员',
      roomDisplayName: '小林',
      action: LivePresenceAnnouncementAction.removed,
    );

    expect(left.actionLabel, '离开了语音频道');
    expect(removed.actionLabel, '被踢出了语音频道');
  });

  test('presence announcement falls back to account display name', () {
    final announcement = livePresenceAnnouncementForUser(
      user: const UserSummary(
        id: 'user-2',
        username: 'morgan',
        displayName: 'Morgan',
        avatarUrl: null,
        defaultAvatarKey: 'blue-1',
      ),
      action: LivePresenceAnnouncementAction.left,
    );

    expect(announcement.segments, ['成员', 'Morgan', '离开了语音频道']);
  });
}
