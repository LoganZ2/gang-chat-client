import 'dart:convert';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerEnterEvent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:client/main.dart';
import 'package:client/src/app/authenticated_app_context.dart';
import 'package:client/src/auth/auth_client.dart';
import 'package:client/src/auth/token_store.dart';
import 'package:client/src/protocol/api_client.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/settings/settings_page.dart';
import 'package:client/src/ui/ui.dart' as ui;
import 'package:client/src/v2/home_page.dart' as current_home;
import 'package:client/ui_showcase.dart' as showcase;

void main() {
  test('v2 startup argument is recognized', () {
    expect(shouldUseV2(['v2']), isTrue);
    expect(shouldUseV2(['--v2']), isTrue);
    expect(shouldUseV2(['V2']), isTrue);
    expect(shouldUseV2(['--other']), isFalse);
  });

  testWidgets('v2 app renders login entrypoint on real auth gate', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      GangApp(tokenStore: _MemoryTokenStore(), useV2: true),
    );
    await tester.pump();

    expect(find.text('Gang Chat'), findsOneWidget);
    expect(find.text('Username or email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, 'Login'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsOneWidget);

    final authSurfaceRect = tester.getRect(
      find.byKey(const ValueKey('auth-surface')),
    );
    final modeSwitchRect = tester.getRect(
      find.byWidgetPredicate((widget) => widget is ui.SegmentedControl),
    );
    final titleRect = tester.getRect(find.text('Gang Chat'));
    expect(titleRect.height, lessThanOrEqualTo(16));
    expect(
      tester
          .widgetList<MouseRegion>(
            find.ancestor(
              of: find.text('Gang Chat'),
              matching: find.byType(MouseRegion),
            ),
          )
          .map((region) => region.cursor),
      contains(SystemMouseCursors.basic),
    );
    expect(modeSwitchRect.top - authSurfaceRect.top, closeTo(36, 0.01));
    _expectSubmitButtonFullWidth(tester, submitLabel: 'Login');
    expect(find.text('Enter your credentials to continue.'), findsNothing);
    final normalSurfaceHeight = tester
        .getSize(find.byKey(const ValueKey('auth-surface')))
        .height;
    final normalBottomGap = _submitBottomGap(tester, submitLabel: 'Login');

    await tester.tap(find.widgetWithText(ui.Button, 'Login'));
    await tester.pump();

    expect(find.text('Enter your credentials to continue.'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('auth-surface'))).height,
      closeTo(normalSurfaceHeight + 20, 0.01),
    );
    expect(
      _submitBottomGap(tester, submitLabel: 'Login'),
      closeTo(normalBottomGap, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('v2 register mode exposes full auth form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      GangApp(tokenStore: _MemoryTokenStore(), useV2: true),
    );
    await tester.pump();

    final loginGap = _authActionGap(tester, submitLabel: 'Login');
    final loginBottomGap = _submitBottomGap(tester, submitLabel: 'Login');

    await tester.tap(find.text('Register'));
    await tester.pump();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsNWidgets(2));
    expect(find.widgetWithText(ui.Button, 'Create account'), findsOneWidget);
    expect(
      _authActionGap(tester, submitLabel: 'Create account'),
      closeTo(loginGap, 0.01),
    );
    expect(
      _submitBottomGap(tester, submitLabel: 'Create account'),
      closeTo(loginBottomGap, 0.01),
    );
    _expectSubmitButtonFullWidth(tester, submitLabel: 'Create account');
    expect(find.text('Enter your credentials to continue.'), findsNothing);
    final normalSurfaceHeight = tester
        .getSize(find.byKey(const ValueKey('auth-surface')))
        .height;

    await tester.tap(find.byTooltip('Show password').first);
    await tester.pump();

    expect(find.byTooltip('Hide password'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.widgetWithText(ui.Button, 'Create account'));
    await tester.pump();

    expect(find.text('Enter your credentials to continue.'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('auth-surface'))).height,
      closeTo(normalSurfaceHeight + 20, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated home shell renders server-only sidebar', (
    WidgetTester tester,
  ) async {
    final requestedPaths = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: current_home.HomePage(
          app: _homeTestAppContext(requestedPaths: requestedPaths),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/rooms'));
    expect(find.byType(ui.Sidebar), findsNothing);
    expect(find.text('Gang Chat'), findsNothing);
    expect(find.text('Workspace'), findsNothing);
    expect(find.text('Tools'), findsNothing);
    expect(find.text('Rooms'), findsNothing);
    expect(find.text('Activity'), findsNothing);
    expect(find.text('People'), findsNothing);
    expect(find.text('Files'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Kai'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('@kai'), findsNothing);
    expect(find.text('Alpha Room'), findsOneWidget);
    expect(find.text('Beta Room'), findsOneWidget);
    expect(find.text('2 members · 1 live'), findsOneWidget);
    expect(find.text('5 members'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    final userSummaryRect = tester.getRect(
      find.byKey(const ValueKey('home-sidebar-user-summary')),
    );
    final alphaCardRect = tester.getRect(
      find.ancestor(
        of: find.text('Alpha Room'),
        matching: find.byType(ui.PressableSurface),
      ),
    );
    expect(userSummaryRect.right - alphaCardRect.right, closeTo(0, 0.01));

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ui.PressableSurface>(
            find.ancestor(
              of: find.text('Alpha Room'),
              matching: find.byType(ui.PressableSurface),
            ),
          )
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'authenticated home shell reserves gutter only when list scrolls',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: Center(
            child: SizedBox(
              width: 420,
              height: 190,
              child: current_home.HomePage(app: _homeTestAppContext()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final userSummaryRect = tester.getRect(
        find.byKey(const ValueKey('home-sidebar-user-summary')),
      );
      final alphaCardRect = tester.getRect(
        find.ancestor(
          of: find.text('Alpha Room'),
          matching: find.byType(ui.PressableSurface),
        ),
      );

      expect(userSummaryRect.right - alphaCardRect.right, closeTo(15, 0.01));
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('authenticated home shell offsets macOS sidebar content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme().copyWith(platform: TargetPlatform.macOS),
        home: current_home.HomePage(app: _homeTestAppContext()),
      ),
    );
    await tester.pumpAndSettle();

    final userSummaryRect = tester.getRect(
      find.byKey(const ValueKey('home-sidebar-user-summary')),
    );

    expect(userSummaryRect.top, closeTo(34, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'authenticated home shell opens blank content from narrow server list',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: Center(
            child: SizedBox(
              width: 420,
              height: 620,
              child: current_home.HomePage(app: _homeTestAppContext()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alpha Room'), findsOneWidget);
      expect(find.byTooltip('Show servers'), findsNothing);

      await tester.tap(find.text('Alpha Room'));
      await tester.pumpAndSettle();

      expect(find.text('Beta Room'), findsNothing);
      expect(find.byTooltip('Show servers'), findsOneWidget);
      expect(find.text('Alpha Room'), findsOneWidget);

      await tester.tap(find.byTooltip('Show servers'));
      await tester.pumpAndSettle();

      expect(find.text('Beta Room'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('auth login layout is identical with and without v2 flag', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(GangApp(tokenStore: _MemoryTokenStore()));
    await tester.pump();

    final regularSurfaceRect = tester.getRect(
      find.byKey(const ValueKey('auth-surface')),
    );
    final regularModeSwitchRect = tester.getRect(
      find.byWidgetPredicate((widget) => widget is ui.SegmentedControl),
    );
    final regularInputRect = tester.getRect(find.byType(ui.Input).first);
    final regularSubmitRect = tester.getRect(
      find.widgetWithText(ui.Button, 'Login'),
    );
    final regularCursorColor = Theme.of(
      tester.element(find.byKey(const ValueKey('auth-surface'))),
    ).textSelectionTheme.cursorColor;

    await tester.pumpWidget(
      GangApp(tokenStore: _MemoryTokenStore(), useV2: true),
    );
    await tester.pump();

    _expectRectCloseTo(
      tester.getRect(find.byKey(const ValueKey('auth-surface'))),
      regularSurfaceRect,
    );
    _expectRectCloseTo(
      tester.getRect(
        find.byWidgetPredicate((widget) => widget is ui.SegmentedControl),
      ),
      regularModeSwitchRect,
    );
    _expectRectCloseTo(
      tester.getRect(find.byType(ui.Input).first),
      regularInputRect,
    );
    _expectRectCloseTo(
      tester.getRect(find.widgetWithText(ui.Button, 'Login')),
      regularSubmitRect,
    );
    expect(
      Theme.of(
        tester.element(find.byKey(const ValueKey('auth-surface'))),
      ).textSelectionTheme.cursorColor,
      regularCursorColor,
    );
    expect(tester.takeException(), isNull);
  });

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
    final segmentOffsets = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(ui.SegmentedControl<String>),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((container) => container.transform?.storage[13])
        .toList();
    expect(segmentOffsets, [closeTo(-2, 0.01), closeTo(3, 0.01)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui navigation tabs expose reusable segmented navigation', (
    WidgetTester tester,
  ) async {
    var selected = 'chat';

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ui.NavigationTabs<String>(
                value: selected,
                onChanged: (value) => setState(() => selected = value),
                items: const [
                  ui.NavigationItem(
                    value: 'chat',
                    label: 'Chat',
                    icon: Icons.chat_bubble_outline,
                  ),
                  ui.NavigationItem(
                    value: 'forms',
                    label: 'Forms',
                    icon: Icons.tune,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(find.byType(ui.SegmentedControl<String>), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Forms'), findsOneWidget);

    await tester.tap(find.text('Forms'));
    await tester.pumpAndSettle();

    expect(selected, 'forms');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui sidebar renders groups and changes selection', (
    WidgetTester tester,
  ) async {
    var selected = 'overview';

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                height: 320,
                child: ui.Sidebar(
                  width: 220,
                  selectedId: selected,
                  onItemSelected: (value) => setState(() => selected = value),
                  header: const Text(
                    'Navigation',
                    style: ui.UiTypography.title,
                  ),
                  footer: const Text('Footer', style: ui.UiTypography.label),
                  groups: const [
                    ui.SidebarGroup(
                      label: 'Workspace',
                      items: [
                        ui.SidebarItem(
                          id: 'overview',
                          label: 'Overview',
                          icon: Icons.space_dashboard_outlined,
                          badge: '4',
                        ),
                        ui.SidebarItem(
                          id: 'threads',
                          label: 'Threads',
                          icon: Icons.forum_outlined,
                        ),
                        ui.SidebarItem(
                          id: 'archive',
                          label: 'Archive',
                          icon: Icons.inventory_2_outlined,
                          enabled: false,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(ui.Sidebar)).width, 220);
    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Footer'), findsOneWidget);
    expect(
      tester
          .widget<ui.PressableSurface>(
            find.ancestor(
              of: find.text('Overview'),
              matching: find.byType(ui.PressableSurface),
            ),
          )
          .selected,
      isTrue,
    );

    await tester.tap(find.text('Threads'));
    await tester.pump();

    expect(selected, 'threads');
    expect(
      tester
          .widget<ui.PressableSurface>(
            find.ancestor(
              of: find.text('Threads'),
              matching: find.byType(ui.PressableSurface),
            ),
          )
          .selected,
      isTrue,
    );

    await tester.tap(find.text('Archive'));
    await tester.pump();

    expect(selected, 'threads');
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui showcase narrow layout enters content from sidebar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Center(
          child: SizedBox(
            width: 420,
            height: 760,
            child: showcase.UiShowcasePage(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ui.Sidebar), findsOneWidget);
    expect(find.text('Sections'), findsOneWidget);
    expect(find.text('Buttons'), findsNothing);
    expect(find.byTooltip('Show sections'), findsNothing);

    await tester.tap(find.text('Forms'));
    await tester.pump();

    expect(find.byType(ui.Sidebar), findsNothing);
    expect(find.byTooltip('Show sections'), findsOneWidget);
    expect(find.text('Fields'), findsOneWidget);

    await tester.tap(find.byTooltip('Show sections'));
    await tester.pump();

    expect(find.byType(ui.Sidebar), findsOneWidget);
    expect(find.text('Fields'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui input focuses from padding and grows upward', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 120,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 280,
                  child: ui.Input(
                    controller: controller,
                    focusNode: focusNode,
                    hintText: 'Type here',
                    prefixIcon: Icons.person_outline,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final inputFinder = find.byType(ui.Input);
    final textFieldFinder = find.byType(TextField);
    expect(find.byType(ui.Input), findsOneWidget);
    expect(textFieldFinder, findsOneWidget);
    expect(
      find.descendant(
        of: inputFinder,
        matching: find.byType(ui.PressableSurface),
      ),
      findsNothing,
    );
    expect(
      tester.widget<TextField>(textFieldFinder).mouseCursor,
      SystemMouseCursors.text,
    );
    final textFieldPadding =
        tester.widget<TextField>(textFieldFinder).decoration?.contentPadding
            as EdgeInsets;
    expect(textFieldPadding.top, greaterThan(textFieldPadding.bottom));
    expect(textFieldPadding.top - textFieldPadding.bottom, closeTo(8, 0.01));
    expect(
      tester
          .widgetList<Transform>(
            find.ancestor(
              of: find.byIcon(Icons.person_outline),
              matching: find.byType(Transform),
            ),
          )
          .map((transform) => transform.transform.storage[13]),
      contains(closeTo(5, 0.01)),
    );

    final initialRect = tester.getRect(inputFinder);
    await tester.tapAt(initialRect.topLeft + const Offset(4, 6));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);

    focusNode.unfocus();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);

    final paddingPoints = [
      Offset(initialRect.center.dx, initialRect.top + 6),
      Offset(initialRect.center.dx, initialRect.bottom - 14),
      Offset(initialRect.center.dx, initialRect.top + 6),
      Offset(initialRect.right - 4, initialRect.top + 6),
      Offset(initialRect.right - 4, initialRect.center.dy),
      Offset(initialRect.right - 4, initialRect.bottom - 14),
    ];
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 99,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    for (final point in paddingPoints) {
      await mouse.moveTo(point);
      await tester.pump();
      await mouse.down(point);
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);

      await mouse.up();
      await tester.pump();
      await mouse.down(point);
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);

      await mouse.up();
      await tester.pump();
    }

    await tester.enterText(find.byType(TextField), 'First line\nSecond line');
    await tester.pumpAndSettle();

    final multilineRect = tester.getRect(inputFinder);
    expect(multilineRect.height, greaterThan(initialRect.height));
    expect(multilineRect.bottom, closeTo(initialRect.bottom, 0.01));
    expect(multilineRect.top, lessThan(initialRect.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ui input hover animates without changing colors', (
    WidgetTester tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: ui.Input(focusNode: focusNode, hintText: 'Type here'),
            ),
          ),
        ),
      ),
    );

    final inputFinder = find.byType(ui.Input);
    final animatedCapFinder = find.descendant(
      of: inputFinder,
      matching: find.byType(AnimatedPositioned),
    );
    expect(animatedCapFinder, findsOneWidget);
    final animatedCap = tester.widget<AnimatedPositioned>(animatedCapFinder);
    expect(animatedCap.duration, const Duration(milliseconds: 95));
    expect(animatedCap.curve, Curves.easeOutCubic);
    expect(animatedCap.top, closeTo(3, 0.01));

    var inputDecorations = _inputLayerDecorations(tester, inputFinder);
    expect(inputDecorations, hasLength(2));
    expect(_topBorderColor(inputDecorations.first), ui.UiColors.border);
    expect(_topBorderColor(inputDecorations.last), ui.UiColors.border);
    expect(inputDecorations.last.color, ui.UiColors.surface);

    var inputRect = tester.getRect(inputFinder);
    await tester.tapAt(inputRect.center);
    await tester.pumpAndSettle();

    expect(focusNode.hasFocus, isTrue);
    expect(
      tester.widget<AnimatedPositioned>(animatedCapFinder).top,
      closeTo(3, 0.01),
    );
    inputDecorations = _inputLayerDecorations(tester, inputFinder);
    expect(_topBorderColor(inputDecorations.first), ui.UiColors.accentBorder);
    expect(_topBorderColor(inputDecorations.last), ui.UiColors.accentBorder);
    expect(inputDecorations.last.color, ui.UiColors.selected);

    focusNode.unfocus();
    await tester.pumpAndSettle();

    expect(
      tester.widget<AnimatedPositioned>(animatedCapFinder).top,
      closeTo(3, 0.01),
    );
    inputDecorations = _inputLayerDecorations(tester, inputFinder);
    expect(_topBorderColor(inputDecorations.first), ui.UiColors.border);
    expect(_topBorderColor(inputDecorations.last), ui.UiColors.border);
    expect(inputDecorations.last.color, ui.UiColors.surface);

    final hoverRegions = tester
        .widgetList<MouseRegion>(
          find.descendant(of: inputFinder, matching: find.byType(MouseRegion)),
        )
        .where((region) => region.onEnter != null);
    for (final region in hoverRegions) {
      region.onEnter?.call(const PointerEnterEvent(position: Offset.zero));
    }

    await tester.pump();

    var positionedLayers = tester
        .widgetList<Positioned>(
          find.descendant(of: inputFinder, matching: find.byType(Positioned)),
        )
        .toList();
    expect(positionedLayers, hasLength(2));
    expect(positionedLayers.last.top, closeTo(3, 0.01));
    expect(
      tester.widget<AnimatedPositioned>(animatedCapFinder).top,
      closeTo(0, 0.01),
    );

    inputDecorations = _inputLayerDecorations(tester, inputFinder);
    expect(_topBorderColor(inputDecorations.first), ui.UiColors.border);
    expect(_topBorderColor(inputDecorations.last), ui.UiColors.border);
    expect(inputDecorations.last.color, ui.UiColors.surface);

    await tester.pump(const Duration(milliseconds: 20));
    positionedLayers = tester
        .widgetList<Positioned>(
          find.descendant(of: inputFinder, matching: find.byType(Positioned)),
        )
        .toList();
    expect(positionedLayers.last.top, lessThan(3));
    expect(positionedLayers.last.top, greaterThan(0));

    await tester.pumpAndSettle();
    positionedLayers = tester
        .widgetList<Positioned>(
          find.descendant(of: inputFinder, matching: find.byType(Positioned)),
        )
        .toList();
    expect(positionedLayers.last.top, closeTo(0, 0.01));

    inputRect = tester.getRect(inputFinder);
    await tester.tapAt(inputRect.center);
    await tester.pumpAndSettle();

    expect(focusNode.hasFocus, isTrue);
    inputDecorations = _inputLayerDecorations(tester, inputFinder);
    expect(_topBorderColor(inputDecorations.first), ui.UiColors.accentBorder);
    expect(_topBorderColor(inputDecorations.last), ui.UiColors.accentBorder);
    expect(inputDecorations.last.color, ui.UiColors.selected);
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

  testWidgets('ui button activates after pointer moves inside bounds', (
    WidgetTester tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: ui.Button(
                width: double.infinity,
                onPressed: () => taps++,
                child: const Text('Select'),
              ),
            ),
          ),
        ),
      ),
    );

    final surfaceFinder = find.descendant(
      of: find.widgetWithText(ui.Button, 'Select'),
      matching: find.byType(ui.PressableSurface),
    );
    final rect = tester.getRect(surfaceFinder);
    final gesture = await tester.startGesture(
      rect.center,
      kind: PointerDeviceKind.mouse,
    );

    await tester.pump();
    await gesture.moveTo(rect.center + const Offset(34, 7));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(taps, 1);
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

    final inputFinder = find.byType(ui.Input);

    expect(find.text('Sticker 0'), findsNothing);
    expect(find.text('Voice panel'), findsNothing);
    expect(inputFinder, findsOneWidget);
    expect(
      find.descendant(
        of: inputFinder,
        matching: find.byType(ui.PressableSurface),
      ),
      findsNothing,
    );

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
    final initialInputRect = tester.getRect(inputFinder);
    final stickerRect = tester.getRect(stickerSurfaceFinder);
    final sendRect = tester.getRect(sendSurfaceFinder);
    expect(composerRect.width, closeTo(560, 0.01));
    expect(sendRect.right, closeTo(composerRect.right - 12, 0.01));
    expect(stickerRect.left, closeTo(initialInputRect.right + 10, 0.01));
    expect(
      ui.Input.defaultHeight,
      tester.widget<ui.PressableSurface>(sendSurfaceFinder).height,
    );
    expect(
      tester.getSize(inputFinder).height,
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

    final inputMouseRegions = tester
        .widgetList<MouseRegion>(
          find.descendant(of: inputFinder, matching: find.byType(MouseRegion)),
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
          find.descendant(of: inputFinder, matching: find.byType(Positioned)),
        )
        .toList();
    expect(hoveredInputLayers, hasLength(2));
    expect(hoveredInputLayers.last.top, closeTo(0, 0.01));

    final inputRect = tester.getRect(inputFinder);
    await tester.tapAt(inputRect.topLeft + const Offset(4, 4));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
    );

    await tester.enterText(find.byType(TextField), 'First line\nSecond line');
    await tester.pumpAndSettle();

    final multilineInputRect = tester.getRect(inputFinder);
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

List<BoxDecoration> _inputLayerDecorations(
  WidgetTester tester,
  Finder inputFinder,
) {
  return tester
      .widgetList<DecoratedBox>(
        find.descendant(of: inputFinder, matching: find.byType(DecoratedBox)),
      )
      .where((box) {
        final decoration = box.decoration;
        return decoration is BoxDecoration && decoration.border is Border;
      })
      .map((box) => box.decoration as BoxDecoration)
      .toList();
}

Color _topBorderColor(BoxDecoration decoration) {
  return (decoration.border as Border).top.color;
}

void _expectRectCloseTo(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 0.01));
  expect(actual.top, closeTo(expected.top, 0.01));
  expect(actual.right, closeTo(expected.right, 0.01));
  expect(actual.bottom, closeTo(expected.bottom, 0.01));
}

double _authActionGap(WidgetTester tester, {required String submitLabel}) {
  final lastInputRect = tester.getRect(find.byType(ui.Input).last);
  final submitRect = tester.getRect(
    find.widgetWithText(ui.Button, submitLabel),
  );
  return submitRect.top - lastInputRect.bottom;
}

double _submitBottomGap(WidgetTester tester, {required String submitLabel}) {
  final surfaceRect = tester.getRect(
    find.byKey(const ValueKey('auth-surface')),
  );
  final submitRect = tester.getRect(
    find.widgetWithText(ui.Button, submitLabel),
  );
  return surfaceRect.bottom - submitRect.bottom;
}

void _expectSubmitButtonFullWidth(
  WidgetTester tester, {
  required String submitLabel,
}) {
  final inputRect = tester.getRect(find.byType(ui.Input).first);
  final submitRect = tester.getRect(
    find.widgetWithText(ui.Button, submitLabel),
  );
  expect(submitRect.left, closeTo(inputRect.left, 0.01));
  expect(submitRect.right, closeTo(inputRect.right, 0.01));
}

AuthenticatedAppContext _homeTestAppContext({
  Future<void> Function()? onLogout,
  List<String>? requestedPaths,
}) {
  final user = CurrentUser(
    id: 'user-1',
    uid: 'uid-1',
    username: 'kai',
    displayName: 'Kai',
    bio: '',
    gender: 'secret',
    email: 'kai@example.com',
    emailPublic: false,
    phoneNumber: null,
    phoneNumberPublic: false,
    avatarUrl: null,
    defaultAvatarKey: 'blue-3',
    isSuperuser: false,
    createdAt: DateTime.utc(2026),
  );

  return AuthenticatedAppContext(
    session: AuthSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      accessTokenExpiresAt: DateTime.utc(2026, 1, 1, 1),
      user: user,
    ),
    apiBaseUrl: 'http://localhost:3000',
    accessTokenProvider: ({bool forceRefresh = false}) async => 'access-token',
    logout: onLogout ?? () async {},
    api: _roomsApi(requestedPaths: requestedPaths),
  );
}

GangApi _roomsApi({List<String>? requestedPaths}) {
  return GangApiClient(
    baseUrl: 'http://example.test/api/v1',
    accessTokenProvider: ({bool forceRefresh = false}) async => 'access-token',
    httpClient: MockClient((request) async {
      requestedPaths?.add(request.url.path);
      if (request.url.path == '/api/v1/rooms') {
        return _jsonResponse({'rooms': _serverListJson});
      }
      return http.Response('unexpected request: ${request.url}', 404);
    }),
  );
}

http.Response _jsonResponse(Object body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

final _serverListJson = [
  _roomCardJson(
    id: 'server-alpha',
    name: 'Alpha Room',
    memberCount: 2,
    liveParticipantCount: 1,
    unreadCount: 3,
  ),
  _roomCardJson(id: 'server-beta', name: 'Beta Room', memberCount: 5),
];

Map<String, Object?> _roomCardJson({
  required String id,
  required String name,
  int memberCount = 1,
  int liveParticipantCount = 0,
  int unreadCount = 0,
}) {
  return {
    'id': id,
    'name': name,
    'rid': id,
    'visibility': 'private',
    'description': '',
    'notification_policy': 'all',
    'avatar_url': null,
    'default_avatar_key': 'room-1',
    'member_count': memberCount,
    'live_participant_count': liveParticipantCount,
    'live_avatar_preview': <Object?>[],
    'last_message': null,
    'unread_count': unreadCount,
    'updated_at': '2026-06-05T00:00:00Z',
  };
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
