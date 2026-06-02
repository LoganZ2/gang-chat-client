import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/auth/auth_client.dart';
import 'src/auth/token_store.dart';
import 'src/config/app_config.dart';
import 'src/home/home_page.dart';
import 'src/lifecycle/shutdown_hooks.dart';
import 'src/ui/key_button.dart';
import 'src/ui/title_bar.dart';

const _appWindowMinSize = Size(720, 480);
const _appWindowSize = Size(1180, 760);
const _unboundedWindowSize = Size(100000, 100000);
const _minimumWindowSize = Size(1, 1);
const _windowBackground = Color(0xFF14171D);
const _authWidgetWidth = 430.0;
const _loginWidgetHeight = 256.0;
const _registerWidgetHeight = 344.0;
const _loginWidgetSize = Size(_authWidgetWidth, _loginWidgetHeight);
const _registerWidgetSize = Size(_authWidgetWidth, _registerWidgetHeight);
// Window controls now float as an overlay rather than occupying a dedicated
// strip, so the auth windows are sized exactly to their content.
const _loginWindowSize = _loginWidgetSize;
const _registerWindowSize = _registerWidgetSize;

bool _skipNextLoginWindowLock = false;

bool get _supportsDesktopWindowManagement =>
    !kIsWeb &&
    !Platform.environment.containsKey('FLUTTER_TEST') &&
    (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  final config = await AppConfig.load();

  // Pre-read the refresh token so we can size the initial window correctly
  // (login vs full app) before it ever renders. Without this, an
  // already-logged-in user briefly sees the small login-sized window before
  // it grows to the app size, which looks like a layout flicker.
  const tokenStore = TokenStore();
  final hasStoredSession =
      (await tokenStore.readRefreshToken())?.isNotEmpty ?? false;

  if (_supportsDesktopWindowManagement) {
    await windowManager.ensureInitialized();
    _skipNextLoginWindowLock = Platform.isMacOS;
    await windowManager.waitUntilReadyToShow(
      _initialWindowOptions(authenticated: hasStoredSession),
      () async {},
    );
    if (hasStoredSession) {
      await _prepareAuthenticatedInitialWindow();
    } else {
      await _prepareInitialWindow();
    }
    // Intercept the OS close button so we can flush async cleanup
    // (e.g. leaving the active live voice session on the server) before
    // the process actually exits. The listener is wired up here, at the
    // earliest moment we know windowManager is ready.
    await windowManager.setPreventClose(true);
    windowManager.addListener(_AppWindowListener());
  }
  runApp(
    GangApp(
      config: config,
      tokenStore: tokenStore,
      startsAuthenticated: hasStoredSession,
    ),
  );
  if (_supportsDesktopWindowManagement) {
    await binding.waitUntilFirstFrameRasterized;
    // The window is shown by _AuthGate after it has decided which screen to
    // render. This avoids a brief flash of the wrong layout — both the
    // login-sized window before an auth refresh resizes it up, and the empty
    // pre-restore home screen before the session is loaded.
  }
}

class _AppWindowListener extends WindowListener {
  // How long we let async cleanup (e.g. leaving the live voice session) run
  // before forcing the process to exit. The window is already hidden by then,
  // so this budget is invisible to the user — it only governs how long we
  // wait to give the server a clean departure.
  static const _shutdownBudget = Duration(milliseconds: 1200);
  bool _closing = false;

  @override
  void onWindowClose() {
    // Don't await directly inside this synchronous callback: if it throws,
    // window_manager swallows it and the window never closes. Instead,
    // dispatch to a tiny driver that always finishes by terminating.
    unawaited(_drain());
  }

  Future<void> _drain() async {
    // Guard against re-entrancy: clicking X again while we're already closing
    // would otherwise kick off a second teardown.
    if (_closing) return;
    _closing = true;

    // Hide the window first so the click feels instant. The user shouldn't see
    // a frozen window while LiveKit/WebRTC tears down (which can stall on DTLS
    // timeouts). Cleanup then runs against an already-gone window.
    try {
      await windowManager.hide();
    } catch (_) {}

    try {
      await Future.any([
        ShutdownHooks.runAll(),
        Future<void>.delayed(_shutdownBudget),
      ]);
    } catch (_) {
      // never let cleanup keep the process alive
    }

    // Force the process to exit. windowManager.destroy() alone can leave the
    // app lingering because libwebrtc keeps native threads running after the
    // Dart-side room is disposed; exit(0) guarantees we actually quit.
    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }
}

WindowOptions _initialWindowOptions({bool authenticated = false}) {
  if (Platform.isMacOS) {
    return const WindowOptions(
      backgroundColor: _windowBackground,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      center: true,
    );
  }
  if (authenticated) {
    return const WindowOptions(
      size: _appWindowSize,
      minimumSize: _appWindowMinSize,
      backgroundColor: _windowBackground,
      titleBarStyle: TitleBarStyle.hidden,
      center: true,
    );
  }
  return const WindowOptions(
    size: _loginWindowSize,
    minimumSize: _loginWindowSize,
    maximumSize: _loginWindowSize,
    backgroundColor: _windowBackground,
    titleBarStyle: TitleBarStyle.hidden,
    center: true,
  );
}

Future<void> _prepareInitialWindow() {
  return _configureDesktopWindow(() async {
    await _setWindowMaximizable(false);
    await _setWindowShadow(false);
    await windowManager.setResizable(false);
    await windowManager.setAlignment(Alignment.center);
    if (Platform.isMacOS) {
      // macOS shows the window immediately; opaque-zero it until the AuthGate
      // is ready so we don't see the pre-render frame.
      await windowManager.setOpacity(0);
    }
  });
}

/// Initial window prep when we already know the user is logged in: skip the
/// auth-window lock and jump straight to the app window's sizing/resizable
/// state so the home screen doesn't visibly resize after the auth refresh
/// completes.
Future<void> _prepareAuthenticatedInitialWindow() {
  return _configureDesktopWindow(() async {
    await windowManager.setResizable(true);
    await _setWindowMaximizable(true);
    await _setWindowShadow(false);
    await windowManager.setMaximumSize(_unboundedWindowSize);
    await windowManager.setMinimumSize(_appWindowMinSize);
    await windowManager.setSize(_appWindowSize);
    await windowManager.setAlignment(Alignment.center);
    if (Platform.isMacOS) {
      await windowManager.setOpacity(0);
    }
  });
}

Future<void> _showInitialWindow() {
  return _configureDesktopWindow(() async {
    if (Platform.isMacOS) {
      await windowManager.setOpacity(1);
      return;
    }
    await windowManager.show();
    await windowManager.focus();
  });
}

Size _authWidgetSize(bool registering) =>
    registering ? _registerWidgetSize : _loginWidgetSize;

Size _authWindowSize(bool registering) =>
    registering ? _registerWindowSize : _loginWindowSize;

Future<void> _lockAuthWindow({
  bool registering = false,
  bool moveWindow = true,
  bool centerWindow = false,
}) {
  return _configureDesktopWindow(() async {
    final targetSize = _authWindowSize(registering);
    final alreadySized = await _isAuthWindowSized(targetSize);
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }
    await _setWindowMaximizable(false);
    await _setWindowShadow(false);
    await windowManager.setMaximumSize(_unboundedWindowSize);
    await windowManager.setMinimumSize(_minimumWindowSize);
    if (moveWindow || !alreadySized) {
      await windowManager.setSize(targetSize);
    }
    await windowManager.setMinimumSize(targetSize);
    await windowManager.setMaximumSize(targetSize);
    await windowManager.setResizable(false);
    if (centerWindow) {
      await windowManager.setAlignment(Alignment.center);
    }
  });
}

Future<void> _restoreAppWindow() {
  return _configureDesktopWindow(() async {
    await windowManager.setResizable(true);
    await _setWindowMaximizable(true);
    await _setWindowShadow(false);
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }
    await windowManager.setMaximumSize(_unboundedWindowSize);
    await windowManager.setMinimumSize(_appWindowMinSize);
    await windowManager.setSize(_appWindowSize);
    await windowManager.setAlignment(Alignment.center);
  });
}

Future<void> _configureDesktopWindow(Future<void> Function() configure) async {
  if (!_supportsDesktopWindowManagement) return;
  try {
    await configure();
  } catch (_) {}
}

Future<void> _setWindowMaximizable(bool isMaximizable) async {
  try {
    await windowManager.setMaximizable(isMaximizable);
  } catch (_) {}
}

Future<void> _setWindowShadow(bool hasShadow) async {
  try {
    await windowManager.setHasShadow(hasShadow);
  } catch (_) {}
}

Future<void> _setWindowOpacity(double opacity) {
  return _configureDesktopWindow(() => windowManager.setOpacity(opacity));
}

Future<void> _runWithHiddenWindow(Future<void> Function() body) async {
  if (!_supportsDesktopWindowManagement) {
    await body();
    return;
  }
  await _setWindowOpacity(0);
  try {
    await body();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  } finally {
    await _setWindowOpacity(1);
  }
}

bool _consumeSkipNextLoginWindowLock() {
  if (!_skipNextLoginWindowLock) return false;
  _skipNextLoginWindowLock = false;
  return true;
}

Future<bool> _isAuthWindowSized(Size targetSize) async {
  final size = await windowManager.getSize();
  return (size.width - targetSize.width).abs() < 1 &&
      (size.height - targetSize.height).abs() < 1;
}

class GangApp extends StatelessWidget {
  const GangApp({
    super.key,
    this.tokenStore = const TokenStore(),
    this.config = const AppConfig.defaults(),
    this.startsAuthenticated = false,
  });

  final TokenStore tokenStore;
  final AppConfig config;
  final bool startsAuthenticated;

  @override
  Widget build(BuildContext context) {
    return AppConfigScope(
      config: config,
      child: MaterialApp(
        title: 'Gang Chat',
        theme: _buildTheme(),
        builder: (context, child) {
          return Stack(
            children: [
              Positioned.fill(child: child ?? const SizedBox.shrink()),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: WindowControls(),
              ),
            ],
          );
        },
        home: SelectionArea(
          child: _AuthGate(
            tokenStore: tokenStore,
            config: config,
            startsAuthenticated: startsAuthenticated,
          ),
        ),
      ),
    );
  }
}

ThemeData _buildTheme() {
  const appBackground = Color(0xFF14171D);
  const fieldBackground = Color(0xFF1F232C);
  const accent = Color(0xFF6FCFA6);
  const warmAccent = Color(0xFFD4B675);
  const fieldBorder = Color(0xFF2A2F38);
  const fieldFocusedBorder = Color(0xFF3A4248);
  const fieldDisabledBorder = Color(0xFF22262E);
  const fieldErrorBorder = Color(0xFF553A3F);

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    primary: accent,
    secondary: warmAccent,
    surface: appBackground,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: appBackground,
    // Windows' default UI font (Segoe UI) has no CJK glyphs, so Chinese text
    // falls back to whatever the engine picks (often a mismatched serif).
    // Pin the fallback chain to the Windows-bundled "Microsoft YaHei" family
    // so CJK renders cleanly and consistently with the Latin UI font.
    fontFamilyFallback: const [
      'Segoe UI',
      'Microsoft YaHei UI',
      'Microsoft YaHei',
    ],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fieldBackground,
      hoverColor: Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: const TextStyle(color: Color(0xFF6F7785)),
      labelStyle: const TextStyle(color: Color(0xFF99A1AD)),
      floatingLabelStyle: const TextStyle(color: Color(0xFFB0B8C0)),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: fieldBorder),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: fieldBorder),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: fieldFocusedBorder),
      ),
      disabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: fieldDisabledBorder),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: fieldErrorBorder),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: fieldErrorBorder),
      ),
    ),
  );
}

class _AuthGate extends StatefulWidget {
  const _AuthGate({
    required this.tokenStore,
    required this.config,
    required this.startsAuthenticated,
  });

  final TokenStore tokenStore;
  final AppConfig config;
  final bool startsAuthenticated;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  AuthSession? _session;
  late String _apiBaseUrl = widget.config.apiBaseUrl;
  Timer? _refreshTimer;
  Future<String>? _refreshInFlight;
  // Tracks whether we've finished the initial auth-restore. Used so that on
  // an already-authenticated startup we don't briefly mount the LoginPage
  // (which would shrink the window) before the session resolves.
  bool _initialRestoreDone = false;
  // The window starts hidden and is revealed by _ensureWindowVisible once we
  // know which screen to show. This flag keeps the reveal idempotent so the
  // restore path and the safety-net timeout can't double-fire it.
  bool _windowRevealed = false;
  Timer? _revealFallbackTimer;

  @override
  void initState() {
    super.initState();
    if (widget.startsAuthenticated && _supportsDesktopWindowManagement) {
      // Safety net: if the auth refresh hangs (slow or unreachable server),
      // reveal the window anyway so the user isn't staring at nothing. The
      // home screen renders behind a loading state once the session resolves.
      _revealFallbackTimer = Timer(const Duration(seconds: 4), () {
        unawaited(_ensureWindowVisible());
      });
    }
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    // The asset config (app_config.json / --dart-define) is the single source
    // of truth for which server we talk to. We deliberately do NOT prefer a
    // previously stored base URL here: there's no UI to pick a server, so a
    // stored value is only ever a stale copy of an older config and would pin
    // the app to a server the build no longer targets.
    final storedApiBaseUrl = widget.config.apiBaseUrl;
    final refreshToken = await widget.tokenStore.readRefreshToken();
    if (refreshToken == null) {
      if (!mounted) return;
      setState(() {
        _apiBaseUrl = storedApiBaseUrl;
        _initialRestoreDone = true;
      });
      // Auth gate decided: show the (already-sized) login window now.
      if (widget.startsAuthenticated) {
        // Edge case: token vanished between main() and here. Lock the window
        // back down to the login size before revealing it.
        await _lockAuthWindow(centerWindow: true);
      }
      await _ensureWindowVisible();
      return;
    }

    final client = AuthClient(baseUrl: storedApiBaseUrl);
    try {
      final session = await client.refresh(refreshToken);
      await widget.tokenStore.writeRefreshToken(session.refreshToken);
      if (!mounted) return;
      if (widget.startsAuthenticated) {
        // Window is already sized for the home screen and still hidden.
        // Render the home screen, wait for it to settle, then reveal — no
        // resize, no flash.
        setState(() {
          _apiBaseUrl = storedApiBaseUrl;
          _session = session;
          _initialRestoreDone = true;
        });
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await _ensureWindowVisible();
      } else {
        await _runWithHiddenWindow(() async {
          if (!mounted) return;
          setState(() {
            _apiBaseUrl = storedApiBaseUrl;
            _session = session;
            _initialRestoreDone = true;
          });
          await _restoreAppWindow();
        });
        // Defensive: main() didn't flag an authenticated start (so the window
        // was never shown), yet we found a session. Reveal it now.
        await _ensureWindowVisible();
      }
      _scheduleTokenRefresh(session);
    } catch (_) {
      await widget.tokenStore.clearRefreshToken();
      if (!mounted) return;
      setState(() {
        _apiBaseUrl = storedApiBaseUrl;
        _initialRestoreDone = true;
      });
      if (widget.startsAuthenticated) {
        // Refresh failed: window is currently sized for the app. Resize down
        // to the login layout under cover of opacity 0, then reveal.
        await _runWithHiddenWindow(() async {
          await _lockAuthWindow(centerWindow: true);
        });
      }
      await _ensureWindowVisible();
    } finally {
      client.close();
    }
  }

  Future<void> _ensureWindowVisible() async {
    if (!_supportsDesktopWindowManagement) return;
    if (_windowRevealed) return;
    _windowRevealed = true;
    _revealFallbackTimer?.cancel();
    _revealFallbackTimer = null;
    await _showInitialWindow();
  }

  Future<void> _logout() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshInFlight = null;
    final session = _session;
    await _runWithHiddenWindow(() async {
      if (!mounted) return;
      setState(() => _session = null);
      await _lockAuthWindow(centerWindow: true);
    });
    await widget.tokenStore.clearRefreshToken();
    if (session == null) return;

    final client = AuthClient(baseUrl: _apiBaseUrl);
    try {
      await client.logout(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
    } catch (_) {
    } finally {
      client.close();
    }
  }

  Future<String> _accessToken({bool forceRefresh = false}) {
    final activeRefresh = _refreshInFlight;
    if (activeRefresh != null) return activeRefresh;

    final session = _session;
    if (session == null) return Future.error(StateError('not authenticated'));
    if (forceRefresh) return _refreshAccessToken();
    if (!session.isAccessTokenExpiringSoon()) {
      return Future.value(session.accessToken);
    }
    return _refreshAccessToken();
  }

  Future<String> _refreshAccessToken() {
    final activeRefresh = _refreshInFlight;
    if (activeRefresh != null) return activeRefresh;

    final session = _session;
    if (session == null) return Future.error(StateError('not authenticated'));

    final refresh = _refreshSession(session.refreshToken);
    _refreshInFlight = refresh;
    refresh.whenComplete(() => _refreshInFlight = null);
    return refresh;
  }

  Future<String> _refreshSession(String refreshToken) async {
    final client = AuthClient(baseUrl: _apiBaseUrl);
    try {
      final session = await client.refresh(refreshToken);
      await widget.tokenStore.writeRefreshToken(session.refreshToken);
      if (!mounted) return session.accessToken;
      setState(() => _session = session);
      _scheduleTokenRefresh(session);
      return session.accessToken;
    } catch (_) {
      await widget.tokenStore.clearRefreshToken();
      if (mounted) {
        _refreshTimer?.cancel();
        _refreshTimer = null;
        setState(() => _session = null);
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  void _scheduleTokenRefresh(AuthSession session) {
    _refreshTimer?.cancel();
    final delay = session.accessTokenExpiresAt
        .subtract(const Duration(seconds: 60))
        .difference(DateTime.now());
    _refreshTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _refreshAccessToken().catchError((_) => '');
    });
  }

  Future<void> _acceptSession(AuthSession session) async {
    await widget.tokenStore.writeRefreshToken(session.refreshToken);
    await widget.tokenStore.writeApiBaseUrl(_apiBaseUrl);
    if (!mounted) return;
    await _runWithHiddenWindow(() async {
      if (!mounted) return;
      setState(() => _session = session);
      await _restoreAppWindow();
    });
    _scheduleTokenRefresh(session);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _revealFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      // While we still might be restoring an existing session at startup,
      // render an empty placeholder rather than the login form. Otherwise
      // _LoginPage's initState would lock the window to the login size,
      // undoing the authenticated-startup window prep.
      if (widget.startsAuthenticated && !_initialRestoreDone) {
        return const ColoredBox(color: _windowBackground);
      }
      return _LoginPage(
        apiBaseUrl: _apiBaseUrl,
        onAuthenticated: _acceptSession,
      );
    }

    return HomePage(
      session: session,
      apiBaseUrl: _apiBaseUrl,
      accessTokenProvider: _accessToken,
      onLogout: _logout,
    );
  }
}

class _LoginPage extends StatefulWidget {
  const _LoginPage({required this.apiBaseUrl, required this.onAuthenticated});

  final String apiBaseUrl;
  final Future<void> Function(AuthSession session) onAuthenticated;

  @override
  State<_LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<_LoginPage> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_consumeSkipNextLoginWindowLock()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_lockAuthWindow(moveWindow: false));
    });
  }

  Future<void> _submit() async {
    if (_busy) return;

    final login = _email.text.trim();
    final password = _password.text;
    if (login.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your credentials to continue.');
      return;
    }

    if (_registering) {
      final username = _username.text.trim();
      final confirm = _confirmPassword.text;
      if (username.isEmpty) {
        setState(() => _error = 'Username is required.');
        return;
      }
      if (password != confirm) {
        setState(() => _error = 'Passwords do not match.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final client = AuthClient(baseUrl: widget.apiBaseUrl);
    try {
      final session = _registering
          ? await client.register(
              username: _username.text.trim(),
              email: login,
              password: password,
            )
          : await client.login(login: login, password: password);
      if (!mounted) return;
      await widget.onAuthenticated(session);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Cannot reach the server: $e';
      });
      return;
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _setMode(bool registering) {
    if (_busy || _registering == registering) return;
    if (registering) {
      unawaited(_expandAndShowRegister());
      return;
    }
    setState(() {
      _registering = false;
      _error = null;
    });
    unawaited(_lockAuthWindow());
  }

  Future<void> _expandAndShowRegister() async {
    await _lockAuthWindow(registering: true);
    if (!mounted || _busy) return;
    setState(() {
      _registering = true;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14171D),
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: _authWidgetSize(_registering).width,
          height: _authWidgetSize(_registering).height,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF181C24)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, bottom: 4),
                      child: Text(
                        'Gang Chat',
                        style: TextStyle(
                          color: Color(0xFFECEFF1),
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 17),
                    _AuthModeSwitch(
                      registering: _registering,
                      enabled: !_busy,
                      onLogin: () => _setMode(false),
                      onRegister: () => _setMode(true),
                    ),
                    const SizedBox(height: 12),
                    if (_registering) ...[
                      _LoginLineField(
                        icon: Icons.person_outline,
                        controller: _username,
                        enabled: !_busy,
                        hintText: 'Username',
                        autofillHints: const [AutofillHints.username],
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _LoginLineField(
                      icon: _registering
                          ? Icons.alternate_email
                          : Icons.person_outline,
                      controller: _email,
                      enabled: !_busy,
                      hintText: _registering
                          ? 'Email address'
                          : 'Username or email address',
                      autofillHints: _registering
                          ? const [AutofillHints.email]
                          : const [AutofillHints.username, AutofillHints.email],
                      keyboardType: _registering
                          ? TextInputType.emailAddress
                          : TextInputType.text,
                    ),
                    const SizedBox(height: 8),
                    _LoginLineField(
                      icon: Icons.lock_outline,
                      controller: _password,
                      enabled: !_busy,
                      hintText: 'Password',
                      autofillHints: [
                        _registering
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      obscureText: _obscurePassword,
                      trailing: _PasswordVisibilityToggle(
                        obscure: _obscurePassword,
                        enabled: !_busy,
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                      onSubmitted: _registering ? null : (_) => _submit(),
                    ),
                    if (_registering) ...[
                      const SizedBox(height: 8),
                      _LoginLineField(
                        icon: Icons.lock_outline,
                        controller: _confirmPassword,
                        enabled: !_busy,
                        hintText: 'Confirm password',
                        autofillHints: const [AutofillHints.newPassword],
                        obscureText: _obscureConfirmPassword,
                        trailing: _PasswordVisibilityToggle(
                          obscure: _obscureConfirmPassword,
                          enabled: !_busy,
                          onPressed: () {
                            setState(
                              () => _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                            );
                          },
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 38,
                      child: Stack(
                        children: [
                          if (_error != null)
                            Positioned.fill(
                              right: 130,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _error!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFE58383),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              height: 38,
                              child: OverflowBox(
                                alignment: Alignment.topRight,
                                minHeight: 46,
                                maxHeight: 46,
                                child: KeyButton(
                                  onPressed: _submit,
                                  loading: _busy,
                                  height: 38,
                                  tone: KeyButtonTone.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: _busy
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF6FCFA6),
                                          ),
                                        )
                                      : Text(
                                          _registering
                                              ? 'Create account'
                                              : 'Login',
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthModeSwitch extends StatelessWidget {
  const _AuthModeSwitch({
    required this.registering,
    required this.enabled,
    required this.onLogin,
    required this.onRegister,
  });

  final bool registering;
  final bool enabled;
  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          _AuthModeTab(
            label: 'Login',
            active: !registering,
            enabled: enabled,
            onTap: onLogin,
          ),
          const SizedBox(width: 18),
          _AuthModeTab(
            label: 'Register',
            active: registering,
            enabled: enabled,
            onTap: onRegister,
          ),
        ],
      ),
    );
  }
}

class _AuthModeTab extends StatelessWidget {
  const _AuthModeTab({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFECEFF1) : const Color(0xFF6F7785);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        height: 22,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? const Color(0xFF6FCFA6) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                height: 1,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginLineField extends StatelessWidget {
  const _LoginLineField({
    required this.icon,
    required this.controller,
    required this.enabled,
    required this.hintText,
    this.autofillHints,
    this.keyboardType,
    this.obscureText = false,
    this.trailing,
    this.onSubmitted,
  });

  final IconData icon;
  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final Iterable<String>? autofillHints;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 36,
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, 1.5),
                child: Icon(icon, color: Color(0xFF6F7785), size: 16),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              autofillHints: autofillHints,
              keyboardType: keyboardType,
              obscureText: obscureText,
              onSubmitted: onSubmitted,
              cursorColor: const Color(0xFFB0B8C0),
              style: const TextStyle(
                color: Color(0xFFECEFF1),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF6F7785),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _PasswordVisibilityToggle extends StatelessWidget {
  const _PasswordVisibilityToggle({
    required this.obscure,
    required this.enabled,
    required this.onPressed,
  });

  final bool obscure;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? const Color(0xFFB0B8C0) : const Color(0xFF6F7785);
    return Tooltip(
      message: obscure ? 'Show password' : 'Hide password',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: obscure ? 'Show password' : 'Hide password',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: 30,
            height: 36,
            child: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 17,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
