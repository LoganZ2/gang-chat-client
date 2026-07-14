import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:client/src/app/media_cache_controller.dart';
import 'package:client/src/app/file_transfer_state.dart';
import 'package:client/src/protocol/api_client.dart';

void main() {
  test('getOrDownload stores bytes and reuses cached file', () async {
    final temp = await Directory.systemTemp.createTemp(
      'gang_media_cache_test_',
    );
    addTearDown(() => temp.delete(recursive: true));
    var requests = 0;
    final controller = MediaCacheController(
      cacheDirectoryProvider: () async => temp,
      httpClientFactory: () => _BytesClient(() {
        requests += 1;
        return [1, 2, 3, 4];
      }),
    );
    final request = MediaCacheRequest.tryFromUrl(
      url: 'https://assets.example.test/files/report.pdf',
      filename: 'report.pdf',
      mimeType: 'application/pdf',
      expectedBytes: 4,
    )!;

    final first = await controller.getOrDownload(request: request);
    expect(await first.readAsBytes(), [1, 2, 3, 4]);
    final second = await controller.getOrDownload(request: request);

    expect(second.path, first.path);
    expect(requests, 1);
  });

  test('copyFileToPath writes cached bytes atomically', () async {
    final temp = await Directory.systemTemp.createTemp(
      'gang_media_cache_test_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}/source.bin');
    await source.writeAsBytes([5, 6, 7]);
    final destination = '${temp.path}/nested/destination.bin';
    final controller = MediaCacheController(
      cacheDirectoryProvider: () async => temp,
    );
    final transfer = FileTransferState.download(
      controller: UploadTransferController(),
      totalBytes: 0,
      destinationPath: destination,
    );
    final progress = <int>[];

    await controller.copyFileToPath(
      source: source,
      destinationPath: destination,
      transfer: transfer,
      onProgress: ({required sentBytes, required totalBytes}) {
        expect(totalBytes, 3);
        progress.add(sentBytes);
      },
    );

    expect(await File(destination).readAsBytes(), [5, 6, 7]);
    expect(transfer.wroteDestination, isTrue);
    expect(progress, [0, 3]);
  });

  test('getOrDownload deletes partial cache file after cancellation', () async {
    final temp = await Directory.systemTemp.createTemp(
      'gang_media_cache_test_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final controller = MediaCacheController(
      cacheDirectoryProvider: () async => temp,
      httpClientFactory: () => _BytesClient(() => [8, 9, 10]),
    );
    final request = MediaCacheRequest.tryFromUrl(
      url: 'https://assets.example.test/files/cancel.bin',
      filename: 'cancel.bin',
      expectedBytes: 3,
    )!;
    final transfer = FileTransferState.download(
      controller: UploadTransferController(),
      totalBytes: 0,
      destinationPath: '${temp.path}/cancel.bin',
    );

    await expectLater(
      controller.getOrDownload(
        request: request,
        transfer: transfer,
        onProgress: ({required sentBytes, required totalBytes}) {
          if (sentBytes > 0) transfer.cancelTransfer();
        },
      ),
      throwsA(isA<MediaCacheCancelledException>()),
    );

    final cached = await controller.cachedFile(request);
    expect(cached, isNull);
  });
}

class _BytesClient extends http.BaseClient {
  _BytesClient(this.bytes);

  final List<int> Function() bytes;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('closed', request.url);
    final body = bytes();
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(body.map((byte) => [byte])),
      200,
      contentLength: body.length,
    );
  }

  @override
  void close() {
    _closed = true;
    super.close();
  }
}
