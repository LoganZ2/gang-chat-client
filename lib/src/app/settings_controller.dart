import 'dart:typed_data';

import '../protocol/api_client.dart';
import '../protocol/models.dart';
import '../protocol/sticker_pack_store.dart';

class PersonalStickerPacksResult {
  const PersonalStickerPacksResult({
    required this.packs,
    required this.fromCache,
  });

  final List<StickerPack> packs;
  final bool fromCache;
}

class SettingsController {
  const SettingsController({
    required this.api,
    required this.apiBaseUrl,
    required this.stickerPackStore,
  });

  final GangApi? api;
  final String apiBaseUrl;
  final StickerPackStore stickerPackStore;

  bool get hasApi => api != null;

  Future<AppVersionInfo?> checkAppVersion() {
    final client = api;
    if (client == null) return Future.value();
    return client.getAppVersion();
  }

  Future<CurrentUser?> loadAccount() {
    final client = api;
    if (client == null) return Future.value();
    return client.me();
  }

  Future<List<UserSummary>?> searchUsers({
    required String query,
    int limit = 20,
  }) {
    final client = api;
    if (client == null) return Future.value();
    return client.searchUsers(query: query, limit: limit);
  }

  Future<List<UserSession>?> loadSessions() {
    final client = api;
    if (client == null) return Future.value();
    return client.listSessions();
  }

  Future<PersonalStickerPacksResult?> loadPersonalStickerPacks({
    required String userId,
    bool forceReload = false,
  }) async {
    if (!forceReload) {
      final cached = await stickerPackStore.readPersonalPacks(
        userId: userId,
        apiBaseUrl: apiBaseUrl,
      );
      if (cached != null) {
        return PersonalStickerPacksResult(packs: cached, fromCache: true);
      }
    }

    final client = api;
    if (client == null) return null;
    final packs = await client.listStickerPacks(scope: 'personal');
    await stickerPackStore.writePersonalPacks(
      userId: userId,
      apiBaseUrl: apiBaseUrl,
      packs: packs,
    );
    return PersonalStickerPacksResult(packs: packs, fromCache: false);
  }

  Future<CurrentUser?> updateAccount({
    String? username,
    String? email,
    bool? emailPublic,
    String? phoneNumber,
    bool? phoneNumberPublic,
    String? language,
  }) {
    final client = api;
    if (client == null) return Future.value();
    return client.updateAccount(
      username: username,
      email: email,
      emailPublic: emailPublic,
      phoneNumber: phoneNumber,
      phoneNumberPublic: phoneNumberPublic,
      language: language,
    );
  }

  Future<CurrentUser?> updateProfile({
    String? displayName,
    String? bio,
    String? gender,
    String? avatarAssetId,
    String? defaultAvatarKey,
  }) {
    final client = api;
    if (client == null) return Future.value();
    return client.updateProfile(
      displayName: displayName,
      bio: bio,
      gender: gender,
      avatarAssetId: avatarAssetId,
      defaultAvatarKey: defaultAvatarKey,
    );
  }

  Future<UploadedAsset?> uploadImageAsset({
    required Uint8List bytes,
    required String filename,
    required String purpose,
  }) {
    final client = api;
    if (client == null) return Future.value();
    return client.uploadImageAsset(
      bytes: bytes,
      filename: filename,
      purpose: purpose,
    );
  }

  Future<StickerPack?> createStickerPack({
    required String name,
    int? sortOrder,
  }) {
    final client = api;
    if (client == null) return Future.value();
    return client.createStickerPack(name: name, sortOrder: sortOrder);
  }

  Future<void> addSticker({
    required String packId,
    required String assetId,
    required String name,
    int? sortOrder,
  }) {
    final client = api;
    if (client == null) return Future.value();
    return client.addSticker(
      packId: packId,
      assetId: assetId,
      name: name,
      sortOrder: sortOrder,
    );
  }

  Future<void> deleteSticker({
    required String packId,
    required String stickerId,
  }) {
    final client = api;
    if (client == null) return Future.value();
    return client.deleteSticker(packId: packId, stickerId: stickerId);
  }

  Future<Sticker?> updateSticker({
    required String packId,
    required String stickerId,
    String? name,
    int? sortOrder,
  }) {
    final client = api;
    if (client == null) return Future.value();
    return client.updateSticker(
      packId: packId,
      stickerId: stickerId,
      name: name,
      sortOrder: sortOrder,
    );
  }

  Future<void> reorderStickers({
    required String packId,
    required List<String> stickerIds,
  }) {
    final client = api;
    if (client == null) return Future.value();
    return client.reorderStickers(packId: packId, stickerIds: stickerIds);
  }

  Future<DownloadedFile?> downloadStickers({required List<String> stickerIds}) {
    final client = api;
    if (client == null) return Future.value();
    return client.downloadStickers(stickerIds: stickerIds);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    final client = api;
    if (client == null) return Future.value();
    return client.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  Future<void> deleteMyAccount() {
    final client = api;
    if (client == null) return Future.value();
    return client.deleteMyAccount(confirm: true);
  }
}
