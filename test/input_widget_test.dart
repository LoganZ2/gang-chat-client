import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/ui/input.dart';
import 'package:client/src/ui/text_context_menu.dart';

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

  testWidgets('input stays lifted while focused without hover', (tester) async {
    final controller = TextEditingController(text: 'hello');
    addTearDown(controller.dispose);

    await _pumpInput(tester, controller);

    AnimatedPadding inputCap() {
      return tester.widget<AnimatedPadding>(find.byType(AnimatedPadding));
    }

    expect(inputCap().padding, const EdgeInsets.only(top: 3, bottom: 5));

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(inputCap().padding, const EdgeInsets.only(top: 0, bottom: 8));
  });

  testWidgets('input context menu shows select all without clipboard text', (
    tester,
  ) async {
    _mockClipboardText(null);
    final controller = TextEditingController(text: 'hello');
    controller.selection = const TextSelection.collapsed(offset: 5);
    addTearDown(controller.dispose);

    await _pumpInput(tester, controller);
    await _showInputContextMenu(
      tester,
      selection: const TextSelection.collapsed(offset: 5),
    );

    expect(find.text('全选'), findsOneWidget);
    expect(find.text('Ctrl+A'), findsOneWidget);
    expect(find.text('粘贴'), findsNothing);
    expect(find.text('剪切'), findsNothing);
    expect(find.text('复制'), findsNothing);
  });

  testWidgets('input context menu hides select all when text is empty', (
    tester,
  ) async {
    _mockClipboardText(null);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pumpInput(tester, controller);
    await _showInputContextMenu(
      tester,
      selection: const TextSelection.collapsed(offset: 0),
    );

    expect(find.text('全选'), findsNothing);
    expect(find.text('Ctrl+A'), findsNothing);
    expect(find.text('粘贴'), findsNothing);
  });

  testWidgets('input context menu shows paste when clipboard has text', (
    tester,
  ) async {
    _mockClipboardText('from clipboard');
    final controller = TextEditingController(text: 'hello');
    controller.selection = const TextSelection.collapsed(offset: 5);
    addTearDown(controller.dispose);

    await _pumpInput(tester, controller);
    await _showInputContextMenu(
      tester,
      selection: const TextSelection.collapsed(offset: 5),
    );

    expect(find.text('粘贴'), findsOneWidget);
    expect(find.text('Ctrl+V'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('Ctrl+A'), findsOneWidget);
    expect(find.text('剪切'), findsNothing);
    expect(find.text('复制'), findsNothing);
  });

  testWidgets('input context menu shows edit actions for selected text', (
    tester,
  ) async {
    _mockClipboardText(null);
    final controller = TextEditingController(text: 'hello world');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    addTearDown(controller.dispose);

    await _pumpInput(tester, controller);
    await _showInputContextMenu(
      tester,
      selection: const TextSelection(baseOffset: 0, extentOffset: 5),
    );

    expect(find.text('剪切'), findsOneWidget);
    expect(find.text('Ctrl+X'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('Ctrl+C'), findsOneWidget);
    expect(find.text('粘贴'), findsNothing);
    expect(find.text('Ctrl+V'), findsNothing);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('Ctrl+A'), findsOneWidget);
  });

  testWidgets('input context menu shows paste for selection when pasteable', (
    tester,
  ) async {
    _mockClipboardText('from clipboard');
    final controller = TextEditingController(text: 'hello world');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    addTearDown(controller.dispose);

    await _pumpInput(tester, controller);
    await _showInputContextMenu(
      tester,
      selection: const TextSelection(baseOffset: 0, extentOffset: 5),
    );

    expect(find.text('剪切'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('粘贴'), findsOneWidget);
    expect(find.text('Ctrl+V'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
  });

  testWidgets('input context menu item stays inside tap region', (
    tester,
  ) async {
    _mockClipboardText(null);
    final group = Object();
    final controller = TextEditingController(text: 'hello');
    final undoController = UndoHistoryController();
    var outsideTapCount = 0;
    addTearDown(controller.dispose);
    addTearDown(undoController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TapRegion(
              groupId: group,
              onTapOutside: (_) => outsideTapCount++,
              child: SizedBox(
                width: 320,
                child: TextFieldEditingShortcuts(
                  controller: controller,
                  undoController: undoController,
                  child: TextField(
                    controller: controller,
                    undoController: undoController,
                    contextMenuBuilder: (context, editableTextState) =>
                        buildTextFieldContextMenu(
                          context,
                          editableTextState,
                          undoController: undoController,
                          tapRegionGroupId: group,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await _showInputContextMenu(
      tester,
      selection: const TextSelection.collapsed(offset: 5),
    );

    await tester.tap(find.text('Ctrl+A'));
    await tester.pump();

    expect(outsideTapCount, 0);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
  });

  testWidgets('input context menu remains open through ancestor rebuild', (
    tester,
  ) async {
    _mockClipboardText(null);
    final controller = TextEditingController(text: 'hello');
    final undoController = UndoHistoryController();
    final openStates = <bool>[];
    late StateSetter rebuildHost;
    var generation = 0;
    addTearDown(controller.dispose);
    addTearDown(undoController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuildHost = setState;
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('generation $generation'),
                    SizedBox(
                      width: 320,
                      child: TextFieldEditingShortcuts(
                        controller: controller,
                        undoController: undoController,
                        child: TextField(
                          controller: controller,
                          undoController: undoController,
                          contextMenuBuilder: (context, editableTextState) =>
                              buildTextFieldContextMenu(
                                context,
                                editableTextState,
                                undoController: undoController,
                                onOpenChanged: openStates.add,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    await _showInputContextMenu(
      tester,
      selection: const TextSelection.collapsed(offset: 5),
    );

    expect(
      find.byKey(const ValueKey('text-context-menu-panel')),
      findsOneWidget,
    );
    expect(openStates, [true]);

    rebuildHost(() => generation++);
    await tester.pump();

    expect(find.text('generation 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('text-context-menu-panel')),
      findsOneWidget,
    );
    expect(openStates, [true]);
  });

  testWidgets('input secondary click on blank area keeps selected text', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);

    await _pumpInput(tester, controller);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();

    final fieldRect = tester.getRect(find.byType(TextField));
    final location = Offset(fieldRect.right - 8, fieldRect.center.dy);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: location);
    await tester.pump();
    await gesture.down(location);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('input secondary click on text area keeps selected text', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);

    await _pumpInput(tester, controller);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    const selectedText = TextSelection(baseOffset: 0, extentOffset: 5);
    controller.selection = selectedText;
    await tester.pump();

    final fieldRect = tester.getRect(find.byType(TextField));
    final location = Offset(fieldRect.left + 34, fieldRect.center.dy);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: location);
    await tester.pump();
    await gesture.down(location);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    controller.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
    await tester.pump(const Duration(milliseconds: 60));

    expect(controller.selection, selectedText);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('input secondary click restores late collapsed selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);

    await _pumpInput(tester, controller);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    const selectedText = TextSelection(baseOffset: 0, extentOffset: 5);
    controller.selection = selectedText;
    await tester.pump();

    final fieldRect = tester.getRect(find.byType(TextField));
    final location = Offset(fieldRect.right - 8, fieldRect.center.dy);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: location);
    await tester.pump();
    await gesture.down(location);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    controller.selection = const TextSelection.collapsed(offset: 10);
    await tester.pump(const Duration(milliseconds: 60));

    expect(controller.selection, selectedText);

    controller.selection = const TextSelection.collapsed(offset: 11);
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.selection, selectedText);

    await tester.tapAt(Offset(fieldRect.left + 8, fieldRect.center.dy));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 11);
    await tester.pump();

    expect(controller.selection, const TextSelection.collapsed(offset: 11));
  });

  testWidgets('input secondary click restores focus and selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello world');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await _pumpInput(tester, controller, focusNode: focusNode);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    const selectedText = TextSelection(baseOffset: 0, extentOffset: 5);
    controller.selection = selectedText;
    await tester.pump();

    final fieldRect = tester.getRect(find.byType(TextField));
    final location = Offset(fieldRect.right - 8, fieldRect.center.dy);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: location);
    await tester.pump();
    await gesture.down(location);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    focusNode.unfocus();
    controller.selection = const TextSelection.collapsed(offset: 11);
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
    expect(controller.selection, selectedText);
  });

  testWidgets('input secondary click does not turn caret into select all', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);

    await _pumpInput(tester, controller);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    const caret = TextSelection.collapsed(offset: 5);
    controller.selection = caret;
    await tester.pump();

    final fieldRect = tester.getRect(find.byType(TextField));
    final location = Offset(fieldRect.left + 34, fieldRect.center.dy);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: location);
    await tester.pump();
    await gesture.down(location);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 11);
    await tester.pump();

    expect(controller.selection, caret);
  });

  testWidgets('input secondary click does not restore old selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);

    await _pumpInput(tester, controller);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 11);
    await tester.pump();

    final fieldRect = tester.getRect(find.byType(TextField));
    final location = Offset(fieldRect.left + 34, fieldRect.center.dy);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: location);
    await tester.pump();
    await gesture.down(location);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(controller.selection.isCollapsed, isTrue);
    expect(
      controller.selection,
      isNot(const TextSelection(baseOffset: 0, extentOffset: 5)),
    );
  });

  testWidgets('input context menu shows undo when undo is available', (
    tester,
  ) async {
    _mockClipboardText(null);
    final controller = TextEditingController(text: 'hello');
    controller.selection = const TextSelection.collapsed(offset: 5);
    final undoController = UndoHistoryController(
      value: const UndoHistoryValue(canUndo: true),
    );
    addTearDown(controller.dispose);
    addTearDown(undoController.dispose);

    await _pumpInput(tester, controller, undoController: undoController);
    await _showInputContextMenu(
      tester,
      beforeShow: () {
        undoController.value = const UndoHistoryValue(canUndo: true);
      },
    );

    expect(find.text('撤销'), findsOneWidget);
    expect(find.text('Ctrl+Z'), findsOneWidget);
    final divider = find.byKey(const ValueKey('text-context-menu-divider'));
    expect(divider, findsOneWidget);
    expect(tester.getSize(divider).width, greaterThan(120));
  });

  testWidgets('input ctrl Y invokes redo on the focused field', (tester) async {
    final controller = TextEditingController();
    final undoController = UndoHistoryController(
      value: const UndoHistoryValue(canRedo: true),
    );
    var redoCount = 0;
    void handleRedo() => redoCount++;
    undoController.onRedo.addListener(handleRedo);
    addTearDown(() {
      undoController.onRedo.removeListener(handleRedo);
      undoController.dispose();
      controller.dispose();
    });

    await _pumpInput(tester, controller, undoController: undoController);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    undoController.value = const UndoHistoryValue(canRedo: true);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(redoCount, 1);
  });
}

Future<void> _pumpInput(
  WidgetTester tester,
  TextEditingController controller, {
  FocusNode? focusNode,
  UndoHistoryController? undoController,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: Input(
              controller: controller,
              focusNode: focusNode,
              undoController: undoController,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _showInputContextMenu(
  WidgetTester tester, {
  TextSelection? selection,
  VoidCallback? beforeShow,
}) async {
  await tester.tap(find.byType(TextField));
  await tester.pump();
  final editableTextState = tester.state<EditableTextState>(
    find.byType(EditableText),
  );
  if (selection != null) {
    editableTextState.userUpdateTextEditingValue(
      editableTextState.textEditingValue.copyWith(selection: selection),
      SelectionChangedCause.toolbar,
    );
    await tester.pump();
  }
  beforeShow?.call();
  expect(editableTextState.showToolbar(), isTrue);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void _mockClipboardText(String? text) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return switch (call.method) {
          'Clipboard.getData' =>
            text == null ? null : <String, dynamic>{'text': text},
          'Clipboard.hasStrings' => <String, dynamic>{
            'value': text != null && text.isNotEmpty,
          },
          'Clipboard.setData' => null,
          _ => null,
        };
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}
