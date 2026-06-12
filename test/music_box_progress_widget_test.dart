import 'package:client/src/home/live_channel_pane.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget-level coverage for the server-authoritative progress bar: it renders
/// the snapshot's reported position verbatim and updates only when a fresh
/// snapshot arrives — no local stepping, no client clock.

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
          source: 'netease',
          onTogglePlayback: () {},
          onSkip: () {},
          onStop: () {},
          onQueueResult: (_) {},
          onRemoveItem: (_) {},
          onSourceChanged: (_) {},
        ),
      ),
    ),
  );
}

MusicBoxState _state({
  required MusicBoxPlaybackState playbackState,
  required int positionMs,
  String currentItemId = 'a',
}) {
  return MusicBoxState(
    enabled: true,
    playback: MusicBoxPlayback(
      state: playbackState,
      currentItemId: currentItemId,
      positionMs: positionMs,
      volume: 100,
      updatedAt: null,
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
  testWidgets('renders the server-reported position', (tester) async {
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
  });

  testWidgets('does not advance the position without a fresh snapshot', (
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

    // No local ticker: pumping a frame must not move the position. The server
    // is the only thing that advances it, via a new snapshot.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('0:05'), findsOneWidget);
  });

  testWidgets('updates when a fresh snapshot reports a new position', (
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

    await tester.pumpWidget(
      _host(
        _state(
          playbackState: MusicBoxPlaybackState.playing,
          positionMs: 6000,
        ),
        controller,
      ),
    );
    expect(find.text('0:06'), findsOneWidget);
    expect(find.text('0:05'), findsNothing);
  });
}
