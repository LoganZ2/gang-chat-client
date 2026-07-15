import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/ui/ui.dart';

void main() {
  test('avatarFallbackColor maps known keys and falls back to blue', () {
    expect(avatarFallbackColor('blue-3'), const Color(0xFF526C9F));
    expect(normalizeAvatarPresetKey('room-1'), 'blue-3');
    expect(avatarFallbackColor('room-1'), const Color(0xFF526C9F));
    expect(avatarFallbackColor('graphite-2'), const Color(0xFF5B5D63));
    expect(avatarFallbackColor('red-2'), const Color(0xFF7B4F52));
    expect(avatarFallbackColor('missing'), const Color(0xFF526C9F));
    expect(avatarPresetLabel('room-1'), '蓝色');
    expect(avatarPresetLabel('purple-2'), '紫色');
    expect(avatarPresetLabel('missing'), '蓝色');
    expect(
      kAvatarPresetKeys,
      containsAll(<String>['red-2', 'gold-2', 'black-2']),
    );
  });

  testWidgets('uploaded avatar keeps its background transparent', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: Avatar(
            label: 'Kai',
            imageUrl: 'uploaded-avatar',
            defaultAvatarKey: 'red-2',
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
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, Colors.transparent);
  });

  testWidgets('avatar picker exposes Chinese color names', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AvatarPicker(
            label: '头像',
            displayName: '凯',
            imageUrl: null,
            defaultAvatarKey: 'red-2',
            usingPreset: true,
            uploading: false,
            enabled: true,
            presetKeys: const ['red-2'],
            onUpload: () {},
            onPresetSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('红色'), findsOneWidget);
    expect(find.byTooltip('red-2'), findsNothing);
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

  testWidgets('avatar picker opens preview only for uploaded images', (
    tester,
  ) async {
    var previews = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 460,
              child: AvatarPicker(
                label: 'Avatar',
                displayName: 'Kai',
                imageUrl: 'uploaded-avatar',
                defaultAvatarKey: 'blue-3',
                usingPreset: false,
                uploading: false,
                enabled: true,
                onUpload: () {},
                onPresetSelected: (_) {},
                onImagePreview: () => previews += 1,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('avatar-picker-preview')));
    await tester.pump();

    expect(previews, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 460,
              child: AvatarPicker(
                label: 'Avatar',
                displayName: 'Kai',
                imageUrl: 'uploaded-avatar',
                defaultAvatarKey: 'blue-3',
                usingPreset: true,
                uploading: false,
                enabled: true,
                onUpload: () {},
                onPresetSelected: (_) {},
                onImagePreview: () => previews += 1,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('avatar-picker-preview')));
    await tester.pump();

    expect(previews, 1);
  });
}
