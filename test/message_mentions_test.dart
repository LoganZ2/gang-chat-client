import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/message_mentions.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  group('activeMessageMentionQuery', () {
    test('finds the query before the cursor', () {
      final query = activeMessageMentionQuery(
        text: 'hello @pan',
        cursorOffset: 'hello @pan'.length,
      );

      expect(query, isNotNull);
      expect(query!.start, 6);
      expect(query.end, 10);
      expect(query.query, 'pan');
    });

    test('ignores email-like text', () {
      final query = activeMessageMentionQuery(
        text: 'mail a@b.com',
        cursorOffset: 'mail a@b.com'.length,
      );

      expect(query, isNull);
    });

    test('finds mention directly after existing text', () {
      final query = activeMessageMentionQuery(
        text: 'hello@pan',
        cursorOffset: 'hello@pan'.length,
      );

      expect(query, isNotNull);
      expect(query!.start, 5);
      expect(query.end, 9);
      expect(query.query, 'pan');
    });

    test('finds mention directly after chinese text', () {
      final query = activeMessageMentionQuery(
        text: '你好@潘',
        cursorOffset: '你好@潘'.length,
      );

      expect(query, isNotNull);
      expect(query!.start, 2);
      expect(query.query, '潘');
    });
  });

  test('messageMentionRanges highlights mention tokens', () {
    final ranges = messageMentionRanges('hi @alpha and @beta plus text@gamma');

    expect(ranges.map((range) => [range.start, range.end]), [
      [3, 9],
      [14, 19],
      [29, 35],
    ]);
  });

  test('messageMentionRanges ignores email addresses', () {
    final ranges = messageMentionRanges('mail a@b.com and hi@alpha');

    expect(ranges.map((range) => [range.start, range.end]), [
      [19, 25],
    ]);
  });

  test('messageMentionOptions filters by room display name and role', () {
    final owner = _member('1', 'owner', 'Panel Owner', role: 'owner');
    final admin = _member('2', 'admin', 'Panel Admin', role: 'admin');
    final member = _member('3', 'member', 'Panel Member');

    final options = messageMentionOptions(
      members: [member, admin, owner],
      query: 'pan',
      ownerUserId: owner.user.id,
    );

    expect(options.map((option) => option.label), [
      'Panel Owner',
      'Panel Admin',
      'Panel Member',
    ]);
  });

  test('messageMentionOptions excludes the current user', () {
    final currentUser = _member('1', 'me', 'Panel Me');
    final otherUser = _member('2', 'other', 'Panel Other');

    final options = messageMentionOptions(
      members: [currentUser, otherUser],
      query: 'pan',
      ownerUserId: null,
      excludedUserId: currentUser.user.id,
    );

    expect(options.map((option) => option.label), ['Panel Other']);
  });

  test('messageMentionOptions filters by UID', () {
    final member = _member('1', 'member', 'Panel Member', uid: '10000088');

    final options = messageMentionOptions(
      members: [member],
      query: '0088',
      ownerUserId: null,
    );

    expect(options.map((option) => option.label), ['Panel Member']);
  });
}

RoomMember _member(
  String id,
  String username,
  String roomDisplayName, {
  String role = 'member',
  String? uid,
}) {
  final user = UserSummary(
    id: id,
    username: username,
    displayName: username,
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    uid: uid,
    roomDisplayName: roomDisplayName,
    roomRole: role,
  );
  return RoomMember(
    user: user,
    role: role,
    joinedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    roomDisplayName: roomDisplayName,
  );
}
