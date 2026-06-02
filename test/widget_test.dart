import 'package:flutter/gestures.dart' show PointerEnterEvent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/main.dart';
import 'package:client/src/auth/token_store.dart';
import 'package:client/src/settings/settings_page.dart';
import 'package:client/src/ui/key_button.dart';

void main() {
  testWidgets('app renders auth entrypoint', (WidgetTester tester) async {
    await tester.pumpWidget(GangApp(tokenStore: _MemoryTokenStore()));
    await tester.pump();

    expect(find.text('Gang Chat'), findsAtLeastNWidgets(1));
    expect(find.text('Username or email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(find.widgetWithText(KeyButton, 'Login'), findsOneWidget);
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
    expect(find.widgetWithText(KeyButton, 'Create account'), findsOneWidget);

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

    await tester.tap(find.widgetWithText(KeyButton, 'Login'));
    await tester.pump();

    expect(find.text('Enter your credentials to continue.'), findsOneWidget);
  });

  testWidgets('key button lays out with automatic width in a row', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [KeyButton(onPressed: () {}, child: const Text('Send'))],
          ),
        ),
      ),
    );

    expect(find.text('Send'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full-width key button uses finite parent width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: KeyButton(
                width: double.infinity,
                onPressed: () {},
                child: const Text('Create'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(KeyButton)).width, 240);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading key buttons keep tone colors without tapping', (
    WidgetTester tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              KeyButton(
                loading: true,
                tone: KeyButtonTone.primary,
                height: 40,
                onPressed: () => taps++,
                child: const Text('Loading'),
              ),
              KeyIconButton(
                loading: true,
                tone: KeyButtonTone.danger,
                onPressed: () => taps++,
                tooltip: 'Call',
                icon: const Icon(Icons.call),
              ),
            ],
          ),
        ),
      ),
    );

    final surfaces = tester.widgetList<KeySurface>(find.byType(KeySurface));

    expect(
      surfaces.map((surface) => surface.backgroundColor),
      containsAllInOrder([const Color(0xFF1F2D27), const Color(0xFF2E1F22)]),
    );
    expect(surfaces.map((surface) => surface.enabled), everyElement(isTrue));
    expect(surfaces.map((surface) => surface.onPressed), everyElement(isNull));

    final layers = tester
        .widgetList<Positioned>(
          find.descendant(
            of: find.byType(KeySurface),
            matching: find.byType(Positioned),
          ),
        )
        .toList();

    expect(layers.first.top, closeTo(3, 0.01));
    expect(layers[1].top, closeTo(3, 0.01));

    await tester.tap(find.text('Loading'));
    await tester.tap(find.byIcon(Icons.call));

    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('key surface shadow depth follows hover lift', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: KeySurface(
              width: 120,
              height: 40,
              hoverLift: 4,
              baseDepth: 8,
              onPressed: () {},
              child: const Text('Key'),
            ),
          ),
        ),
      ),
    );

    final mouseRegionFinder = find.descendant(
      of: find.byType(KeySurface),
      matching: find.byType(MouseRegion),
    );
    final mouseRegion = tester.widget<MouseRegion>(mouseRegionFinder);
    mouseRegion.onEnter?.call(const PointerEnterEvent(position: Offset.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final layers = tester
        .widgetList<Positioned>(
          find.descendant(
            of: find.byType(KeySurface),
            matching: find.byType(Positioned),
          ),
        )
        .toList();

    expect(layers, hasLength(2));
    expect(layers.first.top, closeTo(4, 0.01));
    expect(layers.last.top, closeTo(0, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pressed key surface returns to the unhovered footprint', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: KeySurface(
              width: 120,
              height: 40,
              hoverLift: 4,
              baseDepth: 8,
              onPressed: () {},
              child: const Text('Key'),
            ),
          ),
        ),
      ),
    );

    final surfaceFinder = find.byType(KeySurface);
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
    expect(layers.first.top, closeTo(4, 0.01));
    expect(layers.last.top, closeTo(4, 0.01));
    expect(tester.takeException(), isNull);
    await gesture.up();
  });

  testWidgets('key shadows are derived from button background colors', (
    WidgetTester tester,
  ) async {
    const customBackground = Color(0xFF334455);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              KeyButton(
                tone: KeyButtonTone.primary,
                onPressed: () {},
                child: const Text('Primary'),
              ),
              KeyButton(
                tone: KeyButtonTone.danger,
                onPressed: () {},
                child: const Text('Danger'),
              ),
              KeySurface(
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
            of: find.byType(KeySurface),
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
  final hsl = HSLColor.fromColor(background);
  final saturation = (hsl.saturation * 1.35).clamp(0.0, 1.0).toDouble();
  final lightness = (hsl.lightness * 0.49).clamp(0.06, 0.12).toDouble();
  return hsl.withSaturation(saturation).withLightness(lightness).toColor();
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
