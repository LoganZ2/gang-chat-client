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
}
