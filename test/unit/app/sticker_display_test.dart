import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/sticker_display.dart';
import 'package:client/src/app/sticker_uploads.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('stickerPanelStickers flattens packs from the selected source', () {
    final personal = [
      _pack('personal_pack', ['p1', 'p2']),
    ];
    final room = [
      _pack('room_pack', ['r1']),
    ];

    expect(
      stickerPanelStickers(
        source: StickerPanelSource.personal,
        personalPacks: personal,
        roomPacks: room,
      ).map((sticker) => sticker.id),
      ['p1', 'p2'],
    );
    expect(
      stickerPanelStickers(
        source: StickerPanelSource.room,
        personalPacks: personal,
        roomPacks: room,
      ).map((sticker) => sticker.id),
      ['r1'],
    );
  });

  test('stickerPanelBodyState prioritizes result loading error and empty', () {
    final stickers = _pack('pack', ['s1']).stickers;

    expect(
      stickerPanelBodyState(
        loading: true,
        error: 'network',
        stickers: stickers,
      ),
      StickerPanelBodyState.results,
    );
    expect(
      stickerPanelBodyState(
        loading: true,
        error: 'network',
        stickers: const [],
      ),
      StickerPanelBodyState.loading,
    );
    expect(
      stickerPanelBodyState(
        loading: false,
        error: 'network',
        stickers: const [],
      ),
      StickerPanelBodyState.error,
    );
    expect(
      stickerPanelBodyState(loading: false, error: null, stickers: const []),
      StickerPanelBodyState.empty,
    );
  });

  test('stickerPanelEmptyText describes the selected source', () {
    expect(stickerPanelEmptyText(StickerPanelSource.personal), '暂无个人表情');
    expect(stickerPanelEmptyText(StickerPanelSource.room), '暂无房间表情');
  });

  test('sticker panel load state covers reset source and load gates', () {
    const initial = StickerPanelLoadState();

    expect(initial.source, StickerPanelSource.personal);
    expect(initial.personalPacks, isEmpty);
    expect(initial.roomPacks, isEmpty);
    expect(initial.loading, isFalse);
    expect(initial.loaded, isFalse);
    expect(initial.error, isNull);
    expect(shouldLoadStickerPanel(state: initial, forceReload: false), isTrue);

    final roomSource = stickerPanelSourceChanged(
      initial,
      StickerPanelSource.room,
    );
    final started = stickerPanelLoadStarted(roomSource);

    expect(started.source, StickerPanelSource.room);
    expect(started.loading, isTrue);
    expect(started.error, isNull);
    expect(shouldLoadStickerPanel(state: started, forceReload: true), isFalse);

    final reset = stickerPanelReset(source: started.source);

    expect(reset.source, StickerPanelSource.room);
    expect(reset.loaded, isFalse);
    expect(reset.loading, isFalse);
  });

  test('sticker panel load patches keep cached and loaded packs reusable', () {
    const initial = StickerPanelLoadState(error: 'previous');
    final cached = [
      _pack('cached_pack', ['cached']),
    ];
    final room = [
      _pack('room_pack', ['room']),
    ];

    final started = stickerPanelLoadStarted(initial);
    final cachedApplied = stickerPanelCachedPersonalApplied(
      state: started,
      packs: cached,
    );

    expect(cachedApplied.personalPacks.map((pack) => pack.id), ['cached_pack']);
    expect(cachedApplied.loading, isTrue);

    final succeeded = stickerPanelLoadSucceeded(
      state: cachedApplied,
      personalPacks: cached,
      roomPacks: room,
    );

    expect(succeeded.personalPacks.map((pack) => pack.id), ['cached_pack']);
    expect(succeeded.roomPacks.map((pack) => pack.id), ['room_pack']);
    expect(succeeded.loading, isFalse);
    expect(succeeded.loaded, isTrue);
    expect(succeeded.error, isNull);
    expect(
      shouldLoadStickerPanel(state: succeeded, forceReload: false),
      isFalse,
    );
    expect(shouldLoadStickerPanel(state: succeeded, forceReload: true), isTrue);

    final failed = stickerPanelLoadFailed(
      state: stickerPanelLoadStarted(succeeded),
      failure: StateError('network failed'),
    );

    expect(failed.personalPacks.map((pack) => pack.id), ['cached_pack']);
    expect(failed.roomPacks.map((pack) => pack.id), ['room_pack']);
    expect(failed.loading, isFalse);
    expect(failed.loaded, isTrue);
    expect(failed.error, 'Bad state: network failed');

    final finished = stickerPanelLoadFinished(failed);

    expect(finished.loading, isFalse);
    expect(finished.error, failed.error);
  });

  test('stickerDimensionsText prefers asset dimensions', () {
    expect(
      stickerDimensionsText(
        _asset(width: 80, height: 64),
        resolved: const StickerImageDimensions(width: 10, height: 10),
        resolving: false,
        failed: false,
      ),
      '80x64',
    );
  });

  test('stickerDimensionsText uses resolved dimensions and states', () {
    expect(
      stickerDimensionsText(
        _asset(),
        resolved: const StickerImageDimensions(width: 20, height: 30),
        resolving: false,
        failed: false,
      ),
      '20x30',
    );
    expect(
      stickerDimensionsText(_asset(), resolving: true, failed: false),
      '正在读取尺寸',
    );
    expect(
      stickerDimensionsText(_asset(), resolving: false, failed: true),
      '尺寸读取失败',
    );
    expect(
      stickerDimensionsText(_asset(), resolving: false, failed: false),
      '未知尺寸',
    );
  });
}

StickerPack _pack(String id, List<String> stickerIds) {
  return StickerPack(
    id: id,
    scope: 'personal',
    roomId: null,
    name: id,
    sortOrder: 10,
    updatedAt: DateTime.utc(2026, 6, 5),
    stickers: [
      for (final entry in stickerIds.asMap().entries)
        Sticker(
          id: entry.value,
          name: entry.value,
          sortOrder: (entry.key + 1) * 10,
          asset: _asset(),
        ),
    ],
  );
}

UploadedAsset _asset({int? width, int? height}) {
  return UploadedAsset(
    id: 'asset_1',
    url: '/stickers/asset.png',
    thumbnailUrl: null,
    mimeType: 'image/png',
    filename: 'asset.png',
    sizeBytes: 128,
    width: width,
    height: height,
  );
}
