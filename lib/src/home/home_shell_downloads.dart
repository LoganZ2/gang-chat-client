part of 'home_shell.dart';

/// Download orchestration for file attachments shown in the chat.
///
/// Kept deliberately thin: the streaming/IO lives in [FileDownloadsController]
/// and all of the "what state is this transfer in" decisions live in
/// `file_display.dart`. This extension only wires the two to the widget tree
/// and the local [_fileDownloads] map, and surfaces user-facing notices.
extension _HomeShellDownloads on _HomeShellState {
  /// Start saving [attachment] to a user-picked location. [resolvedUrl] is the
  /// absolute asset URL (resolved by the widget layer against [AppConfig]).
  Future<void> _downloadAttachment({
    required Message message,
    required MessageAttachment attachment,
    required int index,
    required String resolvedUrl,
  }) async {
    final downloadKey = file_display.fileDownloadKey(message, attachment, index);
    if (!_fileDownloadsController.canStartDownload(
      downloads: _fileDownloads,
      downloadKey: downloadKey,
    )) {
      return;
    }

    final uri = file_display.fileDownloadUri(resolvedUrl);
    if (uri == null) {
      _showDownloadNotice(file_display.fileDownloadUnavailableMessage());
      return;
    }

    final suggestedName = file_display.fileAttachmentTitle(attachment);
    SaveFileLocation? location;
    try {
      location = await _fileSelectionService.getSaveLocation(
        suggestedName: suggestedName,
      );
    } catch (error) {
      if (!mounted) return;
      _showDownloadNotice(file_display.filePickerOpenFailureMessage(error));
      return;
    }
    if (!mounted || location == null) return;

    final transfer = _fileDownloadsController.createDownload(
      totalBytes: attachment.asset?.sizeBytes ?? 0,
      destinationPath: location.path,
    );
    _setHomeState(
      () => _applyDownloadPatch(
        _fileDownloadsController.patchStartedDownload(
          downloads: _fileDownloads,
          downloadKey: downloadKey,
          transfer: transfer,
        ),
      ),
    );

    try {
      await _fileDownloadsController.downloadToFile(
        uri: uri,
        transfer: transfer,
        onProgress: ({required sentBytes, required totalBytes}) {
          if (!mounted) return;
          final patch = _fileDownloadsController.patchDownloadProgress(
            downloads: _fileDownloads,
            downloadKey: downloadKey,
            transfer: transfer,
          );
          if (patch == null) return;
          _setHomeState(() => _applyDownloadPatch(patch));
        },
      );
      if (!_fileDownloadsController.canCompleteDownload(
        downloads: _fileDownloads,
        downloadKey: downloadKey,
        transfer: transfer,
      )) {
        return;
      }
      if (!mounted) return;
      _setHomeState(
        () => _applyDownloadPatch(
          _fileDownloadsController.patchCompletedDownload(
            downloads: _fileDownloads,
            downloadKey: downloadKey,
          ),
        ),
      );
      _showDownloadNotice(file_display.fileDownloadedNotice());
    } on DownloadCancelledException {
      // Cancellation already removed the entry via [_cancelDownload]; nothing
      // to report.
    } catch (error) {
      if (!mounted) return;
      _setHomeState(
        () => _applyDownloadPatch(
          _fileDownloadsController.patchFailedDownload(
            downloads: _fileDownloads,
            transfer: transfer,
            failure: error,
          ),
        ),
      );
    }
  }

  void _pauseDownload(String downloadKey) {
    final patch = _fileDownloadsController.patchPausedDownload(
      downloads: _fileDownloads,
      downloadKey: downloadKey,
    );
    if (patch == null) return;
    _setHomeState(() => _applyDownloadPatch(patch));
  }

  void _resumeDownload(String downloadKey) {
    final patch = _fileDownloadsController.patchResumedDownload(
      downloads: _fileDownloads,
      downloadKey: downloadKey,
    );
    if (patch == null) return;
    _setHomeState(() => _applyDownloadPatch(patch));
  }

  /// Cancel an in-flight download and drop it from the map. The streaming loop
  /// in [FileDownloadsController.downloadToFile] sees the cancellation, cleans
  /// up the partial file, and throws [DownloadCancelledException].
  void _cancelDownload(String downloadKey) {
    final transfer = _fileDownloads[downloadKey];
    if (transfer == null) return;
    _fileDownloadsController.cancel(transfer);
    _setHomeState(
      () => _applyDownloadPatch(
        _fileDownloadsController.patchRemovedDownload(
          downloads: _fileDownloads,
          downloadKey: downloadKey,
        ),
      ),
    );
  }

  /// Clear a finished-but-failed download entry so the tile returns to its
  /// idle, re-downloadable state.
  void _dismissDownload(String downloadKey) {
    if (!_fileDownloads.containsKey(downloadKey)) return;
    _setHomeState(
      () => _applyDownloadPatch(
        _fileDownloadsController.patchRemovedDownload(
          downloads: _fileDownloads,
          downloadKey: downloadKey,
        ),
      ),
    );
  }

  /// Cancel every active download (used on dispose) so no http client or sink
  /// is left dangling after the shell goes away.
  void _cancelActiveDownloads() {
    for (final transfer in _fileDownloads.values) {
      _fileDownloadsController.cancel(transfer);
    }
  }

  void _applyDownloadPatch(FileDownloadStatePatch patch) {
    _fileDownloads = patch.downloads;
  }

  void _showDownloadNotice(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
