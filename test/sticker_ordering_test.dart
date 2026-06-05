import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/sticker_ordering.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('orderedStickers honors draft order and keeps missing stickers', () {
    final pack = _pack('pack_1', ['a', 'b', 'c']);

    final ordered = orderedStickers(pack, order: ['c', 'missing', 'a']);

    expect(ordered.map((sticker) => sticker.id), ['c', 'a', 'b']);
  });

  test('asset id pinning preserves uploaded asset order', () {
    final pack = _pack('pack_1', ['a', 'b', 'c']);

    final next = stickerOrderWithAssetIdsPinnedToFront(pack, [
      'asset_c',
      'asset_a',
    ]);

    expect(next, ['c', 'a', 'b']);
  });

  test('move and pin return null when order does not change', () {
    final pack = _pack('pack_1', ['a', 'b', 'c']);

    expect(movedStickerOrder(pack, 'b', 1), ['a', 'c', 'b']);
    expect(movedStickerOrder(pack, 'a', -1), isNull);
    expect(pinnedStickerOrder(pack, 'c'), ['c', 'a', 'b']);
    expect(pinnedStickerOrder(pack, 'a'), isNull);
  });

  test('stickerPlacement exposes reusable move and pin state', () {
    final packs = [
      _pack('pack_1', ['a', 'b', 'c']),
    ];

    final first = stickerPlacement(packs, 'a');
    expect(first?.index, 0);
    expect(first?.total, 3);
    expect(first?.canMoveUp, isFalse);
    expect(first?.canMoveDown, isTrue);
    expect(first?.canPin, isFalse);

    final middle = stickerPlacement(packs, 'b');
    expect(middle?.pack.id, 'pack_1');
    expect(middle?.sticker.id, 'b');
    expect(middle?.canMoveUp, isTrue);
    expect(middle?.canMoveDown, isTrue);
    expect(middle?.canPin, isTrue);

    expect(stickerPlacement(packs, 'missing'), isNull);
  });

  test('selectedStickerIdsByPack groups visible selection by owning pack', () {
    final packs = [
      _pack('pack_1', ['a', 'b']),
      _pack('pack_2', ['c']),
    ];

    final grouped = selectedStickerIdsByPack(packs, ['c', 'missing', 'a']);

    expect(grouped, {
      'pack_2': ['c'],
      'pack_1': ['a'],
    });
  });
}

StickerPack _pack(String id, List<String> stickerIds) {
  return StickerPack(
    id: id,
    scope: 'personal',
    roomId: null,
    name: id,
    sortOrder: 10,
    updatedAt: DateTime.utc(2026, 6, 4),
    stickers: [
      for (final entry in stickerIds.asMap().entries)
        Sticker(
          id: entry.value,
          name: entry.value,
          sortOrder: (entry.key + 1) * 10,
          asset: UploadedAsset(
            id: 'asset_${entry.value}',
            url: '/assets/${entry.value}.png',
            thumbnailUrl: null,
            mimeType: 'image/png',
          ),
        ),
    ],
  );
}
