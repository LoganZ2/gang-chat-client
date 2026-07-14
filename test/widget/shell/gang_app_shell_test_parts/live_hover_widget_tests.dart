part of '../gang_app_shell_test.dart';

void registerShellLiveHoverWidgetTests() {
  test('live stage defaults collapsed except local screen share', () {
    final remoteCamera = _liveVideoTrack(
      identity: 'user-2',
      isScreenShare: false,
      isLocal: false,
    );
    final localCamera = _liveVideoTrack(
      identity: 'user-1',
      isScreenShare: false,
      isLocal: true,
    );
    final localShare = _liveVideoTrack(
      identity: 'user-1',
      isScreenShare: true,
      isLocal: true,
    );

    expect(
      live_pane.resolveLiveStageTrackForTest(
        tracks: [remoteCamera, localCamera],
        selection: null,
      ),
      isNull,
    );
    expect(
      live_pane.resolveLiveStageTrackForTest(
        tracks: [remoteCamera, localCamera, localShare],
        selection: null,
      ),
      same(localShare),
    );
    expect(
      live_pane.resolveLiveStageTrackForTest(
        tracks: [remoteCamera, localShare],
        selection: live_pane.LiveStageSelection.fromTrack(remoteCamera),
      ),
      same(remoteCamera),
    );
    expect(
      live_pane.resolveLiveStageTrackForTest(
        tracks: [localShare],
        selection: const live_pane.LiveStageSelection.none(),
      ),
      isNull,
    );
  });

  testWidgets('hover card reset hides portal safely during rebuild', (
    WidgetTester tester,
  ) async {
    var resetKey = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Center(
                child: HoverCardAnchor(
                  resetKey: resetKey,
                  cardBuilder: (context) => TextButton(
                    onPressed: () => setState(() => resetKey++),
                    child: const Text('Reset card'),
                  ),
                  child: const SizedBox.square(
                    key: ValueKey('hover-card-anchor'),
                    dimension: 40,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('hover-card-anchor'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reset card'), findsOneWidget);

    await tester.tap(find.text('Reset card'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
