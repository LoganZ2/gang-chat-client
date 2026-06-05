import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:client/src/app/file_downloads_controller.dart';
import 'package:client/src/app/file_transfer_state.dart';
import 'package:client/src/protocol/api_client.dart';

void main() {
  test('downloadToFile streams bytes and reports progress', () async {
    final temp = await Directory.systemTemp.createTemp('gang_download_test_');
    addTearDown(() => temp.delete(recursive: true));
    final destination = '${temp.path}/report.txt';
    final controller = FileDownloadsController(
      httpClientFactory: () => _StreamClient(
        Stream<List<int>>.fromIterable([
          [1, 2],
          [3, 4],
        ]),
        contentLength: 4,
      ),
    );
    final transfer = controller.createDownload(
      totalBytes: 0,
      destinationPath: destination,
    );
    final progress = <int>[];

    await controller.downloadToFile(
      uri: Uri.parse('http://example.test/report.txt'),
      transfer: transfer,
      onProgress: ({required sentBytes, required totalBytes}) {
        expect(totalBytes, 4);
        progress.add(sentBytes);
      },
    );

    expect(await File(destination).readAsBytes(), [1, 2, 3, 4]);
    expect(progress, [0, 2, 4]);
    expect(transfer.downloadClient, isNull);
  });

  test('downloadToFile deletes partial file after cancellation', () async {
    final temp = await Directory.systemTemp.createTemp('gang_download_test_');
    addTearDown(() => temp.delete(recursive: true));
    final destination = '${temp.path}/partial.bin';
    final controller = FileDownloadsController(
      httpClientFactory: () => _StreamClient(
        Stream<List<int>>.fromIterable([
          [1, 2, 3],
        ]),
        contentLength: 3,
      ),
    );
    final transfer = controller.createDownload(
      totalBytes: 0,
      destinationPath: destination,
    );

    await expectLater(
      controller.downloadToFile(
        uri: Uri.parse('http://example.test/partial.bin'),
        transfer: transfer,
        onProgress: ({required sentBytes, required totalBytes}) {
          if (sentBytes > 0) controller.cancel(transfer);
        },
      ),
      throwsA(isA<DownloadCancelledException>()),
    );

    expect(await File(destination).exists(), isFalse);
    expect(transfer.downloadClient, isNull);
  });

  test('download state patches cover started completed failed and removed', () {
    final controller = FileDownloadsController();
    final transfer = controller.createDownload(
      totalBytes: 100,
      destinationPath: '/tmp/report.pdf',
    );

    expect(
      controller.canStartDownload(
        downloads: const {},
        downloadKey: 'message_1:file',
      ),
      isTrue,
    );

    var patch = controller.patchStartedDownload(
      downloads: const {},
      downloadKey: 'message_1:file',
      transfer: transfer,
    );
    expect(patch.downloads['message_1:file'], same(transfer));
    expect(
      controller.canStartDownload(
        downloads: patch.downloads,
        downloadKey: 'message_1:file',
      ),
      isFalse,
    );
    expect(
      controller.shouldApplyDownloadProgress(
        downloads: patch.downloads,
        downloadKey: 'message_1:file',
        transfer: transfer,
      ),
      isTrue,
    );
    final progressPatch = controller.patchDownloadProgress(
      downloads: patch.downloads,
      downloadKey: 'message_1:file',
      transfer: transfer,
    );
    expect(progressPatch, isNotNull);
    expect(progressPatch!.downloads, same(patch.downloads));

    patch = controller.patchFailedDownload(
      downloads: patch.downloads,
      transfer: transfer,
      failure: 'network failed',
    );
    expect(transfer.failed, isTrue);
    expect(transfer.error, 'network failed');

    patch = controller.patchRemovedDownload(
      downloads: patch.downloads,
      downloadKey: 'message_1:file',
    );
    expect(patch.downloads, isEmpty);
  });

  test('download completion and cleanup guards reject stale transfers', () {
    final controller = FileDownloadsController();
    final active = controller.createDownload(
      totalBytes: 100,
      destinationPath: '/tmp/active.pdf',
    );
    final stale = controller.createDownload(
      totalBytes: 100,
      destinationPath: '/tmp/stale.pdf',
    );
    final downloads = {'download': active};

    expect(
      controller.canCompleteDownload(
        downloads: downloads,
        downloadKey: 'download',
        transfer: active,
      ),
      isTrue,
    );
    expect(
      controller.canCompleteDownload(
        downloads: downloads,
        downloadKey: 'download',
        transfer: stale,
      ),
      isFalse,
    );

    active.wroteDestination = true;
    expect(controller.partialDownloadPathToDelete(active), '/tmp/active.pdf');
    expect(controller.partialDownloadPathToDelete(stale), isNull);

    active.cancelTransfer();
    expect(
      controller.canCompleteDownload(
        downloads: downloads,
        downloadKey: 'download',
        transfer: active,
      ),
      isFalse,
    );
  });

  test('download controls pause resume and cancel only download transfers', () {
    final controller = FileDownloadsController();
    final download = controller.createDownload(
      totalBytes: 100,
      destinationPath: '/tmp/report.pdf',
    );
    final upload = FileTransferState.upload(
      controller: UploadTransferController(),
      totalBytes: 100,
    );
    final downloads = {'download': download, 'upload': upload};

    expect(
      controller.patchPausedDownload(
        downloads: downloads,
        downloadKey: 'download',
      ),
      isNotNull,
    );
    expect(download.paused, isTrue);
    expect(
      controller.patchPausedDownload(
        downloads: downloads,
        downloadKey: 'download',
      ),
      isNull,
    );

    expect(
      controller.patchResumedDownload(
        downloads: downloads,
        downloadKey: 'download',
      ),
      isNotNull,
    );
    expect(download.paused, isFalse);
    expect(
      controller.patchResumedDownload(
        downloads: downloads,
        downloadKey: 'download',
      ),
      isNull,
    );

    expect(
      controller.pauseDownload(downloads: downloads, downloadKey: 'upload'),
      isFalse,
    );
    expect(
      controller.cancelDownload(downloads: downloads, downloadKey: 'upload'),
      isFalse,
    );
    expect(
      controller.cancelDownload(downloads: downloads, downloadKey: 'missing'),
      isFalse,
    );

    expect(
      controller.cancelDownload(downloads: downloads, downloadKey: 'download'),
      isTrue,
    );
    expect(download.cancelled, isTrue);
    expect(
      controller.cancelDownload(downloads: downloads, downloadKey: 'download'),
      isFalse,
    );
  });
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.stream, {required this.contentLength});

  final Stream<List<int>> stream;
  final int contentLength;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('closed', request.url);
    return http.StreamedResponse(stream, 200, contentLength: contentLength);
  }

  @override
  void close() {
    _closed = true;
    super.close();
  }
}
