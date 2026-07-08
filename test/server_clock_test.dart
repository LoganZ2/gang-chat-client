import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/server_clock.dart';

void main() {
  test('parses valid server time headers as UTC', () {
    expect(
      parseServerTimeHeader('2026-07-08T09:00:00Z'),
      DateTime.utc(2026, 7, 8, 9),
    );
    expect(parseServerTimeHeader(''), isNull);
    expect(parseServerTimeHeader('not-a-time'), isNull);
  });

  test('derives current time from server time and monotonic elapsed time', () {
    var localNow = DateTime.utc(2026, 7, 8, 1);
    var monotonicNow = Duration.zero;
    final clock = ServerClock(
      localNow: () => localNow,
      monotonicNow: () => monotonicNow,
    );
    var notifications = 0;
    clock.addListener(() => notifications += 1);

    expect(clock.now(), localNow);

    expect(clock.updateFromHeader('2026-07-08T09:00:00Z'), isTrue);
    expect(notifications, 1);

    localNow = DateTime.utc(2026, 7, 8, 3, 5);
    monotonicNow = const Duration(minutes: 5);
    expect(clock.now(), DateTime.utc(2026, 7, 8, 9, 5));

    expect(clock.updateFromHeader('not-a-time'), isFalse);
    expect(notifications, 1);
  });

  test('records the latest successful request round-trip latency', () {
    final clock = ServerClock();
    var notifications = 0;
    clock.addListener(() => notifications += 1);

    expect(clock.requestRoundTrip, isNull);
    expect(
      clock.updateRequestRoundTrip(const Duration(milliseconds: 87)),
      isTrue,
    );

    expect(clock.requestRoundTrip, const Duration(milliseconds: 87));
    expect(notifications, 1);
    expect(
      clock.updateRequestRoundTrip(const Duration(milliseconds: -1)),
      isFalse,
    );
    expect(clock.requestRoundTrip, const Duration(milliseconds: 87));
    expect(notifications, 1);
  });
}
