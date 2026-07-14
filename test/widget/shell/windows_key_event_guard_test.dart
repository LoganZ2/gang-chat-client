// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:client/src/shell/windows_key_event_guard.dart';

void main() {
  test('normalizes malformed left Alt key-down modifiers on Windows', () {
    final message = <Object?, Object?>{
      'keymap': 'windows',
      'type': 'keydown',
      'keyCode': 0xA4,
      'scanCode': 56,
      'characterCodePoint': 0,
      'modifiers': 0,
    };

    final normalized = normalizeWindowsAltKeyMessageForTest(message);

    expect(normalized, isA<Map<Object?, Object?>>());
    expect(
      (normalized! as Map<Object?, Object?>)['modifiers'],
      (1 << 6) | (1 << 7),
    );
    expect(message['modifiers'], 0);
  });

  test('normalizes malformed right Alt key-down modifiers on Windows', () {
    final normalized =
        normalizeWindowsAltKeyMessageForTest(<Object?, Object?>{
              'keymap': 'windows',
              'type': 'keydown',
              'keyCode': 0xA5,
              'modifiers': 1 << 0,
            })
            as Map<Object?, Object?>;

    expect(normalized['modifiers'], (1 << 0) | (1 << 6) | (1 << 8));
  });

  test('leaves non-Alt and key-up messages unchanged', () {
    final keyA = <Object?, Object?>{
      'keymap': 'windows',
      'type': 'keydown',
      'keyCode': 0x41,
      'modifiers': 0,
    };
    final altUp = <Object?, Object?>{
      'keymap': 'windows',
      'type': 'keyup',
      'keyCode': 0xA4,
      'modifiers': 0,
    };

    expect(identical(normalizeWindowsAltKeyMessageForTest(keyA), keyA), isTrue);
    expect(
      identical(normalizeWindowsAltKeyMessageForTest(altUp), altUp),
      isTrue,
    );
  });

  testWidgets('normalized Alt down survives Flutter raw key handling', (
    tester,
  ) async {
    final normalized =
        normalizeWindowsAltKeyMessageForTest(<Object?, Object?>{
              'keymap': 'windows',
              'type': 'keydown',
              'keyCode': 0xA4,
              'scanCode': 56,
              'characterCodePoint': 0,
              'modifiers': 0,
            })
            as Map<Object?, Object?>;

    // The production guard delegates to this same legacy raw-key handler after
    // fixing the malformed Windows Alt message.
    final downResult = await ServicesBinding.instance.keyEventManager
        .handleRawKeyMessage(normalized);
    await ServicesBinding.instance.keyEventManager.handleRawKeyMessage({
      'keymap': 'windows',
      'type': 'keyup',
      'keyCode': 0xA4,
      'scanCode': 56,
      'characterCodePoint': 0,
      'modifiers': 0,
    });

    expect(downResult, containsPair('handled', isA<bool>()));
  });
}
