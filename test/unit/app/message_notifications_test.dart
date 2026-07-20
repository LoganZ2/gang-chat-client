import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/message_notifications.dart';

void main() {
  test('only explicit realtime message updates under all policy notify', () {
    final tracker = RealtimeMessageNotificationTracker();

    expect(
      tracker.register(
        roomId: 'room-1',
        updateReason: '',
        notificationPolicy: 'all',
        messageId: 'message-history',
      ),
      isFalse,
    );
    expect(
      tracker.register(
        roomId: 'room-1',
        updateReason: realtimeMessageCreatedUpdateReason,
        notificationPolicy: 'all',
        messageId: 'message-live',
      ),
      isTrue,
    );
  });

  test('duplicates stay silent even if the notification policy changes', () {
    final tracker = RealtimeMessageNotificationTracker();

    expect(
      tracker.register(
        roomId: 'room-1',
        updateReason: realtimeMessageCreatedUpdateReason,
        notificationPolicy: 'silent',
        messageId: 'message-1',
      ),
      isFalse,
    );
    expect(
      tracker.register(
        roomId: 'room-1',
        updateReason: realtimeMessageCreatedUpdateReason,
        notificationPolicy: 'all',
        messageId: 'message-1',
      ),
      isFalse,
    );
  });

  test('room id participates in deduplication and old entries are bounded', () {
    final tracker = RealtimeMessageNotificationTracker(capacity: 2);

    bool register(String roomId, String messageId) => tracker.register(
      roomId: roomId,
      updateReason: realtimeMessageCreatedUpdateReason,
      notificationPolicy: 'all',
      messageId: messageId,
    );

    expect(register('room-1', 'message-1'), isTrue);
    expect(register('room-2', 'message-1'), isTrue);
    expect(register('room-3', 'message-3'), isTrue);
    expect(register('room-1', 'message-1'), isTrue);
  });

  test('clear permits notifications in a replacement account session', () {
    final tracker = RealtimeMessageNotificationTracker();

    expect(
      tracker.register(
        roomId: 'room-1',
        updateReason: realtimeMessageCreatedUpdateReason,
        notificationPolicy: 'all',
        messageId: 'message-1',
      ),
      isTrue,
    );
    tracker.clear();
    expect(
      tracker.register(
        roomId: 'room-1',
        updateReason: realtimeMessageCreatedUpdateReason,
        notificationPolicy: 'all',
        messageId: 'message-1',
      ),
      isTrue,
    );
  });
}
