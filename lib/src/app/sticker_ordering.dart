import '../protocol/models.dart';

class StickerPlacementData {
  const StickerPlacementData({
    required this.pack,
    required this.sticker,
    required this.index,
    required this.total,
  });

  final StickerPack pack;
  final Sticker sticker;
  final int index;
  final int total;

  bool get canMoveUp => index > 0;
  bool get canMoveDown => index < total - 1;
  bool get canPin => index > 0;
}

List<Sticker> orderedStickers(StickerPack pack, {List<String>? order}) {
  final remaining = {for (final sticker in pack.stickers) sticker.id: sticker};
  final targetOrder = order ?? pack.stickers.map((sticker) => sticker.id);
  final ordered = <Sticker>[];
  for (final stickerId in targetOrder) {
    final sticker = remaining.remove(stickerId);
    if (sticker != null) ordered.add(sticker);
  }
  ordered.addAll(remaining.values);
  return ordered;
}

List<String> orderedStickerIds(StickerPack pack, {List<String>? order}) {
  return orderedStickers(
    pack,
    order: order,
  ).map((sticker) => sticker.id).toList();
}

StickerPack? stickerPackById(List<StickerPack> packs, String packId) {
  for (final pack in packs) {
    if (pack.id == packId) return pack;
  }
  return null;
}

StickerPack? stickerPackForSticker(List<StickerPack> packs, String stickerId) {
  for (final pack in packs) {
    if (pack.stickers.any((sticker) => sticker.id == stickerId)) return pack;
  }
  return null;
}

StickerPlacementData? stickerPlacement(
  List<StickerPack> packs,
  String stickerId, {
  List<String>? Function(StickerPack pack)? orderForPack,
}) {
  for (final pack in packs) {
    final ordered = orderedStickers(pack, order: orderForPack?.call(pack));
    final index = ordered.indexWhere((sticker) => sticker.id == stickerId);
    if (index < 0) continue;
    return StickerPlacementData(
      pack: pack,
      sticker: ordered[index],
      index: index,
      total: ordered.length,
    );
  }
  return null;
}

List<String>? movedStickerOrder(
  StickerPack pack,
  String stickerId,
  int delta, {
  List<String>? order,
}) {
  final ids = orderedStickerIds(pack, order: order);
  final from = ids.indexOf(stickerId);
  if (from < 0) return null;
  final to = (from + delta).clamp(0, ids.length - 1).toInt();
  if (from == to) return null;
  final moving = ids.removeAt(from);
  ids.insert(to, moving);
  return ids;
}

List<String>? pinnedStickerOrder(
  StickerPack pack,
  String stickerId, {
  List<String>? order,
}) {
  final ids = orderedStickerIds(pack, order: order);
  final index = ids.indexOf(stickerId);
  if (index <= 0) return null;
  final moving = ids.removeAt(index);
  ids.insert(0, moving);
  return ids;
}

List<String>? stickerOrderWithAssetIdsPinnedToFront(
  StickerPack pack,
  List<String> assetIds, {
  List<String>? order,
}) {
  if (assetIds.isEmpty) return null;
  final stickersByAssetId = {
    for (final sticker in pack.stickers) sticker.asset.id: sticker,
  };
  final pinnedStickerIds = <String>[];
  for (final assetId in assetIds) {
    final sticker = stickersByAssetId[assetId];
    if (sticker != null) pinnedStickerIds.add(sticker.id);
  }
  if (pinnedStickerIds.isEmpty) return null;

  return stickerOrderWithStickerIdsPinnedToFront(
    pack,
    pinnedStickerIds,
    order: order,
  );
}

List<String>? stickerOrderWithStickerIdsPinnedToFront(
  StickerPack pack,
  List<String> stickerIds, {
  List<String>? order,
}) {
  if (stickerIds.isEmpty) return null;
  final pinnedSet = stickerIds.toSet();
  final currentOrder = orderedStickerIds(pack, order: order);
  final nextOrder = [
    for (final stickerId in stickerIds)
      if (currentOrder.contains(stickerId)) stickerId,
    for (final stickerId in currentOrder)
      if (!pinnedSet.contains(stickerId)) stickerId,
  ];
  if (_sameStringList(currentOrder, nextOrder)) return null;
  return nextOrder;
}

Map<String, List<String>> selectedStickerIdsByPack(
  List<StickerPack> packs,
  List<String> selectedIds,
) {
  final selectedByPack = <String, List<String>>{};
  for (final stickerId in selectedIds) {
    final pack = stickerPackForSticker(packs, stickerId);
    if (pack == null) continue;
    selectedByPack.putIfAbsent(pack.id, () => <String>[]).add(stickerId);
  }
  return selectedByPack;
}

bool _sameStringList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
