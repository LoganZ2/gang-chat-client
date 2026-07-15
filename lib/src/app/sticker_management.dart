import '../protocol/models.dart';
import 'error_display.dart';
import 'sticker_ordering.dart' as sticker_ordering;

enum StickerManagementScope { personal, room }

enum StickerActionKind { upload, delete, order, download }

enum StickerPreviewActionKind {
  rename,
  setAvatar,
  download,
  delete,
  moveUp,
  moveDown,
  pin,
}

class StickerManagementCapabilities {
  const StickerManagementCapabilities({
    this.canUpload = true,
    this.canBatchManage = true,
    this.canFilter = true,
    this.canDownload = true,
    this.canSelectAll = true,
    this.canDelete = true,
    this.canPin = true,
    this.canRename = true,
    this.canMove = true,
    this.canSetAvatar = true,
  });

  const StickerManagementCapabilities.readOnlyDownloads()
    : canUpload = false,
      canBatchManage = true,
      canFilter = true,
      canDownload = true,
      canSelectAll = true,
      canDelete = false,
      canPin = false,
      canRename = false,
      canMove = false,
      canSetAvatar = false;

  final bool canUpload;
  final bool canBatchManage;
  final bool canFilter;
  final bool canDownload;
  final bool canSelectAll;
  final bool canDelete;
  final bool canPin;
  final bool canRename;
  final bool canMove;
  final bool canSetAvatar;
}

const Object _stickerPreviewErrorUnchanged = Object();

class ManagedSticker {
  const ManagedSticker({required this.pack, required this.sticker});

  final StickerPack pack;
  final Sticker sticker;
}

class StickerPackLoadPatch {
  const StickerPackLoadPatch({
    required this.packs,
    required this.selectedStickerIds,
    required this.loading,
    required this.error,
  });

  final List<StickerPack> packs;
  final List<String> selectedStickerIds;
  final bool loading;
  final String? error;
}

class StickerSelectionPatch {
  const StickerSelectionPatch({
    required this.managing,
    required this.filterKeyword,
    required this.filterMimeType,
    required this.selectedStickerIds,
  });

  final bool managing;
  final String filterKeyword;
  final String filterMimeType;
  final List<String> selectedStickerIds;
}

class StickerFilterDraft {
  const StickerFilterDraft({required this.keyword, required this.mimeType});

  final String keyword;
  final String mimeType;
}

class StickerFilterDraftPatch {
  const StickerFilterDraftPatch({required this.mimeType});

  final String mimeType;
}

class StickerActionPatch {
  const StickerActionPatch({
    required this.uploading,
    required this.deleting,
    required this.savingOrder,
    required this.downloading,
    required this.selectedStickerIds,
    required this.error,
    required this.notice,
  });

  final bool uploading;
  final bool deleting;
  final bool savingOrder;
  final bool downloading;
  final List<String> selectedStickerIds;
  final String? error;
  final String? notice;
}

class StickerPreviewState {
  const StickerPreviewState({
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canPin,
    this.savingName = false,
    this.settingAvatar = false,
    this.downloading = false,
    this.deleting = false,
    this.movingUp = false,
    this.movingDown = false,
    this.pinning = false,
    this.error,
  });

  factory StickerPreviewState.initial({
    required bool canMoveUp,
    required bool canMoveDown,
    required bool canPin,
  }) {
    return StickerPreviewState(
      canMoveUp: canMoveUp,
      canMoveDown: canMoveDown,
      canPin: canPin,
    );
  }

  final bool canMoveUp;
  final bool canMoveDown;
  final bool canPin;
  final bool savingName;
  final bool settingAvatar;
  final bool downloading;
  final bool deleting;
  final bool movingUp;
  final bool movingDown;
  final bool pinning;
  final String? error;

  bool get busy =>
      savingName ||
      settingAvatar ||
      downloading ||
      deleting ||
      movingUp ||
      movingDown ||
      pinning;

  StickerPreviewState copyWith({
    bool? canMoveUp,
    bool? canMoveDown,
    bool? canPin,
    bool? savingName,
    bool? settingAvatar,
    bool? downloading,
    bool? deleting,
    bool? movingUp,
    bool? movingDown,
    bool? pinning,
    Object? error = _stickerPreviewErrorUnchanged,
  }) {
    return StickerPreviewState(
      canMoveUp: canMoveUp ?? this.canMoveUp,
      canMoveDown: canMoveDown ?? this.canMoveDown,
      canPin: canPin ?? this.canPin,
      savingName: savingName ?? this.savingName,
      settingAvatar: settingAvatar ?? this.settingAvatar,
      downloading: downloading ?? this.downloading,
      deleting: deleting ?? this.deleting,
      movingUp: movingUp ?? this.movingUp,
      movingDown: movingDown ?? this.movingDown,
      pinning: pinning ?? this.pinning,
      error: identical(error, _stickerPreviewErrorUnchanged)
          ? this.error
          : error as String?,
    );
  }
}

List<ManagedSticker> managedStickerItems(
  List<StickerPack> packs, {
  List<String>? Function(StickerPack pack)? orderForPack,
}) {
  return [
    for (final pack in packs)
      for (final sticker in sticker_ordering.orderedStickers(
        pack,
        order: orderForPack?.call(pack),
      ))
        ManagedSticker(pack: pack, sticker: sticker),
  ];
}

List<ManagedSticker> filteredManagedStickerItems(
  Iterable<ManagedSticker> items, {
  required String keyword,
  required String mimeType,
}) {
  final normalizedKeyword = keyword.trim().toLowerCase();
  return [
    for (final item in items)
      if (_matchesStickerFilter(
        item.sticker,
        keyword: normalizedKeyword,
        mimeType: mimeType,
      ))
        item,
  ];
}

bool stickerFilterActive({required String keyword, required String mimeType}) {
  return keyword.trim().isNotEmpty || mimeType.isNotEmpty;
}

bool stickerManagementBusy({
  required bool uploading,
  required bool deleting,
  required bool savingOrder,
  required bool downloading,
}) {
  return uploading || deleting || savingOrder || downloading;
}

String stickerManagementCountText({
  required bool filterActive,
  required int visibleCount,
  required int totalCount,
}) {
  return filterActive ? '$visibleCount / $totalCount 个' : '$totalCount 个';
}

bool canStartStickerPrimaryAction({required bool busy, bool allowed = true}) {
  return allowed && !busy;
}

bool canStartStickerSelectionAction({
  required bool busy,
  required Iterable<String> selectedStickerIds,
  bool allowed = true,
}) {
  return allowed && !busy && selectedStickerIds.isNotEmpty;
}

bool canSelectVisibleStickers({
  required bool busy,
  required Iterable<ManagedSticker> visibleItems,
  bool allowed = true,
}) {
  return allowed && !busy && visibleItems.isNotEmpty;
}

bool stickerAllVisibleSelected({
  required Iterable<String> selectedStickerIds,
  required List<ManagedSticker> visibleItems,
}) {
  if (visibleItems.isEmpty) return false;
  final selectedSet = selectedStickerIds.toSet();
  return visibleItems.every((item) => selectedSet.contains(item.sticker.id));
}

String stickerVisibleSelectionButtonText({
  required Iterable<String> selectedStickerIds,
  required List<ManagedSticker> visibleItems,
}) {
  return '全选';
}

bool canUseStickerManagementControl({required bool busy, bool allowed = true}) {
  return allowed && !busy;
}

String? stickerRenameName(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool canStartStickerRename({
  required bool busy,
  required String name,
  bool allowed = true,
}) {
  return allowed && !busy && stickerRenameName(name) != null;
}

bool canStartStickerPreviewAction({
  required StickerPreviewState state,
  required StickerPreviewActionKind action,
  String? name,
}) {
  if (action == StickerPreviewActionKind.rename) {
    return canStartStickerRename(busy: state.busy, name: name ?? '');
  }
  return !state.busy;
}

StickerPreviewState? stickerPreviewActionRequested({
  required StickerPreviewState state,
  required StickerPreviewActionKind action,
  String? name,
}) {
  if (!canStartStickerPreviewAction(state: state, action: action, name: name)) {
    return null;
  }
  return stickerPreviewActionStarted(state: state, action: action);
}

String defaultStickerPackName(StickerManagementScope scope) {
  return scope == StickerManagementScope.room ? '房间表情包' : '我的表情包';
}

String stickerUploadNotice({
  required StickerManagementScope scope,
  required int count,
}) {
  return scope == StickerManagementScope.room
      ? '已添加 $count 个房间表情'
      : '已添加 $count 个表情';
}

String stickerDeleteDialogTitle(StickerManagementScope scope) {
  return scope == StickerManagementScope.room ? '删除房间表情' : '删除表情';
}

String stickerSingleDeleteConfirmBody({
  required StickerManagementScope scope,
  required String stickerName,
}) {
  return scope == StickerManagementScope.room
      ? '将从这个房间的表情包中删除「$stickerName」。'
      : '将从服务端删除「$stickerName」，删除后不会再出现在你的表情包里。';
}

String stickerBulkDeleteConfirmBody({
  required StickerManagementScope scope,
  required int count,
}) {
  return scope == StickerManagementScope.room
      ? '将从这个房间的表情包中删除选中的 $count 个表情。'
      : '将从服务端删除选中的 $count 个表情，删除后不会再出现在你的表情包里。';
}

String stickerDeletedNotice({
  required StickerManagementScope scope,
  int? count,
}) {
  if (scope == StickerManagementScope.room) {
    return count == null ? '房间表情已删除' : '已删除 $count 个房间表情';
  }
  return count == null ? '表情已删除' : '已删除 $count 个表情';
}

String stickerDownloadNotice({
  required StickerManagementScope scope,
  required int count,
}) {
  if (scope == StickerManagementScope.room) {
    return count == 1 ? '房间表情已下载' : '房间表情压缩包已下载';
  }
  return count == 1 ? '表情已下载' : '表情压缩包已下载';
}

String stickerNoOrderChangeNotice(StickerManagementScope scope) {
  return scope == StickerManagementScope.room ? '房间表情排序没有变化' : '表情排序没有变化';
}

String stickerPinnedNotice({
  required StickerManagementScope scope,
  int? count,
}) {
  if (scope == StickerManagementScope.room) {
    return count == null ? '房间表情已置顶' : '已置顶 $count 个房间表情';
  }
  return count == null ? '表情已置顶' : '已置顶 $count 个表情';
}

String stickerMoveNotice({
  required StickerManagementScope scope,
  required int delta,
}) {
  final direction = delta < 0 ? '上' : '下';
  return scope == StickerManagementScope.room
      ? '房间表情已$direction移一位'
      : '表情已$direction移一位';
}

StickerActionPatch stickerActionStarted({
  required StickerActionKind action,
  required bool uploading,
  required bool deleting,
  required bool savingOrder,
  required bool downloading,
  required Iterable<String> selectedStickerIds,
}) {
  return _stickerActionPatch(
    action: action,
    actionBusy: true,
    uploading: uploading,
    deleting: deleting,
    savingOrder: savingOrder,
    downloading: downloading,
    selectedStickerIds: selectedStickerIds.toList(),
    error: null,
    notice: null,
  );
}

StickerActionPatch stickerActionSucceeded({
  required StickerActionKind action,
  required bool uploading,
  required bool deleting,
  required bool savingOrder,
  required bool downloading,
  required Iterable<String> selectedStickerIds,
  required String? error,
  required String notice,
  bool clearSelection = false,
}) {
  return _stickerActionPatch(
    action: action,
    actionBusy: false,
    uploading: uploading,
    deleting: deleting,
    savingOrder: savingOrder,
    downloading: downloading,
    selectedStickerIds: clearSelection ? const [] : selectedStickerIds.toList(),
    error: error,
    notice: notice,
  );
}

StickerActionPatch stickerActionFailed({
  required StickerActionKind action,
  required bool uploading,
  required bool deleting,
  required bool savingOrder,
  required bool downloading,
  required Iterable<String> selectedStickerIds,
  required Object failure,
}) {
  return _stickerActionPatch(
    action: action,
    actionBusy: false,
    uploading: uploading,
    deleting: deleting,
    savingOrder: savingOrder,
    downloading: downloading,
    selectedStickerIds: selectedStickerIds.toList(),
    error: userFacingErrorMessage(failure),
    notice: null,
  );
}

StickerActionPatch stickerActionCancelled({
  required StickerActionKind action,
  required bool uploading,
  required bool deleting,
  required bool savingOrder,
  required bool downloading,
  required Iterable<String> selectedStickerIds,
}) {
  return _stickerActionPatch(
    action: action,
    actionBusy: false,
    uploading: uploading,
    deleting: deleting,
    savingOrder: savingOrder,
    downloading: downloading,
    selectedStickerIds: selectedStickerIds.toList(),
    error: null,
    notice: null,
  );
}

StickerActionPatch stickerActionNoticeShown({
  required bool uploading,
  required bool deleting,
  required bool savingOrder,
  required bool downloading,
  required Iterable<String> selectedStickerIds,
  required String? error,
  required String notice,
}) {
  return StickerActionPatch(
    uploading: uploading,
    deleting: deleting,
    savingOrder: savingOrder,
    downloading: downloading,
    selectedStickerIds: selectedStickerIds.toList(),
    error: error,
    notice: notice,
  );
}

StickerActionPatch stickerActionErrorShown({
  required bool uploading,
  required bool deleting,
  required bool savingOrder,
  required bool downloading,
  required Iterable<String> selectedStickerIds,
  required Object failure,
  String? notice,
}) {
  return StickerActionPatch(
    uploading: uploading,
    deleting: deleting,
    savingOrder: savingOrder,
    downloading: downloading,
    selectedStickerIds: selectedStickerIds.toList(),
    error: userFacingErrorMessage(failure),
    notice: notice,
  );
}

StickerPreviewState stickerPreviewActionStarted({
  required StickerPreviewState state,
  required StickerPreviewActionKind action,
}) {
  return _stickerPreviewActionState(
    state,
    action: action,
    active: true,
    error: null,
  );
}

StickerPreviewState stickerPreviewActionFinished({
  required StickerPreviewState state,
  required StickerPreviewActionKind action,
}) {
  return _stickerPreviewActionState(state, action: action, active: false);
}

StickerPreviewState stickerPreviewActionFailed({
  required StickerPreviewState state,
  required StickerPreviewActionKind action,
  required Object failure,
}) {
  return _stickerPreviewActionState(
    state,
    action: action,
    active: false,
    error: userFacingErrorMessage(failure),
  );
}

StickerPreviewState stickerPreviewMoveSucceeded({
  required StickerPreviewState state,
  required StickerPreviewActionKind action,
  required bool canMoveUp,
  required bool canMoveDown,
  required bool canPin,
}) {
  return _stickerPreviewActionState(
    state,
    action: action,
    active: false,
  ).copyWith(canMoveUp: canMoveUp, canMoveDown: canMoveDown, canPin: canPin);
}

StickerPackLoadPatch stickerPacksLoadStarted({
  required Iterable<StickerPack> packs,
  required Iterable<String> selectedStickerIds,
}) {
  return StickerPackLoadPatch(
    packs: packs.toList(),
    selectedStickerIds: selectedStickerIds.toList(),
    loading: true,
    error: null,
  );
}

StickerPackLoadPatch stickerPacksLoadSucceeded({
  required Iterable<StickerPack> packs,
  required Iterable<String> selectedStickerIds,
}) {
  final nextPacks = packs.toList();
  return StickerPackLoadPatch(
    packs: nextPacks,
    selectedStickerIds: retainedStickerSelection(
      selectedStickerIds.toList(),
      nextPacks,
    ),
    loading: false,
    error: null,
  );
}

StickerPackLoadPatch stickerPacksLoadFailed({
  required Iterable<StickerPack> packs,
  required Iterable<String> selectedStickerIds,
  required Object failure,
}) {
  return StickerPackLoadPatch(
    packs: packs.toList(),
    selectedStickerIds: selectedStickerIds.toList(),
    loading: false,
    error: userFacingErrorMessage(failure),
  );
}

StickerPackLoadPatch stickerPackUpserted({
  required Iterable<StickerPack> packs,
  required Iterable<String> selectedStickerIds,
  required StickerPack pack,
  required bool loading,
  required String? error,
}) {
  final nextPacks = _upsertStickerPack(packs.toList(), pack);
  return StickerPackLoadPatch(
    packs: nextPacks,
    selectedStickerIds: retainedStickerSelection(
      selectedStickerIds.toList(),
      nextPacks,
    ),
    loading: loading,
    error: error,
  );
}

StickerSelectionPatch stickerManagementModeToggled({
  required bool managing,
  required String filterKeyword,
  required String filterMimeType,
}) {
  return StickerSelectionPatch(
    managing: !managing,
    filterKeyword: filterKeyword,
    filterMimeType: filterMimeType,
    selectedStickerIds: const [],
  );
}

StickerSelectionPatch stickerSelectionToggled({
  required bool managing,
  required String filterKeyword,
  required String filterMimeType,
  required Iterable<String> selectedStickerIds,
  required String stickerId,
}) {
  return StickerSelectionPatch(
    managing: managing,
    filterKeyword: filterKeyword,
    filterMimeType: filterMimeType,
    selectedStickerIds: managing
        ? toggledStickerSelection(selectedStickerIds.toList(), stickerId)
        : selectedStickerIds.toList(),
  );
}

StickerSelectionPatch stickerVisibleSelectionToggled({
  required bool managing,
  required bool busy,
  required String filterKeyword,
  required String filterMimeType,
  required Iterable<String> selectedStickerIds,
  required List<ManagedSticker> visibleItems,
}) {
  return StickerSelectionPatch(
    managing: managing,
    filterKeyword: filterKeyword,
    filterMimeType: filterMimeType,
    selectedStickerIds:
        managing &&
            canSelectVisibleStickers(busy: busy, visibleItems: visibleItems)
        ? stickerSelectionForVisibleItems(
            selectedStickerIds.toList(),
            visibleItems,
          )
        : selectedStickerIds.toList(),
  );
}

StickerSelectionPatch stickerFilterApplied({
  required bool managing,
  required String keyword,
  required String mimeType,
}) {
  return StickerSelectionPatch(
    managing: managing,
    filterKeyword: keyword,
    filterMimeType: mimeType,
    selectedStickerIds: const [],
  );
}

StickerFilterDraftPatch stickerFilterMimeTypeChanged({
  required String mimeType,
}) {
  return StickerFilterDraftPatch(mimeType: mimeType);
}

StickerFilterDraftPatch stickerFilterDraftReset() {
  return const StickerFilterDraftPatch(mimeType: '');
}

Map<String, int> stickerSelectionNumbers(List<String> selectedStickerIds) {
  return {
    for (final entry in selectedStickerIds.asMap().entries)
      entry.value: entry.key + 1,
  };
}

List<String> toggledStickerSelection(
  List<String> selectedStickerIds,
  String stickerId,
) {
  final next = [...selectedStickerIds];
  if (next.contains(stickerId)) {
    next.remove(stickerId);
  } else {
    next.add(stickerId);
  }
  return next;
}

List<String> stickerSelectionForVisibleItems(
  List<String> selectedStickerIds,
  List<ManagedSticker> visibleItems,
) {
  if (visibleItems.isEmpty) return selectedStickerIds;
  final visibleIds = visibleItems.map((item) => item.sticker.id).toList();
  final visibleSet = visibleIds.toSet();
  final allVisibleSelected = stickerAllVisibleSelected(
    selectedStickerIds: selectedStickerIds,
    visibleItems: visibleItems,
  );
  return allVisibleSelected
      ? selectedStickerIds.where((id) => !visibleSet.contains(id)).toList()
      : visibleIds.reversed.toList();
}

List<String> retainedStickerSelection(
  List<String> selectedStickerIds,
  List<StickerPack> packs,
) {
  final stickerIds = {
    for (final pack in packs)
      for (final sticker in pack.stickers) sticker.id,
  };
  return selectedStickerIds.where(stickerIds.contains).toList();
}

ManagedSticker? managedStickerById(
  Iterable<ManagedSticker> items,
  String stickerId,
) {
  for (final item in items) {
    if (item.sticker.id == stickerId) return item;
  }
  return null;
}

List<StickerPack> _upsertStickerPack(
  List<StickerPack> packs,
  StickerPack pack,
) {
  final next = <StickerPack>[];
  var replaced = false;
  for (final current in packs) {
    if (current.id == pack.id) {
      next.add(pack);
      replaced = true;
    } else {
      next.add(current);
    }
  }
  if (!replaced) {
    final insertionIndex = next.indexWhere(
      (current) => current.sortOrder > pack.sortOrder,
    );
    if (insertionIndex < 0) {
      next.add(pack);
    } else {
      next.insert(insertionIndex, pack);
    }
  }
  return next;
}

bool _matchesStickerFilter(
  Sticker sticker, {
  required String keyword,
  required String mimeType,
}) {
  if (keyword.isNotEmpty && !sticker.name.toLowerCase().contains(keyword)) {
    return false;
  }
  if (mimeType.isNotEmpty && sticker.asset.mimeType != mimeType) {
    return false;
  }
  return true;
}

StickerActionPatch _stickerActionPatch({
  required StickerActionKind action,
  required bool actionBusy,
  required bool uploading,
  required bool deleting,
  required bool savingOrder,
  required bool downloading,
  required List<String> selectedStickerIds,
  required String? error,
  required String? notice,
}) {
  return StickerActionPatch(
    uploading: action == StickerActionKind.upload ? actionBusy : uploading,
    deleting: action == StickerActionKind.delete ? actionBusy : deleting,
    savingOrder: action == StickerActionKind.order ? actionBusy : savingOrder,
    downloading: action == StickerActionKind.download
        ? actionBusy
        : downloading,
    selectedStickerIds: selectedStickerIds,
    error: error,
    notice: notice,
  );
}

StickerPreviewState _stickerPreviewActionState(
  StickerPreviewState state, {
  required StickerPreviewActionKind action,
  required bool active,
  Object? error = _stickerPreviewErrorUnchanged,
}) {
  switch (action) {
    case StickerPreviewActionKind.rename:
      return state.copyWith(savingName: active, error: error);
    case StickerPreviewActionKind.setAvatar:
      return state.copyWith(settingAvatar: active, error: error);
    case StickerPreviewActionKind.download:
      return state.copyWith(downloading: active, error: error);
    case StickerPreviewActionKind.delete:
      return state.copyWith(deleting: active, error: error);
    case StickerPreviewActionKind.moveUp:
      return state.copyWith(movingUp: active, error: error);
    case StickerPreviewActionKind.moveDown:
      return state.copyWith(movingDown: active, error: error);
    case StickerPreviewActionKind.pin:
      return state.copyWith(pinning: active, error: error);
  }
}
