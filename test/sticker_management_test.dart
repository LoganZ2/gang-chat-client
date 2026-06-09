import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/sticker_management.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('managedStickerItems expands packs and honors draft order', () {
    final packs = [
      _pack('pack_1', ['a', 'b', 'c']),
    ];

    final items = managedStickerItems(packs, orderForPack: (_) => ['c', 'a']);

    expect(items.map((item) => item.sticker.id), ['c', 'a', 'b']);
    expect(items.map((item) => item.pack.id).toSet(), {'pack_1'});
  });

  test('filteredManagedStickerItems matches keyword and mime type', () {
    final items = managedStickerItems([
      _pack(
        'pack_1',
        ['happy', 'sad', 'wave'],
        mimeTypes: {'happy': 'image/gif', 'wave': 'image/webp'},
      ),
    ]);

    expect(
      filteredManagedStickerItems(
        items,
        keyword: ' HAP ',
        mimeType: '',
      ).map((item) => item.sticker.id),
      ['happy'],
    );
    expect(
      filteredManagedStickerItems(
        items,
        keyword: '',
        mimeType: 'image/webp',
      ).map((item) => item.sticker.id),
      ['wave'],
    );
    expect(
      filteredManagedStickerItems(items, keyword: 'sad', mimeType: 'image/gif'),
      isEmpty,
    );
  });

  test('selection helpers keep selection behavior reusable', () {
    final items = managedStickerItems([
      _pack('pack_1', ['a', 'b', 'c']),
    ]);

    expect(stickerFilterActive(keyword: ' ', mimeType: ''), isFalse);
    expect(stickerFilterActive(keyword: '', mimeType: 'image/png'), isTrue);
    expect(stickerSelectionNumbers(['b', 'a']), {'b': 1, 'a': 2});
    expect(toggledStickerSelection(['a'], 'b'), ['a', 'b']);
    expect(toggledStickerSelection(['a', 'b'], 'a'), ['b']);
    expect(stickerSelectionForVisibleItems([], items.take(2).toList()), [
      'b',
      'a',
    ]);
    expect(
      stickerAllVisibleSelected(
        selectedStickerIds: ['b', 'a'],
        visibleItems: items.take(2).toList(),
      ),
      isTrue,
    );
    expect(
      stickerVisibleSelectionButtonText(
        selectedStickerIds: ['b', 'a'],
        visibleItems: items.take(2).toList(),
      ),
      '全选',
    );
    expect(
      stickerSelectionForVisibleItems(['a', 'b'], items.take(2).toList()),
      <String>[],
    );
    expect(
      stickerAllVisibleSelected(
        selectedStickerIds: ['a'],
        visibleItems: items.take(2).toList(),
      ),
      isFalse,
    );
    expect(
      stickerVisibleSelectionButtonText(
        selectedStickerIds: ['a'],
        visibleItems: items.take(2).toList(),
      ),
      '全选',
    );
  });

  test('management state helpers describe counts and action gates', () {
    final items = managedStickerItems([
      _pack('pack_1', ['a', 'b']),
    ]);

    expect(
      stickerManagementBusy(
        uploading: false,
        deleting: false,
        savingOrder: false,
        downloading: false,
      ),
      isFalse,
    );
    expect(
      stickerManagementBusy(
        uploading: false,
        deleting: true,
        savingOrder: false,
        downloading: false,
      ),
      isTrue,
    );
    expect(
      stickerManagementCountText(
        filterActive: false,
        visibleCount: 1,
        totalCount: 2,
      ),
      '2 个',
    );
    expect(
      stickerManagementCountText(
        filterActive: true,
        visibleCount: 1,
        totalCount: 2,
      ),
      '1 / 2 个',
    );
    expect(canStartStickerPrimaryAction(busy: false), isTrue);
    expect(canStartStickerPrimaryAction(busy: true), isFalse);
    expect(canStartStickerPrimaryAction(busy: false, allowed: false), isFalse);
    expect(
      canStartStickerSelectionAction(busy: false, selectedStickerIds: ['a']),
      isTrue,
    );
    expect(
      canStartStickerSelectionAction(
        busy: false,
        selectedStickerIds: ['a'],
        allowed: false,
      ),
      isFalse,
    );
    expect(
      canStartStickerSelectionAction(busy: false, selectedStickerIds: const []),
      isFalse,
    );
    expect(
      canStartStickerSelectionAction(busy: true, selectedStickerIds: ['a']),
      isFalse,
    );
    expect(canSelectVisibleStickers(busy: false, visibleItems: items), isTrue);
    expect(
      canSelectVisibleStickers(busy: false, visibleItems: const []),
      isFalse,
    );
    expect(canUseStickerManagementControl(busy: false), isTrue);
    expect(canUseStickerManagementControl(busy: true), isFalse);
    expect(
      canUseStickerManagementControl(busy: false, allowed: false),
      isFalse,
    );
    const roomReadOnly = StickerManagementCapabilities.readOnlyDownloads();
    expect(roomReadOnly.canUpload, isFalse);
    expect(roomReadOnly.canBatchManage, isTrue);
    expect(roomReadOnly.canFilter, isTrue);
    expect(roomReadOnly.canDownload, isTrue);
    expect(roomReadOnly.canSelectAll, isTrue);
    expect(roomReadOnly.canDelete, isFalse);
    expect(roomReadOnly.canPin, isFalse);
    expect(roomReadOnly.canRename, isFalse);
    expect(roomReadOnly.canMove, isFalse);
  });

  test('sticker rename helpers normalize and gate empty names', () {
    expect(stickerRenameName('  wave  '), 'wave');
    expect(stickerRenameName('   '), isNull);
    expect(canStartStickerRename(busy: false, name: ' wave '), isTrue);
    expect(canStartStickerRename(busy: false, name: '   '), isFalse);
    expect(canStartStickerRename(busy: true, name: 'wave'), isFalse);
    expect(
      canStartStickerRename(busy: false, name: 'wave', allowed: false),
      isFalse,
    );
  });

  test('sticker preview state gates actions and tracks busy flags', () {
    final initial = StickerPreviewState.initial(
      canMoveUp: true,
      canMoveDown: false,
      canPin: true,
    );

    expect(initial.busy, isFalse);
    expect(
      canStartStickerPreviewAction(
        state: initial,
        action: StickerPreviewActionKind.rename,
        name: ' wave ',
      ),
      isTrue,
    );
    expect(
      canStartStickerPreviewAction(
        state: initial,
        action: StickerPreviewActionKind.rename,
        name: '   ',
      ),
      isFalse,
    );

    final requested = stickerPreviewActionRequested(
      state: initial,
      action: StickerPreviewActionKind.rename,
      name: ' wave ',
    );
    expect(requested, isNotNull);
    expect(requested!.savingName, isTrue);
    expect(requested.error, isNull);
    expect(
      stickerPreviewActionRequested(
        state: initial,
        action: StickerPreviewActionKind.rename,
        name: '   ',
      ),
      isNull,
    );

    final downloading = stickerPreviewActionStarted(
      state: initial,
      action: StickerPreviewActionKind.download,
    );

    expect(downloading.busy, isTrue);
    expect(downloading.downloading, isTrue);
    expect(downloading.error, isNull);
    expect(
      canStartStickerPreviewAction(
        state: downloading,
        action: StickerPreviewActionKind.delete,
      ),
      isFalse,
    );
    expect(
      stickerPreviewActionRequested(
        state: downloading,
        action: StickerPreviewActionKind.delete,
      ),
      isNull,
    );

    final failed = stickerPreviewActionFailed(
      state: downloading,
      action: StickerPreviewActionKind.download,
      failure: StateError('download failed'),
    );

    expect(failed.busy, isFalse);
    expect(failed.downloading, isFalse);
    expect(failed.error, 'Bad state: download failed');

    final renaming = stickerPreviewActionStarted(
      state: failed,
      action: StickerPreviewActionKind.rename,
    );

    expect(renaming.savingName, isTrue);
    expect(renaming.error, isNull);

    final finished = stickerPreviewActionFinished(
      state: renaming,
      action: StickerPreviewActionKind.rename,
    );

    expect(finished.savingName, isFalse);
    expect(finished.error, isNull);
  });

  test('sticker preview move success updates placement controls', () {
    final initial = StickerPreviewState.initial(
      canMoveUp: true,
      canMoveDown: true,
      canPin: true,
    );
    final moving = stickerPreviewActionStarted(
      state: initial,
      action: StickerPreviewActionKind.pin,
    );

    final succeeded = stickerPreviewMoveSucceeded(
      state: moving,
      action: StickerPreviewActionKind.pin,
      canMoveUp: false,
      canMoveDown: true,
      canPin: false,
    );

    expect(succeeded.pinning, isFalse);
    expect(succeeded.busy, isFalse);
    expect(succeeded.canMoveUp, isFalse);
    expect(succeeded.canMoveDown, isTrue);
    expect(succeeded.canPin, isFalse);
    expect(succeeded.error, isNull);
  });

  test('personal sticker management copy stays reusable outside UI', () {
    expect(defaultStickerPackName(StickerManagementScope.personal), '我的表情包');
    expect(
      stickerUploadNotice(scope: StickerManagementScope.personal, count: 3),
      '已添加 3 个表情',
    );
    expect(stickerDeleteDialogTitle(StickerManagementScope.personal), '删除表情');
    expect(
      stickerSingleDeleteConfirmBody(
        scope: StickerManagementScope.personal,
        stickerName: 'wave',
      ),
      '将从服务端删除「wave」，删除后不会再出现在你的表情包里。',
    );
    expect(
      stickerBulkDeleteConfirmBody(
        scope: StickerManagementScope.personal,
        count: 2,
      ),
      '将从服务端删除选中的 2 个表情，删除后不会再出现在你的表情包里。',
    );
    expect(
      stickerDeletedNotice(scope: StickerManagementScope.personal),
      '表情已删除',
    );
    expect(
      stickerDeletedNotice(scope: StickerManagementScope.personal, count: 2),
      '已删除 2 个表情',
    );
    expect(
      stickerDownloadNotice(scope: StickerManagementScope.personal, count: 1),
      '表情已下载',
    );
    expect(
      stickerDownloadNotice(scope: StickerManagementScope.personal, count: 2),
      '表情压缩包已下载',
    );
    expect(
      stickerNoOrderChangeNotice(StickerManagementScope.personal),
      '表情排序没有变化',
    );
    expect(
      stickerPinnedNotice(scope: StickerManagementScope.personal),
      '表情已置顶',
    );
    expect(
      stickerPinnedNotice(scope: StickerManagementScope.personal, count: 2),
      '已置顶 2 个表情',
    );
    expect(
      stickerMoveNotice(scope: StickerManagementScope.personal, delta: -1),
      '表情已上移一位',
    );
    expect(
      stickerMoveNotice(scope: StickerManagementScope.personal, delta: 1),
      '表情已下移一位',
    );
  });

  test('room sticker management copy stays reusable outside UI', () {
    expect(defaultStickerPackName(StickerManagementScope.room), '房间表情包');
    expect(
      stickerUploadNotice(scope: StickerManagementScope.room, count: 3),
      '已添加 3 个房间表情',
    );
    expect(stickerDeleteDialogTitle(StickerManagementScope.room), '删除房间表情');
    expect(
      stickerSingleDeleteConfirmBody(
        scope: StickerManagementScope.room,
        stickerName: 'wave',
      ),
      '将从这个房间的表情包中删除「wave」。',
    );
    expect(
      stickerBulkDeleteConfirmBody(
        scope: StickerManagementScope.room,
        count: 2,
      ),
      '将从这个房间的表情包中删除选中的 2 个表情。',
    );
    expect(stickerDeletedNotice(scope: StickerManagementScope.room), '房间表情已删除');
    expect(
      stickerDeletedNotice(scope: StickerManagementScope.room, count: 2),
      '已删除 2 个房间表情',
    );
    expect(
      stickerDownloadNotice(scope: StickerManagementScope.room, count: 1),
      '房间表情已下载',
    );
    expect(
      stickerDownloadNotice(scope: StickerManagementScope.room, count: 2),
      '房间表情压缩包已下载',
    );
    expect(
      stickerNoOrderChangeNotice(StickerManagementScope.room),
      '房间表情排序没有变化',
    );
    expect(stickerPinnedNotice(scope: StickerManagementScope.room), '房间表情已置顶');
    expect(
      stickerPinnedNotice(scope: StickerManagementScope.room, count: 2),
      '已置顶 2 个房间表情',
    );
    expect(
      stickerMoveNotice(scope: StickerManagementScope.room, delta: -1),
      '房间表情已上移一位',
    );
    expect(
      stickerMoveNotice(scope: StickerManagementScope.room, delta: 1),
      '房间表情已下移一位',
    );
  });

  test('sticker pack load patches retain current selection safely', () {
    final currentPacks = [
      _pack('pack_1', ['a', 'b']),
    ];
    final nextPacks = [
      _pack('pack_2', ['b', 'c']),
    ];

    final started = stickerPacksLoadStarted(
      packs: currentPacks,
      selectedStickerIds: ['b'],
    );

    expect(started.packs.map((pack) => pack.id), ['pack_1']);
    expect(started.selectedStickerIds, ['b']);
    expect(started.loading, isTrue);
    expect(started.error, isNull);

    final succeeded = stickerPacksLoadSucceeded(
      packs: nextPacks,
      selectedStickerIds: ['missing', 'b', 'a'],
    );

    expect(succeeded.packs.map((pack) => pack.id), ['pack_2']);
    expect(succeeded.selectedStickerIds, ['b']);
    expect(succeeded.loading, isFalse);
    expect(succeeded.error, isNull);

    final failed = stickerPacksLoadFailed(
      packs: currentPacks,
      selectedStickerIds: ['a'],
      failure: StateError('network failed'),
    );

    expect(failed.packs.map((pack) => pack.id), ['pack_1']);
    expect(failed.selectedStickerIds, ['a']);
    expect(failed.loading, isFalse);
    expect(failed.error, 'Bad state: network failed');
  });

  test(
    'sticker pack upsert patch preserves load state and valid selection',
    () {
      final currentPacks = [
        _pack('pack_1', ['a', 'b']),
        _pack('pack_2', ['c']),
      ];

      final inserted = stickerPackUpserted(
        packs: currentPacks,
        selectedStickerIds: ['missing', 'a', 'd'],
        pack: _pack('pack_3', ['d']),
        loading: true,
        error: 'previous',
      );

      expect(inserted.packs.map((pack) => pack.id), [
        'pack_3',
        'pack_1',
        'pack_2',
      ]);
      expect(inserted.selectedStickerIds, ['a', 'd']);
      expect(inserted.loading, isTrue);
      expect(inserted.error, 'previous');

      final replaced = stickerPackUpserted(
        packs: currentPacks,
        selectedStickerIds: ['b', 'c', 'x'],
        pack: _pack('pack_1', ['x']),
        loading: false,
        error: null,
      );

      expect(replaced.packs.map((pack) => pack.id), ['pack_1', 'pack_2']);
      expect(replaced.packs.first.stickers.map((sticker) => sticker.id), ['x']);
      expect(replaced.selectedStickerIds, ['c', 'x']);
      expect(replaced.loading, isFalse);
      expect(replaced.error, isNull);
    },
  );

  test('sticker selection patches keep selection state reusable', () {
    final items = managedStickerItems([
      _pack('pack_1', ['a', 'b', 'c']),
    ]);

    final manageMode = stickerManagementModeToggled(
      managing: false,
      filterKeyword: 'gif',
      filterMimeType: 'image/gif',
    );

    expect(manageMode.managing, isTrue);
    expect(manageMode.filterKeyword, 'gif');
    expect(manageMode.filterMimeType, 'image/gif');
    expect(manageMode.selectedStickerIds, isEmpty);

    final ignoredSelection = stickerSelectionToggled(
      managing: false,
      filterKeyword: '',
      filterMimeType: '',
      selectedStickerIds: ['a'],
      stickerId: 'b',
    );

    expect(ignoredSelection.selectedStickerIds, ['a']);

    final toggledSelection = stickerSelectionToggled(
      managing: true,
      filterKeyword: '',
      filterMimeType: '',
      selectedStickerIds: ['a'],
      stickerId: 'b',
    );

    expect(toggledSelection.selectedStickerIds, ['a', 'b']);

    final ignoredVisibleSelection = stickerVisibleSelectionToggled(
      managing: true,
      busy: true,
      filterKeyword: '',
      filterMimeType: '',
      selectedStickerIds: ['a'],
      visibleItems: items,
    );

    expect(ignoredVisibleSelection.selectedStickerIds, ['a']);

    final visibleSelection = stickerVisibleSelectionToggled(
      managing: true,
      busy: false,
      filterKeyword: '',
      filterMimeType: '',
      selectedStickerIds: const [],
      visibleItems: items.take(2).toList(),
    );

    expect(visibleSelection.selectedStickerIds, ['b', 'a']);

    final filter = stickerFilterApplied(
      managing: true,
      keyword: 'webp',
      mimeType: 'image/webp',
    );

    expect(filter.managing, isTrue);
    expect(filter.filterKeyword, 'webp');
    expect(filter.filterMimeType, 'image/webp');
    expect(filter.selectedStickerIds, isEmpty);
  });

  test('sticker filter draft patches are shared by filter dialogs', () {
    const draft = StickerFilterDraft(keyword: 'happy', mimeType: 'image/gif');

    expect(draft.keyword, 'happy');
    expect(draft.mimeType, 'image/gif');
    expect(
      stickerFilterMimeTypeChanged(mimeType: 'image/webp').mimeType,
      'image/webp',
    );
    expect(stickerFilterDraftReset().mimeType, '');
  });

  test('sticker action patches update one busy flag and transient copy', () {
    final started = stickerActionStarted(
      action: StickerActionKind.upload,
      uploading: false,
      deleting: false,
      savingOrder: true,
      downloading: false,
      selectedStickerIds: ['a'],
    );

    expect(started.uploading, isTrue);
    expect(started.deleting, isFalse);
    expect(started.savingOrder, isTrue);
    expect(started.downloading, isFalse);
    expect(started.selectedStickerIds, ['a']);
    expect(started.error, isNull);
    expect(started.notice, isNull);

    final succeeded = stickerActionSucceeded(
      action: StickerActionKind.delete,
      uploading: false,
      deleting: true,
      savingOrder: false,
      downloading: false,
      selectedStickerIds: ['a', 'b'],
      error: null,
      notice: 'deleted',
      clearSelection: true,
    );

    expect(succeeded.uploading, isFalse);
    expect(succeeded.deleting, isFalse);
    expect(succeeded.selectedStickerIds, isEmpty);
    expect(succeeded.error, isNull);
    expect(succeeded.notice, 'deleted');

    final failed = stickerActionFailed(
      action: StickerActionKind.order,
      uploading: false,
      deleting: false,
      savingOrder: true,
      downloading: false,
      selectedStickerIds: ['b'],
      failure: StateError('sort failed'),
    );

    expect(failed.savingOrder, isFalse);
    expect(failed.selectedStickerIds, ['b']);
    expect(failed.error, 'Bad state: sort failed');
    expect(failed.notice, isNull);
  });

  test('sticker action notice/error patches preserve independent state', () {
    final cancelled = stickerActionCancelled(
      action: StickerActionKind.download,
      uploading: false,
      deleting: false,
      savingOrder: false,
      downloading: true,
      selectedStickerIds: ['a'],
    );

    expect(cancelled.downloading, isFalse);
    expect(cancelled.selectedStickerIds, ['a']);
    expect(cancelled.error, isNull);
    expect(cancelled.notice, isNull);

    final notice = stickerActionNoticeShown(
      uploading: false,
      deleting: false,
      savingOrder: false,
      downloading: false,
      selectedStickerIds: ['a'],
      error: 'previous',
      notice: 'nothing changed',
    );

    expect(notice.error, 'previous');
    expect(notice.notice, 'nothing changed');
    expect(notice.selectedStickerIds, ['a']);

    final error = stickerActionErrorShown(
      uploading: false,
      deleting: false,
      savingOrder: false,
      downloading: false,
      selectedStickerIds: ['a'],
      failure: 'picker failed',
      notice: 'previous notice',
    );

    expect(error.error, 'picker failed');
    expect(error.notice, 'previous notice');
    expect(error.selectedStickerIds, ['a']);
  });

  test('retainedStickerSelection and managedStickerById use current packs', () {
    final packs = [
      _pack('pack_1', ['a']),
      _pack('pack_2', ['b']),
    ];
    final items = managedStickerItems(packs);

    expect(retainedStickerSelection(['missing', 'b', 'a'], packs), ['b', 'a']);
    expect(managedStickerById(items, 'b')?.pack.id, 'pack_2');
    expect(managedStickerById(items, 'missing'), isNull);
  });
}

StickerPack _pack(
  String id,
  List<String> stickerIds, {
  Map<String, String> mimeTypes = const {},
}) {
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
            mimeType: mimeTypes[entry.value] ?? 'image/png',
          ),
        ),
    ],
  );
}
