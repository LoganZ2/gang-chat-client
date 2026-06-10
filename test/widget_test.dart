import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerEnterEvent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'package:client/main.dart';
import 'package:client/src/app/audio_device_store.dart';
import 'package:client/src/app/authenticated_app_context.dart';
import 'package:client/src/app/live_session_controller.dart';
import 'package:client/src/app/realtime_controller.dart';
import 'package:client/src/auth/auth_client.dart';
import 'package:client/src/auth/token_store.dart';
import 'package:client/src/live/live_session.dart';
import 'package:client/src/protocol/api_client.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/settings/settings_page.dart';
import 'package:client/src/shell/login_page.dart';
import 'package:client/src/ui/ui.dart' as ui;
import 'package:client/src/home/home_page.dart';
import 'package:client/src/home/live_channel_pane.dart' as live_pane;
import 'package:client/ui_showcase.dart' as showcase;

void main() {
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
    expect(find.text('请输入账号和密码后继续。'), findsNothing);
    final normalSurfaceHeight = tester
        .getSize(find.byKey(const ValueKey('auth-surface')))
        .height;
    final normalBottomGap = _submitBottomGap(tester, submitLabel: '登录');

    await tester.tap(find.widgetWithText(ui.Button, '登录'));
    await tester.pump();

    expect(find.text('请输入账号和密码后继续。'), findsOneWidget);
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
          sizeForMode: (_, {showingError = false}) => const Size(416, 250),
          consumeInitialWindowLock: () => true,
          lockAuthWindow:
              ({
                bool registering = false,
                bool moveWindow = false,
                bool centerWindow = false,
                Size? size,
              }) async {},
          onSubmit: (_) async {
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

  testWidgets('register mode exposes full auth form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(GangApp(tokenStore: _MemoryTokenStore()));
    await tester.pump();

    final loginGap = _authActionGap(tester, submitLabel: '登录');
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
      _authActionGap(tester, submitLabel: '创建账号'),
      closeTo(loginGap, 0.01),
    );
    expect(
      _submitBottomGap(tester, submitLabel: '创建账号'),
      closeTo(loginBottomGap, 0.01),
    );
    _expectSubmitButtonFullWidth(tester, submitLabel: '创建账号');
    expect(find.text('请输入账号和密码后继续。'), findsNothing);
    final normalSurfaceHeight = tester
        .getSize(find.byKey(const ValueKey('auth-surface')))
        .height;

    await tester.tap(find.byTooltip('显示密码').first);
    await tester.pump();

    expect(find.byTooltip('隐藏密码'), findsOneWidget);
    expect(find.byTooltip('显示密码'), findsOneWidget);

    await tester.tap(find.widgetWithText(ui.Button, '创建账号'));
    await tester.pump();

    expect(find.text('请输入账号和密码后继续。'), findsOneWidget);
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
    expect(find.text('2 名成员 · 1 直播中'), findsOneWidget);
    expect(find.text('5 名成员'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    final searchRect = tester.getRect(
      find.byKey(const ValueKey('home-title-search')),
    );
    expect(searchRect.center.dx, closeTo(400, 0.01));

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

    expect(requestedPaths, contains('/api/v1/rooms/server-alpha'));
    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/messages'));
    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/live'));
    expect(find.text('Hello from Morgan'), findsOneWidget);
    expect(find.text('Reply from Kai'), findsOneWidget);
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

  testWidgets('authenticated home shell search tag filters sidebar rooms', (
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

    final searchField = find.descendant(
      of: find.byKey(const ValueKey('home-title-search')),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'Beta');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/search'));
    expect(find.text('我的房间 1'), findsWidgets);
    expect(find.text('公开房间 1'), findsWidgets);
    expect(find.text('聊天记录 1'), findsWidgets);
    expect(find.text('聊天文件 1'), findsWidgets);
    expect(
      find.byKey(const ValueKey('public-room-action-server-public')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('public-room-action-server-public')),
    );
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/rooms/server-public/join'));

    await tester.tap(find.text('我的房间 1').first);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-title-search')),
        matching: find.text('我的房间'),
      ),
      findsOneWidget,
    );
    expect(find.text('Beta Room'), findsWidgets);
    expect(find.text('Alpha Room'), findsNothing);

    await tester.tap(find.byTooltip('关闭筛选'));
    await tester.pumpAndSettle();

    expect(find.text('Alpha Room'), findsOneWidget);
    expect(find.text('Beta Room'), findsWidgets);
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
    expect(body['default_avatar_key'], 'room-1');
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
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('邀请'), findsOneWidget);
      expect(find.text('申请'), findsOneWidget);
      expect(find.text('房间通知'), findsOneWidget);
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
    final liveSession = _FakeLiveSession();
    final liveSessionController = _FakeLiveSessionController(
      session: liveSession,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: HomePage(
          app: _homeTestAppContext(requestedPaths: requestedPaths),
          audioDeviceStore: const _FakeAudioDeviceStore(),
          liveSessionController: liveSessionController,
          realtime: _NoopRealtimeService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha Room'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('进入直播频道'));
    await tester.pumpAndSettle();

    expect(find.text('Morgan'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '加入'), findsOneWidget);
    expect(find.byTooltip('收起直播频道'), findsOneWidget);
    expect(find.byTooltip('已加入语音'), findsNothing);

    await tester.tap(find.widgetWithText(ui.Button, '加入'));
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/live/join'));
    expect(liveSession.connectAttempts, 1);
    expect(find.text('Kai (you)'), findsOneWidget);
    expect(find.text('Morgan'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '加入'), findsNothing);
    expect(find.byTooltip('静音'), findsOneWidget);
    expect(find.byTooltip('离开'), findsOneWidget);
    expect(find.byTooltip('已加入语音'), findsOneWidget);

    await tester.tap(find.byTooltip('静音'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('耳机静音'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('开启摄像头'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('共享屏幕'));
    await tester.pumpAndSettle();
    expect(find.text('Primary Display'), findsOneWidget);
    await tester.tap(find.text('Primary Display'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ui.Button, '共享'));
    await tester.pumpAndSettle();

    expect(liveSession.micMutes, contains(true));
    expect(liveSession.outputMutes, [true]);
    expect(liveSession.cameraEnables, [true]);
    expect(liveSession.screenShareEnables, [true]);
    expect(liveSession.screenShareSourceIds, ['screen-primary']);
    expect(
      requestedPaths
          .where((path) => path == '/api/v1/rooms/server-alpha/live/me')
          .length,
      greaterThanOrEqualTo(3),
    );

    await tester.tap(find.byTooltip('离开'));
    await tester.pumpAndSettle();

    expect(liveSession.disconnects, 1);
    expect(find.widgetWithText(ui.Button, '加入'), findsOneWidget);
    expect(find.byTooltip('已加入语音'), findsNothing);

    await tester.tap(find.byTooltip('收起直播频道'));
    await tester.pumpAndSettle();

    expect(find.text('Kai (you)'), findsNothing);
    expect(find.text('Hello from Morgan'), findsOneWidget);
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

    await tester.tap(find.byTooltip('房间详情'));
    await tester.pumpAndSettle();

    expect(find.text('成员'), findsAtLeastNWidgets(1));
    expect(find.text('邀请成员'), findsOneWidget);
    expect(find.text('申请说明：Please approve my request'), findsOneWidget);
    expect(find.text('Kai'), findsWidgets);
    expect(find.text('Morgan'), findsWidgets);
    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/members'));
    expect(
      requestedPaths,
      contains('/api/v1/rooms/server-alpha/join-requests'),
    );

    await tester.ensureVisible(_textFieldWithHint('按用户名、昵称或 UID 搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(_textFieldWithHint('按用户名、昵称或 UID 搜索'), 'ri');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/users/search'));
    expect(find.textContaining('Riley'), findsAtLeastNWidgets(1));

    await tester.tap(find.widgetWithText(ui.Button, '邀请'));
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/api/v1/rooms/server-alpha/invites'));
    expect(find.widgetWithText(ui.Button, '已邀请'), findsOneWidget);

    await tester.tap(find.byTooltip('返回').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('房间操作'));
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
    await tester.tap(find.text('进入直播频道'));
    await tester.pumpAndSettle();

    expect(find.text('Riley'), findsNothing);
    expect(find.text('2 名成员 · 1 直播中'), findsOneWidget);

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
    expect(find.text('2 名成员 · 2 直播中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    expect(logoutRect.top, closeTo(createRect.top, 0.01));
    expect(logoutRect.bottom, closeTo(createRect.bottom, 0.01));
    expect(logoutRect.right, closeTo(userSummaryRect.right, 0.01));
    expect(logoutRect.left - settingsRect.right, closeTo(8, 0.01));

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
    await tester.pump();

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
      expect(find.text('进入直播频道'), findsOneWidget);
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

    expect(find.text('请输入账号和密码后继续。'), findsOneWidget);
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
  List<Uri>? requestedUris,
  List<Map<String, Object?>>? accountUpdates,
  List<Map<String, Object?>>? roomCreations,
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
    api: _roomsApi(
      requestedPaths: requestedPaths,
      requestedUris: requestedUris,
      accountUpdates: accountUpdates,
      roomCreations: roomCreations,
    ),
  );
}

GangApi _roomsApi({
  List<String>? requestedPaths,
  List<Uri>? requestedUris,
  List<Map<String, Object?>>? accountUpdates,
  List<Map<String, Object?>>? roomCreations,
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
            ..._serverListJson,
          ],
        });
      }
      if (request.url.path == '/api/v1/search') {
        return _jsonResponse({
          'my_rooms': [_roomCardJson(id: 'server-beta', name: 'Beta Room')],
          'public_rooms': [
            {
              ..._roomCardJson(id: 'server-public', name: 'Beta Public'),
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
              joinPolicy: body['join_policy'] as String? ?? 'approval_required',
              aiVoiceAnnouncementsEnabled:
                  body['ai_voice_announcements_enabled'] as bool? ?? true,
            ),
          });
        }
        return _jsonResponse({
          'room': _roomDetailJson(
            id: 'server-alpha',
            name: 'Alpha Room',
            memberCount: 2,
            onlineMemberCount: 1,
            liveParticipantCount: 1,
          ),
        });
      }
      if (request.url.path == '/api/v1/rooms/server-alpha/members') {
        return _jsonResponse({
          'members': [
            _roomMemberJson(user: _currentUserJson, role: 'owner'),
            _roomMemberJson(
              user: _userJson(
                id: 'user-2',
                username: 'morgan',
                displayName: 'Morgan',
                isOnline: true,
              ),
            ),
          ],
          'next_cursor': null,
        });
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
  'status': '在线',
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
    'created_by': _currentUserJson,
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
  bool headphonesMuted = false,
  bool voiceBlocked = false,
  bool cameraOn = false,
  bool screenSharing = false,
}) {
  return {
    'live_session_id': liveSessionId,
    'user': user,
    'joined_at': '2026-06-05T08:00:00Z',
    'mic_muted': micMuted,
    'headphones_muted': headphonesMuted,
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
  bool? isOnline,
}) {
  final json = <String, Object?>{
    'id': id,
    'username': username,
    'display_name': displayName,
    'avatar_url': null,
    'default_avatar_key': 'blue-3',
  };
  if (isOnline != null) json['is_online'] = isOnline;
  return json;
}

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

class _FakeAudioDeviceStore extends AudioDeviceStore {
  const _FakeAudioDeviceStore();

  @override
  Future<StoredAudioDevices> read() async {
    return const StoredAudioDevices(inputVolume: 0.35, outputVolume: 0.75);
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

class _NoopRealtimeService implements RealtimeService {
  final _events = const Stream<RealtimeEvent>.empty();

  @override
  void Function()? onReconnect;

  @override
  Stream<RealtimeEvent> get events => _events;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}

class _FakeRealtimeService implements RealtimeService {
  final _controller = StreamController<RealtimeEvent>.broadcast();

  @override
  void Function()? onReconnect;

  @override
  Stream<RealtimeEvent> get events => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  void add(RealtimeEvent event) => _controller.add(event);

  @override
  void dispose() {
    _controller.close();
  }
}

class _FakeLiveSessionController extends LiveSessionController {
  _FakeLiveSessionController({required LiveSession session})
    : super(
        apiBaseUrl: 'http://localhost:3000',
        audioDeviceStore: const _FakeAudioDeviceStore(),
        session: session,
        audioDeviceRestorer: (_) async {},
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
