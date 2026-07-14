import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:client/src/app/messages_controller.dart';
import 'package:client/src/app/room_read_sync_controller.dart';

void main() {
  test('serializes and coalesces read receipts for one room', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final requestedMessageIds = <String>[];
    final messages = _FakeMessagesController((_, messageId) async {
      requestedMessageIds.add(messageId);
      if (requestedMessageIds.length == 1) {
        firstStarted.complete();
        await releaseFirst.future;
      }
      return 0;
    });
    final controller = RoomReadSyncController(messages: messages);
    addTearDown(controller.close);

    final first = controller.markRead(
      roomId: 'room_1',
      lastReadMessageId: 'msg_1',
      messageCreatedAt: DateTime.utc(2026, 7, 14, 10),
    );
    await firstStarted.future;
    final second = controller.markRead(
      roomId: 'room_1',
      lastReadMessageId: 'msg_2',
      messageCreatedAt: DateTime.utc(2026, 7, 14, 10, 1),
    );
    releaseFirst.complete();
    await Future.wait([first, second]);

    expect(requestedMessageIds, ['msg_1', 'msg_2']);
    expect(controller.isSynced(roomId: 'room_1', messageId: 'msg_2'), isTrue);
  });

  test('retains a failed receipt and retries it after reconnect', () async {
    var requests = 0;
    final messages = _FakeMessagesController((_, _) async {
      requests++;
      if (requests == 1) throw StateError('offline');
      return 0;
    });
    final controller = RoomReadSyncController(messages: messages);
    addTearDown(controller.close);

    await controller.markRead(
      roomId: 'room_1',
      lastReadMessageId: 'msg_2',
      messageCreatedAt: DateTime.utc(2026, 7, 14, 10),
    );
    expect(controller.isSynced(roomId: 'room_1', messageId: 'msg_2'), isFalse);

    await controller.retryPending();

    expect(requests, 2);
    expect(controller.isSynced(roomId: 'room_1', messageId: 'msg_2'), isTrue);
  });

  test(
    'does not replace a failed newer receipt with an older intent',
    () async {
      final requestedMessageIds = <String>[];
      final messages = _FakeMessagesController((_, messageId) async {
        requestedMessageIds.add(messageId);
        if (requestedMessageIds.length == 1) throw StateError('offline');
        return 0;
      });
      final controller = RoomReadSyncController(messages: messages);
      addTearDown(controller.close);

      await controller.markRead(
        roomId: 'room_1',
        lastReadMessageId: 'msg_2',
        messageCreatedAt: DateTime.utc(2026, 7, 14, 10, 1),
      );
      await controller.markRead(
        roomId: 'room_1',
        lastReadMessageId: 'msg_1',
        messageCreatedAt: DateTime.utc(2026, 7, 14, 10),
      );

      expect(requestedMessageIds, ['msg_2', 'msg_2']);
      expect(controller.isSynced(roomId: 'room_1', messageId: 'msg_2'), isTrue);
    },
  );

  test('does not resend an already synced receipt', () async {
    var requests = 0;
    final messages = _FakeMessagesController((_, _) async {
      requests++;
      return 0;
    });
    final controller = RoomReadSyncController(messages: messages);
    addTearDown(controller.close);

    await controller.markRead(
      roomId: 'room_1',
      lastReadMessageId: 'msg_2',
      messageCreatedAt: DateTime.utc(2026, 7, 14, 10),
    );
    await controller.markRead(
      roomId: 'room_1',
      lastReadMessageId: 'msg_2',
      messageCreatedAt: DateTime.utc(2026, 7, 14, 10),
    );

    expect(requests, 1);
  });

  test('drains different rooms independently', () async {
    final roomOneStarted = Completer<void>();
    final releaseRoomOne = Completer<void>();
    final requestedRooms = <String>[];
    final messages = _FakeMessagesController((roomId, _) async {
      requestedRooms.add(roomId);
      if (roomId == 'room_1') {
        roomOneStarted.complete();
        await releaseRoomOne.future;
      }
      return 0;
    });
    final controller = RoomReadSyncController(messages: messages);
    addTearDown(controller.close);

    final roomOne = controller.markRead(
      roomId: 'room_1',
      lastReadMessageId: 'msg_1',
      messageCreatedAt: DateTime.utc(2026, 7, 14, 10),
    );
    await roomOneStarted.future;
    await controller.markRead(
      roomId: 'room_2',
      lastReadMessageId: 'msg_2',
      messageCreatedAt: DateTime.utc(2026, 7, 14, 10),
    );

    expect(requestedRooms, containsAll(<String>['room_1', 'room_2']));
    expect(controller.isSynced(roomId: 'room_2', messageId: 'msg_2'), isTrue);
    releaseRoomOne.complete();
    await roomOne;
  });

  test('close ignores a successful response that arrives late', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var requests = 0;
    final messages = _FakeMessagesController((_, _) async {
      requests++;
      started.complete();
      await release.future;
      return 0;
    });
    final controller = RoomReadSyncController(messages: messages);

    final pending = controller.markRead(
      roomId: 'room_1',
      lastReadMessageId: 'msg_1',
      messageCreatedAt: DateTime.utc(2026, 7, 14, 10),
    );
    await started.future;
    controller.close();
    release.complete();
    await pending;
    await controller.retryPending();

    expect(requests, 1);
    expect(controller.isSynced(roomId: 'room_1', messageId: 'msg_1'), isFalse);
  });

  test(
    'uses the message id as a stable tie-breaker for equal timestamps',
    () async {
      final requestedMessageIds = <String>[];
      final messages = _FakeMessagesController((_, messageId) async {
        requestedMessageIds.add(messageId);
        return 0;
      });
      final controller = RoomReadSyncController(messages: messages);
      addTearDown(controller.close);
      final createdAt = DateTime.utc(2026, 7, 14, 10);

      await controller.markRead(
        roomId: 'room_1',
        lastReadMessageId: 'msg_b',
        messageCreatedAt: createdAt,
      );
      await controller.markRead(
        roomId: 'room_1',
        lastReadMessageId: 'msg_a',
        messageCreatedAt: createdAt,
      );

      expect(requestedMessageIds, <String>['msg_b']);
      expect(controller.isSynced(roomId: 'room_1', messageId: 'msg_b'), isTrue);
    },
  );

  test('ignores blank room and message identifiers', () async {
    var requests = 0;
    final messages = _FakeMessagesController((_, _) async {
      requests++;
      return 0;
    });
    final controller = RoomReadSyncController(messages: messages);
    addTearDown(controller.close);
    final createdAt = DateTime.utc(2026, 7, 14, 10);

    await controller.markRead(
      roomId: '',
      lastReadMessageId: 'msg_1',
      messageCreatedAt: createdAt,
    );
    await controller.markRead(
      roomId: 'room_1',
      lastReadMessageId: '',
      messageCreatedAt: createdAt,
    );

    expect(requests, 0);
  });
}

class _FakeMessagesController extends MessagesController {
  _FakeMessagesController(this.onMarkRead);

  final Future<int> Function(String roomId, String messageId) onMarkRead;

  @override
  Future<int> markRead({
    required String roomId,
    required String lastReadMessageId,
  }) {
    return onMarkRead(roomId, lastReadMessageId);
  }
}
