import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chat composer action can be highlighted externally', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: ui.ChatComposer(
            actions: [
              ui.ComposerAction(
                id: 'file',
                icon: Icons.attach_file,
                label: 'File',
                selected: true,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    final button = tester.widget<ui.ButtonIcon>(
      find.byWidgetPredicate(
        (widget) => widget is ui.ButtonIcon && widget.tooltip == 'File',
      ),
    );
    expect(button.selected, isTrue);
  });

  testWidgets('chat composer reports paste shortcut from the input', (
    tester,
  ) async {
    var pasteAttempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: ui.ChatComposer(
            onPasteFiles: () => pasteAttempts++,
            actions: const [
              ui.ComposerAction(
                id: 'file',
                icon: Icons.attach_file,
                label: 'File',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(pasteAttempts, 1);
  });
}
