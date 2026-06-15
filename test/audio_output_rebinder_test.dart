import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/live/audio_output_rebinder.dart';

void main() {
  test('rebinds output and re-applies routing on a device change', () async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    final selected = <String>[];
    var rebounds = 0;

    final rebinder = AudioOutputRebinder(
      deviceChanges: changes.stream,
      currentOutputDeviceId: () async => 'speaker_1',
      selectOutput: (id) async => selected.add(id),
      onRebound: () async => rebounds += 1,
      debounce: const Duration(milliseconds: 10),
    );
    addTearDown(rebinder.stop);
    rebinder.start();

    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(selected, ['speaker_1']);
    expect(rebounds, 1);
  });

  test('coalesces a burst of changes into a single rebind', () async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    var selects = 0;
    var rebounds = 0;

    final rebinder = AudioOutputRebinder(
      deviceChanges: changes.stream,
      currentOutputDeviceId: () async => 'speaker_1',
      selectOutput: (_) async => selects += 1,
      onRebound: () async => rebounds += 1,
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(rebinder.stop);
    rebinder.start();

    // A single profile flip emits several events in quick succession.
    changes
      ..add(null)
      ..add(null)
      ..add(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(selects, 1);
    expect(rebounds, 1);
  });

  test('re-applies routing even without a known output id', () async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    var selects = 0;
    var rebounds = 0;

    final rebinder = AudioOutputRebinder(
      deviceChanges: changes.stream,
      currentOutputDeviceId: () async => null,
      selectOutput: (_) async => selects += 1,
      onRebound: () async => rebounds += 1,
      debounce: const Duration(milliseconds: 10),
    );
    addTearDown(rebinder.stop);
    rebinder.start();

    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // No id to select, but routing is still refreshed so volumes re-bind to
    // whatever endpoint WebRTC ended up on.
    expect(selects, 0);
    expect(rebounds, 1);
  });

  test('a failed rebind is swallowed and does not block later ones', () async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    var attempts = 0;

    final rebinder = AudioOutputRebinder(
      deviceChanges: changes.stream,
      currentOutputDeviceId: () async {
        attempts += 1;
        if (attempts == 1) throw StateError('native failure');
        return 'speaker_2';
      },
      selectOutput: (_) async {},
      onRebound: () async {},
      debounce: const Duration(milliseconds: 10),
    );
    addTearDown(rebinder.stop);
    rebinder.start();

    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(attempts, 2);
  });

  test('stop cancels a pending rebind', () async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    var rebounds = 0;

    final rebinder = AudioOutputRebinder(
      deviceChanges: changes.stream,
      currentOutputDeviceId: () async => 'speaker_1',
      selectOutput: (_) async {},
      onRebound: () async => rebounds += 1,
      debounce: const Duration(milliseconds: 30),
    );
    rebinder.start();

    changes.add(null);
    await rebinder.stop();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(rebounds, 0);
  });

  test('ignores events after stop', () async {
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    var rebounds = 0;

    final rebinder = AudioOutputRebinder(
      deviceChanges: changes.stream,
      currentOutputDeviceId: () async => 'speaker_1',
      selectOutput: (_) async {},
      onRebound: () async => rebounds += 1,
      debounce: const Duration(milliseconds: 10),
    );
    rebinder.start();
    await rebinder.stop();

    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(rebounds, 0);
  });
}
