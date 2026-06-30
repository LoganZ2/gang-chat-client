import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/ui/read_only_text_box.dart';
import 'package:client/src/ui/tokens.dart';

void main() {
  testWidgets('read-only text box shows select all when text is unselected', (
    tester,
  ) async {
    await _pumpReadOnlyTextBox(tester, 'hello world');
    await _showReadOnlyContextMenu(
      tester,
      selection: const TextSelection.collapsed(offset: 5),
    );

    expect(find.text('全选'), findsOneWidget);
    expect(find.text('Ctrl+A'), findsOneWidget);
    expect(find.text('复制'), findsNothing);
    expect(find.text('剪切'), findsNothing);
    expect(find.text('粘贴'), findsNothing);

    await tester.tap(find.text('全选'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 11),
    );
  });

  testWidgets('read-only text box shows copy when text is selected', (
    tester,
  ) async {
    final clipboardWrites = <String>[];
    _mockClipboard(clipboardWrites);

    await _pumpReadOnlyTextBox(tester, 'hello world');
    await _showReadOnlyContextMenu(
      tester,
      selection: const TextSelection(baseOffset: 0, extentOffset: 5),
    );

    expect(find.text('复制'), findsOneWidget);
    expect(find.text('Ctrl+C'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('剪切'), findsNothing);
    expect(find.text('粘贴'), findsNothing);

    await tester.tap(find.text('复制'));
    await tester.pump();

    expect(clipboardWrites, ['hello']);
  });

  testWidgets('read-only text box hides menu when text is empty', (
    tester,
  ) async {
    await _pumpReadOnlyTextBox(tester, '');
    await _showReadOnlyContextMenu(
      tester,
      selection: const TextSelection.collapsed(offset: 0),
    );

    expect(find.text('全选'), findsNothing);
    expect(find.text('复制'), findsNothing);
  });
}

Future<void> _pumpReadOnlyTextBox(WidgetTester tester, String value) {
  return tester.pumpWidget(
    MaterialApp(
      theme: uiTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 320, child: ReadOnlyTextBox(value: value)),
        ),
      ),
    ),
  );
}

Future<void> _showReadOnlyContextMenu(
  WidgetTester tester, {
  required TextSelection selection,
}) async {
  await tester.tap(find.byType(TextField));
  await tester.pump();
  final editableTextState = tester.state<EditableTextState>(
    find.byType(EditableText),
  );
  editableTextState.userUpdateTextEditingValue(
    editableTextState.textEditingValue.copyWith(selection: selection),
    SelectionChangedCause.toolbar,
  );
  await tester.pump();
  expect(editableTextState.showToolbar(), isTrue);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void _mockClipboard(List<String> writes) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          writes.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
          return null;
        }
        if (call.method == 'Clipboard.hasStrings') {
          return const <String, dynamic>{'value': false};
        }
        return null;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}
