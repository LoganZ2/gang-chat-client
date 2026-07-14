import 'messages_controller.dart';

/// Coalesces room read receipts and retains failed receipts for reconnect.
///
/// The server remains the source of truth. This controller only serializes
/// writes per room so a burst of UI updates cannot issue overlapping receipts,
/// and so a transient failure can be retried when realtime connectivity heals.
class RoomReadSyncController {
  RoomReadSyncController({required MessagesController messages})
    : _messages = messages;

  final MessagesController _messages;
  final Map<String, _RoomReadCursor> _pending = <String, _RoomReadCursor>{};
  final Map<String, _RoomReadCursor> _lastSynced = <String, _RoomReadCursor>{};
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  bool _closed = false;
  int _generation = 0;

  bool isSynced({required String roomId, required String messageId}) {
    return !_pending.containsKey(roomId) &&
        _lastSynced[roomId]?.messageId == messageId;
  }

  Future<void> markRead({
    required String roomId,
    required String lastReadMessageId,
    required DateTime messageCreatedAt,
  }) {
    if (_closed || roomId.isEmpty || lastReadMessageId.isEmpty) {
      return Future<void>.value();
    }
    if (isSynced(roomId: roomId, messageId: lastReadMessageId)) {
      return Future<void>.value();
    }

    final candidate = _RoomReadCursor(
      messageId: lastReadMessageId,
      createdAt: messageCreatedAt,
    );
    final pending = _pending[roomId];
    final synced = _lastSynced[roomId];
    if (synced != null && !candidate.isAfter(synced) && pending == null) {
      return Future<void>.value();
    }
    if (pending == null || candidate.isAfter(pending)) {
      // Keep only the newest UI intent. If a request is already running, its
      // drain loop will observe this replacement and immediately send it next.
      _pending[roomId] = candidate;
    }
    return _ensureDrain(roomId);
  }

  Future<void> retryPending() async {
    if (_closed || _pending.isEmpty) return;
    await Future.wait<void>([
      for (final roomId in _pending.keys.toList()) _ensureDrain(roomId),
    ]);
  }

  Future<void> _ensureDrain(String roomId) {
    final existing = _inFlight[roomId];
    if (existing != null) return existing;

    final generation = _generation;
    late final Future<void> future;
    future = _drain(roomId, generation).whenComplete(() {
      if (identical(_inFlight[roomId], future)) {
        _inFlight.remove(roomId);
      }
    });
    _inFlight[roomId] = future;
    return future;
  }

  Future<void> _drain(String roomId, int generation) async {
    while (!_closed && generation == _generation) {
      final cursor = _pending[roomId];
      if (cursor == null) return;
      final synced = _lastSynced[roomId];
      if (synced != null && !cursor.isAfter(synced)) {
        if (_pending[roomId]?.messageId == cursor.messageId) {
          _pending.remove(roomId);
        }
        continue;
      }

      try {
        await _messages.markRead(
          roomId: roomId,
          lastReadMessageId: cursor.messageId,
        );
      } catch (_) {
        // Keep the desired cursor queued. retryPending() will resume it after
        // realtime reconnects, while a later markRead call can retry sooner.
        return;
      }
      if (_closed || generation != _generation) return;

      final previous = _lastSynced[roomId];
      if (previous == null || cursor.isAfter(previous)) {
        _lastSynced[roomId] = cursor;
      }
      if (_pending[roomId]?.messageId == cursor.messageId) {
        _pending.remove(roomId);
      }
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _generation++;
    _pending.clear();
    _lastSynced.clear();
  }
}

class _RoomReadCursor {
  const _RoomReadCursor({required this.messageId, required this.createdAt});

  final String messageId;
  final DateTime createdAt;

  bool isAfter(_RoomReadCursor other) {
    final timeComparison = createdAt.compareTo(other.createdAt);
    if (timeComparison != 0) return timeComparison > 0;
    return messageId.compareTo(other.messageId) > 0;
  }
}
