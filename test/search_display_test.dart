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
    );

    expect(globalSearchCategoryLabel(GlobalSearchCategory.myRooms), '我的房间');
    expect(globalSearchCategoryCount(results, GlobalSearchCategory.myRooms), 1);
    expect(
      globalSearchCategoryCount(results, GlobalSearchCategory.publicRooms),
      1,
    );
    expect(
      globalSearchCategoryCount(results, GlobalSearchCategory.messages),
      1,
    );
    expect(globalSearchCategoryCount(results, GlobalSearchCategory.files), 1);
    expect(globalSearchHasResults(results), isTrue);
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
}

RoomCard _room(String id) {
  return RoomCard(
    id: id,
    name: id == 'room_1' ? 'Alpha' : 'Beta',
    avatarUrl: null,
    defaultAvatarKey: 'room-1',
    memberCount: 2,
    liveParticipantCount: 0,
    liveAvatarPreview: const [],
    lastMessage: null,
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

MessageSearchResult _messageResult(String roomId, {String type = 'text'}) {
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
      createdAt: DateTime.utc(2026, 6, 1),
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
                ),
              ),
            ]
          : const [],
    ),
  );
}
