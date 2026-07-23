import 'package:client/src/ui/ui.dart' as ui;
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
            semanticLabel: '228 ms',
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
