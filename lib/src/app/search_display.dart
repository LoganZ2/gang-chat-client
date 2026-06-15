import '../protocol/models.dart';
import 'file_display.dart' as file_display;
import 'room_display.dart' as room_display;
import 'room_notifications.dart' as room_notifications;

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

GlobalSearchResults globalSearchResultsForView(
  GlobalSearchResults results, {
  required String query,
}) {
  return GlobalSearchResults(
    myRooms: visibleMyRoomSearchResults(rooms: results.myRooms, query: query),
    publicRooms: results.publicRooms,
    messages: results.messages,
    files: results.files,
  );
}

List<RoomCard> visibleMyRoomSearchResults({
  required Iterable<RoomCard> rooms,
  required String query,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return List.unmodifiable(rooms);
  return [
    for (final room in rooms)
      if (_visibleRoomCardMatches(room, normalizedQuery)) room,
  ];
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

String globalSearchMessageTitle(MessageSearchResult result) {
  final roomName = result.room.name.trim();
  return roomName.isNotEmpty ? roomName : '房间';
}

String globalSearchMessageSubtitle(MessageSearchResult result) {
  final senderName = globalSearchMessageSenderName(result);
  final body = result.message.body.trim();
  if (body.isEmpty) return senderName;
  return '$senderName · $body';
}

String globalSearchMessageSenderName(MessageSearchResult result) {
  final roomDisplayName = result.message.sender.roomDisplayName?.trim();
  if (roomDisplayName != null && roomDisplayName.isNotEmpty) {
    return roomDisplayName;
  }
  final displayName = result.message.sender.displayName.trim();
  if (displayName.isNotEmpty) return displayName;
  final username = result.message.sender.username.trim();
  return username.isNotEmpty ? username : '用户';
}

String globalSearchFileTitle(MessageSearchResult result) {
  final attachment = _firstFileAttachment(result.message);
  if (attachment != null) return file_display.fileAttachmentTitle(attachment);
  final body = result.message.body.trim();
  return body.isNotEmpty ? body : 'file';
}

String globalSearchFileSubtitle(MessageSearchResult result) {
  final meta = file_display.fileAttachmentMeta(
    _firstFileAttachment(result.message)?.asset,
  );
  return meta.isNotEmpty ? meta : '文件';
}

String globalSearchResultTimeLabel(MessageSearchResult result) {
  return room_notifications.roomInviteTimestampLabel(result.message.createdAt);
}

MessageAttachment? _firstFileAttachment(Message message) {
  for (final attachment in message.fileAttachments) {
    return attachment;
  }
  return null;
}

bool _visibleRoomCardMatches(RoomCard room, String query) {
  if (_contains(room.name, query)) return true;
  if (_contains(room.remarkName, query)) return true;
  if (_contains(room.displayName, query)) return true;
  if (room.rid.trim().toLowerCase() == query) return true;
  return _contains(room_display.roomSidebarSubtitle(room), query);
}

bool _contains(String? value, String query) {
  final trimmed = value?.trim().toLowerCase();
  return trimmed != null && trimmed.contains(query);
}
