import 'dart:io' show HttpClient, HttpOverrides, Platform, SecurityContext;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'src/auth/token_store.dart';
import 'src/config/app_config.dart';
import 'src/shell/desktop_window_controller.dart';
import 'src/shell/gang_app.dart';
import 'src/shell/windows_key_event_guard.dart';

export 'src/shell/gang_app.dart' show GangApp;

Future<void> main(List<String> args) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  installWindowsAltKeyEventGuard();

  // Bypass Apple's voice-processing unit on macOS before the WebRTC factory is
  // created. On Windows, eagerly touching WebRTC during app launch can make the
  // OS treat the app as an active communications client and adjust system audio,
  // so Windows lets the plugin initialize lazily on the first real Live action.
  if (!kIsWeb && Platform.isMacOS) {
    await rtc.WebRTC.initialize(options: {'bypassVoiceProcessing': true});
  }

  final config = await AppConfig.load();
  _installConfiguredHostProxyBypass(config);

  // Pre-read the refresh token so we can size the initial window correctly
  // (login vs full app) before it ever renders. Without this, an
  // already-logged-in user briefly sees the small login-sized window before
  // it grows to the app size, which looks like a layout flicker.
  const tokenStore = TokenStore();
  final hasStoredSession =
      (await tokenStore.readRefreshToken())?.isNotEmpty ?? false;
  final windowController = DesktopWindowController();

  await windowController.prepareForLaunch(
    authenticated: hasStoredSession,
  );
  runApp(
    GangApp(
      config: config,
      tokenStore: tokenStore,
      startsAuthenticated: hasStoredSession,
      windowController: windowController,
    ),
  );
  // The window is shown by AuthGate after it has decided which screen to render.
  // That avoids both login/app resize flicker and pre-restore home flashes.
  await windowController.waitUntilFirstFrameRasterized(binding);
}

void _installConfiguredHostProxyBypass(AppConfig config) {
  if (kIsWeb) return;
  final directHosts = <String>{
    _hostFromUrl(config.apiBaseUrl),
    _hostFromUrl(config.assetBaseUrl),
  }..remove('');
  if (directHosts.isEmpty) return;
  HttpOverrides.global = _GangHttpOverrides(
    directHosts: directHosts,
    parent: HttpOverrides.current,
  );
}

String _hostFromUrl(String value) {
  return Uri.tryParse(value)?.host.toLowerCase() ?? '';
}

class _GangHttpOverrides extends HttpOverrides {
  _GangHttpOverrides({required this.directHosts, required this.parent});

  final Set<String> directHosts;
  final HttpOverrides? parent;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client =
        parent?.createHttpClient(context) ?? super.createHttpClient(context);
    client.findProxy = (uri) {
      if (directHosts.contains(uri.host.toLowerCase())) return 'DIRECT';
      return HttpClient.findProxyFromEnvironment(uri);
    };
    return client;
  }
}
