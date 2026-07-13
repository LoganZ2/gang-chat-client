import '../protocol/api_client.dart';
import '../protocol/models.dart';
import '../protocol/sticker_pack_store.dart';

class StickerPacksController {
  const StickerPacksController({
    required this.api,
    required this.apiBaseUrl,
    required this.stickerPackStore,
  });

  final GangApi api;
  final String apiBaseUrl;
  final StickerPackStore stickerPackStore;

  Future<List<StickerPack>?> readCachedPersonalPacks({required String userId}) {
    return stickerPackStore.readPersonalPacks(
      userId: userId,
      apiBaseUrl: apiBaseUrl,
    );
  }

  Future<List<StickerPack>> loadPersonalPacks({
    required String userId,
    bool forceReload = false,
  }) async {
    if (!forceReload) {
      final cached = await readCachedPersonalPacks(userId: userId);
      if (cached != null) return cached;
    }

    final packs = await api.listStickerPacks(scope: 'personal');
    await stickerPackStore.writePersonalPacks(
      userId: userId,
      apiBaseUrl: apiBaseUrl,
      packs: packs,
    );
    return packs;
  }

  Future<List<StickerPack>> loadRoomPacks(String roomId) {
    return api.listStickerPacks(scope: 'room', roomId: roomId);
  }

  Future<StickerPack> saveSticker({
    required String roomId,
    required String stickerId,
    required String targetScope,
    required String userId,
    String? sourceMessageId,
    String? name,
  }) async {
    final pack = await api.saveSticker(
      roomId: roomId,
      stickerId: stickerId,
      sourceMessageId: sourceMessageId,
      targetScope: targetScope,
      name: name,
    );
    if (targetScope == 'personal') {
      final packs = await api.listStickerPacks(scope: 'personal');
      await stickerPackStore.writePersonalPacks(
        userId: userId,
        apiBaseUrl: apiBaseUrl,
        packs: packs,
      );
    }
    return pack;
  }
}
