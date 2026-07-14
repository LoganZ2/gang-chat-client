import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/sticker_uploads.dart';

void main() {
  test(
    'stickerUploadItemsFromFiles extracts valid images from zip files',
    () async {
      final archive = Archive()
        ..addFile(
          ArchiveFile('stickers/hello.png', _pngBytes.length, _pngBytes),
        )
        ..addFile(
          ArchiveFile('__MACOSX/ignored.png', _pngBytes.length, _pngBytes),
        )
        ..addFile(ArchiveFile('notes.txt', 5, utf8.encode('notes')));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      final temp = await Directory.systemTemp.createTemp('sticker_uploads_');
      addTearDown(() => temp.delete(recursive: true));
      final zipFile = File('${temp.path}/pack.zip');
      await zipFile.writeAsBytes(zipBytes);

      final items = await stickerUploadItemsFromFiles(
        [
          StickerUploadSource(
            filename: 'pack.zip',
            readBytes: zipFile.readAsBytes,
          ),
        ],
        decodeImageDimensions: (_) async =>
            const StickerImageDimensions(width: 1, height: 1),
      );

      expect(items, hasLength(1));
      expect(items.single.filename, 'hello.png');
      expect(items.single.bytes, _pngBytes);
    },
  );

  test('sticker upload helpers produce stable names for UI callers', () {
    expect(stickerNameFromFilename('hello-world.webp'), 'hello-world');
    expect(stickerNameFromFilename('.png'), 'sticker');

    final filename = stickerUploadFilename('hello world.WEBP', 3);
    expect(filename, startsWith('hello-world-'));
    expect(filename, endsWith('-3.webp'));
  });

  test('sticker upload error copy stays outside UI', () {
    expect(stickerPackRequiresServerMessage(), '表情包需要登录后从服务端读取');
    expect(stickerPickerOpenFailureMessage('denied'), '无法打开文件选择器：denied');
    expect(stickerNoUploadableImagesMessage(), '没有找到可上传的图片');
  });
}

final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
);
