import 'package:client/src/home/live_channel_pane.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget-level coverage for the client-authoritative progress bar. The bar
/// anchors on the snapshot's base position and ignores the server wall clock,
/// re-anchors when a fresh snapshot moves the base, and holds while paused. The
/// per-second stepping arithmetic itself is covered by the pure-function tests
/// in `music_box_display_test.dart` (the widget steps on a real monotonic
/// [Stopwatch], which a widget test's fake clock can't advance).

Widget _host(MusicBoxState state, TextEditingController searchController) {
  return MaterialApp(
    theme: uiTheme(),
    home: Scaffold(
      body: SizedBox(
        width: 360,
        child: LiveMusicBoxPanel(
          state: state,
          searchController: searchController,
          searchResults: const [],
          searching: false,
          searchError: null,
          onTogglePlayback: () {},
          onSkip: () {},
          onStop: () {},
          onQueueResult: (_) {},
          onRemoveItem: (_) {},
        ),
      ),
    ),
  );
}

MusicBoxState _state({
  required MusicBoxPlaybackState playbackState,
  required int positionMs,
  String currentItemId = 'a',
  DateTime? updatedAt,
}) {
  return MusicBoxState(
    enabled: true,
    playback: MusicBoxPlayback(
      state: playbackState,
      currentItemId: currentItemId,
      positionMs: positionMs,
      volume: 100,
      updatedAt: updatedAt,
    ),
    queue: [
      MusicBoxQueueItem(
        id: currentItemId,
        source: 'netease',
        trackId: 'track-$currentItemId',
        title: 'Song',
        artist: '',
        picId: '',
        durationMs: 200000,
        status: MusicBoxQueueItemStatus.ready,
        fileSizeBytes: 0,
        error: '',
        addedByUserId: 'user',
        createdAt: null,
      ),
    ],
    usage: const MusicBoxUsage(usedBytes: 0, limitBytes: 0),
  );
}

void main() {
  testWidgets('anchors on the snapshot base, ignoring the server wall clock', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        _state(
          playbackState: MusicBoxPlaybackState.playing,
          positionMs: 5000,
          // A wildly skewed server timestamp the bar must not use.
          updatedAt: DateTime.utc(1990, 1, 1),
        ),
        controller,
      ),
    );

    expect(find.text('0:05'), findsOneWidget);
  });

  testWidgets('re-anchors when a fresh snapshot moves the base position', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        _state(
          playbackState: MusicBoxPlaybackState.playing,
          positionMs: 5000,
        ),
        controller,
      ),
    );
    expect(find.text('0:05'), findsOneWidget);

    // A new snapshot resets the base; the bar jumps to it immediately.
    await tester.pumpWidget(
      _host(
        _state(
          playbackState: MusicBoxPlaybackState.playing,
          positionMs: 30000,
        ),
        controller,
      ),
    );
    expect(find.text('0:30'), findsOneWidget);
    expect(find.text('0:05'), findsNothing);
  });

  testWidgets('holds the recorded position while paused', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        _state(
          playbackState: MusicBoxPlaybackState.paused,
          positionMs: 12000,
        ),
        controller,
      ),
    );
    expect(find.text('0:12'), findsOneWidget);

    // No ticker while paused: a bounded pump must not advance the label.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('0:12'), findsOneWidget);
  });
}
