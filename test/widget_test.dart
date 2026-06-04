import 'package:flutter/gestures.dart' show PointerEnterEvent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/main.dart';
import 'package:client/src/auth/token_store.dart';
import 'package:client/src/settings/settings_page.dart';
import 'package:client/src/ui/ui.dart' as ui;

void main() {
  testWidgets('app renders auth entrypoint', (WidgetTester tester) async {
    await tester.pumpWidget(GangApp(tokenStore: _MemoryTokenStore()));
    await tester.pump();

    expect(find.text('Gang Chat'), findsAtLeastNWidgets(1));
    expect(find.text('Username or email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, 'Login'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('switching to register reveals additional fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(GangApp(tokenStore: _MemoryTokenStore()));
    await tester.pump();

    await tester.tap(find.text('Register'));
    await tester.pump();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsNWidgets(2));
    expect(find.widgetWithText(ui.Button, 'Create account'), findsOneWidget);

    await tester.tap(find.byTooltip('Show password').first);
    await tester.pump();

    expect(find.byTooltip('Hide password'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsOneWidget);
  });

  testWidgets('submitting empty form surfaces inline error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(GangApp(tokenStore: _MemoryTokenStore()));
    await tester.pump();

    await tester.tap(find.widgetWithText(ui.Button, 'Login'));
    await tester.pump();

    expect(find.text('Enter your credentials to continue.'), findsOneWidget);
  });

  testWidgets('button lays out with automatic width in a row', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [ui.Button(onPressed: () {}, child: const Text('Send'))],
          ),
        ),
      ),
    );

    expect(find.text('Send'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full-width button uses finite parent width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: ui.Button(
                width: double.infinity,
                onPressed: () {},
                child: const Text('Create'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(ui.Button)).width, 240);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui button truncates inside narrow bounds', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: Column(
              children: [
                SizedBox(
                  width: 98,
                  child: ui.Button(
                    loading: true,
                    onPressed: () {},
                    child: const Text('Loading'),
                  ),
                ),
                SizedBox(
                  width: 98,
                  child: ui.Button(
                    icon: const Icon(Icons.extension_outlined),
                    onPressed: () {},
                    child: const Text('Command'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('ui button lays out with automatic width in a row', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Row(
            children: [ui.Button(onPressed: () {}, child: const Text('Send'))],
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(ui.Button));

    expect(find.text('Send'), findsOneWidget);
    expect(size.width.isFinite, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui pressable surface lays out cap and base layers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: ui.PressableSurface(
                height: 40,
                onPressed: () {},
                child: const Text('Surface'),
              ),
            ),
          ),
        ),
      ),
    );

    final surfaceFinder = find.byType(ui.PressableSurface);
    final restingLayers = tester
        .widgetList<Positioned>(
          find.descendant(of: surfaceFinder, matching: find.byType(Positioned)),
        )
        .toList();
    expect(restingLayers, hasLength(2));
    expect(restingLayers.first.top, closeTo(8, 0.01));
    expect(restingLayers.last.top, closeTo(3, 0.01));
    final decorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: surfaceFinder,
            matching: find.byType(DecoratedBox),
          ),
        )
        .where((box) => box.decoration is BoxDecoration)
        .map((box) => box.decoration as BoxDecoration)
        .toList();
    expect(decorations, hasLength(2));
    expect(
      (decorations.first.border as Border).top.color,
      (decorations.last.border as Border).top.color,
    );
    expect((decorations.first.border as Border).top.color.a, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui kit segmented control does not use material ripple', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: ui.SegmentedControl<String>(
              value: 'chat',
              onChanged: (_) {},
              segments: const [
                ui.Segment(value: 'chat', label: 'Chat'),
                ui.Segment(value: 'forms', label: 'Forms'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(InkWell), findsNothing);
    expect(
      tester.getSize(find.byType(ui.SegmentedControl<String>)).width,
      lessThan(192),
    );
    expect(
      tester.getSize(find.byType(ui.SegmentedControl<String>)).height,
      closeTo(41, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui button supports toggle mode', (WidgetTester tester) async {
    var enabled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                return ui.Button(
                  icon: const Icon(Icons.mic),
                  toggleValue: enabled,
                  onToggleChanged: (value) => setState(() => enabled = value),
                  child: const Text('Mic'),
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.widgetWithText(ui.Button, 'Mic'),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Mic'));
    await tester.pump();

    expect(enabled, isTrue);
    final toggledButton = tester.widget<ui.PressableSurface>(
      find.descendant(
        of: find.widgetWithText(ui.Button, 'Mic'),
        matching: find.byType(ui.PressableSurface),
      ),
    );
    expect(toggledButton.selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui kit chat composer switches list and static panels', (
    WidgetTester tester,
  ) async {
    var sends = 0;
    final pageScrollController = ScrollController();
    addTearDown(pageScrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: pageScrollController,
            child: Padding(
              padding: const EdgeInsets.only(top: 80, bottom: 900),
              child: Center(
                child: SizedBox(
                  width: 560,
                  child: ui.ChatComposer(
                    hintText: 'Message',
                    actions: [
                      ui.ComposerAction(
                        id: 'stickers',
                        icon: Icons.emoji_emotions_outlined,
                        label: 'Stickers',
                        panel: ui.ComposerPanel.list(
                          itemCount: 24,
                          itemBuilder: (context, index) {
                            return SizedBox(
                              width: 84,
                              height: 76,
                              child: Center(child: Text('Sticker $index')),
                            );
                          },
                        ),
                      ),
                      const ui.ComposerAction(
                        id: 'voice',
                        icon: Icons.mic_none,
                        label: 'Voice',
                        panel: ui.ComposerPanel.static(
                          child: Center(child: Text('Voice panel')),
                        ),
                      ),
                      ui.ComposerAction(
                        id: 'send',
                        icon: Icons.send_rounded,
                        label: 'Send',
                        onPressed: () => sends++,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final inputSurfaceFinder = find.ancestor(
      of: find.byType(TextField),
      matching: find.byType(ui.PressableSurface),
    );

    expect(find.text('Sticker 0'), findsNothing);
    expect(find.text('Voice panel'), findsNothing);
    expect(inputSurfaceFinder, findsOneWidget);

    final sendSurfaceFinder = find.ancestor(
      of: find.byIcon(Icons.send_rounded),
      matching: find.byType(ui.PressableSurface),
    );
    expect(sendSurfaceFinder, findsOneWidget);
    final stickerSurfaceFinder = find.ancestor(
      of: find.byIcon(Icons.emoji_emotions_outlined),
      matching: find.byType(ui.PressableSurface),
    );
    expect(stickerSurfaceFinder, findsOneWidget);

    final composerRect = tester.getRect(find.byType(ui.ChatComposer));
    final initialInputRect = tester.getRect(inputSurfaceFinder);
    final stickerRect = tester.getRect(stickerSurfaceFinder);
    final sendRect = tester.getRect(sendSurfaceFinder);
    expect(composerRect.width, closeTo(560, 0.01));
    expect(sendRect.right, closeTo(composerRect.right - 12, 0.01));
    expect(stickerRect.left, closeTo(initialInputRect.right + 10, 0.01));
    expect(
      tester.widget<ui.PressableSurface>(inputSurfaceFinder).height,
      tester.widget<ui.PressableSurface>(sendSurfaceFinder).height,
    );
    expect(
      tester.getSize(inputSurfaceFinder).height,
      tester.getSize(sendSurfaceFinder).height,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).textAlignVertical,
      TextAlignVertical.center,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).mouseCursor,
      SystemMouseCursors.text,
    );
    expect(tester.widget<ui.PressableSurface>(inputSurfaceFinder).hoverLift, 3);
    expect(
      tester.widget<ui.PressableSurface>(inputSurfaceFinder).interactive,
      isTrue,
    );
    expect(
      tester.widget<ui.PressableSurface>(inputSurfaceFinder).mouseCursor,
      SystemMouseCursors.text,
    );
    expect(
      tester.widget<ui.PressableSurface>(inputSurfaceFinder).hoverEffect,
      isTrue,
    );
    expect(
      tester.widget<ui.PressableSurface>(inputSurfaceFinder).pressEffect,
      isFalse,
    );

    final inputMouseRegions = tester
        .widgetList<MouseRegion>(
          find.descendant(
            of: inputSurfaceFinder,
            matching: find.byType(MouseRegion),
          ),
        )
        .where(
          (region) =>
              region.cursor == SystemMouseCursors.text &&
              region.onEnter != null,
        );
    for (final region in inputMouseRegions) {
      region.onEnter?.call(const PointerEnterEvent(position: Offset.zero));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final hoveredInputLayers = tester
        .widgetList<Positioned>(
          find.descendant(
            of: inputSurfaceFinder,
            matching: find.byType(Positioned),
          ),
        )
        .toList();
    expect(hoveredInputLayers, hasLength(2));
    expect(hoveredInputLayers.last.top, closeTo(0, 0.01));

    final inputRect = tester.getRect(inputSurfaceFinder);
    await tester.tapAt(inputRect.topLeft + const Offset(4, 4));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
    );
    expect(tester.widget<ui.PressableSurface>(inputSurfaceFinder).hoverLift, 3);
    expect(
      tester.widget<ui.PressableSurface>(inputSurfaceFinder).hoverEffect,
      isTrue,
    );

    await tester.enterText(find.byType(TextField), 'First line\nSecond line');
    await tester.pumpAndSettle();

    final multilineInputRect = tester.getRect(inputSurfaceFinder);
    final multilineSendRect = tester.getRect(sendSurfaceFinder);
    expect(multilineInputRect.height, greaterThan(multilineSendRect.height));
    expect(multilineInputRect.bottom, closeTo(multilineSendRect.bottom, 0.01));
    expect(multilineInputRect.top, lessThan(multilineSendRect.top));

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Stickers'));
    await tester.pumpAndSettle();

    expect(find.text('Sticker 0'), findsOneWidget);
    expect(find.text('Sticker 8'), findsOneWidget);
    expect(find.text('Voice panel'), findsNothing);
    expect(pageScrollController.offset, 0);
    final stickerScrollerFinder = find.descendant(
      of: find.byType(ui.ChatComposer),
      matching: find.byType(SingleChildScrollView),
    );
    expect(stickerScrollerFinder, findsOneWidget);
    expect(tester.getSize(stickerScrollerFinder).height, closeTo(194, 0.01));
    expect(
      find.descendant(
        of: find.byType(ui.ChatComposer),
        matching: find.byType(Wrap),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ui.ChatComposer),
        matching: find.byType(ListView),
      ),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Voice'));
    await tester.pumpAndSettle();

    expect(find.text('Sticker 0'), findsNothing);
    expect(find.text('Voice panel'), findsOneWidget);

    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(sends, 1);
    expect(find.text('Voice panel'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui kit chat composer list panel shrinks to one row', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 560,
              child: ui.ChatComposer(
                hintText: 'Message',
                actions: [
                  ui.ComposerAction(
                    id: 'stickers',
                    icon: Icons.emoji_emotions_outlined,
                    label: 'Stickers',
                    panel: ui.ComposerPanel.list(
                      itemCount: 3,
                      itemBuilder: (context, index) {
                        return SizedBox(
                          width: 84,
                          height: 76,
                          child: Center(child: Text('Sticker $index')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Stickers'));
    await tester.pumpAndSettle();

    final stickerScrollerFinder = find.descendant(
      of: find.byType(ui.ChatComposer),
      matching: find.byType(SingleChildScrollView),
    );
    expect(stickerScrollerFinder, findsOneWidget);
    expect(tester.getSize(stickerScrollerFinder).height, closeTo(76, 0.01));
    expect(find.text('Sticker 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui kit anchored panel opens above its anchor', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: ui.AnchoredPanelAnchor(
              width: 240,
              anchor: (context, open, toggle) => ui.Button(
                selected: open,
                onPressed: toggle,
                child: const Text('Open'),
              ),
              panel: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Mock panel content'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Mock panel content'), findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(find.text('Mock panel content'), findsOneWidget);

    final anchorRect = tester.getRect(find.widgetWithText(ui.Button, 'Open'));
    final panelRect = tester.getRect(find.byType(ui.AnchoredPanel));

    expect(panelRect.center.dx, closeTo(anchorRect.center.dx, 0.01));
    expect(anchorRect.top - panelRect.bottom, closeTo(8, 0.01));

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();

    expect(find.text('Mock panel content'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui kit anchored panel stays pinned in a scrolled layout', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 360),
                  Row(
                    children: [
                      const Expanded(child: Text('Scrolled layout anchor')),
                      ui.AnchoredPanelAnchor(
                        width: 240,
                        anchor: (context, open, toggle) => ui.Button(
                          selected: open,
                          onPressed: toggle,
                          child: const Text('Scrolled panel'),
                        ),
                        panel: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Scrolled panel content'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 520),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Scrolled panel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scrolled panel'));
    await tester.pump();

    final anchorRect = tester.getRect(
      find.widgetWithText(ui.Button, 'Scrolled panel'),
    );
    final panelRect = tester.getRect(find.byType(ui.AnchoredPanel));

    expect(panelRect.center.dx, closeTo(anchorRect.center.dx, 0.01));
    expect(panelRect.top - anchorRect.bottom, closeTo(8, 0.01));
    expect(panelRect.top, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui kit popover opens above and right-aligned to its anchor', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: ui.PopoverAnchor(
              width: 240,
              anchor: (context, open, toggle) => ui.ButtonIcon(
                tooltip: 'Open popover',
                selected: open,
                onPressed: toggle,
                icon: const Icon(Icons.widgets_outlined),
              ),
              popover: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Mock popover content'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Open popover'));
    await tester.pump();

    final anchorRect = tester.getRect(find.byType(ui.ButtonIcon));
    final popoverRect = tester.getRect(find.byType(ui.PopoverSurface));

    expect(popoverRect.right, closeTo(anchorRect.right, 0.01));
    expect(anchorRect.top - popoverRect.bottom, closeTo(8, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading buttons keep tone colors without tapping', (
    WidgetTester tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ui.Button(
                loading: true,
                tone: ui.ButtonTone.primary,
                height: 40,
                onPressed: () => taps++,
                child: const Text('Loading'),
              ),
              ui.ButtonIcon(
                loading: true,
                tone: ui.ButtonTone.danger,
                onPressed: () => taps++,
                tooltip: 'Call',
                icon: const Icon(Icons.call),
              ),
            ],
          ),
        ),
      ),
    );

    final surfaces = tester.widgetList<ui.PressableSurface>(
      find.byType(ui.PressableSurface),
    );

    expect(
      surfaces.map((surface) => surface.backgroundColor),
      containsAllInOrder([const Color(0xFF1F2D27), const Color(0xFF2E1F22)]),
    );
    expect(
      surfaces.map((surface) => surface.borderColor),
      containsAllInOrder([ui.UiColors.accentBorder, ui.UiColors.dangerBorder]),
    );
    expect(surfaces.map((surface) => surface.enabled), everyElement(isTrue));
    expect(surfaces.map((surface) => surface.onPressed), everyElement(isNull));

    await tester.tap(find.text('Loading'));
    await tester.tap(find.byIcon(Icons.call));

    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('surface shadow depth follows hover lift', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ui.PressableSurface(
              width: 120,
              height: 40,
              hoverLift: 4,
              baseDepth: 8,
              onPressed: () {},
              child: const Text('Surface'),
            ),
          ),
        ),
      ),
    );

    final mouseRegionFinder = find.descendant(
      of: find.byType(ui.PressableSurface),
      matching: find.byType(MouseRegion),
    );
    final mouseRegion = tester.widget<MouseRegion>(mouseRegionFinder);
    mouseRegion.onEnter?.call(const PointerEnterEvent(position: Offset.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final layers = tester
        .widgetList<Positioned>(
          find.descendant(
            of: find.byType(ui.PressableSurface),
            matching: find.byType(Positioned),
          ),
        )
        .toList();

    expect(layers, hasLength(2));
    expect(layers.first.top, closeTo(12, 0.01));
    expect(layers.last.top, closeTo(0, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pressed surface lands at the bottom of the base', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ui.PressableSurface(
              width: 120,
              height: 40,
              hoverLift: 4,
              baseDepth: 8,
              onPressed: () {},
              child: const Text('Surface'),
            ),
          ),
        ),
      ),
    );

    final surfaceFinder = find.byType(ui.PressableSurface);
    final mouseRegion = tester.widget<MouseRegion>(
      find.descendant(of: surfaceFinder, matching: find.byType(MouseRegion)),
    );
    mouseRegion.onEnter?.call(const PointerEnterEvent(position: Offset.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final gesture = await tester.startGesture(tester.getCenter(surfaceFinder));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final layers = tester
        .widgetList<Positioned>(
          find.descendant(of: surfaceFinder, matching: find.byType(Positioned)),
        )
        .toList();

    expect(layers, hasLength(2));
    expect(layers.first.top, closeTo(12, 0.01));
    expect(layers.last.top, closeTo(12, 0.01));
    expect(tester.takeException(), isNull);
    await gesture.up();
  });

  testWidgets('button shadows are derived from background colors', (
    WidgetTester tester,
  ) async {
    const customBackground = Color(0xFF334455);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ui.Button(
                tone: ui.ButtonTone.primary,
                onPressed: () {},
                child: const Text('Primary'),
              ),
              ui.Button(
                tone: ui.ButtonTone.danger,
                onPressed: () {},
                child: const Text('Danger'),
              ),
              ui.PressableSurface(
                height: 40,
                backgroundColor: customBackground,
                onPressed: () {},
                child: const Text('Custom'),
              ),
            ],
          ),
        ),
      ),
    );

    final baseColors = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(ui.PressableSurface),
            matching: find.byType(DecoratedBox),
          ),
        )
        .where((box) => box.decoration is BoxDecoration)
        .map((box) => (box.decoration as BoxDecoration).color);

    expect(
      baseColors,
      containsAllInOrder([
        _expectedShadowForBackground(const Color(0xFF1F2D27)),
        _expectedShadowForBackground(const Color(0xFF2E1F22)),
        _expectedShadowForBackground(customBackground),
      ]),
    );
    expect(tester.takeException(), isNull);
  });

  test('visualizer band levels use overall audio energy', () {
    expect(levelFromVisualizerBandsForTest([0.0, 0.03, null, double.nan]), 0);

    final singleSpike = levelFromVisualizerBandsForTest(<Object?>[
      1.0,
      ...List<double>.filled(13, 0.0),
    ]);
    final broadVoice = levelFromVisualizerBandsForTest(
      List<double>.filled(14, 0.5),
    );

    expect(singleSpike, greaterThan(0));
    expect(singleSpike, lessThan(0.7));
    expect(broadVoice, greaterThan(singleSpike));
    expect(levelFromVisualizerBandsForTest(List<double>.filled(14, 1.0)), 1);
  });

  testWidgets('embedded settings page exposes a close button', (
    WidgetTester tester,
  ) async {
    var closeCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(isSubWindow: true, onClose: () => closeCount += 1),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Close settings'), findsOneWidget);

    await tester.tap(find.byTooltip('Close settings'));
    await tester.pump();

    expect(closeCount, 1);
    expect(tester.takeException(), isNull);
  });
}

Color _expectedShadowForBackground(Color background) {
  return Color.lerp(background, Colors.black, 0.46)!;
}

class _MemoryTokenStore extends TokenStore {
  String? _refreshToken;
  String? _apiBaseUrl;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> writeRefreshToken(String refreshToken) async {
    _refreshToken = refreshToken;
  }

  @override
  Future<void> clearRefreshToken() async {
    _refreshToken = null;
  }

  @override
  Future<String?> readApiBaseUrl() async => _apiBaseUrl;

  @override
  Future<void> writeApiBaseUrl(String baseUrl) async {
    _apiBaseUrl = baseUrl;
  }
}
