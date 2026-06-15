part of 'home_shell.dart';

/// Actions backing the full-screen image preview overlay (see
/// [ChatImagePreviewActions]): download to the Downloads folder, save-as via a
/// picker, copy the image to the clipboard, and save a sticker into the user's
/// personal stickers.
extension _HomeShellImagePreview on _HomeShellState {
  ChatImagePreviewActions get _imagePreviewActions {
    return ChatImagePreviewActions(
      onDownload: _previewDownloadToDownloads,
      onSaveAs: _previewSaveAs,
      onCopyToClipboard: _previewCopyToClipboard,
      onSaveSticker: _previewSaveSticker,
    );
  }

  /// Fetch the bytes for an image at [url]. Throws a user-facing message on a
  /// non-2xx response or transport failure.
  Future<Uint8List> _fetchImageBytes(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      throw Exception('图片地址无效');
    }
    final client = http.Client();
    try {
      final response = await client.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('下载失败 (${response.statusCode})');
      }
      return response.bodyBytes;
    } finally {
      client.close();
    }
  }

  Future<void> _previewDownloadToDownloads(
    String url,
    String suggestedName,
  ) async {
    final bytes = await _fetchImageBytes(url);
    final directory = await _resolveDownloadsDirectory();
    final path = _uniqueDestinationPath(
      directory: directory.path,
      filename: suggestedName,
    );
    await _fileSelectionService.saveBytesToPath(
      bytes: bytes,
      path: path,
      filename: suggestedName,
    );
  }

  Future<void> _previewSaveAs(String url, String suggestedName) async {
    // Fetch first so a transport failure surfaces before the picker opens.
    final bytes = await _fetchImageBytes(url);
    final location = await _fileSelectionService.getSaveLocation(
      suggestedName: suggestedName,
    );
    if (location == null) {
      // User cancelled the picker; treat as a silent no-op.
      throw const ImagePreviewActionCancelled();
    }
    await _fileSelectionService.saveBytesToPath(
      bytes: bytes,
      path: location.path,
      filename: suggestedName,
    );
  }

  Future<void> _previewCopyToClipboard(String url) async {
    final bytes = await _fetchImageBytes(url);
    final ok = await _clipboardService.writeImage(bytes);
    if (!ok) {
      throw Exception('当前平台不支持复制图片到剪贴板');
    }
  }

  Future<void> _previewSaveSticker(
    Message message,
    MessageAttachment attachment,
  ) async {
    final stickerId = attachment.stickerId;
    if (stickerId == null || stickerId.isEmpty) {
      throw Exception('该表情无法保存');
    }
    await _stickerPacksController.saveSticker(
      roomId: message.roomId,
      stickerId: stickerId,
      targetScope: 'personal',
      userId: _currentUser.id,
    );
  }

  /// The directory new downloads land in. Prefers the platform Downloads
  /// folder, falling back to the app documents directory when unavailable.
  Future<Directory> _resolveDownloadsDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    } catch (_) {
      // Fall through to the documents directory.
    }
    return getApplicationDocumentsDirectory();
  }

  /// Builds a destination path inside [directory] for [filename], appending a
  /// " (n)" suffix before the extension when the name already exists so a
  /// download never silently overwrites an existing file.
  String _uniqueDestinationPath({
    required String directory,
    required String filename,
  }) {
    final separator = Platform.pathSeparator;
    final base = directory.endsWith(separator)
        ? directory.substring(0, directory.length - 1)
        : directory;
    String candidate(String name) => '$base$separator$name';

    if (!File(candidate(filename)).existsSync()) return candidate(filename);

    final dot = filename.lastIndexOf('.');
    final stem = dot <= 0 ? filename : filename.substring(0, dot);
    final ext = dot <= 0 ? '' : filename.substring(dot);
    for (var i = 1; i < 1000; i++) {
      final name = '$stem ($i)$ext';
      if (!File(candidate(name)).existsSync()) return candidate(name);
    }
    return candidate(filename);
  }
}
