import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/ui/input.dart';

void main() {
  testWidgets('input clear button clears text and reports the change', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'alice');
    final changes = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: Input(
                controller: controller,
                hintText: '搜索',
                showClearButton: true,
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('清空搜索'), findsOneWidget);

    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(changes, contains(''));
    expect(find.byTooltip('清空搜索'), findsNothing);
  });

  testWidgets('search input submits with enter instead of accepting newlines', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'alice');
    final submissions = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: Input(
                controller: controller,
                hintText: '搜索成员',
                prefixIcon: Icons.search,
                showClearButton: true,
                onSubmitted: submissions.add,
              ),
            ),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLines, 1);
    expect(field.textInputAction, TextInputAction.search);

    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(controller.text, 'alice');
    expect(submissions, ['alice']);
  });
}
