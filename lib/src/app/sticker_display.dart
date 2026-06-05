import '../protocol/models.dart';
import 'sticker_uploads.dart';

enum StickerPanelSource { personal, room }

enum StickerPanelBodyState { loading, error, empty, results }

class StickerPanelLoadState {
  const StickerPanelLoadState({
    this.source = StickerPanelSource.personal,
    this.personalPacks = const [],
    this.roomPacks = const [],
    this.loading = false,
    this.loaded = false,
    this.error,
  });

  final StickerPanelSource source;
  final List<StickerPack> personalPacks;
  final List<StickerPack> roomPacks;
  final bool loading;
  final bool loaded;
  final String? error;

  StickerPanelLoadState copyWith({
    StickerPanelSource? source,
    List<StickerPack>? personalPacks,
    List<StickerPack>? roomPacks,
    bool? loading,
    bool? loaded,
    Object? error = _stickerPanelErrorUnchanged,
  }) {
    return StickerPanelLoadState(
      source: source ?? this.source,
      personalPacks: personalPacks ?? this.personalPacks,
      roomPacks: roomPacks ?? this.roomPacks,
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      error: identical(error, _stickerPanelErrorUnchanged)
          ? this.error
          : error as String?,
    );
  }
}

const Object _stickerPanelErrorUnchanged = Object();

List<Sticker> stickerPanelStickers({
  required StickerPanelSource source,
  required Iterable<StickerPack> personalPacks,
  required Iterable<StickerPack> roomPacks,
}) {
  final packs = source == StickerPanelSource.personal
      ? personalPacks
      : roomPacks;
  return [for (final pack in packs) ...pack.stickers];
}

StickerPanelBodyState stickerPanelBodyState({
  required bool loading,
  required String? error,
  required Iterable<Sticker> stickers,
}) {
  if (stickers.isNotEmpty) return StickerPanelBodyState.results;
  if (loading) return StickerPanelBodyState.loading;
  if (error != null) return StickerPanelBodyState.error;
  return StickerPanelBodyState.empty;
}

String stickerPanelEmptyText(StickerPanelSource source) {
  return source == StickerPanelSource.personal ? '暂无个人表情' : '暂无房间表情';
}

StickerPanelLoadState stickerPanelReset({
  StickerPanelSource source = StickerPanelSource.personal,
}) {
  return StickerPanelLoadState(source: source);
}

StickerPanelLoadState stickerPanelSourceChanged(
  StickerPanelLoadState state,
  StickerPanelSource source,
) {
  return state.copyWith(source: source);
}

bool shouldLoadStickerPanel({
  required StickerPanelLoadState state,
  required bool forceReload,
}) {
  return !state.loading && (forceReload || !state.loaded);
}

StickerPanelLoadState stickerPanelLoadStarted(StickerPanelLoadState state) {
  return state.copyWith(loading: true, error: null);
}

StickerPanelLoadState stickerPanelCachedPersonalApplied({
  required StickerPanelLoadState state,
  required Iterable<StickerPack> packs,
}) {
  return state.copyWith(personalPacks: packs.toList());
}

StickerPanelLoadState stickerPanelLoadSucceeded({
  required StickerPanelLoadState state,
  required Iterable<StickerPack> personalPacks,
  required Iterable<StickerPack> roomPacks,
}) {
  return state.copyWith(
    personalPacks: personalPacks.toList(),
    roomPacks: roomPacks.toList(),
    loading: false,
    loaded: true,
    error: null,
  );
}

StickerPanelLoadState stickerPanelLoadFailed({
  required StickerPanelLoadState state,
  required Object failure,
}) {
  return state.copyWith(loading: false, error: failure.toString());
}

StickerPanelLoadState stickerPanelLoadFinished(StickerPanelLoadState state) {
  return state.copyWith(loading: false);
}

String stickerDimensionsText(
  UploadedAsset asset, {
  StickerImageDimensions? resolved,
  required bool resolving,
  required bool failed,
}) {
  final width = asset.width ?? resolved?.width;
  final height = asset.height ?? resolved?.height;
  if (width != null && height != null) return '${width}x$height';
  if (resolving) return '正在读取尺寸';
  if (failed) return '尺寸读取失败';
  return '未知尺寸';
}
