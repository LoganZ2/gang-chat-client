import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerEnterEvent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/main.dart';
import 'package:client/src/app/audio_device_info.dart';
import 'package:client/src/app/audio_device_store.dart';
import 'package:client/src/app/authenticated_app_context.dart';
import 'package:client/src/app/close_behavior.dart';
import 'package:client/src/app/login_account_history.dart';
import 'package:client/src/app/live_session_controller.dart';
import 'package:client/src/app/realtime_controller.dart';
import 'package:client/src/auth/auth_client.dart';
import 'package:client/src/auth/token_store.dart';
import 'package:client/src/live/audio_device_service.dart';
import 'package:client/src/live/live_session.dart';
import 'package:client/src/live/system_audio_devices.dart';
import 'package:client/src/protocol/api_client.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/settings/settings_page.dart';
import 'package:client/src/shell/desktop_window_controller.dart';
import 'package:client/src/shell/login_page.dart';
import 'package:client/src/ui/ui.dart' as ui;
import 'package:client/src/home/hover_card_anchor.dart';
import 'package:client/src/home/home_page.dart';
import 'package:client/src/home/live_channel_pane.dart' as live_pane;
import 'package:client/ui_showcase.dart' as showcase;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('live stage defaults collapsed except local screen share', () {
    final remoteCamera = _liveVideoTrack(
      identity: 'user-2',
      isScreenShare: false,
      isLocal: false,
    );
    final localCamera = _liveVideoTrack(
      identity: 'user-1',
      isScreenShare: false,
      isLocal: true,
    );
    final localShare = _liveVideoTrack(
      identity: 'user-1',
      isScreenShare: true,
      isLocal: true,
    );

    expect(
      live_pane.resolveLiveStageTrackForTest(
        tracks: [remoteCamera, localCamera],
        selection: null,
      ),
      isNull,
    );
    expect(
      live_pane.resolveLiveStageTrackForTest(
        tracks: [remoteCamera, localCamera, localShare],
        selection: null,
      ),
      same(localShare),
    );
    expect(
      live_pane.resolveLiveStageTrackForTest(
        tracks: [remoteCamera, localShare],
        selection: live_pane.LiveStageSelection.fromTrack(remoteCamera),
      ),
      same(remoteCamera),
    );
    expect(
      live_pane.resolveLiveStageTrackForTest(
        tracks: [localShare],
        selection: const live_pane.LiveStageSelection.none(),
      ),
      isNull,
    );
  });

  testWidgets('hover card reset hides portal safely during rebuild', (
    WidgetTester tester,
  ) async {
    var resetKey = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Center(
                child: HoverCardAnchor(
                  resetKey: resetKey,
                  cardBuilder: (context) => TextButton(
                    onPressed: () => setState(() => resetKey++),
                    child: const Text('Reset card'),
                  ),
                  child: const SizedBox.square(
                    key: ValueKey('hover-card-anchor'),
                    dimension: 40,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('hover-card-anchor'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reset card'), findsOneWidget);

    await tester.tap(find.text('Reset card'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('app renders login entrypoint on real auth gate', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(GangApp(tokenStore: _MemoryTokenStore()));
    await tester.pump();

    expect(find.text('Gang Chat'), findsOneWidget);
    expect(find.text('用户名或邮箱地址'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '登录'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
    expect(find.byTooltip('显示密码'), findsOneWidget);

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
    _expectSubmitButtonFullWidth(tester, submitLabel: '登录');
    expect(find.text('请输入账号和密码后继续'), findsNothing);
    final normalSurfaceHeight = tester
        .getSize(find.byKey(const ValueKey('auth-surface')))
        .height;
    final normalBottomGap = _submitBottomGap(tester, submitLabel: '登录');

    await tester.tap(find.widgetWithText(ui.Button, '登录'));
    await tester.pump();

    expect(find.text('请输入账号和密码后继续'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('auth-surface'))).height,
      closeTo(normalSurfaceHeight + 20, 0.01),
    );
    expect(
      _submitBottomGap(tester, submitLabel: '登录'),
      closeTo(normalBottomGap, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth login error layout stays scrollable across retries', (
    WidgetTester tester,
  ) async {
    var attempts = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: LoginPage(
          sizeForMode: (_, {showingError = false}) => const Size(416, 284),
          consumeInitialWindowLock: () => true,
          lockAuthWindow:
              ({
                bool registering = false,
                bool moveWindow = false,
                bool centerWindow = false,
                Size? size,
              }) async {},
          onSubmit: (_, {required rememberPassword}) async {
            attempts += 1;
            throw Exception('登录失败');
          },
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(_textFieldWithHint('用户名或邮箱地址'), 'kai');
    await tester.enterText(_textFieldWithHint('密码'), 'secret123');
    await tester.tap(find.widgetWithText(ui.Button, '登录'));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.widgetWithText(ui.Button, '登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ui.Button, '登录'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('windows auth page shows compact custom window controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme().copyWith(platform: TargetPlatform.windows),
        home: LoginPage(
          sizeForMode: (_, {showingError = false}) => const Size(430, 291),
          consumeInitialWindowLock: () => true,
          lockAuthWindow:
              ({
                bool registering = false,
                bool moveWindow = false,
                bool centerWindow = false,
                Size? size,
              }) async {},
          windowController: DesktopWindowController(),
          onSubmit: (_, {required rememberPassword}) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('最小化'), findsOneWidget);
    expect(find.byTooltip('最大化'), findsNothing);
    expect(find.byTooltip('还原'), findsNothing);
    expect(find.byTooltip('关闭'), findsOneWidget);
  });

  testWidgets('auth account history expands, selects and deletes records', (
    WidgetTester tester,
  ) async {
    final store = _MemoryLoginAccountHistoryStore([
      LoginAccountRecord(
        login: 'kai',
        password: 'secret123',
        defaultAvatarKey: 'green-2',
        useCount: 3,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      LoginAccountRecord(
        login: 'morgan',
        useCount: 1,
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: LoginPage(
          sizeForMode: (_, {showingError = false}) => const Size(430, 291),
          consumeInitialWindowLock: () => true,
          lockAuthWindow:
              ({
                bool registering = false,
                bool moveWindow = false,
                bool centerWindow = false,
                Size? size,
              }) async {},
          accountHistoryStore: store,
          onSubmit: (_, {required rememberPassword}) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(_textFieldWithHint('用户名或邮箱地址'), findsOneWidget);
    expect(
      tester.widget<TextField>(_textFieldWithHint('用户名或邮箱地址')).controller!.text,
      'morgan',
    );
    expect(
      tester.widget<TextField>(_textFieldWithHint('密码')).controller!.text,
      isEmpty,
    );
    expect(tester.widget<ui.UiSwitch>(find.byType(ui.UiSwitch)).value, isFalse);
    expect(find.byTooltip('清除账号'), findsOneWidget);

    await tester.tap(find.byTooltip('展开账号记录'));
    await tester.pump();

    expect(find.text('kai'), findsOneWidget);
    expect(find.text('morgan'), findsWidgets);
    expect(find.byType(ui.Avatar), findsNWidgets(2));
    expect(
      tester.widget<ui.Avatar>(find.byType(ui.Avatar).first).defaultAvatarKey,
      'green-2',
    );
    expect(
      tester.getTopLeft(find.text('kai')).dy,
      lessThan(tester.getTopLeft(find.text('morgan').last).dy),
    );
    expect(find.byTooltip('删除账号记录'), findsNWidgets(2));

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();

    expect(find.byTooltip('收起账号记录'), findsNothing);
    expect(find.byTooltip('展开账号记录'), findsOneWidget);

    await tester.tap(find.byTooltip('清除账号'));
    await tester.pump();

    expect(
      tester.widget<TextField>(_textFieldWithHint('用户名或邮箱地址')).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<TextField>(_textFieldWithHint('密码')).controller!.text,
      isEmpty,
    );
    expect(tester.widget<ui.UiSwitch>(find.byType(ui.UiSwitch)).value, isFalse);
    expect(find.byTooltip('清除账号'), findsNothing);

    await tester.tap(find.byTooltip('展开账号记录'));
    await tester.pump();

    await tester.tap(find.text('kai'));
    await tester.pump();

    expect(
      tester.widget<TextField>(_textFieldWithHint('用户名或邮箱地址')).controller!.text,
      'kai',
    );
    expect(
      tester.widget<TextField>(_textFieldWithHint('密码')).controller!.text,
      'secret123',
    );
    expect(find.byTooltip('收起账号记录'), findsNothing);

    await tester.tap(find.byTooltip('展开账号记录'));
    await tester.pump();
    await tester.tap(find.byTooltip('删除账号记录').last);
    await tester.pump();

    expect(find.text('morgan'), findsNothing);
    expect(store.records.map((record) => record.login), ['kai']);
  });

  testWidgets('auth fills remembered password for latest login', (
    WidgetTester tester,
  ) async {
    final store = _MemoryLoginAccountHistoryStore([
      LoginAccountRecord(
        login: 'kai',
        useCount: 4,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
      LoginAccountRecord(
        login: 'morgan',
        password: 'moonbase',
        useCount: 1,
        updatedAt: DateTime.utc(2026, 1, 2),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: LoginPage(
          sizeForMode: (_, {showingError = false}) => const Size(430, 291),
          consumeInitialWindowLock: () => true,
          lockAuthWindow:
              ({
                bool registering = false,
                bool moveWindow = false,
                bool centerWindow = false,
                Size? size,
              }) async {},
          accountHistoryStore: store,
          onSubmit: (_, {required rememberPassword}) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(_textFieldWithHint('用户名或邮箱地址')).controller!.text,
      'morgan',
    );
    expect(
      tester.widget<TextField>(_textFieldWithHint('密码')).controller!.text,
      'moonbase',
    );
    expect(tester.widget<ui.UiSwitch>(find.byType(ui.UiSwitch)).value, isTrue);
  });

  testWidgets('remember password stores successful login locally', (
    WidgetTester tester,
  ) async {
    final store = _MemoryLoginAccountHistoryStore();
    bool? submittedRememberPassword;

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: LoginPage(
          sizeForMode: (_, {showingError = false}) => const Size(430, 291),
          consumeInitialWindowLock: () => true,
          lockAuthWindow:
              ({
                bool registering = false,
                bool moveWindow = false,
                bool centerWindow = false,
                Size? size,
              }) async {},
          accountHistoryStore: store,
          onSubmit: (_, {required rememberPassword}) async {
            submittedRememberPassword = rememberPassword;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(_textFieldWithHint('用户名或邮箱地址'), 'kai');
    await tester.enterText(_textFieldWithHint('密码'), 'secret123');
    await tester.tap(find.byTooltip('记住密码'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ui.Button, '登录'));
    await tester.pumpAndSettle();

    expect(submittedRememberPassword, isTrue);
    expect(store.records, hasLength(1));
    expect(store.records.single.login, 'kai');
    expect(store.records.single.password, 'secret123');
  });

  testWidgets('register mode exposes full auth form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(GangApp(tokenStore: _MemoryTokenStore()));
    await tester.pump();

    final loginBottomGap = _submitBottomGap(tester, submitLabel: '登录');

    await tester.tap(find.text('注册'));
    await tester.pump();

    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('邮箱地址'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('确认密码'), findsOneWidget);
    expect(find.byTooltip('显示密码'), findsNWidgets(2));
    expect(find.widgetWithText(ui.Button, '创建账号'), findsOneWidget);
    expect(
      _submitBottomGap(tester, submitLabel: '创建账号'),
      closeTo(loginBottomGap, 0.01),
    );
    _expectSubmitButtonFullWidth(tester, submitLabel: '创建账号');
    expect(find.text('请输入账号和密码后继续'), findsNothing);
    final normalSurfaceHeight = tester
        .getSize(find.byKey(const ValueKey('auth-surface')))
        .height;

    await tester.tap(find.byTooltip('显示密码').first);
    await tester.pump();

    expect(find.byTooltip('隐藏密码'), findsOneWidget);
    expect(find.byTooltip('显示密码'), findsOneWidget);

    await tester.tap(find.widgetWithText(ui.Button, '创建账号'));
    await tester.pump();

    expect(find.text('请输入账号和密码后继续'), findsOneWidget);
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
        home: HomePage(
          app: _homeTestAppContext(requestedPaths: requestedPaths),
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/rooms'));
    expect(find.byType(ui.Sidebar), findsNothing);
    expect(find.text('Gang Chat'), findsNothing);
    expect(find.byKey(const ValueKey('home-title-search')), findsOneWidget);
    expect(find.byTooltip('最小化'), findsOneWidget);
    expect(find.byTooltip('最大化'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(find.text('Workspace'), findsNothing);
    expect(find.text('Tools'), findsNothing);
    expect(find.text('Rooms'), findsNothing);
    expect(find.text('Activity'), findsNothing);
    expect(find.text('People'), findsNothing);
    expect(find.text('Files'), findsNothing);
    expect(find.text('设置'), findsNothing);
    expect(find.byTooltip('创建房间'), findsOneWidget);
    expect(find.byTooltip('通知'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.byTooltip('退出登录'), findsOneWidget);
    expect(find.text('Kai'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('@kai'), findsNothing);
    expect(find.text('Alpha Room'), findsOneWidget);
    expect(find.text('Beta Room'), findsOneWidget);
    expect(find.text('2 名成员 · 1 人语音'), findsOneWidget);
    expect(find.text('5 名成员'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    final searchRect = tester.getRect(
      find.byKey(const ValueKey('home-title-search')),
    );
    expect(searchRect.center.dx, closeTo(400, 0.01));
    expect(searchRect.width, closeTo(520, 0.01));
    expect(searchRect.height, closeTo(30, 0.01));

    final userSummaryRect = tester.getRect(
      find.byKey(const ValueKey('home-sidebar-user-summary')),
    );
    final userSummaryAvatar = tester.widget<ui.Avatar>(
      find.descendant(
        of: find.byKey(const ValueKey('home-sidebar-user-summary')),
        matching: find.byType(ui.Avatar),
      ),
    );
    final displayNameRect = tester.getRect(find.text('Kai'));
    final statusRect = tester.getRect(find.text('在线'));
    final statusDotRect = tester.getRect(
      find.byKey(const ValueKey('home-sidebar-presence-dot')),
    );
    expect(userSummaryAvatar.showBorder, isFalse);
    expect(statusRect.top, greaterThan(displayNameRect.bottom));
    expect(statusRect.left, greaterThan(userSummaryRect.left));
    expect(statusRect.right, lessThan(userSummaryRect.right));
    expect(statusDotRect.width, closeTo(6, 0.01));
    expect(statusDotRect.height, closeTo(6, 0.01));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-sidebar-user-summary')),
        matching: find.byType(ui.PresencePill),
      ),
      findsNothing,
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

    expect(requestedPaths, contains('/api/v1/rooms/server-alpha'));
    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/messages'));
    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/live'));
    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/read'));
    expect(find.text('Hello from Morgan'), findsOneWidget);
    expect(find.text('Reply from Kai'), findsOneWidget);
    expect(find.text('查看 3 条新消息'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    expect(find.byType(ui.ChatComposer), findsOneWidget);
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

  testWidgets('authenticated home shell title search keeps fixed resize size', (
    WidgetTester tester,
  ) async {
    Future<Size> pumpHomeAtWidth(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: Center(
            child: SizedBox(
              width: width,
              height: 620,
              child: HomePage(
                app: _homeTestAppContext(),
                realtime: _NoopRealtimeService(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(const ValueKey('home-title-search')));
    }

    final wideSize = await pumpHomeAtWidth(1180);
    final resizedSize = await pumpHomeAtWidth(900);

    expect(wideSize.width, closeTo(520, 0.01));
    expect(wideSize.height, closeTo(30, 0.01));
    expect(resizedSize.width, closeTo(wideSize.width, 0.01));
    expect(resizedSize.height, closeTo(wideSize.height, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'authenticated home shell title live room module controls joined voice',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final requestedPaths = <String>[];
      final liveSession = _FakeLiveSession();
      final liveSessionController = _FakeLiveSessionController(
        session: liveSession,
      );
      final app = _homeTestAppContext(requestedPaths: requestedPaths);

      Future<void> pumpHomeAtWidth(double width) async {
        tester.view.physicalSize = Size(width, 620);
        await tester.pumpWidget(
          MaterialApp(
            theme: ui.uiTheme(),
            home: SizedBox(
              width: width,
              height: 620,
              child: HomePage(
                app: app,
                audioDeviceStore: const _FakeAudioDeviceStore(),
                liveSessionController: liveSessionController,
                realtime: _NoopRealtimeService(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpHomeAtWidth(1180);
      expect(
        find.byKey(const ValueKey<String>('home-title-live-room')),
        findsNothing,
      );

      await tester.tap(find.text('Alpha Room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('进入语音频道'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ui.Button, '加入'));
      await tester.pumpAndSettle();

      final dock = find.byKey(const ValueKey<String>('home-title-live-room'));
      final search = find.byKey(const ValueKey('home-title-search'));
      expect(dock, findsOneWidget);
      expect(tester.getSize(dock).width, closeTo(250, 0.01));
      expect(tester.getSize(dock).height, closeTo(30, 0.01));
      expect(tester.getRect(dock).right, lessThan(tester.getRect(search).left));
      expect(
        find.descendant(of: dock, matching: find.byIcon(Icons.volume_up)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dock, matching: find.text('Alpha Room')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dock, matching: find.byIcon(Icons.mic)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dock, matching: find.byIcon(Icons.headphones)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dock, matching: find.byIcon(Icons.call_end)),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('home-title-live-room:mic')),
      );
      await tester.pumpAndSettle();

      expect(liveSession.inputVolumes.last, 0.0);
      expect(
        find.descendant(of: dock, matching: find.byIcon(Icons.mic_off)),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('home-title-live-room:headphones')),
      );
      await tester.pumpAndSettle();

      expect(liveSession.outputVolumes.last, 0.0);
      expect(
        find.descendant(of: dock, matching: find.byIcon(Icons.headset_off)),
        findsOneWidget,
      );

      await pumpHomeAtWidth(900);
      expect(dock, findsNothing);

      await pumpHomeAtWidth(1180);
      expect(dock, findsOneWidget);
      expect(tester.getSize(dock).width, closeTo(250, 0.01));
      expect(tester.getSize(dock).height, closeTo(30, 0.01));

      await tester.tap(find.text('Beta Room'));
      await tester.pumpAndSettle();
      expect(_liveControl('leave'), findsNothing);
      expect(find.byType(live_pane.LiveChannelPane), findsNothing);

      final alphaDetailsBeforeLeave = requestedPaths
          .where((path) => path == '/api/v1/rooms/server-alpha')
          .length;
      await tester.tap(
        find.byKey(const ValueKey<String>('home-title-live-room:leave')),
      );
      await tester.pumpAndSettle();

      expect(liveSession.disconnects, 1);
      expect(dock, findsNothing);
      expect(_liveControl('leave'), findsNothing);
      expect(find.byType(live_pane.LiveChannelPane), findsNothing);
      expect(find.text('Beta Room'), findsWidgets);
      expect(
        requestedPaths
            .where((path) => path == '/api/v1/rooms/server-alpha')
            .length,
        alphaDetailsBeforeLeave,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'authenticated home shell title live room module waits for room before switching',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 620);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final requestedPaths = <String>[];
      var holdAlphaDetail = false;
      final alphaDetailGate = Completer<void>();
      final liveSession = _FakeLiveSession();
      final liveSessionController = _FakeLiveSessionController(
        session: liveSession,
      );
      final app = _homeTestAppContext(
        requestedPaths: requestedPaths,
        beforeRoomDetailResponse: (roomId) async {
          if (roomId == 'server-alpha' && holdAlphaDetail) {
            await alphaDetailGate.future;
          }
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: SizedBox(
            width: 1180,
            height: 620,
            child: HomePage(
              app: app,
              audioDeviceStore: const _FakeAudioDeviceStore(),
              liveSessionController: liveSessionController,
              realtime: _NoopRealtimeService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha Room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('进入语音频道'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ui.Button, '加入'));
      await tester.pumpAndSettle();

      final dock = find.byKey(const ValueKey<String>('home-title-live-room'));
      expect(dock, findsOneWidget);

      await tester.tap(find.text('Beta Room'));
      await tester.pumpAndSettle();
      expect(_liveControl('leave'), findsNothing);
      expect(find.text('Beta Room'), findsWidgets);

      final alphaDetailsBeforeOpen = requestedPaths
          .where((path) => path == '/api/v1/rooms/server-alpha')
          .length;
      holdAlphaDetail = true;
      await tester.tap(dock);
      await tester.pump();

      expect(_liveControl('leave'), findsNothing);
      expect(find.text('Beta Room'), findsWidgets);

      alphaDetailGate.complete();
      await tester.pumpAndSettle();

      expect(_liveControl('leave'), findsOneWidget);
      expect(find.text('Morgan'), findsOneWidget);
      expect(
        requestedPaths
            .where((path) => path == '/api/v1/rooms/server-alpha')
            .length,
        greaterThan(alphaDetailsBeforeOpen),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'authenticated home shell title live room module is right on macOS',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 620);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final liveSession = _FakeLiveSession();
      final liveSessionController = _FakeLiveSessionController(
        session: liveSession,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme().copyWith(platform: TargetPlatform.macOS),
          home: SizedBox(
            width: 1180,
            height: 620,
            child: HomePage(
              app: _homeTestAppContext(),
              audioDeviceStore: const _FakeAudioDeviceStore(),
              liveSessionController: liveSessionController,
              realtime: _NoopRealtimeService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha Room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('进入语音频道'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ui.Button, '加入'));
      await tester.pumpAndSettle();

      final dock = find.byKey(const ValueKey<String>('home-title-live-room'));
      final search = find.byKey(const ValueKey('home-title-search'));
      expect(dock, findsOneWidget);
      expect(
        tester.getRect(dock).left,
        greaterThan(tester.getRect(search).right),
      );
      expect(find.byTooltip('最小化'), findsNothing);
      expect(find.byTooltip('最大化'), findsNothing);
      expect(find.byTooltip('关闭'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'authenticated home shell search category filters sidebar rooms',
    (WidgetTester tester) async {
      final requestedPaths = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: HomePage(
            app: _homeTestAppContext(requestedPaths: requestedPaths),
            realtime: _NoopRealtimeService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.descendant(
        of: find.byKey(const ValueKey('home-title-search')),
        matching: find.byType(TextField),
      );
      await tester.enterText(searchField, 'Beta');
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pumpAndSettle();

      expect(requestedPaths, contains('/api/v1/search'));
      expect(
        find.byKey(const ValueKey('home-title-search-results')),
        findsOneWidget,
      );
      expect(find.text('我的房间 1'), findsWidgets);
      expect(find.text('公开房间 1'), findsWidgets);
      expect(find.text('聊天记录 1'), findsWidgets);
      expect(find.text('聊天文件 1'), findsWidgets);
      expect(
        find.byKey(const ValueKey('public-room-action-server-public')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('my-room-action-server-beta')),
        findsOneWidget,
      );
      expect(find.widgetWithText(ui.Button, '进入房间'), findsOneWidget);
      expect(find.widgetWithText(ui.Button, '加入房间'), findsOneWidget);
      expect(find.text('5 名成员'), findsWidgets);
      expect(find.text('2 名成员'), findsWidgets);
      expect(find.text('server-public - 2 名成员'), findsNothing);

      final searchPanel = find.byKey(
        const ValueKey('home-title-search-results'),
      );
      final myRoomAvatar = find.descendant(
        of: searchPanel,
        matching: find.byWidgetPredicate(
          (widget) => widget is ui.Avatar && widget.label == 'Beta Room',
        ),
      );
      expect(myRoomAvatar, findsWidgets);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(myRoomAvatar.first));
      await tester.pumpAndSettle();

      expect(requestedPaths, contains('/api/v1/rooms/server-beta'));
      final creatorAvatar = find.byWidgetPredicate(
        (widget) => widget is ui.Avatar && widget.label == 'Morgan',
      );
      expect(creatorAvatar, findsOneWidget);

      await tester.tap(creatorAvatar);
      await tester.pumpAndSettle();

      expect(
        requestedPaths,
        contains('/api/v1/rooms/server-beta/members/user-2/profile'),
      );
      expect(find.text('@morgan'), findsOneWidget);
      expect(find.text('Creator profile'), findsOneWidget);

      final sharedRoomAvatar = find.byWidgetPredicate(
        (widget) => widget is ui.Avatar && widget.label == 'Shared Alpha',
      );
      expect(sharedRoomAvatar, findsOneWidget);

      await tester.tap(sharedRoomAvatar);
      await tester.pumpAndSettle();

      expect(requestedPaths, contains('/api/v1/rooms/server-alpha'));
      expect(find.text('RID: server-alpha'), findsOneWidget);

      final alphaRidRect = tester.getRect(find.text('RID: server-alpha'));
      final alphaEnterButtonElement = find
          .widgetWithText(ui.Button, '进入房间')
          .evaluate()
          .singleWhere((element) {
            final renderObject = element.renderObject;
            if (renderObject is! RenderBox || !renderObject.hasSize) {
              return false;
            }
            final buttonRect =
                renderObject.localToGlobal(Offset.zero) & renderObject.size;
            return buttonRect.top > alphaRidRect.bottom &&
                (buttonRect.center.dx - alphaRidRect.center.dx).abs() < 160;
          });
      await tester.tap(find.byWidget(alphaEnterButtonElement.widget));
      await tester.pumpAndSettle();

      expect(requestedPaths, contains('/api/v1/rooms/server-alpha/messages'));
      expect(
        find.byKey(const ValueKey('home-title-search-results')),
        findsOneWidget,
      );
      expect(find.text('创建者'), findsWidgets);

      await tester.tapAt(const Offset(740, 100));
      await tester.pumpAndSettle();
      await tester.tap(searchField);
      await tester.pumpAndSettle();

      await gesture.moveTo(const Offset(20, 520));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final pathsBeforeSearchRowTap = List<String>.of(requestedPaths);
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const ValueKey('home-title-search-results')),
              matching: find.text('Beta Public'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(requestedPaths, pathsBeforeSearchRowTap);

      await tester.tap(
        find.byKey(const ValueKey('public-room-action-server-public')),
      );
      await tester.pumpAndSettle();

      expect(requestedPaths, contains('/api/v1/rooms/server-public/join'));

      // Selecting the 我的房间 category filters the sidebar to matching rooms.
      await tester.tap(find.byKey(const ValueKey('search-category-myRooms')));
      await tester.pumpAndSettle();

      expect(find.text('Beta Room'), findsWidgets);
      expect(find.text('Alpha Room'), findsNothing);

      // The active category persists across query edits.
      await tester.enterText(searchField, 'Beta R');
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pumpAndSettle();

      expect(find.text('Beta Room'), findsWidgets);
      expect(find.text('Alpha Room'), findsNothing);

      // Re-tapping the active category clears it and restores the full sidebar.
      await tester.tap(find.byKey(const ValueKey('search-category-myRooms')));
      await tester.pumpAndSettle();

      expect(find.text('Alpha Room'), findsOneWidget);
      expect(find.text('Beta Room'), findsWidgets);

      // Closing the dropdown hides the results panel; reopening restores it.
      await tester.tapAt(const Offset(740, 100));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home-title-search-results')),
        findsNothing,
      );

      await tester.tap(searchField);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home-title-search-results')),
        findsOneWidget,
      );

      expect(find.text('Alpha Room'), findsOneWidget);
      expect(find.text('Beta Room'), findsWidgets);

      await tester.enterText(searchField, '1');
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-title-search-results')),
          matching: find.byKey(const ValueKey('my-room-action-server-beta')),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('authenticated home shell search scroll loads next cursor page', (
    WidgetTester tester,
  ) async {
    final requestedUris = <Uri>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(requestedUris: requestedUris),
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final searchField = find.descendant(
      of: find.byKey(const ValueKey('home-title-search')),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'Page');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();

    expect(find.text('聊天记录 9'), findsWidgets);
    expect(find.text('聊天记录 8'), findsNothing);
    expect(_highlightedSearchText('Page result 9'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('search-category-messages')));
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('home-title-search-results'));
    final resultsList = find.descendant(
      of: panel,
      matching: find.byType(ListView),
    );
    expect(resultsList, findsOneWidget);

    await tester.drag(resultsList, const Offset(0, -360));
    await tester.pump();
    await tester.pumpAndSettle();

    final cursorRequests = requestedUris
        .where(
          (uri) =>
              uri.path == '/api/v1/search' &&
              uri.queryParameters['messages_cursor'] == 'message-cursor-8',
        )
        .toList();
    expect(cursorRequests, hasLength(1));
    final cursorRequest = cursorRequests.single;
    expect(cursorRequest.queryParameters['categories'], 'messages');
    expect(
      cursorRequest.queryParameters.containsKey('my_rooms_cursor'),
      isFalse,
    );
    expect(
      cursorRequest.queryParameters.containsKey('public_rooms_cursor'),
      isFalse,
    );
    expect(cursorRequest.queryParameters.containsKey('files_cursor'), isFalse);
    expect(find.text('聊天记录 9'), findsWidgets);
    await tester.drag(resultsList, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(
      requestedUris.where(
        (uri) =>
            uri.path == '/api/v1/search' &&
            uri.queryParameters['messages_cursor'] == 'message-cursor-8',
      ),
      hasLength(1),
    );
    expect(_highlightedSearchText('Page result 9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated home shell creates room from footer template', (
    WidgetTester tester,
  ) async {
    final roomCreations = <Map<String, Object?>>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(roomCreations: roomCreations),
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('创建房间'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ui.ButtonIcon>(
            find.byKey(const ValueKey('home-sidebar-create-room-button')),
          )
          .selected,
      isTrue,
    );
    expect(find.text('创建房间'), findsOneWidget);
    await tester.tap(find.byTooltip('创建房间'));
    await tester.pumpAndSettle();

    expect(find.text('创建房间'), findsNothing);
    expect(
      tester
          .widget<ui.ButtonIcon>(
            find.byKey(const ValueKey('home-sidebar-create-room-button')),
          )
          .selected,
      isFalse,
    );

    await tester.tap(find.byTooltip('创建房间'));
    await tester.pumpAndSettle();

    expect(find.text('创建房间'), findsOneWidget);
    expect(find.text('房间信息'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '确定'), findsOneWidget);
    expect(find.text('保存房间设置'), findsNothing);
    expect(find.text('离开房间'), findsNothing);
    expect(find.text('删除房间'), findsNothing);

    await tester.enterText(_textFieldWithHint('房间名称'), 'Project Nest');
    await tester.enterText(_textFieldWithHint('简介'), 'A focused room');
    final confirmButton = find.widgetWithText(ui.Button, '确定');
    await tester.ensureVisible(confirmButton);
    await tester.pumpAndSettle();
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(roomCreations, hasLength(1));
    final body = roomCreations.single;
    expect(body['name'], 'Project Nest');
    expect(body['description'], 'A focused room');
    expect(body['visibility'], 'public');
    expect(body['join_policy'], 'approval_required');
    expect(body['ai_voice_announcements_enabled'], isTrue);
    expect(body['default_avatar_key'], 'blue-3');
    expect(find.text('Project Nest'), findsAtLeastNWidgets(1));
    expect(find.text('创建房间'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'authenticated home shell opens notifications and reviews invite',
    (WidgetTester tester) async {
      final requestedUris = <Uri>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: HomePage(
            app: _homeTestAppContext(requestedUris: requestedUris),
            realtime: _NoopRealtimeService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('通知'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ui.ButtonIcon>(
              find.byKey(const ValueKey('home-sidebar-notifications-button')),
            )
            .selected,
        isTrue,
      );
      expect(find.text('通知'), findsOneWidget);
      await tester.tap(find.byTooltip('通知'));
      await tester.pumpAndSettle();

      expect(find.text('通知'), findsNothing);
      expect(
        tester
            .widget<ui.ButtonIcon>(
              find.byKey(const ValueKey('home-sidebar-notifications-button')),
            )
            .selected,
        isFalse,
      );

      await tester.tap(find.byTooltip('通知'));
      await tester.pumpAndSettle();

      expect(find.text('通知'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('邀请'), findsOneWidget);
      expect(find.text('申请'), findsOneWidget);
      expect(find.text('房间'), findsOneWidget);
      expect(
        find.ancestor(
          of: _textFieldWithHint('搜索通知'),
          matching: find.byType(ui.Input),
        ),
        findsOneWidget,
      );
      expect(find.text('邀请您加入'), findsAtLeastNWidgets(1));
      expect(find.text('已失效'), findsOneWidget);
      expect(find.text('您已申请加入'), findsAtLeastNWidgets(1));
      expect(find.text('批准了您的申请'), findsOneWidget);
      expect(find.textContaining('Morgan Member'), findsOneWidget);
      expect(find.textContaining('成员'), findsWidgets);
      expect(
        find.byKey(const ValueKey('notification-inviter-avatar-invite-alpha')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('notification-room-avatar-invite-alpha')),
        findsOneWidget,
      );
      final notificationRects = [
        tester.getRect(
          find.byKey(const ValueKey('notification-time-invite-alpha')),
        ),
        tester.getRect(
          find.byKey(
            const ValueKey('notification-inviter-avatar-invite-alpha'),
          ),
        ),
        tester.getRect(
          find.byKey(const ValueKey('notification-inviter-name-invite-alpha')),
        ),
        tester.getRect(
          find.byKey(const ValueKey('notification-inviter-role-invite-alpha')),
        ),
        tester.getRect(
          find.byKey(const ValueKey('notification-invite-action-invite-alpha')),
        ),
        tester.getRect(
          find.byKey(const ValueKey('notification-room-avatar-invite-alpha')),
        ),
        tester.getRect(
          find.byKey(const ValueKey('notification-room-name-invite-alpha')),
        ),
        tester.getRect(find.byTooltip('接受邀请')),
      ];
      for (var index = 1; index < notificationRects.length; index++) {
        expect(
          notificationRects[index].left,
          greaterThan(notificationRects[index - 1].left),
        );
      }
      expect(
        requestedUris.any(
          (uri) =>
              uri.path == '/api/v1/room-invites' &&
              uri.queryParameters['status'] == 'all',
        ),
        isTrue,
      );
      expect(
        requestedUris.any(
          (uri) =>
              uri.path == '/api/v1/room-applications' &&
              uri.queryParameters['status'] == 'all',
        ),
        isTrue,
      );

      await tester.tap(find.byTooltip('撤回申请'));
      await tester.pumpAndSettle();

      expect(
        requestedUris.any(
          (uri) => uri.path == '/api/v1/room-applications/application-alpha',
        ),
        isTrue,
      );

      await tester.tap(find.byTooltip('接受邀请'));
      await tester.tap(find.byTooltip('接受邀请'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('申请加入'), findsOneWidget);
      expect(find.text('您需要等待'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭').last);
      await tester.pumpAndSettle();

      expect(find.text('申请加入'), findsNothing);

      await tester.tap(find.byTooltip('接受邀请'));
      await tester.pumpAndSettle();

      expect(find.text('申请加入'), findsOneWidget);
      await tester.tap(find.widgetWithText(ui.Button, '取消'));
      await tester.pumpAndSettle();

      expect(find.text('申请加入'), findsNothing);

      await tester.tap(find.byTooltip('接受邀请'));
      await tester.pumpAndSettle();

      expect(find.text('申请加入'), findsOneWidget);
      await tester.enterText(_textFieldWithHint('申请说明'), 'I was invited');
      await tester.tap(find.widgetWithText(ui.Button, '发送申请'));
      await tester.pumpAndSettle();

      expect(
        requestedUris.any(
          (uri) => uri.path == '/api/v1/room-invites/invite-alpha',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('authenticated home shell sends messages through real API path', (
    WidgetTester tester,
  ) async {
    final requestedPaths = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(requestedPaths: requestedPaths),
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(ui.ChatComposer),
        matching: find.byType(TextField),
      ),
      'Fresh message',
    );
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/messages'));
    expect(find.text('Fresh message'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated home shell opens live channel pane', (
    WidgetTester tester,
  ) async {
    final requestedPaths = <String>[];
    final liveModerationActions = <String>[];
    final liveSession = _FakeLiveSession();
    final liveSessionController = _FakeLiveSessionController(
      session: liveSession,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(
            requestedPaths: requestedPaths,
            liveModerationActions: liveModerationActions,
          ),
          audioDeviceStore: const _FakeAudioDeviceStore(),
          liveSessionController: liveSessionController,
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('进入语音频道'));
    await tester.pumpAndSettle();

    expect(find.text('Morgan'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '加入'), findsOneWidget);
    expect(_liveControl('collapse'), findsOneWidget);
    expect(find.byTooltip('收起语音频道'), findsOneWidget);
    expect(find.byTooltip('已加入语音'), findsNothing);

    await tester.tap(find.widgetWithText(ui.Button, '加入'));
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/live/join'));
    expect(liveSession.connectAttempts, 1);
    final selfLiveMemberCard = find.ancestor(
      of: find.byKey(const ValueKey<String>('live-member-status:mic:user-1')),
      matching: find.byType(ui.PressableSurface),
    );
    final selfLiveName = tester.widget<Text>(
      find.descendant(of: selfLiveMemberCard, matching: find.text('Kai')),
    );
    expect(selfLiveName.style?.color, ui.UiColors.accent);
    expect(find.text('Kai (you)'), findsNothing);
    expect(find.text('Morgan'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '加入'), findsNothing);
    expect(_liveControl('mic'), findsOneWidget);
    expect(_liveControl('leave'), findsOneWidget);
    expect(find.byTooltip('静音'), findsNothing);
    expect(find.byTooltip('耳机静音'), findsNothing);
    expect(find.byTooltip('关闭麦克风'), findsOneWidget);
    expect(find.byTooltip('关闭耳机'), findsOneWidget);
    expect(find.byTooltip('共享屏幕'), findsOneWidget);
    expect(find.byTooltip('开启摄像头'), findsOneWidget);
    expect(find.byTooltip('离开'), findsNothing);
    expect(find.byTooltip('离开语音频道'), findsOneWidget);
    expect(find.byTooltip('已加入语音'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-sidebar-user-summary')),
        matching: find.text('语音'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-sidebar-user-summary')),
        matching: find.text('active'),
      ),
      findsNothing,
    );
    final selfVoiceVolumeButton = find.byKey(
      const ValueKey<String>('live-member-status:voice-volume:user-1'),
    );
    final selfKickButton = find.byKey(
      const ValueKey<String>('live-member-status:kick:user-1'),
    );
    final remoteVoiceVolumeButton = find.byKey(
      const ValueKey<String>('live-member-status:voice-volume:user-2'),
    );
    final remoteMicButton = find.byKey(
      const ValueKey<String>('live-member-status:mic:user-2'),
    );
    final remoteHeadphonesButton = find.byKey(
      const ValueKey<String>('live-member-status:headphones:user-2'),
    );
    final remoteKickButton = find.byKey(
      const ValueKey<String>('live-member-status:kick:user-2'),
    );
    expect(selfVoiceVolumeButton, findsNothing);
    expect(selfKickButton, findsNothing);
    expect(remoteVoiceVolumeButton, findsOneWidget);
    expect(remoteMicButton, findsOneWidget);
    expect(remoteHeadphonesButton, findsOneWidget);
    expect(remoteKickButton, findsOneWidget);

    final memberHover = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await memberHover.addPointer(
      location: tester.getCenter(remoteVoiceVolumeButton),
    );
    await tester.pump();
    final memberVolumeSlider = find.byKey(
      const ValueKey<String>('live-volume-slider:Morgan语音音量'),
    );
    expect(memberVolumeSlider, findsOneWidget);
    await tester.tapAt(
      tester.getRect(memberVolumeSlider).bottomCenter - const Offset(0, 1),
    );
    await tester.pump();
    expect(liveSession.participantVoiceVolumeWrites.last, 'user-2:0.00');

    await memberHover.removePointer();
    await tester.pumpAndSettle();
    await tester.tap(remoteMicButton);
    await tester.pumpAndSettle();
    expect(find.text('禁言此用户'), findsOneWidget);
    await tester.tap(find.widgetWithText(ui.Button, '禁言'));
    await tester.pumpAndSettle();
    expect(liveModerationActions.last, 'mute_mic');

    await tester.tap(remoteHeadphonesButton);
    await tester.pumpAndSettle();
    expect(find.text('隔离此用户'), findsOneWidget);
    await tester.tap(find.widgetWithText(ui.Button, '隔离'));
    await tester.pumpAndSettle();
    expect(liveModerationActions.last, 'block_voice');

    await tester.tap(remoteHeadphonesButton);
    await tester.pumpAndSettle();
    expect(find.text('恢复耳机'), findsOneWidget);
    await tester.tap(find.widgetWithText(ui.Button, '恢复'));
    await tester.pumpAndSettle();
    expect(liveModerationActions.last, 'restore_headphones');

    await tester.tap(remoteMicButton);
    await tester.pumpAndSettle();
    expect(find.text('取消禁言'), findsOneWidget);
    await tester.tap(find.widgetWithText(ui.Button, '解除'));
    await tester.pumpAndSettle();
    expect(liveModerationActions.last, 'restore_voice');

    await tester.tap(remoteKickButton);
    await tester.pumpAndSettle();
    expect(find.text('踢出语音频道'), findsOneWidget);
    await tester.tap(find.widgetWithText(ui.Button, '踢出'));
    await tester.pumpAndSettle();
    expect(liveModerationActions.last, 'kick');
    expect(
      requestedPaths,
      contains(
        '/api/v1/rooms/server-alpha/live/participants/user-2/moderation',
      ),
    );
    expect(find.text('Morgan'), findsNothing);

    await tester.tap(_liveControl('mic'));
    await tester.pumpAndSettle();
    expect(liveSession.inputVolumes.last, 0.0);
    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic_off),
      ),
      findsOneWidget,
    );

    await tester.tap(_liveControl('mic'));
    await tester.pumpAndSettle();
    expect(liveSession.inputVolumes.last, closeTo(0.35, 1e-9));
    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic),
      ),
      findsOneWidget,
    );

    await tester.tap(_liveControl('headphones'));
    await tester.pumpAndSettle();
    expect(liveSession.outputVolumes.last, 0.0);
    expect(liveSession.inputVolumes.last, 0.0);
    expect(liveSession.micMutes, contains(true));
    expect(
      find.descendant(
        of: _liveControl('headphones'),
        matching: find.byIcon(Icons.headset_off),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic_off),
      ),
      findsOneWidget,
    );

    await tester.tap(_liveControl('headphones'));
    await tester.pumpAndSettle();
    expect(liveSession.outputVolumes.last, closeTo(0.75, 1e-9));
    expect(
      find.descendant(
        of: _liveControl('headphones'),
        matching: find.byIcon(Icons.headphones),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic_off),
      ),
      findsOneWidget,
    );

    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: tester.getCenter(_liveControl('mic')));
    await tester.pump();
    final micVolumeSlider = find.byKey(
      const ValueKey<String>('live-volume-slider:麦克风输入音量'),
    );
    final micVolumeThumb = find.byKey(
      const ValueKey<String>('live-volume-thumb:麦克风输入音量'),
    );
    final micVolumeFill = find.byKey(
      const ValueKey<String>('live-volume-fill:麦克风输入音量'),
    );
    final micVolumePanel = find.byKey(
      const ValueKey<String>('live-volume-panel:麦克风输入音量'),
    );
    expect(micVolumeSlider, findsOneWidget);
    expect(
      tester.getSize(micVolumePanel).width,
      tester.getSize(_liveControl('mic')).width,
    );
    expect(tester.getSize(micVolumePanel).height, lessThan(174));
    expect(
      tester.getRect(micVolumePanel).bottom,
      lessThan(tester.getRect(_liveControl('mic')).top),
    );
    expect(tester.getSize(micVolumeFill).width, greaterThanOrEqualTo(7));
    final fillDecoration =
        tester.widget<DecoratedBox>(micVolumeFill).decoration as BoxDecoration;
    final fillRadius = fillDecoration.borderRadius as BorderRadius;
    expect(fillRadius.topLeft, Radius.zero);
    expect(fillRadius.topRight, Radius.zero);
    expect(tester.getSize(micVolumeThumb).width, greaterThanOrEqualTo(26));
    expect(tester.getSize(micVolumeThumb).height, greaterThanOrEqualTo(7));
    expect(
      (tester.getRect(micVolumeFill).top -
              tester.getRect(micVolumeThumb).bottom)
          .abs(),
      lessThanOrEqualTo(0.5),
    );
    await hover.moveTo(tester.getCenter(micVolumeThumb));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('live-volume-percent:麦克风输入音量')),
      findsOneWidget,
    );
    final micVolumePercent = find.byKey(
      const ValueKey<String>('live-volume-percent:麦克风输入音量'),
    );
    expect(
      tester.getRect(micVolumePercent).left,
      greaterThan(tester.getRect(micVolumeThumb).right),
    );
    final percentDecoration =
        tester.widget<DecoratedBox>(micVolumePercent).decoration
            as BoxDecoration;
    expect(percentDecoration.color, Colors.white);
    expect(percentDecoration.border, isNull);
    var volumeSliderRect = tester.getRect(micVolumeSlider);
    await tester.tapAt(volumeSliderRect.bottomCenter - const Offset(0, 1));
    await tester.pumpAndSettle();
    expect(liveSession.inputVolumes, contains(0.0));
    expect(liveSession.micMutes, contains(true));
    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic_off),
      ),
      findsOneWidget,
    );

    await tester.tap(_liveControl('mic'));
    await tester.pumpAndSettle();
    expect(liveSession.inputVolumes.last, closeTo(0.5, 1e-9));
    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic),
      ),
      findsOneWidget,
    );

    await hover.moveTo(tester.getCenter(_liveControl('headphones')));
    await tester.pump();
    final outputVolumeSlider = find.byKey(
      const ValueKey<String>('live-volume-slider:语音输出音量'),
    );
    expect(outputVolumeSlider, findsOneWidget);
    volumeSliderRect = tester.getRect(outputVolumeSlider);
    await tester.tapAt(volumeSliderRect.bottomCenter - const Offset(0, 1));
    await tester.pumpAndSettle();
    expect(liveSession.outputVolumes, contains(0.0));
    expect(liveSession.inputVolumes, contains(0.0));
    expect(liveSession.micMutes, contains(true));
    expect(liveSession.outputMutes, containsAll([true, false]));
    expect(
      find.descendant(
        of: _liveControl('headphones'),
        matching: find.byIcon(Icons.headset_off),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic_off),
      ),
      findsOneWidget,
    );

    await tester.tap(_liveControl('headphones'));
    await tester.pumpAndSettle();
    expect(liveSession.outputVolumes.last, closeTo(0.75, 1e-9));
    expect(
      find.descendant(
        of: _liveControl('headphones'),
        matching: find.byIcon(Icons.headphones),
      ),
      findsOneWidget,
    );

    await hover.moveTo(tester.getCenter(_liveControl('screen-share')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.byKey(const ValueKey<String>('live-volume-slider:共享屏幕输出音量')),
      findsNothing,
    );
    await hover.removePointer();
    await tester.pump();

    await tester.tap(_liveControl('camera'));
    await tester.pumpAndSettle();
    await tester.tap(_liveControl('screen-share'));
    await tester.pumpAndSettle();
    expect(find.text('Primary Display'), findsOneWidget);
    await tester.tap(find.text('Primary Display'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ui.Button, '共享'));
    await tester.pumpAndSettle();

    expect(liveSession.micMutes, contains(true));
    expect(liveSession.outputMutes, containsAll([true, false]));
    expect(liveSession.cameraEnables, [true]);
    expect(liveSession.screenShareEnables, [true]);
    expect(liveSession.screenShareSourceIds, ['screen-primary']);
    expect(
      requestedPaths
          .where((path) => path == '/api/v1/rooms/server-alpha/live/me')
          .length,
      greaterThanOrEqualTo(3),
    );

    await tester.tap(_liveControl('leave'));
    await tester.pumpAndSettle();

    expect(liveSession.disconnects, 1);
    expect(find.widgetWithText(ui.Button, '加入'), findsOneWidget);
    expect(find.byTooltip('已加入语音'), findsNothing);

    await tester.tap(_liveControl('collapse'));
    await tester.pumpAndSettle();

    expect(find.text('Kai (you)'), findsNothing);
    expect(find.text('Hello from Morgan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'direct close exit keeps token while leaving live and going offline',
    (WidgetTester tester) async {
      final events = <String>[];
      final requestedPaths = <String>[];
      final liveSession = _FakeLiveSession();
      final liveSessionController = _FakeLiveSessionController(
        session: liveSession,
      );
      final realtime = _RecordingRealtimeService(events);
      final windowController = _RecordingWindowController(events);

      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: HomePage(
            app: _homeTestAppContext(
              onLogout: () async => events.add('logout'),
              onExitSessionForAppExit: () async => events.add('exit-session'),
              requestedPaths: requestedPaths,
            ),
            audioDeviceStore: const _FakeAudioDeviceStore(),
            liveSessionController: liveSessionController,
            realtime: realtime,
            closeBehaviorStore: const _FixedCloseBehaviorStore(
              CloseBehavior.exitProgram,
            ),
            windowController: windowController,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .ancestor(
              of: find.text('Alpha Room'),
              matching: find.byType(ui.PressableSurface),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(requestedPaths, contains('/api/v1/rooms/server-alpha'));
      expect(requestedPaths, contains('/api/v1/rooms/server-alpha/live'));

      final enterLiveChannel = find.text('进入语音频道');
      if (enterLiveChannel.evaluate().isNotEmpty) {
        await tester.tap(enterLiveChannel);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.widgetWithText(ui.Button, '加入'));
      await tester.pumpAndSettle();

      final handler = windowController.closeRequestHandler;
      expect(handler, isNotNull);
      expect(await handler!(), isTrue);

      expect(requestedPaths, contains('/api/v1/rooms/server-alpha/live/me'));
      expect(liveSession.disconnects, 1);
      expect(events, ['hide', 'realtime-stop', 'exit-session', 'terminate']);
      expect(events, isNot(contains('logout')));
    },
  );

  testWidgets('settings audio volumes sync to live channel sliders', (
    WidgetTester tester,
  ) async {
    final liveSession = _FakeLiveSession();
    final liveSessionController = _FakeLiveSessionController(
      session: liveSession,
      audioDeviceStore: const _FakeAudioDeviceStore(
        inputVolume: 0.35,
        outputVolume: 0.75,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(),
          audioDeviceStore: const _FakeAudioDeviceStore(
            inputVolume: 0.62,
            outputVolume: 0.27,
          ),
          liveSessionController: liveSessionController,
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入语音频道'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ui.Button, '加入'));
    await tester.pumpAndSettle();

    expect(liveSession.inputVolumes.last, closeTo(0.35, 1e-9));
    expect(liveSession.outputVolumes.last, closeTo(0.75, 1e-9));

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语音和视频').first);
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('输入音量'), findsOneWidget);
    expect(liveSession.inputVolumes.last, closeTo(0.62, 1e-9));
    expect(liveSession.outputVolumes.last, closeTo(0.27, 1e-9));
    expect(liveSession.micMutes, isEmpty);
    expect(liveSession.outputMutes, isEmpty);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入语音频道'));
    await tester.pumpAndSettle();

    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: tester.getCenter(_liveControl('mic')));
    await tester.pump();
    _expectLiveVolumeFill(tester, '麦克风输入音量', 0.62);

    await hover.moveTo(tester.getCenter(_liveControl('headphones')));
    await tester.pump();
    _expectLiveVolumeFill(tester, '语音输出音量', 0.27);
    await hover.removePointer();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('settings audio sliders apply live mute coupling rules', (
    WidgetTester tester,
  ) async {
    final volumeChanges = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: SettingsPage(
          isSubWindow: true,
          audioDeviceStore: const _FakeAudioDeviceStore(
            inputVolume: 0.62,
            outputVolume: 0,
          ),
          audioDeviceService: const _FakeSettingsAudioDeviceService(),
          systemAudioDevices: SystemAudioDevices(supported: false),
          onVolumeChanged: (kind, volume) {
            volumeChanges.add('$kind:${volume.toStringAsFixed(2)}');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('\u8bed\u97f3\u548c\u89c6\u9891').first);
    await tester.pumpAndSettle();

    final sliders = find.byType(Slider);
    double sliderValue(int index) {
      return tester.widget<Slider>(sliders.at(index)).value;
    }

    expect(sliders, findsNWidgets(2));
    expect(sliderValue(0), 0);
    expect(sliderValue(1), 0);
    expect(volumeChanges, contains('audioinput:0.00'));
    expect(volumeChanges, contains('audiooutput:0.00'));

    tester.widget<Slider>(sliders.at(0)).onChanged!(0.8);
    await tester.pump();

    expect(sliderValue(0), closeTo(0.8, 1e-9));
    expect(sliderValue(1), closeTo(0.5, 1e-9));
    expect(volumeChanges, contains('audioinput:0.80'));
    expect(volumeChanges, contains('audiooutput:0.50'));

    tester.widget<Slider>(sliders.at(1)).onChanged!(0);
    await tester.pump();

    expect(sliderValue(0), 0);
    expect(sliderValue(1), 0);
    expect(volumeChanges, contains('audioinput:0.00'));
    expect(volumeChanges, contains('audiooutput:0.00'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('settings nonzero audio volumes clear live mute states', (
    WidgetTester tester,
  ) async {
    final liveStateUpdates = <Map<String, Object?>>[];
    final liveSession = _FakeLiveSession();
    final liveSessionController = _FakeLiveSessionController(
      session: liveSession,
      audioDeviceStore: const _FakeAudioDeviceStore(
        inputVolume: 0.35,
        outputVolume: 0.75,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(liveStateUpdates: liveStateUpdates),
          audioDeviceStore: const _FakeAudioDeviceStore(
            inputVolume: 0.62,
            outputVolume: 0.27,
          ),
          liveSessionController: liveSessionController,
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入语音频道'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ui.Button, '加入'));
    await tester.pumpAndSettle();

    await tester.tap(_liveControl('headphones'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic_off),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _liveControl('headphones'),
        matching: find.byIcon(Icons.headset_off),
      ),
      findsOneWidget,
    );

    liveStateUpdates.clear();
    liveSession.micMutes.clear();
    liveSession.outputMutes.clear();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语音和视频').first);
    await tester.pumpAndSettle();

    expect(liveSession.inputVolumes.last, closeTo(0.62, 1e-9));
    expect(liveSession.outputVolumes.last, closeTo(0.27, 1e-9));
    expect(liveSession.micMutes, contains(false));
    expect(liveSession.outputMutes, contains(false));
    expect(liveStateUpdates.any((body) => body['mic_muted'] == false), isTrue);
    expect(
      liveStateUpdates.any((body) => body['headphones_muted'] == false),
      isTrue,
    );

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入语音频道'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _liveControl('headphones'),
        matching: find.byIcon(Icons.headphones),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('microphone unmute clears headphones mute', (
    WidgetTester tester,
  ) async {
    final liveStateUpdates = <Map<String, Object?>>[];
    final liveSession = _FakeLiveSession();
    final liveSessionController = _FakeLiveSessionController(
      session: liveSession,
      audioDeviceStore: const _FakeAudioDeviceStore(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(liveStateUpdates: liveStateUpdates),
          liveSessionController: liveSessionController,
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入语音频道'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ui.Button, '加入'));
    await tester.pumpAndSettle();

    await tester.tap(_liveControl('headphones'));
    await tester.pump();
    expect(liveSession.outputVolumes.last, 0.0);
    expect(liveSession.inputVolumes.last, 0.0);
    expect(liveSession.micMutes, contains(true));
    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic_off),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _liveControl('headphones'),
        matching: find.byIcon(Icons.headset_off),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(liveStateUpdates.last['mic_muted'], true);
    expect(liveStateUpdates.last['headphones_muted'], true);

    liveStateUpdates.clear();
    liveSession.micMutes.clear();
    liveSession.outputMutes.clear();

    await tester.tap(_liveControl('mic'));
    await tester.pump();
    expect(liveSession.inputVolumes.last, closeTo(0.35, 1e-9));
    expect(liveSession.outputVolumes.last, closeTo(0.75, 1e-9));
    expect(liveSession.micMutes, contains(false));
    expect(liveSession.outputMutes, contains(false));
    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _liveControl('headphones'),
        matching: find.byIcon(Icons.headphones),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(liveStateUpdates.last['mic_muted'], false);
    expect(liveStateUpdates.last['headphones_muted'], false);
    expect(
      find.descendant(
        of: _liveControl('mic'),
        matching: find.byIcon(Icons.mic),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _liveControl('headphones'),
        matching: find.byIcon(Icons.headphones),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated home shell opens room management with real APIs', (
    WidgetTester tester,
  ) async {
    final requestedPaths = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(requestedPaths: requestedPaths),
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('room-members-entry-badge')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.groups_outlined));
    await tester.pumpAndSettle();

    expect(find.text('成员'), findsAtLeastNWidgets(1));
    expect(find.text('房间成员'), findsOneWidget);
    expect(find.text('新成员'), findsOneWidget);
    expect(find.text('黑名单'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-members-tab-badge')), findsOneWidget);
    expect(find.text('邀请成员'), findsNothing);
    expect(find.text('语音 1'), findsOneWidget);
    expect(find.text('在线 2'), findsOneWidget);
    expect(find.text('管理员 1'), findsOneWidget);
    expect(find.text('创建者 1'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('room-members-list'))).height,
      greaterThan(260),
    );
    expect(find.text('@riley'), findsNothing);
    expect(find.text('10000001'), findsNothing);
    expect(find.text('Kai'), findsWidgets);
    expect(find.text('Morgan'), findsWidgets);
    expect(find.text('uid-1 · @kai'), findsNothing);
    expect(find.text('user-2 · @morgan'), findsNothing);
    expect(find.text('创建者'), findsWidgets);
    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/members'));
    expect(
      requestedPaths,
      contains('/api/v1/rooms/server-alpha/join-requests'),
    );

    await tester.tap(find.text('新成员'));
    await tester.pumpAndSettle();

    expect(find.text('邀请成员'), findsOneWidget);
    expect(find.text('加入申请'), findsOneWidget);
    expect(find.byTooltip('详情'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('详情'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ui.ButtonIcon>(_buttonIconWithTooltip('详情')).selected,
      isTrue,
    );
    expect(find.text('申请详情'), findsOneWidget);
    expect(find.text('来源'), findsOneWidget);
    expect(find.text('公开房间搜索'), findsOneWidget);
    expect(find.text('申请理由'), findsOneWidget);
    expect(find.text('Please approve my request'), findsOneWidget);
    await tester.tap(find.widgetWithText(ui.Button, '关闭'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ui.ButtonIcon>(_buttonIconWithTooltip('详情')).selected,
      isFalse,
    );

    await tester.ensureVisible(_textFieldWithHint('按用户名、昵称或 UID 搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(_textFieldWithHint('按用户名、昵称或 UID 搜索'), 'mo');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();

    expect(find.textContaining('Morgan'), findsAtLeastNWidgets(1));
    expect(find.text('@morgan'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '在房间内'), findsOneWidget);

    await tester.enterText(_textFieldWithHint('按用户名、昵称或 UID 搜索'), '');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();

    await tester.tap(find.text('房间成员'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('设为管理员'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设为管理员'));
    await tester.pumpAndSettle();

    expect(find.text('设为管理员'), findsWidgets);
    expect(find.textContaining('Morgan'), findsAtLeastNWidgets(1));
    await tester.tap(find.widgetWithText(ui.Button, '设为管理员'));
    await tester.pumpAndSettle();

    expect(
      requestedPaths,
      contains('/api/v1/rooms/server-alpha/members/user-2'),
    );

    await tester.ensureVisible(find.byTooltip('踢出此用户'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('踢出此用户'));
    await tester.pumpAndSettle();

    expect(find.text('踢出此用户'), findsOneWidget);
    await tester.tap(find.widgetWithText(ui.Button, '踢出'));
    await tester.pumpAndSettle();

    expect(
      requestedPaths
          .where((path) => path == '/api/v1/rooms/server-alpha/members/user-2')
          .length,
      2,
    );
    expect(find.text('Morgan'), findsNothing);

    await tester.tap(find.text('新成员'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(_textFieldWithHint('按用户名、昵称或 UID 搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(_textFieldWithHint('按用户名、昵称或 UID 搜索'), 'ri');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/users/search'));
    expect(find.textContaining('Riley'), findsAtLeastNWidgets(1));
    expect(find.text('@riley'), findsOneWidget);
    expect(find.text('@river'), findsOneWidget);
    expect(find.text('@rina'), findsOneWidget);
    expect(find.text('@riko'), findsOneWidget);
    expect(find.text('@rita'), findsOneWidget);

    await tester.tap(find.widgetWithText(ui.Button, '邀请').first);
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/invites'));
    expect(find.widgetWithText(ui.Button, '已邀请'), findsOneWidget);

    await tester.tap(find.byTooltip('返回').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('房间设置'));
    await tester.pumpAndSettle();

    expect(find.text('房间设置'), findsOneWidget);
    expect(find.text('房间信息'), findsOneWidget);
    expect(find.byType(ui.UiSwitch), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(tester.widget<TextField>(_textFieldWithHint('简介')).maxLines, isNull);
    final roomInfoSectionDecorations = tester
        .widgetList<DecoratedBox>(
          find.ancestor(
            of: find.text('房间信息'),
            matching: find.byType(DecoratedBox),
          ),
        )
        .where((box) => box.decoration is BoxDecoration)
        .map((box) => box.decoration as BoxDecoration);
    expect(
      roomInfoSectionDecorations.any(
        (decoration) => decoration.color == null && decoration.border is Border,
      ),
      isTrue,
    );

    await tester.enterText(_textFieldWithHint('房间名称'), 'Alpha Renamed');
    final saveButton = find.widgetWithText(ui.Button, '保存房间设置');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/rooms/server-alpha'));
    // The success notice renders at the top of the scrollable dialog body;
    // scroll back up so the lazily-built strip is in the tree before asserting.
    await tester.scrollUntilVisible(
      find.text('房间信息已保存'),
      -200,
      scrollable: find
          .ancestor(of: saveButton, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('房间信息已保存'), findsOneWidget);
    expect(find.textContaining('Alpha Renamed'), findsAtLeastNWidgets(1));

    await tester.tap(find.byTooltip('返回').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Alpha Renamed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'authenticated home shell hides member removal for regular users',
    (WidgetTester tester) async {
      final requestedPaths = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: HomePage(
            app: _homeTestAppContext(
              requestedPaths: requestedPaths,
              currentRoomRole: 'member',
              currentRoomJoinPolicy: 'closed',
            ),
            realtime: _NoopRealtimeService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha Room'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('room-members-entry-badge')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('房间成员'));
      await tester.pumpAndSettle();

      expect(find.text('成员'), findsAtLeastNWidgets(1));
      expect(find.text('房间成员'), findsNothing);
      expect(find.text('新成员'), findsNothing);
      expect(find.text('黑名单'), findsNothing);
      expect(find.text('Morgan'), findsWidgets);
      expect(find.byTooltip('踢出此用户'), findsNothing);
      expect(find.byTooltip('设为管理员'), findsNothing);
      expect(find.byTooltip('转让创建者'), findsNothing);
      expect(requestedPaths, contains('/api/v1/rooms/server-alpha/members'));
      expect(
        requestedPaths,
        isNot(contains('/api/v1/rooms/server-alpha/join-requests')),
      );
      expect(
        requestedPaths,
        isNot(contains('/api/v1/rooms/server-alpha/blacklist')),
      );
    },
  );

  testWidgets('authenticated home shell hides new members for closed rooms', (
    WidgetTester tester,
  ) async {
    final requestedPaths = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(
            requestedPaths: requestedPaths,
            currentRoomJoinPolicy: 'closed',
          ),
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('room-members-entry-badge')),
      findsNothing,
    );

    await tester.tap(find.byTooltip('房间成员'));
    await tester.pumpAndSettle();

    expect(find.text('房间成员'), findsOneWidget);
    expect(find.text('新成员'), findsNothing);
    expect(find.text('黑名单'), findsOneWidget);
    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/members'));
    expect(
      requestedPaths,
      isNot(contains('/api/v1/rooms/server-alpha/join-requests')),
    );
  });

  testWidgets('authenticated home shell lets superusers remove creators', (
    WidgetTester tester,
  ) async {
    final requestedPaths = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(
            requestedPaths: requestedPaths,
            currentRoomRole: 'member',
            currentUserIsSuperuser: true,
            secondaryMemberRole: 'owner',
          ),
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('房间成员'));
    await tester.pumpAndSettle();

    expect(find.text('Morgan'), findsWidgets);
    expect(find.text('创建者'), findsWidgets);
    expect(find.byTooltip('踢出此用户'), findsOneWidget);
    expect(find.byTooltip('设为管理员'), findsNothing);
    expect(find.byTooltip('转让创建者'), findsNothing);
    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/members'));
  });

  testWidgets('creator removal action aligns with member action group', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(
            currentRoomRole: 'member',
            currentUserIsSuperuser: true,
            secondaryMemberRole: 'owner',
            includeActionComparisonMember: true,
          ),
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('房间成员'));
    await tester.pumpAndSettle();

    expect(find.text('Morgan'), findsWidgets);
    expect(find.text('Taylor'), findsWidgets);
    expect(_buttonIconWithTooltip('踢出此用户'), findsNWidgets(2));
    expect(_buttonIconWithTooltip('转让创建者'), findsOneWidget);

    final creatorRemoveRect = tester.getRect(
      _buttonIconWithTooltip('踢出此用户').first,
    );
    final memberTransferRect = tester.getRect(_buttonIconWithTooltip('转让创建者'));
    expect(creatorRemoveRect.right, closeTo(memberTransferRect.right, 0.01));
  });

  testWidgets('message profile can jump to member management by UID', (
    WidgetTester tester,
  ) async {
    final requestedPaths = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(requestedPaths: requestedPaths),
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final messageAvatar = find.byWidgetPredicate(
      (widget) => widget is ui.Avatar && widget.label == 'Morgan',
    );
    expect(messageAvatar, findsOneWidget);

    await gesture.moveTo(tester.getCenter(messageAvatar));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ui.Button, '管理成员'), findsOneWidget);
    await tester.tap(find.widgetWithText(ui.Button, '管理成员'));
    await tester.pumpAndSettle();

    expect(find.text('成员'), findsAtLeastNWidgets(1));
    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/members'));
    final memberSearchField = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == '搜索成员',
      ),
    );
    expect(memberSearchField.controller?.text, 'uid-2');
    expect(find.textContaining('Morgan'), findsAtLeastNWidgets(1));
  });

  testWidgets('authenticated home shell applies realtime live snapshots', (
    WidgetTester tester,
  ) async {
    final realtime = _FakeRealtimeService();

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(app: _homeTestAppContext(), realtime: realtime),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入语音频道'));
    await tester.pumpAndSettle();

    expect(find.text('Riley'), findsNothing);
    expect(find.text('2 名成员 · 1 人语音'), findsOneWidget);

    realtime.add(
      const RealtimeEvent(
        type: 'live_participant_joined',
        data: {
          'room_id': 'server-alpha',
          'participant_count': 2,
          'preview': <Object?>[],
          'live': {
            'room_id': 'server-alpha',
            'participant_count': 2,
            'participants': [
              {
                'live_session_id': 'live-session-morgan',
                'user': {
                  'id': 'user-2',
                  'username': 'morgan',
                  'display_name': 'Morgan',
                  'avatar_url': null,
                  'default_avatar_key': 'blue-3',
                },
                'joined_at': '2026-06-05T08:00:00Z',
                'mic_muted': true,
                'headphones_muted': false,
                'voice_blocked': false,
                'camera_on': false,
                'screen_sharing': false,
                'connection_state': 'connected',
              },
              {
                'live_session_id': 'live-session-riley',
                'user': {
                  'id': 'user-3',
                  'username': 'riley',
                  'display_name': 'Riley',
                  'avatar_url': null,
                  'default_avatar_key': 'green-2',
                },
                'joined_at': '2026-06-05T08:00:00Z',
                'mic_muted': false,
                'headphones_muted': false,
                'voice_blocked': false,
                'camera_on': false,
                'screen_sharing': false,
                'connection_state': 'connected',
              },
            ],
            'updated_at': '2026-06-05T08:00:00Z',
          },
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Riley'), findsOneWidget);
    expect(find.text('2 名成员 · 2 人语音'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated home shell shows realtime reconnecting marker', (
    WidgetTester tester,
  ) async {
    final realtime = _FakeRealtimeService();

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(app: _homeTestAppContext(), realtime: realtime),
      ),
    );
    await tester.pumpAndSettle();

    final userSummary = find.byKey(const ValueKey('home-sidebar-user-summary'));
    expect(
      find.descendant(of: userSummary, matching: find.textContaining('重连中')),
      findsNothing,
    );

    realtime.setStatus(RealtimeConnectionStatus.reconnecting);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: userSummary, matching: find.text('重连中')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: userSummary, matching: find.text('在线')),
      findsNothing,
    );

    realtime.setStatus(RealtimeConnectionStatus.connected);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: userSummary, matching: find.textContaining('重连中')),
      findsNothing,
    );
    expect(
      find.descendant(of: userSummary, matching: find.text('在线')),
      findsOneWidget,
    );
  });

  testWidgets(
    'authenticated home shell restores live after realtime reconnect',
    (WidgetTester tester) async {
      final realtime = _FakeRealtimeService();
      final liveJoinRequests = <Map<String, Object?>>[];
      final liveStateUpdates = <Map<String, Object?>>[];
      final liveSession = _FakeLiveSession();
      final liveSessionController = _FakeLiveSessionController(
        session: liveSession,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: HomePage(
            app: _homeTestAppContext(
              liveJoinRequests: liveJoinRequests,
              liveStateUpdates: liveStateUpdates,
            ),
            liveSessionController: liveSessionController,
            realtime: realtime,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha Room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('进入语音频道'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ui.Button, '加入'));
      await tester.pumpAndSettle();

      expect(liveSession.connectAttempts, 1);
      liveJoinRequests.clear();
      liveStateUpdates.clear();

      await tester.tap(_liveControl('mic'));
      await tester.pumpAndSettle();
      expect(liveStateUpdates.last['mic_muted'], true);
      liveStateUpdates.clear();

      realtime.setStatus(RealtimeConnectionStatus.reconnecting);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-sidebar-user-summary')),
          matching: find.text('重连中'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-sidebar-user-summary')),
          matching: find.text('语音'),
        ),
        findsNothing,
      );

      realtime.setStatus(RealtimeConnectionStatus.connected);
      realtime.emitReconnect();
      await tester.pumpAndSettle();

      expect(
        liveJoinRequests.map((body) => body['source']),
        contains('reconnect'),
      );
      expect(liveSession.connectAttempts, 2);
      expect(liveStateUpdates.last['mic_muted'], true);
      expect(liveStateUpdates.last['headphones_muted'], false);
      expect(liveStateUpdates.last['camera_on'], false);
      expect(liveStateUpdates.last['screen_sharing'], false);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-sidebar-user-summary')),
          matching: find.textContaining('重连中'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-sidebar-user-summary')),
          matching: find.text('语音'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('authenticated home shell footer opens settings and logs out', (
    WidgetTester tester,
  ) async {
    final accountUpdates = <Map<String, Object?>>[];
    var logoutCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(
            onLogout: () async => logoutCount++,
            accountUpdates: accountUpdates,
          ),
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final userSummaryRect = tester.getRect(
      find.byKey(const ValueKey('home-sidebar-user-summary')),
    );
    final createRect = tester.getRect(find.byTooltip('创建房间'));
    final notificationsRect = tester.getRect(find.byTooltip('通知'));
    final settingsRect = tester.getRect(find.byTooltip('设置'));
    final logoutRect = tester.getRect(find.byTooltip('退出登录'));
    expect(createRect.left, closeTo(userSummaryRect.left, 0.01));
    expect(notificationsRect.top, closeTo(createRect.top, 0.01));
    expect(notificationsRect.bottom, closeTo(createRect.bottom, 0.01));
    expect(settingsRect.top, closeTo(createRect.top, 0.01));
    expect(settingsRect.bottom, closeTo(createRect.bottom, 0.01));
    // The logout control now lives inline in the top user summary bar, anchored
    // to its right edge — not in the bottom footer alongside settings.
    expect(logoutRect.top, greaterThanOrEqualTo(userSummaryRect.top - 0.01));
    expect(logoutRect.bottom, lessThanOrEqualTo(userSummaryRect.bottom + 0.01));
    expect(logoutRect.bottom, lessThan(createRect.top));
    expect(logoutRect.right, lessThanOrEqualTo(userSummaryRect.right + 0.01));

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.textContaining('设置 ·'), findsNothing);
    expect(find.text('用户资料'), findsOneWidget);
    expect(find.text('偏好设置'), findsOneWidget);
    expect(find.byTooltip('刷新设置'), findsOneWidget);
    expect(
      tester
          .widget<ui.PressableSurface>(
            find.ancestor(
              of: find.byTooltip('设置'),
              matching: find.byType(ui.PressableSurface),
            ),
          )
          .selected,
      isTrue,
    );

    await tester.tap(find.text('偏好设置'));
    await tester.pumpAndSettle();

    expect(find.text('语言切换'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('繁體中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '保存偏好设置'), findsOneWidget);
    expect(find.text('隐私和安全'), findsOneWidget);
    expect(find.text('用户资料'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ui.Button, '保存偏好设置'));
    await tester.pumpAndSettle();

    expect(accountUpdates, hasLength(1));
    expect(accountUpdates.single['language'], 'en');
    expect(find.text('偏好设置已保存'), findsOneWidget);

    await tester.tap(find.byTooltip('退出登录'));
    await tester.pumpAndSettle();

    expect(logoutCount, 0);
    expect(find.text('确认退出当前账号？'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '取消'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '退出登录'), findsOneWidget);
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byTooltip('退出登录'),
              matching: find.byIcon(Icons.logout),
            ),
          )
          .color,
      ui.UiColors.accent,
    );

    await tester.tap(find.widgetWithText(ui.Button, '取消'));
    await tester.pumpAndSettle();
    expect(logoutCount, 0);
    expect(find.text('确认退出当前账号？'), findsNothing);
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byTooltip('退出登录'),
              matching: find.byIcon(Icons.logout),
            ),
          )
          .color,
      ui.UiColors.textMuted,
    );

    await tester.tap(find.byTooltip('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ui.Button, '退出登录'));
    await tester.pumpAndSettle();
    expect(logoutCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated home shell lets sidebar scrollbar auto-hide', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Center(
          child: SizedBox(
            width: 420,
            height: 190,
            child: HomePage(
              app: _homeTestAppContext(),
              realtime: _NoopRealtimeService(),
            ),
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

    expect(userSummaryRect.right - alphaCardRect.right, closeTo(0, 0.01));
    expect(find.byType(Scrollbar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated home shell keeps macOS sidebar below title bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme().copyWith(platform: TargetPlatform.macOS),
        home: HomePage(
          app: _homeTestAppContext(),
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final userSummaryRect = tester.getRect(
      find.byKey(const ValueKey('home-sidebar-user-summary')),
    );
    final searchRect = tester.getRect(
      find.byKey(const ValueKey('home-title-search')),
    );

    expect(find.text('Gang Chat'), findsNothing);
    expect(find.byTooltip('最小化'), findsNothing);
    expect(find.byTooltip('最大化'), findsNothing);
    expect(find.byTooltip('关闭'), findsNothing);
    expect(searchRect.center.dx, closeTo(400, 0.01));
    expect(userSummaryRect.top, closeTo(60, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'authenticated home shell opens chat content from narrow server list',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ui.uiTheme(),
          home: Center(
            child: SizedBox(
              width: 420,
              height: 620,
              child: HomePage(
                app: _homeTestAppContext(),
                realtime: _NoopRealtimeService(),
              ),
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
      expect(find.byTooltip('Show servers'), findsNothing);
      expect(find.text('进入语音频道'), findsOneWidget);
      expect(find.text('Hello from Morgan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('auth login layout is stable across rebuilds', (
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
      find.widgetWithText(ui.Button, '登录'),
    );
    final regularCursorColor = Theme.of(
      tester.element(find.byKey(const ValueKey('auth-surface'))),
    ).textSelectionTheme.cursorColor;

    await tester.pumpWidget(GangApp(tokenStore: _MemoryTokenStore()));
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
      tester.getRect(find.widgetWithText(ui.Button, '登录')),
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
    expect(find.text('用户名或邮箱地址'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.byTooltip('显示密码'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '登录'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);

    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();

    expect(find.byTooltip('隐藏密码'), findsOneWidget);
  });

  testWidgets('switching to register reveals additional fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(GangApp(tokenStore: _MemoryTokenStore()));
    await tester.pump();

    await tester.tap(find.text('注册'));
    await tester.pump();

    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('邮箱地址'), findsOneWidget);
    expect(find.text('确认密码'), findsOneWidget);
    expect(find.byTooltip('显示密码'), findsNWidgets(2));
    expect(find.widgetWithText(ui.Button, '创建账号'), findsOneWidget);

    await tester.tap(find.byTooltip('显示密码').first);
    await tester.pump();

    expect(find.byTooltip('隐藏密码'), findsOneWidget);
    expect(find.byTooltip('显示密码'), findsOneWidget);
  });

  testWidgets('submitting empty form surfaces inline error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(GangApp(tokenStore: _MemoryTokenStore()));
    await tester.pump();

    await tester.tap(find.widgetWithText(ui.Button, '登录'));
    await tester.pump();

    expect(find.text('请输入账号和密码后继续'), findsOneWidget);
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
      find.descendant(
        of: find.byType(ui.SegmentedControl<String>),
        matching: find.byType(ui.PressableSurface),
      ),
      findsNWidgets(2),
    );
    final surfaces = tester
        .widgetList<ui.PressableSurface>(
          find.descendant(
            of: find.byType(ui.SegmentedControl<String>),
            matching: find.byType(ui.PressableSurface),
          ),
        )
        .toList();
    expect(surfaces.first.backgroundColor, ui.UiColors.background);
    expect(surfaces.first.selectedBackgroundColor, ui.UiColors.selected);
    expect(surfaces.first.pressedBackgroundColor, ui.UiColors.surfaceLow);
    expect(surfaces.first.selected, isTrue);
    expect(surfaces.last.selected, isFalse);
    expect(
      tester.widget<Text>(find.text('Chat')).style?.color,
      ui.UiColors.controlAccent,
    );
    expect(
      tester.widget<Text>(find.text('Forms')).style?.color,
      ui.UiColors.textSecondary,
    );
    expect(
      tester.widget<Text>(find.text('Chat')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester.widget<Text>(find.text('Forms')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(
      tester.getSize(find.byType(ui.SegmentedControl<String>)).width,
      lessThan(192),
    );
    expect(
      tester.getSize(find.byType(ui.SegmentedControl<String>)).height,
      closeTo(42, 0.01),
    );
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
      matching: find.byType(AnimatedPadding),
    );
    expect(animatedCapFinder, findsOneWidget);
    final animatedCap = tester.widget<AnimatedPadding>(animatedCapFinder);
    expect(animatedCap.duration, const Duration(milliseconds: 95));
    expect(animatedCap.curve, Curves.easeOutCubic);
    expect((animatedCap.padding as EdgeInsets).top, closeTo(3, 0.01));
    expect((animatedCap.padding as EdgeInsets).bottom, closeTo(5, 0.01));

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
      (tester.widget<AnimatedPadding>(animatedCapFinder).padding as EdgeInsets)
          .top,
      closeTo(3, 0.01),
    );
    inputDecorations = _inputLayerDecorations(tester, inputFinder);
    expect(_topBorderColor(inputDecorations.first), ui.UiColors.accentBorder);
    expect(_topBorderColor(inputDecorations.last), ui.UiColors.accentBorder);
    expect(inputDecorations.last.color, ui.UiColors.selected);

    focusNode.unfocus();
    await tester.pumpAndSettle();

    expect(
      (tester.widget<AnimatedPadding>(animatedCapFinder).padding as EdgeInsets)
          .top,
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

    expect(
      (tester.widget<AnimatedPadding>(animatedCapFinder).padding as EdgeInsets)
          .top,
      closeTo(0, 0.01),
    );
    expect(
      (tester.widget<AnimatedPadding>(animatedCapFinder).padding as EdgeInsets)
          .bottom,
      closeTo(8, 0.01),
    );

    inputDecorations = _inputLayerDecorations(tester, inputFinder);
    expect(_topBorderColor(inputDecorations.first), ui.UiColors.border);
    expect(_topBorderColor(inputDecorations.last), ui.UiColors.border);
    expect(inputDecorations.last.color, ui.UiColors.surface);

    await tester.pumpAndSettle();
    expect(
      (tester.widget<AnimatedPadding>(animatedCapFinder).padding as EdgeInsets)
          .top,
      closeTo(0, 0.01),
    );

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

  testWidgets('ui input grows without an internal line cap', (
    WidgetTester tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ui.Input(
                controller: controller,
                hintText: 'Description',
                prefixIcon: Icons.notes_outlined,
                maxLines: null,
              ),
            ),
          ),
        ),
      ),
    );

    TextField textField() =>
        tester.widget<TextField>(_textFieldWithHint('Description'));

    expect(textField().minLines, 1);
    expect(textField().maxLines, isNull);
    final initialHeight = tester.getSize(find.byType(ui.Input)).height;

    await tester.enterText(
      _textFieldWithHint('Description'),
      'One two three four five six seven eight nine ten eleven twelve '
      'thirteen fourteen fifteen sixteen seventeen eighteen.',
    );
    await tester.pumpAndSettle();

    expect(textField().maxLines, isNull);
    expect(
      tester.getSize(find.byType(ui.Input)).height,
      greaterThan(initialHeight * 2),
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

  testWidgets('ui switch toggles and keeps custom surface', (
    WidgetTester tester,
  ) async {
    var enabled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                return ui.UiSwitch(
                  value: enabled,
                  onChanged: (value) => setState(() => enabled = value),
                );
              },
            ),
          ),
        ),
      ),
    );

    final switchFinder = find.byType(ui.UiSwitch);
    expect(switchFinder, findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(
      find.descendant(of: switchFinder, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(tester.getSize(switchFinder), const Size(56, 32));

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(enabled, isTrue);
    final decorations = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: switchFinder,
            matching: find.byType(DecoratedBox),
          ),
        )
        .where((box) => box.decoration is BoxDecoration)
        .map((box) => box.decoration as BoxDecoration)
        .toList();
    expect(
      decorations.any((decoration) => decoration.color == ui.UiColors.selected),
      isTrue,
    );

    final switchRect = tester.getRect(switchFinder);
    final gesture = await tester.startGesture(
      switchRect.center,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(switchRect.center + const Offset(12, 4));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(enabled, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: const Scaffold(
          body: Center(child: ui.UiSwitch(value: true, onChanged: null)),
        ),
      ),
    );
    await tester.tap(switchFinder);
    await tester.pump();

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
                        alignment: ui.ComposerActionAlignment.trailing,
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
    // Input spans the full composer width on its own row.
    expect(initialInputRect.left, closeTo(composerRect.left + 12, 0.01));
    expect(initialInputRect.right, closeTo(composerRect.right - 12, 0.01));
    // Actions sit on a row below the input: stickers pinned left, send right.
    expect(stickerRect.top, greaterThan(initialInputRect.bottom));
    expect(sendRect.top, greaterThan(initialInputRect.bottom));
    expect(stickerRect.left, closeTo(composerRect.left + 12, 0.01));
    expect(sendRect.right, closeTo(composerRect.right - 12, 0.01));
    expect(
      ui.Input.defaultHeight,
      tester.widget<ui.PressableSurface>(sendSurfaceFinder).height,
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

    final hoveredInputCap = tester.widget<AnimatedPadding>(
      find.descendant(of: inputFinder, matching: find.byType(AnimatedPadding)),
    );
    expect((hoveredInputCap.padding as EdgeInsets).top, closeTo(0, 0.01));

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
    // The input grows taller while the action row (with send) stays below it.
    expect(multilineInputRect.height, greaterThan(multilineSendRect.height));
    expect(multilineSendRect.top, greaterThan(multilineInputRect.bottom));

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
      containsAllInOrder([
        ui.UiColors.selectedBorder,
        ui.UiColors.dangerBorder,
      ]),
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

  testWidgets('embedded settings page exposes a back button', (
    WidgetTester tester,
  ) async {
    var closeCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(isSubWindow: true, onClose: () => closeCount += 1),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('返回'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pump();

    expect(closeCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings scaffold keeps main header in the old left layout', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 480);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: SettingsPage(isSubWindow: true, onClose: () {}),
      ),
    );
    await tester.pump();

    final titleRect = tester.getRect(find.text('设置'));
    expect(titleRect.left, lessThan(140));
    expect(tester.takeException(), isNull);
  });

  testWidgets('segmented control centers labels inside each segment', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(300, 120);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: Center(
          child: SizedBox(
            width: 300,
            child: ui.SegmentedControl<int>(
              expanded: true,
              value: 0,
              onChanged: (_) {},
              segments: const [
                ui.Segment(value: 0, label: 'A'),
                ui.Segment(value: 1, label: 'B'),
                ui.Segment(value: 2, label: 'C'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final label in ['A', 'B', 'C']) {
      final segment = find.ancestor(
        of: find.text(label),
        matching: find.byType(ui.PressableSurface),
      );
      expect(
        tester.getRect(find.text(label)).center.dx,
        closeTo(tester.getRect(segment).center.dx, 1),
      );
    }
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

Finder _textFieldWithHint(String hintText) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hintText,
  );
}

Finder _highlightedSearchText(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is ui.HighlightedText && widget.text.contains(text),
  );
}

Finder _buttonIconWithTooltip(String tooltip) {
  return find.byWidgetPredicate(
    (widget) => widget is ui.ButtonIcon && widget.tooltip == tooltip,
  );
}

Finder _liveControl(String id) {
  return find.byKey(ValueKey<String>('live-control:$id'));
}

void _expectLiveVolumeFill(WidgetTester tester, String label, double volume) {
  final slider = find.byKey(ValueKey<String>('live-volume-slider:$label'));
  final thumb = find.byKey(ValueKey<String>('live-volume-thumb:$label'));
  final fill = find.byKey(ValueKey<String>('live-volume-fill:$label'));
  expect(slider, findsOneWidget);
  expect(thumb, findsOneWidget);
  expect(fill, findsOneWidget);

  final sliderRect = tester.getRect(slider);
  final thumbRect = tester.getRect(thumb);
  final fillRect = tester.getRect(fill);
  final expectedHeight = (sliderRect.height - thumbRect.height) * volume;
  expect(fillRect.height, closeTo(expectedHeight, 1.0));
}

void _expectRectCloseTo(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 0.01));
  expect(actual.top, closeTo(expected.top, 0.01));
  expect(actual.right, closeTo(expected.right, 0.01));
  expect(actual.bottom, closeTo(expected.bottom, 0.01));
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
  Future<void> Function()? onExitSessionForAppExit,
  List<String>? requestedPaths,
  List<Uri>? requestedUris,
  List<Map<String, Object?>>? accountUpdates,
  List<Map<String, Object?>>? roomCreations,
  List<Map<String, Object?>>? liveJoinRequests,
  List<Map<String, Object?>>? liveStateUpdates,
  List<String>? liveModerationActions,
  String currentRoomRole = 'owner',
  String currentRoomJoinPolicy = 'approval_required',
  bool currentUserIsSuperuser = false,
  String secondaryMemberRole = 'member',
  bool includeActionComparisonMember = false,
  Future<void> Function(String roomId)? beforeRoomDetailResponse,
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
    isSuperuser: currentUserIsSuperuser,
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
    exitSessionForAppExit: onExitSessionForAppExit ?? () async {},
    api: _roomsApi(
      requestedPaths: requestedPaths,
      requestedUris: requestedUris,
      accountUpdates: accountUpdates,
      roomCreations: roomCreations,
      liveJoinRequests: liveJoinRequests,
      liveStateUpdates: liveStateUpdates,
      liveModerationActions: liveModerationActions,
      currentRoomRole: currentRoomRole,
      currentRoomJoinPolicy: currentRoomJoinPolicy,
      secondaryMemberRole: secondaryMemberRole,
      includeActionComparisonMember: includeActionComparisonMember,
      beforeRoomDetailResponse: beforeRoomDetailResponse,
    ),
  );
}

GangApi _roomsApi({
  List<String>? requestedPaths,
  List<Uri>? requestedUris,
  List<Map<String, Object?>>? accountUpdates,
  List<Map<String, Object?>>? roomCreations,
  List<Map<String, Object?>>? liveJoinRequests,
  List<Map<String, Object?>>? liveStateUpdates,
  List<String>? liveModerationActions,
  String currentRoomRole = 'owner',
  String currentRoomJoinPolicy = 'approval_required',
  String secondaryMemberRole = 'member',
  bool includeActionComparisonMember = false,
  Future<void> Function(String roomId)? beforeRoomDetailResponse,
}) {
  return GangApiClient(
    baseUrl: 'http://example.test/api/v1',
    accessTokenProvider: ({bool forceRefresh = false}) async => 'access-token',
    httpClient: MockClient((request) async {
      requestedPaths?.add(request.url.path);
      requestedUris?.add(request.url);
      if (request.url.path == '/api/v1/rooms') {
        if (request.method == 'POST') {
          final body =
              jsonDecode(utf8.decode(request.bodyBytes))
                  as Map<String, Object?>;
          final created = {
            ...body,
            'id': 'server-created-${(roomCreations?.length ?? 0) + 1}',
          };
          roomCreations?.add(created);
          return _jsonResponse({
            'room': _roomDetailJson(
              id: created['id']! as String,
              name: body['name']! as String,
              memberCount: 1,
              onlineMemberCount: 1,
              liveParticipantCount: 0,
              description: body['description'] as String? ?? '',
              visibility: body['visibility'] as String? ?? 'public',
              joinPolicy: body['join_policy'] as String? ?? 'approval_required',
              aiVoiceAnnouncementsEnabled:
                  body['ai_voice_announcements_enabled'] as bool? ?? true,
            ),
          });
        }
        return _jsonResponse({
          'rooms': [
            for (final created in roomCreations ?? const [])
              _roomCardJson(
                id: created['id']! as String,
                name: created['name']! as String,
                memberCount: 1,
              ),
            ..._serverListJson(currentRoomJoinPolicy: currentRoomJoinPolicy),
          ],
        });
      }
      if (request.url.path == '/api/v1/search') {
        final query = request.url.queryParameters['q']?.toLowerCase() ?? '';
        Map<String, Object?> pagedMessage(int index) {
          return {
            'room': _searchRoomContextJson(
              id: 'server-page',
              name: 'Paged Room',
            ),
            'message': _messageJson(
              id: 'msg-page-$index',
              roomId: 'server-page',
              sender: _userJson(
                id: 'user-2',
                username: 'morgan',
                displayName: 'Morgan',
              ),
              clientMessageId: 'client-msg-page-$index',
              body: 'Page result $index',
            ),
          };
        }

        if (query == 'page') {
          if (request.url.queryParameters['messages_cursor'] ==
              'message-cursor-8') {
            return _jsonResponse({
              'my_rooms': <Object?>[],
              'public_rooms': <Object?>[],
              'messages': [pagedMessage(9)],
              'files': <Object?>[],
              'next_cursors': {
                'my_rooms': null,
                'public_rooms': null,
                'messages': null,
                'files': null,
              },
              'total_counts': {
                'my_rooms': 0,
                'public_rooms': 0,
                'messages': 9,
                'files': 0,
              },
            });
          }
          return _jsonResponse({
            'my_rooms': <Object?>[],
            'public_rooms': <Object?>[],
            'messages': [
              for (var index = 1; index <= 8; index += 1) pagedMessage(index),
            ],
            'files': <Object?>[],
            'next_cursors': {
              'my_rooms': null,
              'public_rooms': null,
              'messages': 'message-cursor-8',
              'files': null,
            },
            'total_counts': {
              'my_rooms': 0,
              'public_rooms': 0,
              'messages': 9,
              'files': 0,
            },
          });
        }
        if (query == '1') {
          return _jsonResponse({
            'my_rooms': [
              {
                ..._roomCardJson(
                  id: 'server-beta',
                  name: 'Beta Room',
                  memberCount: 5,
                ),
                'description': '12345',
              },
            ],
            'public_rooms': <Object?>[],
            'messages': <Object?>[],
            'files': <Object?>[],
            'next_cursors': {
              'my_rooms': null,
              'public_rooms': null,
              'messages': null,
              'files': null,
            },
          });
        }
        return _jsonResponse({
          'my_rooms': [
            _roomCardJson(id: 'server-beta', name: 'Beta Room', memberCount: 5),
          ],
          'public_rooms': [
            {
              ..._roomCardJson(
                id: 'server-public',
                name: 'Beta Public',
                memberCount: 2,
              ),
              'visibility': 'public',
              'join_policy': 'open',
              'joined': false,
              'join_state': 'none',
            },
          ],
          'messages': [
            {
              'room': _searchRoomContextJson(
                id: 'server-beta',
                name: 'Beta Room',
              ),
              'message': _messageJson(
                id: 'msg-beta',
                roomId: 'server-beta',
                sender: _userJson(
                  id: 'user-2',
                  username: 'morgan',
                  displayName: 'Morgan',
                ),
                clientMessageId: 'client-msg-beta',
                body: 'Beta release notes',
              ),
            },
          ],
          'files': [
            {
              'room': _searchRoomContextJson(
                id: 'server-beta',
                name: 'Beta Room',
              ),
              'message': {
                ..._messageJson(
                  id: 'msg-file-beta',
                  roomId: 'server-beta',
                  sender: _currentUserJson,
                  clientMessageId: 'client-msg-file-beta',
                  body: 'Beta brief.pdf',
                ),
                'type': 'file',
                'attachments': [
                  {
                    'type': 'file',
                    'name': 'Beta brief.pdf',
                    'asset': {
                      'id': 'asset-beta',
                      'url': '/assets/beta.pdf',
                      'thumbnail_url': null,
                      'mime_type': 'application/pdf',
                      'filename': 'Beta brief.pdf',
                      'size_bytes': 1024,
                    },
                  },
                ],
              },
            },
          ],
          'next_cursors': {
            'my_rooms': null,
            'public_rooms': null,
            'messages': null,
            'files': null,
          },
        });
      }
      if (request.url.path.startsWith('/api/v1/rooms/') &&
          request.url.path.endsWith('/read')) {
        expect(request.method, 'POST');
        final body =
            jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, Object?>;
        expect(body['last_read_message_id'], isA<String>());
        return _jsonResponse({'ok': true, 'unread_count': 0});
      }
      if (request.url.path == '/api/v1/rooms/server-beta') {
        await beforeRoomDetailResponse?.call('server-beta');
        return _jsonResponse({
          'room': _roomDetailJson(
            id: 'server-beta',
            name: 'Beta Room',
            memberCount: 5,
            onlineMemberCount: 1,
            liveParticipantCount: 0,
            visibility: 'private',
            joinPolicy: 'closed',
            role: 'member',
            createdBy: _userJson(
              id: 'user-2',
              username: 'morgan',
              displayName: 'Morgan',
              isOnline: true,
            ),
          ),
        });
      }
      if (request.url.path ==
          '/api/v1/rooms/server-beta/members/user-2/profile') {
        return _jsonResponse({
          'profile': {
            'user': {
              ..._userJson(
                id: 'user-2',
                username: 'morgan',
                displayName: 'Morgan',
                isOnline: true,
              ),
              'bio': 'Creator profile',
              'common_rooms': [
                {
                  'id': 'server-alpha',
                  'rid': 'server-alpha',
                  'name': 'Shared Alpha',
                  'visibility': 'private',
                  'default_avatar_key': 'room-1',
                  'room_role': 'member',
                },
              ],
            },
            'room_display_name': 'Morgan Creator',
            'role': 'owner',
            'joined_at': '2026-06-01T00:00:00Z',
          },
        });
      }
      if (request.url.path ==
          '/api/v1/rooms/server-alpha/members/user-2/profile') {
        return _jsonResponse({
          'profile': {
            'user': _userJson(
              id: 'user-2',
              username: 'morgan',
              displayName: 'Morgan',
              uid: 'uid-2',
              isOnline: true,
            ),
            'role': 'member',
            'joined_at': '2026-06-01T00:00:00Z',
          },
        });
      }
      if (request.url.path == '/api/v1/rooms/server-public/join') {
        return _jsonResponse({
          'room': _roomDetailJson(
            id: 'server-public',
            name: 'Beta Public',
            memberCount: 3,
            onlineMemberCount: 1,
            liveParticipantCount: 0,
            visibility: 'public',
            joinPolicy: 'open',
            role: 'member',
          ),
        });
      }
      if (request.url.path == '/api/v1/users/me/account') {
        final body =
            jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, Object?>;
        accountUpdates?.add(body);
        return _jsonResponse({
          'user': {..._currentUserJson, ...body},
        });
      }
      if (request.url.path == '/api/v1/rooms/server-alpha') {
        if (request.method == 'PATCH') {
          final body =
              jsonDecode(utf8.decode(request.bodyBytes))
                  as Map<String, Object?>;
          return _jsonResponse({
            'room': _roomDetailJson(
              id: 'server-alpha',
              name: body['name']! as String,
              memberCount: 2,
              onlineMemberCount: 1,
              liveParticipantCount: 1,
              description: body['description'] as String? ?? '',
              visibility: body['visibility'] as String? ?? 'private',
              joinPolicy:
                  body['join_policy'] as String? ?? currentRoomJoinPolicy,
              aiVoiceAnnouncementsEnabled:
                  body['ai_voice_announcements_enabled'] as bool? ?? true,
            ),
          });
        }
        await beforeRoomDetailResponse?.call('server-alpha');
        return _jsonResponse({
          'room': _roomDetailJson(
            id: 'server-alpha',
            name: 'Alpha Room',
            memberCount: 2,
            onlineMemberCount: 1,
            liveParticipantCount: 1,
            joinPolicy: currentRoomJoinPolicy,
            role: currentRoomRole,
          ),
        });
      }
      if (request.url.path == '/api/v1/rooms/server-alpha/members') {
        return _jsonResponse({
          'members': [
            _roomMemberJson(user: _currentUserJson, role: currentRoomRole),
            _roomMemberJson(
              user: _userJson(
                id: 'user-2',
                username: 'morgan',
                displayName: 'Morgan',
                uid: 'uid-2',
                isOnline: true,
              ),
              role: secondaryMemberRole,
            ),
            if (includeActionComparisonMember)
              _roomMemberJson(
                user: _userJson(
                  id: 'user-5',
                  username: 'taylor',
                  displayName: 'Taylor',
                  uid: 'uid-5',
                  isOnline: false,
                ),
                role: 'member',
              ),
          ],
          'next_cursor': null,
        });
      }
      if (request.url.path == '/api/v1/rooms/server-alpha/members/user-2') {
        if (request.method == 'PATCH') {
          return _jsonResponse({
            'member': _roomMemberJson(
              user: _userJson(
                id: 'user-2',
                username: 'morgan',
                displayName: 'Morgan',
                isOnline: true,
              ),
              role: 'admin',
            ),
          });
        }
        if (request.method == 'DELETE') {
          return _jsonResponse({'ok': true});
        }
      }
      if (request.url.path ==
          '/api/v1/rooms/server-alpha/live/participants/user-2/moderation') {
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, Object?>;
        liveModerationActions?.add(body['action']! as String);
        expect(
          body['action'],
          isIn([
            'kick',
            'mute_mic',
            'block_voice',
            'restore_voice',
            'restore_headphones',
          ]),
        );
        return _jsonResponse({'ok': true});
      }
      if (request.url.path == '/api/v1/rooms/server-alpha/join-requests') {
        return _jsonResponse({
          'requests': [
            _joinRequestJson(
              id: 'join-request-riley',
              reason: 'Please approve my request',
              user: _userJson(
                id: 'user-3',
                username: 'riley',
                displayName: 'Riley',
                uid: '10000001',
                isOnline: true,
              ),
            ),
          ],
        });
      }
      if (request.url.path ==
          '/api/v1/rooms/server-alpha/join-requests/join-request-riley') {
        return _jsonResponse({});
      }
      if (request.url.path == '/api/v1/users/search') {
        return _jsonResponse({
          'users': [
            _userJson(
              id: 'user-3',
              username: 'riley',
              displayName: 'Riley',
              isOnline: true,
            ),
            _userJson(
              id: 'user-5',
              username: 'river',
              displayName: 'River',
              isOnline: true,
            ),
            _userJson(
              id: 'user-6',
              username: 'rina',
              displayName: 'Rina',
              isOnline: true,
            ),
            _userJson(
              id: 'user-7',
              username: 'riko',
              displayName: 'Riko',
              isOnline: true,
            ),
            _userJson(
              id: 'user-8',
              username: 'rita',
              displayName: 'Rita',
              isOnline: true,
            ),
          ],
        });
      }
      if (request.url.path == '/api/v1/rooms/server-alpha/invites') {
        return _jsonResponse({'invite': _roomInviteJson(id: 'invite-riley')});
      }
      if (request.url.path == '/api/v1/room-invites') {
        return _jsonResponse({
          'invites': [
            _roomInviteJson(
              joinPolicy: 'approval_required',
              inviter: _userJson(
                id: 'user-2',
                username: 'morgan',
                displayName: 'Morgan',
              ),
              inviterRoomRole: 'member',
              inviterRoomDisplayName: 'Morgan Member',
            ),
            _roomInviteJson(
              id: 'invite-invalid',
              inviter: _userJson(
                id: 'user-left',
                username: 'lefty',
                displayName: 'Lefty',
              ),
              inviterRoomRole: 'left',
              inviterRoomDisplayName: 'Lefty',
              invalidReason: 'inviter_left',
            ),
          ],
          'next_cursor': null,
        });
      }
      if (request.url.path == '/api/v1/room-applications') {
        return _jsonResponse({
          'applications': [
            _roomApplicationJson(id: 'application-alpha'),
            _roomApplicationJson(
              id: 'application-approved',
              status: 'approved',
              createdAt: '2026-06-04T08:00:00Z',
              updatedAt: '2026-06-07T08:00:00Z',
              reviewedAt: '2026-06-07T08:00:00Z',
              reviewer: {
                ..._userJson(id: 'user-4', username: 'ivy', displayName: 'Ivy'),
                'room_display_name': 'Ivy Owner',
                'room_role': 'owner',
              },
            ),
          ],
          'next_cursor': null,
        });
      }
      if (request.url.path == '/api/v1/room-notifications') {
        return _jsonResponse({'notifications': [], 'next_cursor': null});
      }
      if (request.url.path == '/api/v1/room-applications/application-alpha') {
        return _jsonResponse({
          'ok': true,
          'application': _roomApplicationJson(
            id: 'application-alpha',
            status: 'withdrawn',
          ),
        });
      }
      if (request.url.path == '/api/v1/room-invites/invite-alpha') {
        return _jsonResponse({
          'ok': true,
          'invite': _roomInviteJson(status: 'accepted'),
          'join_request': {
            'id': 'join-request-alpha',
            'room_id': 'server-alpha',
            'status': 'pending',
            'reason': 'I was invited',
            'created_at': '2026-06-05T08:00:00Z',
          },
        });
      }
      if (request.url.path == '/api/v1/rooms/server-alpha/messages') {
        if (request.method == 'POST') {
          final body =
              jsonDecode(utf8.decode(request.bodyBytes))
                  as Map<String, Object?>;
          return _jsonResponse({
            'message': _messageJson(
              id: 'msg-sent',
              roomId: 'server-alpha',
              sender: _currentUserJson,
              clientMessageId: body['client_message_id']! as String,
              body: body['body']! as String,
            ),
          });
        }
        return _jsonResponse({
          'messages': [
            _messageJson(
              id: 'msg-1',
              roomId: 'server-alpha',
              sender: _userJson(
                id: 'user-2',
                username: 'morgan',
                displayName: 'Morgan',
                uid: 'uid-2',
                isOnline: true,
              ),
              clientMessageId: 'client-msg-1',
              body: 'Hello from Morgan',
            ),
            _messageJson(
              id: 'msg-2',
              roomId: 'server-alpha',
              sender: _currentUserJson,
              clientMessageId: 'client-msg-2',
              body: 'Reply from Kai',
            ),
          ],
          'has_more': false,
          'next_before': null,
        });
      }
      if (request.url.path == '/api/v1/rooms/server-alpha/live') {
        return _jsonResponse({
          'live': _liveStateJson(
            roomId: 'server-alpha',
            participantCount: 1,
            participants: [
              _liveParticipantJson(
                user: _userJson(
                  id: 'user-2',
                  username: 'morgan',
                  displayName: 'Morgan',
                ),
                liveSessionId: 'live-session-morgan',
                micMuted: true,
              ),
            ],
          ),
        });
      }
      if (request.url.path == '/api/v1/rooms/server-alpha/live/join') {
        liveJoinRequests?.add(
          jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, Object?>,
        );
        final participant = _liveParticipantJson(
          user: _currentUserJson,
          liveSessionId: 'live-session-joined',
        );
        return _jsonResponse({
          'livekit': {
            'server_url': 'ws://live.example.test',
            'token': 'live-token',
            'token_expires_at': '2026-06-05T09:00:00Z',
            'room_name': 'room_server_alpha',
          },
          'participant': participant,
          'live': _liveStateJson(
            roomId: 'server-alpha',
            participantCount: 2,
            participants: [
              participant,
              _liveParticipantJson(
                user: _userJson(
                  id: 'user-2',
                  username: 'morgan',
                  displayName: 'Morgan',
                ),
                liveSessionId: 'live-session-morgan',
                micMuted: true,
              ),
            ],
          ),
        });
      }
      if (request.url.path == '/api/v1/rooms/server-alpha/live/me') {
        final body =
            jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, Object?>;
        liveStateUpdates?.add(body);
        return _jsonResponse({
          'participant': _liveParticipantJson(
            user: _currentUserJson,
            liveSessionId: 'live-session-joined',
            micMuted: body['mic_muted'] as bool? ?? false,
            cameraOn: body['camera_on'] as bool? ?? false,
            screenSharing: body['screen_sharing'] as bool? ?? false,
          ),
        });
      }
      if (request.url.path == '/api/v1/me') {
        return _jsonResponse(_currentUserJson);
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

List<Map<String, Object?>> _serverListJson({
  String currentRoomJoinPolicy = 'approval_required',
}) {
  return [
    _roomCardJson(
      id: 'server-alpha',
      name: 'Alpha Room',
      memberCount: 2,
      liveParticipantCount: 1,
      unreadCount: 3,
      joinPolicy: currentRoomJoinPolicy,
    ),
    _roomCardJson(id: 'server-beta', name: 'Beta Room', memberCount: 5),
  ];
}

final _currentUserJson = {
  'id': 'user-1',
  'uid': 'uid-1',
  'username': 'kai',
  'display_name': 'Kai',
  'bio': '',
  'gender': 'secret',
  'email': 'kai@example.com',
  'email_public': false,
  'phone_number': null,
  'phone_number_public': false,
  'avatar_url': null,
  'default_avatar_key': 'blue-3',
  'is_superuser': false,
  'created_at': '2026-01-01T00:00:00Z',
  'status': 'active',
  'language': 'zh-Hans',
};

Map<String, Object?> _roomDetailJson({
  required String id,
  required String name,
  required int memberCount,
  required int onlineMemberCount,
  required int liveParticipantCount,
  String description = '',
  String visibility = 'private',
  String joinPolicy = 'approval_required',
  bool aiVoiceAnnouncementsEnabled = true,
  String role = 'owner',
  Map<String, Object?>? createdBy,
}) {
  return {
    ..._roomCardJson(
      id: id,
      name: name,
      memberCount: memberCount,
      liveParticipantCount: liveParticipantCount,
    ),
    'online_member_count': onlineMemberCount,
    'description': description,
    'visibility': visibility,
    'join_policy': joinPolicy,
    'ai_voice_announcements_enabled': aiVoiceAnnouncementsEnabled,
    'my_membership': {'joined_at': '2026-06-01T00:00:00Z', 'role': role},
    'created_by': createdBy ?? _currentUserJson,
    'live': _liveStateJson(roomId: id, participantCount: liveParticipantCount),
    'created_at': '2026-06-01T00:00:00Z',
  };
}

Map<String, Object?> _messageJson({
  required String id,
  required String roomId,
  required Map<String, Object?> sender,
  required String clientMessageId,
  required String body,
}) {
  return {
    'id': id,
    'room_id': roomId,
    'sender': sender,
    'client_message_id': clientMessageId,
    'type': 'text',
    'body': body,
    'attachments': <Object?>[],
    'created_at': '2026-06-05T08:00:00Z',
  };
}

Map<String, Object?> _liveStateJson({
  required String roomId,
  required int participantCount,
  List<Object?>? participants,
}) {
  final participantList =
      participants ??
      (participantCount <= 0
          ? <Object?>[]
          : [
              _liveParticipantJson(
                user: _currentUserJson,
                liveSessionId: 'live-session-1',
              ),
            ]);
  return {
    'room_id': roomId,
    'participant_count': participantCount,
    'participants': participantList,
    'updated_at': '2026-06-05T08:00:00Z',
  };
}

Map<String, Object?> _liveParticipantJson({
  required Map<String, Object?> user,
  required String liveSessionId,
  bool micMuted = false,
  bool micBlocked = false,
  bool headphonesMuted = false,
  bool headphonesBlocked = false,
  bool voiceBlocked = false,
  bool cameraOn = false,
  bool screenSharing = false,
}) {
  return {
    'live_session_id': liveSessionId,
    'user': user,
    'joined_at': '2026-06-05T08:00:00Z',
    'mic_muted': micMuted,
    'mic_blocked': micBlocked,
    'headphones_muted': headphonesMuted,
    'headphones_blocked': headphonesBlocked,
    'headphones_listening': !headphonesMuted && !headphonesBlocked,
    'voice_blocked': voiceBlocked,
    'camera_on': cameraOn,
    'screen_sharing': screenSharing,
    'connection_state': 'connected',
  };
}

Map<String, Object?> _roomMemberJson({
  required Map<String, Object?> user,
  String role = 'member',
}) {
  return {
    'user': user,
    'role': role,
    'joined_at': '2026-06-01T00:00:00Z',
    'is_online': user['is_online'] as bool? ?? false,
  };
}

Map<String, Object?> _joinRequestJson({
  required String id,
  required Map<String, Object?> user,
  String? reason,
}) {
  final json = <String, Object?>{
    'id': id,
    'status': 'pending',
    'user': user,
    'created_at': '2026-06-05T08:00:00Z',
  };
  if (reason != null) json['reason'] = reason;
  return json;
}

Map<String, Object?> _userJson({
  required String id,
  required String username,
  required String displayName,
  String? uid,
  bool? isOnline,
}) {
  final json = <String, Object?>{
    'id': id,
    'username': username,
    'display_name': displayName,
    'avatar_url': null,
    'default_avatar_key': 'blue-3',
  };
  if (uid != null) json['uid'] = uid;
  if (isOnline != null) json['is_online'] = isOnline;
  return json;
}

Map<String, Object?> _roomCardJson({
  required String id,
  required String name,
  String joinPolicy = 'approval_required',
  int memberCount = 1,
  int liveParticipantCount = 0,
  int unreadCount = 0,
}) {
  return {
    'id': id,
    'name': name,
    'rid': id,
    'visibility': 'private',
    'join_policy': joinPolicy,
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

Map<String, Object?> _searchRoomContextJson({
  required String id,
  required String name,
}) {
  return {
    'id': id,
    'rid': id,
    'name': name,
    'avatar_url': null,
    'default_avatar_key': 'room-1',
  };
}

Map<String, Object?> _roomInviteJson({
  String id = 'invite-alpha',
  String status = 'pending',
  Map<String, Object?>? inviter,
  String inviterRoomRole = 'admin',
  String inviterRoomDisplayName = 'Morgan Admin',
  String joinPolicy = 'closed',
  bool roomExists = true,
  String? invalidReason,
}) {
  return {
    'id': id,
    'status': status,
    'room_exists': roomExists,
    'invalid_reason': invalidReason,
    'room': {
      ..._roomCardJson(
        id: 'server-alpha',
        name: 'Alpha Room',
        memberCount: 2,
        liveParticipantCount: 1,
      ),
      'join_policy': joinPolicy,
      'joined': false,
      'join_state': 'none',
    },
    'inviter': {
      ...(inviter ?? _currentUserJson),
      'room_display_name': inviterRoomDisplayName,
      'room_role': inviterRoomRole,
    },
    'created_at': '2026-06-05T08:00:00Z',
    'updated_at': '2026-06-05T08:00:00Z',
  };
}

Map<String, Object?> _roomApplicationJson({
  String id = 'application-alpha',
  String status = 'pending',
  String createdAt = '2026-06-06T08:00:00Z',
  String updatedAt = '2026-06-06T08:00:00Z',
  String? reviewedAt,
  Map<String, Object?>? reviewer,
}) {
  return {
    'id': id,
    'status': status,
    'room': {
      ..._roomCardJson(
        id: 'server-alpha',
        name: 'Alpha Room',
        memberCount: 2,
        liveParticipantCount: 1,
      ),
      'join_policy': 'approval_required',
      'joined': false,
      'join_state': status == 'pending' ? 'pending' : 'none',
    },
    'created_at': createdAt,
    'updated_at': updatedAt,
    'reviewed_at': reviewedAt,
    'reviewer': reviewer,
  };
}

class _FakeSettingsAudioDeviceService extends LiveAudioDeviceService {
  const _FakeSettingsAudioDeviceService();

  static const _input = AudioDeviceInfo(
    deviceId: 'input-1',
    label: 'Input 1',
    kind: 'audioinput',
  );
  static const _output = AudioDeviceInfo(
    deviceId: 'output-1',
    label: 'Output 1',
    kind: 'audiooutput',
  );

  @override
  Stream<List<AudioDeviceInfo>> get devicesChanged => const Stream.empty();

  @override
  AudioDeviceInfo? get selectedAudioInput => _input;

  @override
  AudioDeviceInfo? get selectedAudioOutput => _output;

  @override
  Future<List<AudioDeviceInfo>> enumerateDevices() async {
    return const [_input, _output];
  }

  @override
  Future<void> selectAudioInput(AudioDeviceInfo device) async {}

  @override
  Future<void> selectAudioOutput(AudioDeviceInfo device) async {}
}

class _FakeAudioDeviceStore extends AudioDeviceStore {
  const _FakeAudioDeviceStore({
    this.inputVolume = 0.35,
    this.outputVolume = 0.75,
  });

  final double inputVolume;
  final double outputVolume;

  @override
  Future<StoredAudioDevices> read() async {
    return StoredAudioDevices(
      inputVolume: inputVolume,
      outputVolume: outputVolume,
    );
  }

  @override
  Future<void> writeInputDeviceId(String deviceId) async {}

  @override
  Future<void> writeOutputDeviceId(String deviceId) async {}

  @override
  Future<void> writeInputVolume(double volume) async {}

  @override
  Future<void> writeOutputVolume(double volume) async {}
}

class _FixedCloseBehaviorStore extends CloseBehaviorStore {
  const _FixedCloseBehaviorStore(this.behavior);

  final CloseBehavior behavior;

  @override
  Future<CloseBehavior> read() async => behavior;

  @override
  Future<void> write(CloseBehavior behavior) async {}
}

class _RecordingWindowController extends DesktopWindowController {
  _RecordingWindowController(this.events);

  final List<String> events;
  AppCloseRequestHandler? closeRequestHandler;
  AppTrayExitHandler? trayExitHandler;

  @override
  void setCloseRequestHandler(AppCloseRequestHandler? handler) {
    closeRequestHandler = handler;
  }

  @override
  void setTrayExitHandler(AppTrayExitHandler? handler) {
    trayExitHandler = handler;
  }

  @override
  Future<void> hideAppWindowForExit() async {
    events.add('hide');
  }

  @override
  Future<void> terminateApplication() async {
    events.add('terminate');
  }
}

class _NoopRealtimeService implements RealtimeService {
  final _events = const Stream<RealtimeEvent>.empty();
  final _statusChanges = const Stream<RealtimeConnectionStatus>.empty();

  @override
  void Function()? onReconnect;

  @override
  Stream<RealtimeEvent> get events => _events;

  @override
  RealtimeConnectionStatus get status => RealtimeConnectionStatus.offline;

  @override
  Stream<RealtimeConnectionStatus> get statusChanges => _statusChanges;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}

class _RecordingRealtimeService implements RealtimeService {
  _RecordingRealtimeService(this.lifecycleEvents);

  final List<String> lifecycleEvents;
  final _events = const Stream<RealtimeEvent>.empty();
  final _statusChanges = const Stream<RealtimeConnectionStatus>.empty();

  @override
  void Function()? onReconnect;

  @override
  Stream<RealtimeEvent> get events => _events;

  @override
  RealtimeConnectionStatus get status => RealtimeConnectionStatus.offline;

  @override
  Stream<RealtimeConnectionStatus> get statusChanges => _statusChanges;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    lifecycleEvents.add('realtime-stop');
  }

  @override
  void dispose() {}
}

class _FakeRealtimeService implements RealtimeService {
  final _controller = StreamController<RealtimeEvent>.broadcast();
  final _statusController =
      StreamController<RealtimeConnectionStatus>.broadcast();
  RealtimeConnectionStatus _status = RealtimeConnectionStatus.connected;

  @override
  void Function()? onReconnect;

  @override
  Stream<RealtimeEvent> get events => _controller.stream;

  @override
  RealtimeConnectionStatus get status => _status;

  @override
  Stream<RealtimeConnectionStatus> get statusChanges =>
      _statusController.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  void add(RealtimeEvent event) => _controller.add(event);

  void setStatus(RealtimeConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void emitReconnect() => onReconnect?.call();

  @override
  void dispose() {
    _controller.close();
    _statusController.close();
  }
}

class _FakeLiveSessionController extends LiveSessionController {
  _FakeLiveSessionController({
    required LiveSession session,
    super.audioDeviceStore = const _FakeAudioDeviceStore(),
  }) : super(
         apiBaseUrl: 'http://localhost:3000',
         session: session,
         audioDeviceRestorer: (_) async => null,
       );

  @override
  Future<List<ScreenSource>> listScreenSources() async {
    return const [
      ScreenSource(
        id: 'screen-primary',
        name: 'Primary Display',
        thumbnail: null,
        isWindow: false,
      ),
    ];
  }

  @override
  Future<void> refreshScreenSourceThumbnails() async {}
}

class _FakeLiveSession extends LiveSession {
  int connectAttempts = 0;
  int disconnects = 0;
  final inputVolumes = <double>[];
  final outputVolumes = <double>[];
  final participantVoiceVolumeWrites = <String>[];
  final screenShareVolumes = <double>[];
  final micMutes = <bool>[];
  final outputMutes = <bool>[];
  final cameraEnables = <bool>[];
  final screenShareEnables = <bool>[];
  final screenShareSourceIds = <String?>[];

  @override
  Future<void> connect({
    required String url,
    required String token,
    required String roomName,
    required bool micMuted,
  }) async {
    connectAttempts += 1;
  }

  @override
  Future<void> disconnect() async {
    disconnects += 1;
  }

  @override
  Future<void> setMicMuted(bool muted) async {
    micMutes.add(muted);
  }

  @override
  Future<void> setOutputMuted(bool muted) async {
    outputMutes.add(muted);
  }

  @override
  Future<void> setInputVolume(double volume) async {
    inputVolumes.add(volume);
    await super.setInputVolume(volume);
  }

  @override
  Future<void> setOutputVolume(double volume) async {
    outputVolumes.add(volume);
    await super.setOutputVolume(volume);
  }

  @override
  Future<void> setParticipantVoiceVolume(String userId, double volume) async {
    participantVoiceVolumeWrites.add('$userId:${volume.toStringAsFixed(2)}');
    await super.setParticipantVoiceVolume(userId, volume);
  }

  @override
  Future<void> setScreenShareVolume(double volume) async {
    screenShareVolumes.add(volume);
    await super.setScreenShareVolume(volume);
  }

  @override
  Future<bool> setCameraEnabled(bool enabled) async {
    cameraEnables.add(enabled);
    return enabled;
  }

  @override
  Future<bool> setScreenShareEnabled(bool enabled, {String? sourceId}) async {
    screenShareEnables.add(enabled);
    screenShareSourceIds.add(sourceId);
    return enabled;
  }
}

LiveVideoTrack _liveVideoTrack({
  required String identity,
  required bool isScreenShare,
  required bool isLocal,
}) {
  return LiveVideoTrack(
    identity: identity,
    track: _FakeVideoTrack(),
    isScreenShare: isScreenShare,
    isLocal: isLocal,
  );
}

class _FakeVideoTrack implements lk.VideoTrack {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _MemoryLoginAccountHistoryStore extends LoginAccountHistoryStore {
  _MemoryLoginAccountHistoryStore([List<LoginAccountRecord> records = const []])
    : records = List<LoginAccountRecord>.unmodifiable(records);

  List<LoginAccountRecord> records;

  @override
  Future<List<LoginAccountRecord>> read() async => records;

  @override
  Future<void> write(List<LoginAccountRecord> records) async {
    this.records = List<LoginAccountRecord>.unmodifiable(records);
  }
}
