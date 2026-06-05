import 'package:flutter/material.dart';

import '../app/room_members_filter.dart';

IconData roomMemberPresenceIcon(RoomMemberPresence presence) {
  return switch (presence) {
    RoomMemberPresence.live => Icons.call,
    RoomMemberPresence.online => Icons.circle,
    RoomMemberPresence.offline => Icons.circle_outlined,
  };
}
