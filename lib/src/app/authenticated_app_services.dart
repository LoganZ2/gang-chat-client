import '../protocol/api_client.dart';
import 'audio_device_store.dart';
import 'authenticated_app_context.dart';
import 'file_downloads_controller.dart';
import 'global_search_controller.dart';
import 'live_controller.dart';
import 'live_session_controller.dart';
import 'messages_controller.dart';
import 'realtime_controller.dart';
import 'rooms_controller.dart';
import 'settings_controller.dart';
import 'sticker_packs_controller.dart';
import 'voice_recorder_controller.dart';

class AuthenticatedAppServices {
  AuthenticatedAppServices._({
    required this.context,
    required this.api,
    required this.rooms,
    required this.messages,
    required this.live,
    required this.liveSession,
    required this.realtime,
    required this.fileDownloads,
    required this.search,
    required this.settings,
    required this.stickers,
    required this.voiceRecorder,
    required this.ownsLiveSession,
    required this.ownsRealtime,
  });

  factory AuthenticatedAppServices(
    AuthenticatedAppContext context, {
    required AudioDeviceStore audioDeviceStore,
    LiveSessionController? liveSessionController,
    RealtimeService? realtime,
  }) {
    final api = context.createApiClient();
    final liveSession =
        liveSessionController ??
        LiveSessionController(
          apiBaseUrl: context.apiBaseUrl,
          audioDeviceStore: audioDeviceStore,
        );
    return AuthenticatedAppServices._(
      context: context,
      api: api,
      rooms: RoomsController(api: api),
      messages: MessagesController(api: api),
      live: LiveController(api: api),
      liveSession: liveSession,
      realtime:
          realtime ??
          RealtimeController(
            apiBaseUrl: context.apiBaseUrl,
            accessTokenProvider: context.accessTokenProvider,
          ),
      fileDownloads: FileDownloadsController(),
      search: GlobalSearchController(api: api),
      settings: SettingsController(
        api: api,
        apiBaseUrl: context.apiBaseUrl,
        stickerPackStore: context.stickerPackStore,
      ),
      stickers: StickerPacksController(
        api: api,
        apiBaseUrl: context.apiBaseUrl,
        stickerPackStore: context.stickerPackStore,
      ),
      voiceRecorder: VoiceRecorderController(),
      ownsLiveSession: liveSessionController == null,
      ownsRealtime: realtime == null,
    );
  }

  final AuthenticatedAppContext context;
  final GangApi api;
  final RoomsController rooms;
  final MessagesController messages;
  final LiveController live;
  final LiveSessionController liveSession;
  final RealtimeService realtime;
  final FileDownloadsController fileDownloads;
  final GlobalSearchController search;
  final SettingsController settings;
  final StickerPacksController stickers;
  final VoiceRecorderController voiceRecorder;
  final bool ownsLiveSession;
  final bool ownsRealtime;

  Future<void> warmPersonalStickerCache({required String userId}) async {
    try {
      await stickers.loadPersonalPacks(userId: userId);
    } catch (_) {
      // Cache warmup is opportunistic; callers should keep rendering the last
      // available state even if the network is down.
    }
  }

  void close() {
    if (ownsRealtime) realtime.dispose();
    if (ownsLiveSession) liveSession.dispose();
    voiceRecorder.dispose();
    api.close();
  }
}
