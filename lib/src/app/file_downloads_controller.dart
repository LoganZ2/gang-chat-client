import 'dart:async';
import 'dart:io' show File, IOSink;

import 'package:http/http.dart' as http;

import '../protocol/api_client.dart';
import 'file_transfer_state.dart';

typedef FileDownloadProgressHandler =
    void Function({required int sentBytes, required int totalBytes});

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => '下载已取消';
}

class FileDownloadStatePatch {
  const FileDownloadStatePatch({required this.downloads});

  final Map<String, FileTransferState> downloads;
}

class FileDownloadsController {
  FileDownloadsController({http.Client Function()? httpClientFactory})
    : _httpClientFactory = httpClientFactory ?? http.Client.new;

  final http.Client Function() _httpClientFactory;

  FileTransferState createDownload({
    required int totalBytes,
    required String destinationPath,
  }) {
    return FileTransferState.download(
      controller: UploadTransferController(),
      totalBytes: totalBytes,
      destinationPath: destinationPath,
    );
  }

  bool canStartDownload({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
  }) {
    return !downloads.containsKey(downloadKey);
  }

  FileDownloadStatePatch patchStartedDownload({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
    required FileTransferState transfer,
  }) {
    return FileDownloadStatePatch(
      downloads: {...downloads, downloadKey: transfer},
    );
  }

  bool shouldApplyDownloadProgress({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
    required FileTransferState transfer,
  }) {
    return identical(downloads[downloadKey], transfer);
  }

  FileDownloadStatePatch? patchDownloadProgress({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
    required FileTransferState transfer,
  }) {
    if (!shouldApplyDownloadProgress(
      downloads: downloads,
      downloadKey: downloadKey,
      transfer: transfer,
    )) {
      return null;
    }
    return FileDownloadStatePatch(downloads: downloads);
  }

  bool canCompleteDownload({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
    required FileTransferState transfer,
  }) {
    return !transfer.cancelled &&
        shouldApplyDownloadProgress(
          downloads: downloads,
          downloadKey: downloadKey,
          transfer: transfer,
        );
  }

  FileDownloadStatePatch patchCompletedDownload({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
  }) {
    return patchRemovedDownload(downloads: downloads, downloadKey: downloadKey);
  }

  FileDownloadStatePatch patchFailedDownload({
    required Map<String, FileTransferState> downloads,
    required FileTransferState transfer,
    required Object failure,
  }) {
    transfer.markFailed(failure, stopTransferSpeed: true);
    return FileDownloadStatePatch(downloads: downloads);
  }

  FileDownloadStatePatch patchRemovedDownload({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
  }) {
    final next = Map<String, FileTransferState>.of(downloads)
      ..remove(downloadKey);
    return FileDownloadStatePatch(downloads: next);
  }

  String? partialDownloadPathToDelete(FileTransferState transfer) {
    final destinationPath = transfer.destinationPath;
    if (destinationPath == null || !transfer.wroteDestination) return null;
    return destinationPath;
  }

  bool pauseDownload({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
  }) {
    final transfer = downloads[downloadKey];
    if (transfer == null || !transfer.isDownload) return false;
    return transfer.pauseTransfer();
  }

  FileDownloadStatePatch? patchPausedDownload({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
  }) {
    final changed = pauseDownload(
      downloads: downloads,
      downloadKey: downloadKey,
    );
    if (!changed) return null;
    return FileDownloadStatePatch(downloads: downloads);
  }

  bool resumeDownload({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
  }) {
    final transfer = downloads[downloadKey];
    if (transfer == null || !transfer.isDownload) return false;
    return transfer.resumeTransfer();
  }

  FileDownloadStatePatch? patchResumedDownload({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
  }) {
    final changed = resumeDownload(
      downloads: downloads,
      downloadKey: downloadKey,
    );
    if (!changed) return null;
    return FileDownloadStatePatch(downloads: downloads);
  }

  bool cancelDownload({
    required Map<String, FileTransferState> downloads,
    required String downloadKey,
  }) {
    final transfer = downloads[downloadKey];
    if (transfer == null || !transfer.isDownload) return false;
    return transfer.cancelTransfer();
  }

  Future<void> downloadToFile({
    required Uri uri,
    required FileTransferState transfer,
    FileDownloadProgressHandler? onProgress,
  }) async {
    final destinationPath = transfer.destinationPath;
    if (destinationPath == null) {
      throw StateError('下载位置不存在');
    }

    http.Client? client;
    IOSink? sink;
    try {
      client = _httpClientFactory();
      transfer.downloadClient = client;
      final request = http.Request('GET', uri);
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('下载失败 (${response.statusCode})');
      }

      final totalBytes = response.contentLength ?? transfer.totalBytes;
      var receivedBytes = 0;
      transfer.updateProgress(sentBytes: 0, totalBytes: totalBytes);
      onProgress?.call(sentBytes: 0, totalBytes: totalBytes);

      final file = File(destinationPath);
      sink = file.openWrite();
      transfer.wroteDestination = true;
      await for (final chunk in response.stream) {
        await transfer.controller.waitIfPaused();
        if (transfer.cancelled) throw const DownloadCancelledException();

        sink.add(chunk);
        receivedBytes += chunk.length;
        transfer.updateProgress(
          sentBytes: receivedBytes,
          totalBytes: totalBytes,
        );
        onProgress?.call(sentBytes: receivedBytes, totalBytes: totalBytes);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (transfer.cancelled) throw const DownloadCancelledException();
    } on DownloadCancelledException {
      if (transfer.wroteDestination) {
        await deletePartialDownload(destinationPath);
      }
      rethrow;
    } catch (_) {
      if (transfer.cancelled) {
        if (transfer.wroteDestination) {
          await deletePartialDownload(destinationPath);
        }
        throw const DownloadCancelledException();
      }
      rethrow;
    } finally {
      client?.close();
      transfer.downloadClient = null;
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          // The client may have been closed to cancel the response stream.
        }
      }
    }
  }

  void cancel(FileTransferState transfer) {
    transfer.cancelTransfer();
  }

  Future<void> deletePartialDownload(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort cleanup for a cancelled or failed partial download.
    }
  }
}
