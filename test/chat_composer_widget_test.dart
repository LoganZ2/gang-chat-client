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

  testWidgets('chat composer sends focused input on Enter', (tester) async {
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);
    final submissions = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: ui.ChatComposer(
            controller: controller,
            onSubmitted: submissions.add,
            actions: const [],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(submissions, ['hello']);
    expect(controller.text, 'hello');
  });

  testWidgets('chat composer inserts newline on Shift Enter', (tester) async {
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);
    final submissions = <String>[];
    final changes = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: ui.ChatComposer(
            controller: controller,
            onSubmitted: submissions.add,
            onChanged: changes.add,
            actions: const [],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(submissions, isEmpty);
    expect(changes, ['hello\n']);
    expect(controller.text, 'hello\n');
    expect(controller.selection.baseOffset, 6);
  });

  testWidgets('chat composer inserts newline on Control Enter', (tester) async {
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);
    final submissions = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: ui.ChatComposer(
            controller: controller,
            onSubmitted: submissions.add,
            actions: const [],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(submissions, isEmpty);
    expect(controller.text, 'h\no');
    expect(controller.selection.baseOffset, 2);
  });
}
