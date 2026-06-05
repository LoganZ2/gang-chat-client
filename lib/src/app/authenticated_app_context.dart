import '../auth/auth_client.dart';
import '../protocol/api_client.dart';
import '../protocol/models.dart';
import '../protocol/sticker_pack_store.dart';

typedef LogoutCallback = Future<void> Function();

class AuthenticatedAppContext {
  const AuthenticatedAppContext({
    required this.session,
    required this.apiBaseUrl,
    required this.accessTokenProvider,
    required this.logout,
    this.api,
    this.stickerPackStore = const StickerPackStore(),
  });

  final AuthSession session;
  final String apiBaseUrl;
  final AccessTokenProvider accessTokenProvider;
  final LogoutCallback logout;
  final GangApi? api;
  final StickerPackStore stickerPackStore;

  CurrentUser get currentUser => session.user;

  GangApi createApiClient() {
    final injectedApi = api;
    if (injectedApi != null) return injectedApi;
    return GangApiClient(
      baseUrl: apiBaseUrl,
      accessTokenProvider: accessTokenProvider,
    );
  }

  bool hasSameApiSource(AuthenticatedAppContext other) {
    return apiBaseUrl == other.apiBaseUrl && api == other.api;
  }
}
