import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as dart_ui;

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../app/media_cache_controller.dart';
import '../protocol/models.dart';
import '../ui/ui.dart';

class ChatImagePreviewActionsScope extends InheritedWidget {
  const ChatImagePreviewActionsScope({
    super.key,
    required this.actions,
    required super.child,
  });

  final ChatImagePreviewActions actions;

  static ChatImagePreviewActions? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ChatImagePreviewActionsScope>()
        ?.actions;
  }

  @override
  bool updateShouldNotify(ChatImagePreviewActionsScope oldWidget) {
    return !identical(actions, oldWidget.actions);
  }
}

/// Callbacks for the full-screen image preview overlay, bundled so they can
/// travel from [ChatPane] down to each image bubble without threading several
/// separate parameters through every intermediate widget. The home shell wires
/// the implementations (download, save-as, clipboard, save-sticker).
class ChatImagePreviewActions {
  const ChatImagePreviewActions({
    required this.onDownload,
    required this.onSaveAs,
    required this.onCopyToClipboard,
    this.onSaveSticker,
    this.onSaveRoomSticker,
    this.mediaCache,
  });

  /// A no-op bundle for tests and previews where the actions aren't exercised.
  ChatImagePreviewActions.disabled()
    : onDownload = _noopWithName,
      onSaveAs = _noopWithName,
      onCopyToClipboard = _noopWithUrl,
      onSaveSticker = null,
      onSaveRoomSticker = null,
      mediaCache = null;

  /// Save the image at [url] straight to the user's Downloads folder, using
  /// [suggestedName] as the filename. Throws on failure.
  final Future<void> Function(String url, String suggestedName) onDownload;

  /// Save the image at [url] through a save-location picker. Throws on failure.
  final Future<void> Function(String url, String suggestedName) onSaveAs;

  /// Copy the image bytes at [url] to the system clipboard. Throws on failure.
  final Future<void> Function(String url) onCopyToClipboard;

  /// Save a sticker message's sticker into the user's personal stickers. Null
  /// when the source isn't a savable sticker (e.g. a plain image attachment) or
  /// the API is unavailable. Throws on failure.
  final Future<void> Function(Message message, MessageAttachment attachment)?
  onSaveSticker;

  /// Add a sticker message's sticker to the current room's sticker pack. Null
  /// unless the source is a savable sticker and the current user can administer
  /// the room. Throws on failure.
  final Future<void> Function(Message message, MessageAttachment attachment)?
  onSaveRoomSticker;

  /// Optional disk cache used for preview rendering and image actions.
  final MediaCacheController? mediaCache;
}

Future<void> _noopWithName(String url, String suggestedName) async {}

Future<void> _noopWithUrl(String url) async {}

/// Thrown by a preview action when the user cancels (e.g. dismisses the save-as
/// picker). The overlay treats it as a silent no-op rather than a failure.
class ImagePreviewActionCancelled implements Exception {
  const ImagePreviewActionCancelled();
}

/// Opens the full-screen image preview as an overlay route. [imageUrl] is the
/// already-resolved absolute URL to display. [suggestedName] seeds the
/// download/save-as filename. When [stickerSource] is non-null and
/// [actions.onSaveSticker] is provided, an "添加到我的表情包" action is shown.
Future<void> showChatImagePreview(
  BuildContext context, {
  required String imageUrl,
  required String suggestedName,
  required ChatImagePreviewActions actions,
  ({Message message, MessageAttachment attachment})? stickerSource,
  bool showActionBar = true,
  bool forceSquare = false,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: const Color(0xD1000000),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 140),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _ImagePreviewOverlay(
          imageUrl: imageUrl,
          suggestedName: suggestedName,
          actions: actions,
          stickerSource: stickerSource,
          showActionBar: showActionBar,
          forceSquare: forceSquare,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _ImagePreviewOverlay extends StatefulWidget {
  const _ImagePreviewOverlay({
    required this.imageUrl,
    required this.suggestedName,
    required this.actions,
    required this.stickerSource,
    required this.showActionBar,
    required this.forceSquare,
  });

  final String imageUrl;
  final String suggestedName;
  final ChatImagePreviewActions actions;
  final ({Message message, MessageAttachment attachment})? stickerSource;
  final bool showActionBar;
  final bool forceSquare;

  @override
  State<_ImagePreviewOverlay> createState() => _ImagePreviewOverlayState();
}

enum _PreviewAction { download, saveAs, copy, saveSticker, saveRoomSticker }

class _ImagePreviewOverlayState extends State<_ImagePreviewOverlay> {
  static const double _minImageScale = 0.25;
  static const double _maxImageScale = 5.0;
  static const double _wheelScaleBase = 1.25;
  static const _previewImageKey = ValueKey('chat-image-preview-url-image');

  final ValueNotifier<_PreviewImageTransform> _imageTransform =
      ValueNotifier<_PreviewImageTransform>(const _PreviewImageTransform());

  Future<_PreviewImageData>? _previewImageData;
  String? _previewImageDataKey;
  double? _gestureStartScale;
  Offset? _gestureStartContentFocal;
  _PreviewAction? _busy;
  String? _notice;
  bool _noticeIsError = false;

  bool get _canSaveSticker =>
      widget.stickerSource != null && widget.actions.onSaveSticker != null;

  bool get _canSaveRoomSticker =>
      widget.stickerSource != null && widget.actions.onSaveRoomSticker != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensurePreviewImageData();
  }

  @override
  void didUpdateWidget(_ImagePreviewOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensurePreviewImageData();
  }

  void _ensurePreviewImageData() {
    final cache = widget.actions.mediaCache ?? MediaCacheScope.of(context);
    final key = [
      widget.imageUrl,
      widget.suggestedName,
      identityHashCode(cache),
    ].join('\n');
    if (_previewImageDataKey == key) return;
    _previewImageDataKey = key;
    _previewImageData = _loadPreviewImageData(cache);
    _imageTransform.value = const _PreviewImageTransform();
    _gestureStartScale = null;
    _gestureStartContentFocal = null;
  }

  Future<_PreviewImageData> _loadPreviewImageData(
    MediaCacheController cache,
  ) async {
    final request = MediaCacheRequest.tryFromUrl(
      url: widget.imageUrl,
      filename: widget.suggestedName,
    );
    if (request == null) {
      throw StateError('图片地址无效');
    }
    final file = await cache.getOrDownload(request: request);
    final size = await _decodePreviewImageSize(file);
    return _PreviewImageData(file: file, size: size);
  }

  Future<Size> _decodePreviewImageSize(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await dart_ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        return Size(image.width.toDouble(), image.height.toDouble());
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Future<void> _run(
    _PreviewAction action,
    Future<void> Function() task, {
    required String successMessage,
  }) async {
    if (_busy != null) return;
    setState(() {
      _busy = action;
      _notice = null;
    });
    try {
      await task();
      if (!mounted) return;
      setState(() {
        _notice = successMessage;
        _noticeIsError = false;
      });
    } on ImagePreviewActionCancelled {
      // User cancelled (e.g. closed the save-as picker); leave the overlay as
      // it was without showing success or error.
      if (mounted) setState(() => _notice = null);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _notice = '$error';
        _noticeIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _imageTransform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                _close();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                // Tapping the backdrop (anywhere outside the image/controls)
                // dismisses the overlay.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                  ),
                ),
                Positioned.fill(
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                      child: Column(
                        children: [
                          Expanded(child: _buildImage()),
                          if (_notice != null) ...[
                            const SizedBox(height: 16),
                            _PreviewNotice(
                              message: _notice!,
                              isError: _noticeIsError,
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (widget.showActionBar) ...[
                            const SizedBox(height: 16),
                            _buildActionBar(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  right: 14,
                  child: SafeArea(
                    child: ButtonIcon(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: '关闭',
                      onPressed: _close,
                      backgroundColor: const Color(0x66000000),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          math.max(1.0, constraints.maxWidth),
          math.max(1.0, constraints.maxHeight),
        );
        return FutureBuilder<_PreviewImageData>(
          future: _previewImageData,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) {
              return _buildImagePlaceholder(error: snapshot.error);
            }
            return _buildLoadedImage(viewport, data);
          },
        );
      },
    );
  }

  Widget _buildImagePlaceholder({Object? error}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: KeyedSubtree(
        key: _previewImageKey,
        child: error == null ? _previewLoading() : _previewError(),
      ),
    );
  }

  Widget _buildLoadedImage(Size viewport, _PreviewImageData data) {
    final contentRect = _previewContentRect(viewport, data.size);
    // The gesture layer intentionally fills the whole preview area. If it
    // only covers the painted image, a dragged image can move out from
    // under the pointer and become difficult to grab again.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) =>
          _handlePreviewTap(details.localPosition, contentRect),
      onScaleStart: _handlePreviewScaleStart,
      onScaleUpdate: (details) =>
          _handlePreviewScaleUpdate(details, viewport, contentRect),
      onScaleEnd: (_) => _handlePreviewScaleEnd(viewport, contentRect),
      child: Listener(
        key: const ValueKey('chat-image-preview-viewer'),
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _handlePreviewScroll(event, viewport, contentRect);
          }
        },
        child: ClipRect(
          child: ValueListenableBuilder<_PreviewImageTransform>(
            valueListenable: _imageTransform,
            builder: (context, transform, child) {
              return Transform(
                transform: transform.matrix,
                alignment: Alignment.topLeft,
                child: child,
              );
            },
            child: SizedBox(
              width: viewport.width,
              height: viewport.height,
              child: _previewImage(data, contentRect),
            ),
          ),
        ),
      ),
    );
  }

  void _handlePreviewTap(Offset position, Rect contentRect) {
    if (!_visibleContentRect(contentRect).contains(position)) _close();
  }

  void _handlePreviewScaleStart(ScaleStartDetails details) {
    final transform = _imageTransform.value;
    _gestureStartScale = transform.scale;
    _gestureStartContentFocal =
        (details.localFocalPoint - transform.offset) / transform.scale;
  }

  void _handlePreviewScaleUpdate(
    ScaleUpdateDetails details,
    Size viewport,
    Rect contentRect,
  ) {
    final startScale = _gestureStartScale ?? _imageTransform.value.scale;
    final contentFocal =
        _gestureStartContentFocal ?? _contentPointFor(details.localFocalPoint);
    final nextScale = (startScale * details.scale)
        .clamp(_minImageScale, _maxImageScale)
        .toDouble();
    final nextTranslation = details.localFocalPoint - contentFocal * nextScale;
    _setImageTransform(nextScale, nextTranslation, viewport, contentRect);
  }

  void _handlePreviewScaleEnd(Size viewport, Rect contentRect) {
    _gestureStartScale = null;
    _gestureStartContentFocal = null;
    _setImageTransform(
      _imageTransform.value.scale,
      _currentImageTranslation(),
      viewport,
      contentRect,
    );
  }

  void _handlePreviewScroll(
    PointerScrollEvent event,
    Size viewport,
    Rect contentRect,
  ) {
    if (event.scrollDelta.dy == 0) return;
    final scrollSteps = _normalizedWheelSteps(event.scrollDelta.dy);
    final scaleDelta = math.pow(_wheelScaleBase, -scrollSteps).toDouble();
    final nextScale = (_imageTransform.value.scale * scaleDelta)
        .clamp(_minImageScale, _maxImageScale)
        .toDouble();
    final imageCenter = _visibleContentRect(contentRect).center;
    final nextTranslation = imageCenter - contentRect.center * nextScale;
    _setImageTransform(nextScale, nextTranslation, viewport, contentRect);
  }

  double _normalizedWheelSteps(double deltaY) {
    final magnitude = deltaY.abs();
    if (magnitude == 0) return 0;
    if (magnitude >= 20) return deltaY / 120;
    return deltaY.sign;
  }

  Offset _currentImageTranslation() {
    return _imageTransform.value.offset;
  }

  Offset _contentPointFor(Offset viewportPoint) {
    final transform = _imageTransform.value;
    return (viewportPoint - transform.offset) / transform.scale;
  }

  Rect _visibleContentRect(Rect contentRect) {
    final transform = _imageTransform.value;
    final scale = transform.scale;
    final offset = transform.offset;
    return Rect.fromLTRB(
      contentRect.left * scale + offset.dx,
      contentRect.top * scale + offset.dy,
      contentRect.right * scale + offset.dx,
      contentRect.bottom * scale + offset.dy,
    );
  }

  Rect _previewContentRect(Size viewport, Size imageSize) {
    if (widget.forceSquare) {
      final side = _squarePreviewSide(viewport);
      return Rect.fromLTWH(
        (viewport.width - side) / 2,
        (viewport.height - side) / 2,
        side,
        side,
      );
    }
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      return Offset.zero & viewport;
    }
    final fitted = applyBoxFit(BoxFit.contain, imageSize, viewport);
    return Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & viewport,
    );
  }

  void _setImageTransform(
    double scale,
    Offset translation,
    Size viewport,
    Rect contentRect,
  ) {
    final clampedScale = scale.clamp(_minImageScale, _maxImageScale).toDouble();
    final clampedX = _clampImageTranslationAxis(
      viewportExtent: viewport.width,
      contentStart: contentRect.left,
      contentEnd: contentRect.right,
      scale: clampedScale,
      translation: translation.dx,
    );
    final clampedY = _clampImageTranslationAxis(
      viewportExtent: viewport.height,
      contentStart: contentRect.top,
      contentEnd: contentRect.bottom,
      scale: clampedScale,
      translation: translation.dy,
    );
    final next = _PreviewImageTransform(
      scale: clampedScale,
      offset: Offset(clampedX, clampedY),
    );
    if (_imageTransform.value == next) return;
    _imageTransform.value = next;
  }

  double _clampImageTranslationAxis({
    required double viewportExtent,
    required double contentStart,
    required double contentEnd,
    required double scale,
    required double translation,
  }) {
    final scaledExtent = (contentEnd - contentStart) * scale;
    if (scaledExtent <= viewportExtent) {
      return (viewportExtent - scaledExtent) / 2 - contentStart * scale;
    }
    final minTranslation = viewportExtent - contentEnd * scale;
    final maxTranslation = -contentStart * scale;
    return translation.clamp(minTranslation, maxTranslation).toDouble();
  }

  Widget _previewImage(_PreviewImageData data, Rect contentRect) {
    return Stack(
      children: [
        Positioned.fromRect(
          rect: contentRect,
          child: Image.file(
            data.file,
            key: _previewImageKey,
            fit: widget.forceSquare ? BoxFit.cover : BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _previewError(),
          ),
        ),
      ],
    );
  }

  double _squarePreviewSide(Size viewport) {
    final availableSide = math.min(viewport.width, viewport.height);
    return math.max(160.0, math.min(360.0, availableSide * 0.72));
  }

  Widget _previewLoading() {
    return const Center(
      child: SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: UiColors.textSecondary,
        ),
      ),
    );
  }

  Widget _previewError() {
    return const Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: UiColors.textMuted,
        size: 48,
      ),
    );
  }

  Widget _buildActionBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        ButtonIcon(
          icon: const Icon(Icons.download_rounded),
          tooltip: '下载',
          loading: _busy == _PreviewAction.download,
          onPressed: _busy == null
              ? () => _run(
                  _PreviewAction.download,
                  () => widget.actions.onDownload(
                    widget.imageUrl,
                    widget.suggestedName,
                  ),
                  successMessage: '已保存到下载文件夹',
                )
              : null,
          backgroundColor: const Color(0x66000000),
        ),
        const SizedBox(width: 10),
        ButtonIcon(
          icon: const Icon(Icons.save_alt_rounded),
          tooltip: '另存为',
          loading: _busy == _PreviewAction.saveAs,
          onPressed: _busy == null
              ? () => _run(
                  _PreviewAction.saveAs,
                  () => widget.actions.onSaveAs(
                    widget.imageUrl,
                    widget.suggestedName,
                  ),
                  successMessage: '已保存',
                )
              : null,
          backgroundColor: const Color(0x66000000),
        ),
        const SizedBox(width: 10),
        ButtonIcon(
          icon: const Icon(Icons.copy_rounded),
          tooltip: '复制到剪贴板',
          loading: _busy == _PreviewAction.copy,
          onPressed: _busy == null
              ? () => _run(
                  _PreviewAction.copy,
                  () => widget.actions.onCopyToClipboard(widget.imageUrl),
                  successMessage: '已复制到剪贴板',
                )
              : null,
          backgroundColor: const Color(0x66000000),
        ),
        if (_canSaveSticker) ...[
          const SizedBox(width: 10),
          ButtonIcon(
            icon: const Icon(Icons.add_reaction_outlined),
            tooltip: '添加到我的表情包',
            loading: _busy == _PreviewAction.saveSticker,
            onPressed: _busy == null
                ? () {
                    final source = widget.stickerSource!;
                    _run(
                      _PreviewAction.saveSticker,
                      () => widget.actions.onSaveSticker!(
                        source.message,
                        source.attachment,
                      ),
                      successMessage: '已添加到我的表情包',
                    );
                  }
                : null,
            backgroundColor: const Color(0x66000000),
          ),
        ],
        if (_canSaveRoomSticker) ...[
          const SizedBox(width: 10),
          ButtonIcon(
            icon: const Icon(Icons.library_add_outlined),
            tooltip: '添加到房间表情包',
            loading: _busy == _PreviewAction.saveRoomSticker,
            onPressed: _busy == null
                ? () {
                    final source = widget.stickerSource!;
                    _run(
                      _PreviewAction.saveRoomSticker,
                      () => widget.actions.onSaveRoomSticker!(
                        source.message,
                        source.attachment,
                      ),
                      successMessage: '已添加到房间表情包',
                    );
                  }
                : null,
            backgroundColor: const Color(0x66000000),
          ),
        ],
      ],
    );
  }
}

class _PreviewNotice extends StatelessWidget {
  const _PreviewNotice({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(
          color: isError ? UiColors.dangerBorder : UiColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: UiTypography.label.copyWith(
            color: isError ? UiColors.danger : UiColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _PreviewImageData {
  const _PreviewImageData({required this.file, required this.size});

  final File file;
  final Size size;
}

class _PreviewImageTransform {
  const _PreviewImageTransform({this.scale = 1.0, this.offset = Offset.zero});

  final double scale;
  final Offset offset;

  Matrix4 get matrix {
    return Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(offset.dx, offset.dy, 0);
  }

  @override
  bool operator ==(Object other) {
    return other is _PreviewImageTransform &&
        other.scale == scale &&
        other.offset == offset;
  }

  @override
  int get hashCode => Object.hash(scale, offset);
}
