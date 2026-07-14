import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/search_display.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('global search labels and counts map result categories', () {
    final results = GlobalSearchResults(
      myRooms: [_room('room_1')],
      publicRooms: [_publicRoom('room_2')],
      messages: [_messageResult('room_1')],
      files: [_messageResult('room_1', type: 'file')],
      totalCounts: const GlobalSearchCounts(
        myRooms: 10,
        publicRooms: 11,
        messages: 12,
        files: 13,
      ),
    );

    expect(globalSearchCategoryLabel(GlobalSearchCategory.myRooms), '我的房间');
    expect(
      globalSearchCategoryCount(results, GlobalSearchCategory.myRooms),
      10,
    );
    expect(
      globalSearchCategoryCount(results, GlobalSearchCategory.publicRooms),
      11,
    );
    expect(
      globalSearchCategoryCount(results, GlobalSearchCategory.messages),
      12,
    );
    expect(globalSearchCategoryCount(results, GlobalSearchCategory.files), 13);
    expect(globalSearchCategoryKey(GlobalSearchCategory.myRooms), 'my_rooms');
    expect(
      globalSearchCategoryKey(GlobalSearchCategory.publicRooms),
      'public_rooms',
    );
    expect(globalSearchCategoryKey(GlobalSearchCategory.messages), 'messages');
    expect(globalSearchCategoryKey(GlobalSearchCategory.files), 'files');
    expect(globalSearchHasResults(results), isTrue);
  });

  test('global search cursors parse and merge selected pages', () {
    final parsed = GlobalSearchResults.fromJson({
      'my_rooms': <Object?>[],
      'public_rooms': <Object?>[],
      'messages': <Object?>[],
      'files': <Object?>[],
      'next_cursors': {
        'my_rooms': 'my-next',
        'public_rooms': null,
        'messages': 'message-next',
        'files': 'file-next',
      },
      'total_counts': {
        'my_rooms': 1,
        'public_rooms': 2,
        'messages': 3,
        'files': 4,
      },
    });

    expect(parsed.nextCursors.myRooms, 'my-next');
    expect(parsed.nextCursors.publicRooms, isNull);
    expect(parsed.nextCursors.messages, 'message-next');
    expect(parsed.nextCursors.files, 'file-next');
    expect(parsed.totalCounts.myRooms, 1);
    expect(parsed.totalCounts.publicRooms, 2);
    expect(parsed.totalCounts.messages, 3);
    expect(parsed.totalCounts.files, 4);

    final current = GlobalSearchResults(
      myRooms: [_room('room_1')],
      publicRooms: [_publicRoom('public_1')],
      messages: [_messageResult('room_1')],
      files: [_messageResult('room_1', type: 'file')],
      nextCursors: const GlobalSearchCursors(
        myRooms: 'my-next',
        publicRooms: 'public-next',
        messages: 'message-next',
        files: 'file-next',
      ),
      totalCounts: const GlobalSearchCounts(
        myRooms: 1,
        publicRooms: 1,
        messages: 8,
        files: 1,
      ),
    );
    final page = GlobalSearchResults(
      myRooms: const [],
      publicRooms: const [],
      messages: [_messageResult('room_2')],
      files: const [],
      nextCursors: const GlobalSearchCursors(messages: 'message-next-2'),
      totalCounts: const GlobalSearchCounts(messages: 9),
    );

    final merged = globalSearchResultsByAppendingPage(
      current: current,
      page: page,
      categories: const [GlobalSearchCategory.messages],
    );

    expect(merged.myRooms, current.myRooms);
    expect(merged.publicRooms, current.publicRooms);
    expect(merged.messages, hasLength(2));
    expect(merged.files, current.files);
    expect(merged.nextCursors.myRooms, 'my-next');
    expect(merged.nextCursors.publicRooms, 'public-next');
    expect(merged.nextCursors.messages, 'message-next-2');
    expect(merged.nextCursors.files, 'file-next');
    expect(merged.totalCounts.myRooms, 1);
    expect(merged.totalCounts.publicRooms, 1);
    expect(merged.totalCounts.messages, 9);
    expect(merged.totalCounts.files, 1);
  });

  test('sidebar search filter only applies to active my rooms category', () {
    final rooms = [_room('room_1'), _room('room_2')];
    final results = GlobalSearchResults(
      myRooms: [_room('room_2')],
      publicRooms: const [],
      messages: const [],
      files: const [],
    );

    expect(
      sidebarRoomsForSearch(
        rooms: rooms,
        query: 'alpha',
        activeCategory: null,
        results: results,
      ),
      rooms,
    );
    expect(
      sidebarRoomsForSearch(
        rooms: rooms,
        query: 'alpha',
        activeCategory: GlobalSearchCategory.messages,
        results: results,
      ),
      rooms,
    );
    expect(
      sidebarRoomsForSearch(
        rooms: rooms,
        query: 'alpha',
        activeCategory: GlobalSearchCategory.myRooms,
        results: results,
      ).map((room) => room.id),
      ['room_2'],
    );
    expect(
      sidebarRoomsForSearch(
        rooms: rooms,
        query: ' ',
        activeCategory: GlobalSearchCategory.myRooms,
        results: results,
      ),
      rooms,
    );
  });

  test('global search view hides my rooms that only match hidden details', () {
    final results = GlobalSearchResults(
      myRooms: [
        _room('hidden', name: 'Hidden', description: '12345'),
        _room('title', name: 'Room 1'),
        _room('message', name: 'Notes', lastMessageBody: 'visible 1'),
        _room('rid', name: 'RID Room', rid: '20000001'),
      ],
      publicRooms: const [],
      messages: const [],
      files: const [],
    );

    final visibleForOne = globalSearchResultsForView(results, query: '1');
    expect(visibleForOne.myRooms.map((room) => room.id), ['title', 'message']);

    final visibleForRid = globalSearchResultsForView(
      results,
      query: '20000001',
    );
    expect(visibleForRid.myRooms.map((room) => room.id), ['rid']);
  });

  test(
    'message search title uses room and subtitle keeps sender with message',
    () {
      final result = _messageResult(
        'room_1',
        createdAt: DateTime(2026, 6, 1, 9, 30),
      );

      expect(globalSearchMessageTitle(result), 'Alpha');
      expect(globalSearchMessageSenderName(result), 'Alice');
      expect(globalSearchMessageSubtitle(result), 'Alice · alpha roadmap');
      expect(globalSearchResultTimeLabel(result), '2026/06/01 09:30');
    },
  );

  test('file search display uses filename and asset metadata', () {
    final result = _messageResult('room_1', type: 'file');

    expect(globalSearchFileTitle(result), 'alpha.pdf');
    expect(globalSearchFileSubtitle(result), 'application/pdf - 4.0 KB');
  });
}

RoomCard _room(
  String id, {
  String? name,
  String rid = '',
  String description = '',
  String? lastMessageBody,
}) {
  return RoomCard(
    id: id,
    name: name ?? (id == 'room_1' ? 'Alpha' : 'Beta'),
    rid: rid,
    description: description,
    avatarUrl: null,
    defaultAvatarKey: 'room-1',
    memberCount: 2,
    liveParticipantCount: 0,
    liveAvatarPreview: const [],
    lastMessage: lastMessageBody == null
        ? null
        : LastMessagePreview(
            id: 'last_$id',
            type: 'text',
            senderDisplayName: 'Alice',
            bodyPreview: lastMessageBody,
            createdAt: DateTime.utc(2026, 6, 1),
          ),
    unreadCount: 0,
    updatedAt: DateTime.utc(2026, 6, 1),
  );
}

PublicRoom _publicRoom(String id) {
  return PublicRoom(
    id: id,
    rid: '900002',
    name: 'Public',
    avatarUrl: null,
    defaultAvatarKey: 'room-2',
    visibility: 'public',
    joinPolicy: 'open',
    memberCount: 2,
    liveParticipantCount: 0,
    joined: false,
    joinState: 'none',
  );
}

MessageSearchResult _messageResult(
  String roomId, {
  String type = 'text',
  DateTime? createdAt,
}) {
  return MessageSearchResult(
    room: SearchRoomContext(
      id: roomId,
      rid: '900001',
      name: 'Alpha',
      avatarUrl: null,
      defaultAvatarKey: 'room-1',
    ),
    message: Message(
      id: 'msg_$type',
      roomId: roomId,
      sender: const UserSummary(
        id: 'user_1',
        username: 'alice',
        displayName: 'Alice',
        avatarUrl: null,
        defaultAvatarKey: 'blue-3',
      ),
      clientMessageId: 'cmsg_$type',
      type: type,
      body: type == 'file' ? 'alpha.pdf' : 'alpha roadmap',
      createdAt: createdAt ?? DateTime.utc(2026, 6, 1),
      attachments: type == 'file'
          ? [
              const MessageAttachment(
                type: 'file',
                name: 'alpha.pdf',
                asset: UploadedAsset(
                  id: 'asset_1',
                  url: '/alpha.pdf',
                  thumbnailUrl: null,
                  mimeType: 'application/pdf',
                  filename: 'alpha.pdf',
                  sizeBytes: 4096,
                ),
              ),
            ]
          : const [],
    ),
  );
}
