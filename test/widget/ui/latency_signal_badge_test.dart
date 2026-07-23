import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('latency signal lights the requested bars', (tester) async {
    await _pumpBadge(tester);

    expect(_barColor(tester, 1), ui.UiColors.presenceReconnecting);
    expect(_barColor(tester, 2), ui.UiColors.presenceReconnecting);
    expect(_barColor(tester, 3), const Color(0xFF8A93A3));
    expect(_barDecoration(tester, 1).border, isNull);
  });

  testWidgets('latency tooltip uses Material Tooltip and pins on touch tap', (
    tester,
  ) async {
    await _pumpBadge(tester);

    expect(find.byType(Tooltip), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('latency-signal-badge')));
    await tester.pumpAndSettle();

    expect(find.text('228 ms'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('228 ms'), findsNothing);
  });

  testWidgets('mouse hover can be pinned after leaving the latency signal', (
    tester,
  ) async {
    await _pumpBadge(tester);

    final badge = find.byKey(const ValueKey('latency-signal-badge'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(badge));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('228 ms'), findsOneWidget);

    await tester.tap(badge, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('228 ms'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('228 ms'), findsNothing);
  });
}

Future<void> _pumpBadge(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ui.uiTheme(),
      home: const Scaffold(
        body: Center(
          child: ui.LatencySignalBadge(
            activeBars: 2,
            activeColor: ui.UiColors.presenceReconnecting,
            tooltip: '228 ms',
          ),
        ),
      ),
    ),
  );
}

Color? _barColor(WidgetTester tester, int index) {
  return _barDecoration(tester, index).color;
}

BoxDecoration _barDecoration(WidgetTester tester, int index) {
  final bar = tester.widget<DecoratedBox>(
    find.byKey(ValueKey('latency-signal-bar-$index')),
  );
  return bar.decoration as BoxDecoration;
}
