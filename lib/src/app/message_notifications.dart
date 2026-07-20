import 'dart:collection';

import 'room_display.dart';

const realtimeMessageCreatedUpdateReason = 'message_created';

/// Tracks realtime message notifications without conflating them with room
/// snapshots loaded during sign-in or reconnect recovery.
class RealtimeMessageNotificationTracker {
  RealtimeMessageNotificationTracker({this.capacity = 256})
    : assert(capacity > 0);

  final int capacity;
  final LinkedHashSet<String> _seenMessageKeys = LinkedHashSet<String>();

  bool register({
    required String roomId,
    required String updateReason,
    required String notificationPolicy,
    required String? messageId,
  }) {
    if (updateReason.trim().toLowerCase() !=
        realtimeMessageCreatedUpdateReason) {
      return false;
    }
    final normalizedRoomId = roomId.trim();
    final normalizedMessageId = messageId?.trim() ?? '';
    if (normalizedRoomId.isEmpty || normalizedMessageId.isEmpty) return false;

    final key = '$normalizedRoomId:$normalizedMessageId';
    if (!_seenMessageKeys.add(key)) return false;
    while (_seenMessageKeys.length > capacity) {
      _seenMessageKeys.remove(_seenMessageKeys.first);
    }

    return normalizeRoomNotificationPolicy(notificationPolicy) == 'all';
  }

  void clear() => _seenMessageKeys.clear();
}
