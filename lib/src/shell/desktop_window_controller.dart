import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../lifecycle/shutdown_hooks.dart';

const appWindowBackground = Color(0xFF14171D);

const _appWindowMinSize = Size(720, 480);
const _appWindowSize = Size(1180, 760);
const _unboundedWindowSize = Size(100000, 100000);
const _minimumWindowSize = Size(1, 1);
const _authWidgetWidth = 430.0;
const _loginWidgetHeight = 256.0;
const _registerWidgetHeight = 344.0;
const _loginWidgetSize = Size(_authWidgetWidth, _loginWidgetHeight);
const _registerWidgetSize = Size(_authWidgetWidth, _registerWidgetHeight);
// Window controls float as an overlay rather than occupying a dedicated strip,
// so auth windows are sized exactly to their content.
const _loginWindowSize = _loginWidgetSize;
const _registerWindowSize = _registerWidgetSize;

class DesktopWindowController {
  bool _skipNextAuthWindowLock = false;

  bool get supportsWindowManagement =>
      !kIsWeb &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  Size get loginWidgetSize => _loginWidgetSize;

  Size authWidgetSize(bool registering) =>
      registering ? _registerWidgetSize : _loginWidgetSize;

  Future<void> prepareForLaunch({required bool authenticated}) async {
    if (!supportsWindowManagement) return;

    await windowManager.ensureInitialized();
    _skipNextAuthWindowLock = Platform.isMacOS;
    await windowManager.waitUntilReadyToShow(
      _initialWindowOptions(authenticated: authenticated),
      () async {},
    );
    if (authenticated) {
      await _prepareAuthenticatedInitialWindow();
    } else {
      await _prepareInitialWindow();
    }
    await windowManager.setPreventClose(true);
    windowManager.addListener(_AppWindowListener());
  }

  Future<void> waitUntilFirstFrameRasterized(WidgetsBinding binding) async {
    if (!supportsWindowManagement) return;
    await binding.waitUntilFirstFrameRasterized;
  }

  Future<void> showInitialWindow() {
    return _configure(() async {
      if (Platform.isMacOS) {
        await windowManager.setOpacity(1);
        return;
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  Future<void> lockAuthWindow({
    bool registering = false,
    bool moveWindow = true,
    bool centerWindow = false,
  }) {
    return _configure(() async {
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

  Future<void> restoreAppWindow() {
    return _configure(() async {
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

  Future<void> runWithHiddenWindow(Future<void> Function() body) async {
    if (!supportsWindowManagement) {
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

  bool consumeSkipNextAuthWindowLock() {
    if (!_skipNextAuthWindowLock) return false;
    _skipNextAuthWindowLock = false;
    return true;
  }

  WindowOptions _initialWindowOptions({bool authenticated = false}) {
    if (Platform.isMacOS) {
      return const WindowOptions(
        backgroundColor: appWindowBackground,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
        center: true,
      );
    }
    if (authenticated) {
      return const WindowOptions(
        size: _appWindowSize,
        minimumSize: _appWindowMinSize,
        backgroundColor: appWindowBackground,
        titleBarStyle: TitleBarStyle.hidden,
        center: true,
      );
    }
    return const WindowOptions(
      size: _loginWindowSize,
      minimumSize: _loginWindowSize,
      maximumSize: _loginWindowSize,
      backgroundColor: appWindowBackground,
      titleBarStyle: TitleBarStyle.hidden,
      center: true,
    );
  }

  Future<void> _prepareInitialWindow() {
    return _configure(() async {
      await _setWindowMaximizable(false);
      await _setWindowShadow(false);
      await windowManager.setResizable(false);
      await windowManager.setAlignment(Alignment.center);
      if (Platform.isMacOS) {
        // macOS shows the window immediately; opaque-zero it until AuthGate is
        // ready so the pre-render frame stays hidden.
        await windowManager.setOpacity(0);
      }
    });
  }

  /// Initial window prep when we already know the user is logged in: skip the
  /// auth-window lock and jump straight to the app window's sizing/resizable
  /// state so the home screen doesn't visibly resize after the auth refresh
  /// completes.
  Future<void> _prepareAuthenticatedInitialWindow() {
    return _configure(() async {
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

  Size _authWindowSize(bool registering) =>
      registering ? _registerWindowSize : _loginWindowSize;

  Future<void> _configure(Future<void> Function() configure) async {
    if (!supportsWindowManagement) return;
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
    return _configure(() => windowManager.setOpacity(opacity));
  }

  Future<bool> _isAuthWindowSized(Size targetSize) async {
    final size = await windowManager.getSize();
    return (size.width - targetSize.width).abs() < 1 &&
        (size.height - targetSize.height).abs() < 1;
  }
}

class _AppWindowListener extends WindowListener {
  // How long async cleanup can run before we force the process to exit. The
  // window is already hidden, so this budget is invisible to the user.
  static const _shutdownBudget = Duration(milliseconds: 1200);
  bool _closing = false;

  @override
  void onWindowClose() {
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_closing) return;
    _closing = true;

    try {
      await windowManager.hide();
    } catch (_) {}

    try {
      await Future.any([
        ShutdownHooks.runAll(),
        Future<void>.delayed(_shutdownBudget),
      ]);
    } catch (_) {
      // Local process shutdown should not be blocked by cleanup errors.
    }

    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }
}
