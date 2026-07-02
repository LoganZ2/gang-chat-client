import 'dart:math' as math;

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
  _PreviewAction? _busy;
  String? _notice;
  bool _noticeIsError = false;

  bool get _canSaveSticker =>
      widget.stickerSource != null && widget.actions.onSaveSticker != null;

  bool get _canSaveRoomSticker =>
      widget.stickerSource != null && widget.actions.onSaveRoomSticker != null;

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
                          Expanded(child: Center(child: _buildImage())),
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
    // Swallow taps on the image itself so they don't fall through to the
    // dismiss-on-backdrop gesture behind it.
    return GestureDetector(
      onTap: () {},
      child: InteractiveViewer(
        maxScale: 5,
        // Let the zoomed image pan freely and don't clip it to the viewport,
        // so scaling isn't confined to the image's original on-screen edges.
        boundaryMargin: const EdgeInsets.all(double.infinity),
        clipBehavior: Clip.none,
        child: _previewImage(),
      ),
    );
  }

  Widget _previewImage() {
    if (widget.forceSquare) {
      final side = _squarePreviewSide();
      return SizedBox.square(
        dimension: side,
        child: _cachedPreviewImage(
          fit: BoxFit.cover,
          width: side,
          height: side,
        ),
      );
    }

    return _cachedPreviewImage(fit: BoxFit.contain);
  }

  double _squarePreviewSide() {
    final size = MediaQuery.sizeOf(context);
    final availableWidth = math.max(0.0, size.width - 48);
    final reservedHeight = widget.showActionBar ? 176.0 : 104.0;
    final availableHeight = math.max(0.0, size.height - reservedHeight);
    final availableSide = math.min(availableWidth, availableHeight);
    return math.max(160.0, math.min(360.0, availableSide * 0.72));
  }

  Widget _cachedPreviewImage({
    required BoxFit fit,
    double? width,
    double? height,
  }) {
    final cache = widget.actions.mediaCache;
    return CachedAssetImage(
      key: const ValueKey('chat-image-preview-url-image'),
      url: widget.imageUrl,
      filename: widget.suggestedName,
      cache: cache,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (_) => _previewLoading(),
      errorBuilder: (_, _, _) => _previewError(),
    );
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
