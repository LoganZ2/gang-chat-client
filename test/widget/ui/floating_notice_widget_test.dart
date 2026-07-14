import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('floating notices work in MaterialApp builder without Overlay', (
    tester,
  ) async {
    await tester.pumpWidget(_productionHost(const _SingleNoticeButton()));

    await tester.tap(find.text('Show notice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('builder notice'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating notices keep newest three and close immediately', (
    tester,
  ) async {
    await tester.pumpWidget(_productionHost(const _NoticeButtons()));

    for (final label in ['one', 'two', 'three', 'four']) {
      await tester.tap(find.text('Show $label'));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('notice one'), findsNothing);
    expect(find.text('notice two'), findsOneWidget);
    expect(find.text('notice three'), findsOneWidget);
    expect(find.text('notice four'), findsOneWidget);

    final fourTop = tester.getTopLeft(find.text('notice four')).dy;
    final threeTop = tester.getTopLeft(find.text('notice three')).dy;
    final twoTop = tester.getTopLeft(find.text('notice two')).dy;
    expect(fourTop, lessThan(threeTop));
    expect(threeTop, lessThan(twoTop));

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();

    expect(find.text('notice four'), findsNothing);
    expect(find.text('notice three'), findsOneWidget);
    expect(find.text('notice two'), findsOneWidget);
  });

  testWidgets('same notice message can be shown as a new event', (
    tester,
  ) async {
    await tester.pumpWidget(_productionHost(const _RepeatNoticeButton()));

    await tester.tap(find.text('Repeat notice'));
    await tester.pump();
    await tester.tap(find.text('Repeat notice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('repeat notice'), findsNWidgets(2));
    final noticeTops = tester
        .widgetList<Text>(find.text('repeat notice'))
        .map((widget) => widget.data)
        .toList();
    expect(noticeTops, hasLength(2));
  });

  testWidgets('auto notices fade out after visible duration', (tester) async {
    await tester.pumpWidget(_productionHost(const _AutoNoticeButton()));

    await tester.tap(find.text('Show auto'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('auto notice'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('auto notice'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('auto notice'), findsNothing);
  });

  testWidgets('persistent notices do not auto dismiss', (tester) async {
    await tester.pumpWidget(_productionHost(const _PersistentNoticeButton()));

    await tester.tap(find.text('Show persistent'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('persistent notice'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('persistent notice'), findsNothing);
  });

  testWidgets('notice emitter only emits fresh notices', (tester) async {
    await tester.pumpWidget(_productionHost(const _EmitterHarness()));

    await tester.tap(find.text('Emit same'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('same notice'), findsOneWidget);

    await tester.tap(find.text('Emit same'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('same notice'), findsNWidgets(2));

    await tester.tap(find.text('Emit next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('same notice'), findsNWidgets(2));
    expect(find.text('next notice'), findsOneWidget);
  });

  testWidgets('standalone overlay fallback still works without host', (
    tester,
  ) async {
    await tester.pumpWidget(_overlayFallbackHost(const _SingleNoticeButton()));

    await tester.tap(find.text('Show notice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('builder notice'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('builder notice'), findsNothing);
  });

  testWidgets('floating notice does not relayout or block page controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_productionHost(const _PageInteractionHarness()));
    final pageButton = find.byKey(const ValueKey('page-control'));
    final searchBox = find.byKey(const ValueKey('top-search-box'));
    final before = tester.getRect(pageButton);
    final searchRect = tester.getRect(searchBox);

    await tester.tap(find.text('Show floating'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(tester.getRect(pageButton), before);
    expect(
      tester.getTopLeft(find.text('small notice')).dy,
      greaterThan(searchRect.bottom),
    );
    expect(find.text('page taps: 0'), findsOneWidget);

    await tester.tap(pageButton);
    await tester.pump();

    expect(find.text('page taps: 1'), findsOneWidget);
    expect(find.text('small notice'), findsOneWidget);
  });

  testWidgets('floating notice matches app text and close button styling', (
    tester,
  ) async {
    await tester.pumpWidget(_productionHost(const _StyleNoticeButton()));

    await tester.tap(find.text('Show style'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final message = tester.widget<Text>(find.text('style notice'));
    expect(message.style?.fontSize, ui.UiTypography.label.fontSize);
    expect(message.style?.height, ui.UiTypography.label.height);
    expect(message.style?.fontWeight, FontWeight.w500);
    expect(message.style?.color, ui.UiColors.text);
    expect(message.style?.fontFamily, ui.kClientFontFamily);
    expect(message.style?.fontFamilyFallback, ui.kClientFontFamilyFallback);
    expect(message.style?.decoration, TextDecoration.none);

    final closeIcon = tester.widget<Icon>(find.byIcon(Icons.close));
    expect(closeIcon.size, 15);
    expect(closeIcon.color, ui.UiColors.textMuted);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('floating-notice-close-button')),
      ),
      const Size(26, 26),
    );

    final messageCenter = tester.getCenter(find.text('style notice')).dy;
    final closeCenter = tester.getCenter(find.byIcon(Icons.close)).dy;
    expect(messageCenter, closeTo(closeCenter, 2));
  });
}

Widget _productionHost(Widget child) {
  return MaterialApp(
    theme: ui.uiTheme(),
    builder: (context, materialChild) =>
        ui.AppNotificationHost(child: materialChild ?? const SizedBox.shrink()),
    home: Scaffold(body: child),
  );
}

Widget _overlayFallbackHost(Widget child) {
  return MaterialApp(
    theme: ui.uiTheme(),
    home: Scaffold(body: child),
  );
}

class _SingleNoticeButton extends StatelessWidget {
  const _SingleNoticeButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () =>
            ui.showFloatingNotice(context, 'builder notice', duration: null),
        child: const Text('Show notice'),
      ),
    );
  }
}

class _NoticeButtons extends StatelessWidget {
  const _NoticeButtons();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        children: [
          for (final label in ['one', 'two', 'three', 'four'])
            TextButton(
              onPressed: () => ui.showFloatingNotice(
                context,
                'notice $label',
                duration: null,
              ),
              child: Text('Show $label'),
            ),
        ],
      ),
    );
  }
}

class _AutoNoticeButton extends StatelessWidget {
  const _AutoNoticeButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => ui.showFloatingNotice(
          context,
          'auto notice',
          duration: const Duration(milliseconds: 100),
        ),
        child: const Text('Show auto'),
      ),
    );
  }
}

class _RepeatNoticeButton extends StatelessWidget {
  const _RepeatNoticeButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () =>
            ui.showFloatingNotice(context, 'repeat notice', duration: null),
        child: const Text('Repeat notice'),
      ),
    );
  }
}

class _PersistentNoticeButton extends StatelessWidget {
  const _PersistentNoticeButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => ui.showFloatingNotice(
          context,
          'persistent notice',
          tone: ui.FloatingNoticeTone.error,
          duration: null,
        ),
        child: const Text('Show persistent'),
      ),
    );
  }
}

class _StyleNoticeButton extends StatelessWidget {
  const _StyleNoticeButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () =>
            ui.showFloatingNotice(context, 'style notice', duration: null),
        child: const Text('Show style'),
      ),
    );
  }
}

class _EmitterHarness extends StatefulWidget {
  const _EmitterHarness();

  @override
  State<_EmitterHarness> createState() => _EmitterHarnessState();
}

class _EmitterHarnessState extends State<_EmitterHarness> {
  String? _message;
  int _eventKey = 0;

  @override
  Widget build(BuildContext context) {
    return ui.FloatingNoticeEmitter(
      notices: [
        if (_message != null)
          ui.FloatingNotice(
            message: _message!,
            duration: null,
            eventKey: _eventKey,
          ),
      ],
      child: Center(
        child: Wrap(
          children: [
            TextButton(
              onPressed: () => setState(() {
                _message = 'same notice';
                _eventKey++;
              }),
              child: const Text('Emit same'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _message = 'next notice';
                _eventKey++;
              }),
              child: const Text('Emit next'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageInteractionHarness extends StatefulWidget {
  const _PageInteractionHarness();

  @override
  State<_PageInteractionHarness> createState() =>
      _PageInteractionHarnessState();
}

class _PageInteractionHarnessState extends State<_PageInteractionHarness> {
  int _pageTaps = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 260,
          top: 7,
          child: Container(
            key: const ValueKey('top-search-box'),
            width: 280,
            height: 30,
            decoration: BoxDecoration(
              color: ui.UiColors.surface,
              borderRadius: BorderRadius.circular(ui.UiRadii.md),
              border: Border.all(color: ui.UiColors.border),
            ),
          ),
        ),
        Positioned(
          left: 16,
          top: 18,
          child: TextButton(
            key: const ValueKey('page-control'),
            onPressed: () => setState(() => _pageTaps++),
            child: Text('page taps: $_pageTaps'),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: TextButton(
            onPressed: () =>
                ui.showFloatingNotice(context, 'small notice', duration: null),
            child: const Text('Show floating'),
          ),
        ),
      ],
    );
  }
}
