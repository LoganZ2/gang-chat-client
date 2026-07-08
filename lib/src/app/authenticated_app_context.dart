import '../auth/auth_client.dart';
import '../protocol/api_client.dart';
import '../protocol/models.dart';
import '../protocol/sticker_pack_store.dart';
import 'server_clock.dart';

typedef LogoutCallback = Future<void> Function();
typedef ExitSessionCallback = Future<void> Function();

class AuthenticatedAppContext {
  const AuthenticatedAppContext({
    required this.session,
    required this.apiBaseUrl,
    required this.accessTokenProvider,
    required this.logout,
    required this.exitSessionForAppExit,
    required this.serverClock,
    this.api,
    this.stickerPackStore = const StickerPackStore(),
  });

  final AuthSession session;
  final String apiBaseUrl;
  final AccessTokenProvider accessTokenProvider;
  final LogoutCallback logout;
  final ExitSessionCallback exitSessionForAppExit;
  final ServerClock serverClock;
  final GangApi? api;
  final StickerPackStore stickerPackStore;

  CurrentUser get currentUser => session.user;

  GangApi createApiClient() {
    final injectedApi = api;
    if (injectedApi != null) return injectedApi;
    return GangApiClient(
      baseUrl: apiBaseUrl,
      accessTokenProvider: accessTokenProvider,
      onServerTime: serverClock.updateFromHeader,
      onRequestLatency: serverClock.updateRequestRoundTrip,
    );
  }

  bool hasSameApiSource(AuthenticatedAppContext other) {
    return apiBaseUrl == other.apiBaseUrl &&
        api == other.api &&
        serverClock == other.serverClock;
  }
}
