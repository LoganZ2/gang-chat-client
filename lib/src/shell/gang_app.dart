import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_client.dart';
import '../auth/token_store.dart';
import '../config/app_config.dart';
import '../ui/ui.dart';
import '../home/home_page.dart';
import '../app/auth_session_controller.dart';
import '../app/app_update.dart';
import '../app/authenticated_app_context.dart';
import '../app/language_preference.dart';
import '../app/login_account_history.dart';
import '../app/server_clock.dart';
import 'app_update_gate.dart';
import 'desktop_window_controller.dart';
import 'local_login_account_history_store.dart';
import 'local_language_preference_store.dart';
import 'login_page.dart';

class GangApp extends StatelessWidget {
  GangApp({
    super.key,
    this.tokenStore = const TokenStore(),
    this.config = const AppConfig.defaults(),
    this.startsAuthenticated = false,
    this.languageStore = const LocalLanguagePreferenceStore(),
    this.loginAccountHistoryStore = const LocalLoginAccountHistoryStore(),
    DesktopWindowController? windowController,
  }) : windowController = windowController ?? DesktopWindowController();

  final TokenStore tokenStore;
  final AppConfig config;
  final bool startsAuthenticated;
  final LanguagePreferenceStore languageStore;
  final LoginAccountHistoryStore loginAccountHistoryStore;
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
            languageStore: languageStore,
            loginAccountHistoryStore: loginAccountHistoryStore,
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
    required this.languageStore,
    required this.loginAccountHistoryStore,
    required this.windowController,
  });

  final TokenStore tokenStore;
  final AppConfig config;
  final bool startsAuthenticated;
  final LanguagePreferenceStore languageStore;
  final LoginAccountHistoryStore loginAccountHistoryStore;
  final DesktopWindowController windowController;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final AuthSessionController _auth = AuthSessionController(
    tokenStore: widget.tokenStore,
    apiBaseUrl: widget.config.apiBaseUrl,
  );
  final ServerClock _serverClock = ServerClock();
  // Tracks whether initial auth restore has finished so an authenticated start
  // does not briefly mount LoginPage and shrink the prepared app window.
  bool _initialRestoreDone = false;
  // The window starts hidden and is revealed once we know which screen to show.
  bool _windowRevealed = false;
  bool _exitingSessionForAppExit = false;
  AvailableAppUpdate? _detectedAppUpdate;
  String _authLanguage = defaultLanguagePreference;
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
    unawaited(_loadAuthLanguage());
    _restoreSession();
  }

  void _onAuthChanged() {
    if (_auth.session == null) {
      unawaited(_loadAuthLanguage());
    }
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
      final session = _auth.session;
      if (session != null) {
        unawaited(_rememberAuthLanguage(session.user.language));
      }
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

  Future<void> _loadAuthLanguage() async {
    try {
      final language = await widget.languageStore.read();
      if (!mounted) return;
      setState(() => _authLanguage = normalizeLanguagePreference(language));
    } catch (_) {
      // A missing/unavailable preference store should keep the default language.
    }
  }

  Future<void> _rememberAuthLanguage(String language) async {
    final normalized = normalizeLanguagePreference(language);
    if (mounted && _authLanguage != normalized) {
      setState(() => _authLanguage = normalized);
    }
    try {
      await widget.languageStore.write(normalized);
    } catch (_) {
      // Login should not fail because a non-sensitive local preference failed.
    }
  }

  Future<void> _logout() async {
    await _loadAuthLanguage();
    AuthSession? session;
    await _window.runWithHiddenWindow(() async {
      if (!mounted) return;
      session = _auth.beginLogout();
      await _lockLoginAuthWindow(centerWindow: true);
    });
    await _auth.finishLogout(session);
  }

  Future<void> _exitSessionForAppExit() async {
    if (mounted) {
      setState(() => _exitingSessionForAppExit = true);
    } else {
      _exitingSessionForAppExit = true;
    }
    _auth.beginLogout();
  }

  Future<void> _lockLoginAuthWindow({bool centerWindow = false}) {
    return _window.lockAuthWindow(
      centerWindow: centerWindow,
      size: _window.authWidgetSize(false),
    );
  }

  Future<void> _submitAuthRequest(
    AuthRequest request, {
    required bool rememberPassword,
  }) async {
    final session = await _auth.authenticate(request);
    if (!request.registering) {
      await _rememberLoginAccount(
        request,
        rememberPassword: rememberPassword,
        avatarUrl: session.user.avatarUrl,
        defaultAvatarKey: session.user.defaultAvatarKey,
      );
    }
    await _rememberAuthLanguage(session.user.language);
    if (!mounted) return;
    await _window.runWithHiddenWindow(() async {
      if (!mounted) return;
      await _auth.acceptSession(session);
      await _window.restoreAppWindow();
    });
  }

  Future<void> _rememberLoginAccount(
    AuthRequest request, {
    required bool rememberPassword,
    required String? avatarUrl,
    required String defaultAvatarKey,
  }) async {
    try {
      final records = await widget.loginAccountHistoryStore.read();
      await widget.loginAccountHistoryStore.write(
        rememberLoginAccount(
          records: records,
          login: request.login,
          password: request.password,
          rememberPassword: rememberPassword,
          avatarUrl: avatarUrl,
          defaultAvatarKey: defaultAvatarKey,
          updateAvatarMetadata: true,
        ),
      );
    } catch (_) {
      // Successful authentication should not be blocked by local history IO.
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    _serverClock.dispose();
    _revealFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _auth.session;
    if (_exitingSessionForAppExit) {
      return const _LoadingPage();
    }
    if (session == null) {
      if (widget.startsAuthenticated && !_initialRestoreDone) {
        return const _LoadingPage();
      }
      return Theme(
        data: uiTheme(),
        child: LoginPage(
          language: _authLanguage,
          onSubmit: _submitAuthRequest,
          sizeForMode: _window.authWidgetSize,
          consumeInitialWindowLock: _window.consumeSkipNextAuthWindowLock,
          lockAuthWindow: _window.lockAuthWindow,
          windowController: _window,
          accountHistoryStore: widget.loginAccountHistoryStore,
        ),
      );
    }

    final app = AuthenticatedAppContext(
      session: session,
      apiBaseUrl: _auth.apiBaseUrl,
      accessTokenProvider: _auth.accessToken,
      logout: _logout,
      exitSessionForAppExit: _exitSessionForAppExit,
      serverClock: _serverClock,
    );

    return SelectionContainer.disabled(
      child: AppUpdateGate(
        releaseBucketUrl: widget.config.releaseBucketUrl,
        windowController: widget.windowController,
        onUpdateAvailable: (update) {
          if (!mounted) return;
          setState(() => _detectedAppUpdate = update);
        },
        child: HomePage(
          app: app,
          languageStore: widget.languageStore,
          windowController: widget.windowController,
          detectedAppUpdate: _detectedAppUpdate,
          onDetectedAppUpdateShown: () {
            if (!mounted || _detectedAppUpdate == null) return;
            setState(() => _detectedAppUpdate = null);
          },
        ),
      ),
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
