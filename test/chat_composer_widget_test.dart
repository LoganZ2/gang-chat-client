import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/material.dart';
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
}
