import '../protocol/models.dart';

enum GlobalSearchCategory { myRooms, publicRooms, messages, files }

const globalSearchCategories = [
  GlobalSearchCategory.myRooms,
  GlobalSearchCategory.publicRooms,
  GlobalSearchCategory.messages,
  GlobalSearchCategory.files,
];

bool hasGlobalSearchQuery(String query) {
  return query.trim().isNotEmpty;
}

String globalSearchCategoryLabel(GlobalSearchCategory category) {
  return switch (category) {
    GlobalSearchCategory.myRooms => '我的房间',
    GlobalSearchCategory.publicRooms => '公开房间',
    GlobalSearchCategory.messages => '聊天记录',
    GlobalSearchCategory.files => '聊天文件',
  };
}

int globalSearchCategoryCount(
  GlobalSearchResults? results,
  GlobalSearchCategory category,
) {
  if (results == null) return 0;
  return switch (category) {
    GlobalSearchCategory.myRooms => results.myRooms.length,
    GlobalSearchCategory.publicRooms => results.publicRooms.length,
    GlobalSearchCategory.messages => results.messages.length,
    GlobalSearchCategory.files => results.files.length,
  };
}

bool globalSearchHasResults(GlobalSearchResults? results) {
  if (results == null) return false;
  return results.myRooms.isNotEmpty ||
      results.publicRooms.isNotEmpty ||
      results.messages.isNotEmpty ||
      results.files.isNotEmpty;
}

List<RoomCard> sidebarRoomsForSearch({
  required List<RoomCard> rooms,
  required String query,
  required GlobalSearchCategory? activeCategory,
  required GlobalSearchResults? results,
}) {
  if (!hasGlobalSearchQuery(query)) return rooms;
  if (activeCategory != GlobalSearchCategory.myRooms) return rooms;
  return results?.myRooms ?? const [];
}

RoomCard roomCardFromSearchContext(
  SearchRoomContext room, {
  required DateTime updatedAt,
}) {
  return RoomCard(
    id: room.id,
    name: room.name,
    rid: room.rid,
    avatarUrl: room.avatarUrl,
    defaultAvatarKey: room.defaultAvatarKey,
    memberCount: 0,
    liveParticipantCount: 0,
    liveAvatarPreview: const [],
    lastMessage: null,
    unreadCount: 0,
    updatedAt: updatedAt,
  );
}
