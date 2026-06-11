import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_client.dart';
import '../auth/token_store.dart';
import '../config/app_config.dart';
import '../ui/ui.dart';
import '../home/home_page.dart';
import '../app/auth_session_controller.dart';
import '../app/authenticated_app_context.dart';
import 'desktop_window_controller.dart';
import 'login_page.dart';

class GangApp extends StatelessWidget {
  GangApp({
    super.key,
    this.tokenStore = const TokenStore(),
    this.config = const AppConfig.defaults(),
    this.startsAuthenticated = false,
    DesktopWindowController? windowController,
  }) : windowController = windowController ?? DesktopWindowController();

  final TokenStore tokenStore;
  final AppConfig config;
  final bool startsAuthenticated;
  final DesktopWindowController windowController;

  @override
  Widget build(BuildContext context) {
    return AppConfigScope(
      config: config,
      child: MaterialApp(
        title: 'Gang Chat',
        theme: uiTheme(),
        home: SelectionArea(
          child: _AuthGate(
            tokenStore: tokenStore,
            config: config,
            startsAuthenticated: startsAuthenticated,
            windowController: windowController,
          ),
        ),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({
    required this.tokenStore,
    required this.config,
    required this.startsAuthenticated,
    required this.windowController,
  });

  final TokenStore tokenStore;
  final AppConfig config;
  final bool startsAuthenticated;
  final DesktopWindowController windowController;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final AuthSessionController _auth = AuthSessionController(
    tokenStore: widget.tokenStore,
    apiBaseUrl: widget.config.apiBaseUrl,
  );
  // Tracks whether initial auth restore has finished so an authenticated start
  // does not briefly mount LoginPage and shrink the prepared app window.
  bool _initialRestoreDone = false;
  // The window starts hidden and is revealed once we know which screen to show.
  bool _windowRevealed = false;
  Timer? _revealFallbackTimer;

  DesktopWindowController get _window => widget.windowController;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    if (widget.startsAuthenticated && _window.supportsWindowManagement) {
      // Safety net: if auth refresh hangs, reveal the window anyway so the user
      // is not left staring at nothing.
      _revealFallbackTimer = Timer(const Duration(seconds: 4), () {
        unawaited(_ensureWindowVisible());
      });
    }
    _restoreSession();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _restoreSession() async {
    // AppConfig is the source of truth for server selection. A stored base URL
    // is only a stale copy of older config because there is no server picker.
    final result = await _auth.restoreSession();
    if (!mounted) return;

    if (result.status == AuthRestoreStatus.missingRefreshToken) {
      setState(() => _initialRestoreDone = true);
      if (widget.startsAuthenticated) {
        await _lockLoginAuthWindow(centerWindow: true);
      }
      await _ensureWindowVisible();
      return;
    }

    if (result.hasSession) {
      if (widget.startsAuthenticated) {
        setState(() => _initialRestoreDone = true);
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _ensureWindowVisible();
      } else {
        await _window.runWithHiddenWindow(() async {
          if (!mounted) return;
          setState(() => _initialRestoreDone = true);
          await _window.restoreAppWindow();
        });
        await _ensureWindowVisible();
      }
      return;
    }

    setState(() => _initialRestoreDone = true);
    if (widget.startsAuthenticated) {
      await _window.runWithHiddenWindow(() async {
        await _lockLoginAuthWindow(centerWindow: true);
      });
    }
    await _ensureWindowVisible();
  }

  Future<void> _ensureWindowVisible() async {
    if (!_window.supportsWindowManagement) return;
    if (_windowRevealed) return;
    _windowRevealed = true;
    _revealFallbackTimer?.cancel();
    _revealFallbackTimer = null;
    await _window.showInitialWindow();
  }

  Future<void> _logout() async {
    AuthSession? session;
    await _window.runWithHiddenWindow(() async {
      if (!mounted) return;
      session = _auth.beginLogout();
      await _lockLoginAuthWindow(centerWindow: true);
    });
    await _auth.finishLogout(session);
  }

  Future<void> _lockLoginAuthWindow({bool centerWindow = false}) {
    return _window.lockAuthWindow(
      centerWindow: centerWindow,
      size: _window.authWidgetSize(false),
    );
  }

  Future<void> _submitAuthRequest(AuthRequest request) async {
    final session = await _auth.authenticate(request);
    if (!mounted) return;
    await _window.runWithHiddenWindow(() async {
      if (!mounted) return;
      await _auth.acceptSession(session);
      await _window.restoreAppWindow();
    });
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    _revealFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _auth.session;
    if (session == null) {
      if (widget.startsAuthenticated && !_initialRestoreDone) {
        return const _LoadingPage();
      }
      return Theme(
        data: uiTheme(),
        child: LoginPage(
          onSubmit: _submitAuthRequest,
          sizeForMode: _window.authWidgetSize,
          consumeInitialWindowLock: _window.consumeSkipNextAuthWindowLock,
          lockAuthWindow: _window.lockAuthWindow,
        ),
      );
    }

    final app = AuthenticatedAppContext(
      session: session,
      apiBaseUrl: _auth.apiBaseUrl,
      accessTokenProvider: _auth.accessToken,
      logout: _logout,
    );

    return SelectionContainer.disabled(
      child: HomePage(app: app, windowController: widget.windowController),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: appWindowBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Gang Chat',
              style: TextStyle(
                color: Color(0xFFECEFF1),
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            SizedBox(height: 20),
            SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF6FCFA6),
              ),
            ),
            SizedBox(height: 14),
            Text(
              '正在加载',
              style: TextStyle(
                color: Color(0xFFB0B8C0),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
