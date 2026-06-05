import '../protocol/models.dart';

List<RoomCard> patchRoomLiveCount({
  required List<RoomCard> rooms,
  required String roomId,
  required LiveState live,
}) {
  return rooms
      .map((room) => room.id == roomId ? roomCardWithLive(room, live) : room)
      .toList();
}

RoomCard roomCardWithLive(RoomCard room, LiveState live) {
  final preview = live.participants.take(5).map((item) => item.user).toList();
  return RoomCard(
    id: room.id,
    name: room.name,
    rid: room.rid,
    visibility: room.visibility,
    remarkName: room.remarkName,
    description: room.description,
    notificationPolicy: room.notificationPolicy,
    avatarUrl: room.avatarUrl,
    defaultAvatarKey: room.defaultAvatarKey,
    memberCount: room.memberCount,
    onlineMemberCount: room.onlineMemberCount,
    liveParticipantCount: live.participantCount,
    liveAvatarPreview: preview,
    lastMessage: room.lastMessage,
    unreadCount: room.unreadCount,
    updatedAt: room.updatedAt,
  );
}
