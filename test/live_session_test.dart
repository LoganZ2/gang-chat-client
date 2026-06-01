import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/live/live_session.dart';

void main() {
  test('screen-share source picker keeps screens without thumbnails', () {
    final sources = filterScreenSourcesForPicker([
      const ScreenSource(
        id: 'screen:0',
        name: 'Screen 1',
        thumbnail: null,
        isWindow: false,
      ),
    ]);

    expect(sources.map((s) => s.id), ['screen:0']);
  });

  test(
    'screen-share source picker filters known invisible overlay windows',
    () {
      final sources = filterScreenSourcesForPicker([
        ScreenSource(
          id: 'window:overlay',
          name: 'NVIDIA GeForce Overlay',
          thumbnail: Uint8List.fromList(List<int>.filled(64, 1)),
          isWindow: true,
        ),
        ScreenSource(
          id: 'window:editor',
          name: 'Code',
          thumbnail: Uint8List.fromList(List<int>.filled(64, 2)),
          isWindow: true,
        ),
      ]);

      expect(sources.map((s) => s.id), ['window:editor']);
    },
  );

  test('screen-share source picker keeps windows without thumbnails', () {
    final sources = filterScreenSourcesForPicker([
      const ScreenSource(
        id: 'window:browser',
        name: 'Browser',
        thumbnail: null,
        isWindow: true,
      ),
    ]);

    expect(sources.map((s) => s.id), ['window:browser']);
  });

  test('screen-share source picker keeps non-overlay system windows', () {
    final sources = filterScreenSourcesForPicker([
      const ScreenSource(
        id: 'window:input',
        name: 'Microsoft Text Input Application',
        thumbnail: null,
        isWindow: true,
      ),
      const ScreenSource(
        id: 'window:program-manager',
        name: 'Program Manager',
        thumbnail: null,
        isWindow: true,
      ),
    ]);

    expect(sources.map((s) => s.id), [
      'window:input',
      'window:program-manager',
    ]);
  });

  test('screen-share thumbnail updates are cached for reopened picker', () async {
    resetScreenSourceThumbnailCacheForTest();
    addTearDown(resetScreenSourceThumbnailCacheForTest);

    final controller = StreamController<Uint8List>.broadcast(sync: true);
    addTearDown(controller.close);

    final observed = <Uint8List>[];
    final subscription = cacheScreenSourceThumbnailUpdatesForTest(
      'screen:0',
      controller.stream,
    ).listen(observed.add);
    addTearDown(subscription.cancel);
    final sourceIdUpdates = <Uint8List>[];
    final sourceIdSubscription = screenSourceThumbnailUpdatesForTest(
      'screen:0',
    ).listen(sourceIdUpdates.add);
    addTearDown(sourceIdSubscription.cancel);

    final thumbnail = Uint8List.fromList([1, 2, 3]);
    controller.add(thumbnail);
    await Future<void>.delayed(Duration.zero);

    expect(observed, hasLength(1));
    expect(observed.single, same(thumbnail));
    expect(sourceIdUpdates, hasLength(1));
    expect(sourceIdUpdates.single, same(thumbnail));
    expect(cachedScreenSourceThumbnailForTest('screen:0'), same(thumbnail));
  });
}
