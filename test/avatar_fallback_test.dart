import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/ui/ui.dart';

void main() {
  test('avatarFallbackColor maps known keys and falls back to blue', () {
    expect(avatarFallbackColor('blue-3'), const Color(0xFF526C9F));
    expect(normalizeAvatarPresetKey('room-1'), 'blue-3');
    expect(avatarFallbackColor('room-1'), const Color(0xFF526C9F));
    expect(avatarFallbackColor('graphite-2'), const Color(0xFF5B5D63));
    expect(avatarFallbackColor('missing'), const Color(0xFF526C9F));
  });

  testWidgets('active avatar paints the status border above its content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: Avatar(
            label: 'Kai',
            active: true,
            activeBorderColor: UiColors.presenceVoice,
            paintBorderOnForeground: true,
          ),
        ),
      ),
    );

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(Avatar),
        matching: find.byType(Container),
      ),
    );
    final foreground = container.foregroundDecoration as BoxDecoration;
    final border = foreground.border! as Border;
    expect(border.top.color, UiColors.presenceVoice);
    expect(border.top.width, 2);
  });

  testWidgets('avatar keeps status border in the background by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: Avatar(label: 'Kai', active: true)),
      ),
    );

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(Avatar),
        matching: find.byType(Container),
      ),
    );
    expect(container.foregroundDecoration, isNull);
  });

  testWidgets('avatar can suppress shared status and base borders', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: Avatar(label: 'Kai', active: true, showBorder: false),
        ),
      ),
    );

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(Avatar),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    final label = tester.widget<Text>(find.text('KA'));
    expect(decoration.border, isNull);
    expect(container.foregroundDecoration, isNull);
    expect(label.style?.color, UiColors.text);
  });
}
