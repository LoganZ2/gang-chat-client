import 'dart:typed_data';

import 'package:archive/archive.dart';

const stickerImageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif'};
const maxStickerUploadsPerBatch = 500;
const maxStickerImageBytes = 25 * 1024 * 1024;

typedef StickerBytesReader = Future<Uint8List> Function();
typedef StickerImageDecoder =
    Future<StickerImageDimensions> Function(Uint8List bytes);

class StickerUploadSource {
  const StickerUploadSource({required this.filename, required this.readBytes});

  final String filename;
  final StickerBytesReader readBytes;
}

class StickerUploadItem {
  const StickerUploadItem({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;
}

class StickerImageDimensions {
  const StickerImageDimensions({required this.width, required this.height});

  final int width;
  final int height;

  @override
  String toString() => '${width}x$height';
}

String stickerPackRequiresServerMessage() {
  return '表情包需要登录后从服务端读取';
}

String stickerPickerOpenFailureMessage(Object error) {
  return '无法打开文件选择器';
}

String stickerNoUploadableImagesMessage() {
  return '没有找到可上传的图片';
}

Future<List<StickerUploadItem>> stickerUploadItemsFromFiles(
  Iterable<StickerUploadSource> files, {
  required StickerImageDecoder decodeImageDimensions,
}) async {
  final items = <StickerUploadItem>[];
  for (final file in files) {
    final filename = _basename(file.filename);
    if (_isZipFilename(filename)) {
      items.addAll(
        await _stickerUploadItemsFromZip(
          file,
          decodeImageDimensions: decodeImageDimensions,
        ),
      );
    } else if (_isStickerImageFilename(filename)) {
      items.add(
        await _stickerUploadItemFromBytes(
          filename,
          await file.readBytes(),
          decodeImageDimensions: decodeImageDimensions,
        ),
      );
    }
    if (items.length > maxStickerUploadsPerBatch) {
      throw StateError('一次最多上传 $maxStickerUploadsPerBatch 个表情');
    }
  }
  return items;
}

String stickerUploadFilename(String originalName, int index) {
  final cleaned = originalName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
  final extensionMatch = RegExp(r'\.([A-Za-z0-9]+)$').firstMatch(cleaned);
  final extension = extensionMatch == null
      ? 'png'
      : extensionMatch.group(1)!.toLowerCase();
  final stem = cleaned.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
  final safeStem = stem.isEmpty ? 'sticker' : stem;
  return '$safeStem-${DateTime.now().millisecondsSinceEpoch}-$index.$extension';
}

String stickerNameFromFilename(String filename) {
  final stem = filename.trim().replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
  if (stem.isEmpty) return 'sticker';
  final chars = String.fromCharCodes(stem.runes.take(32));
  return chars.isEmpty ? 'sticker' : chars;
}

Future<List<StickerUploadItem>> _stickerUploadItemsFromZip(
  StickerUploadSource file, {
  required StickerImageDecoder decodeImageDimensions,
}) async {
  final bytes = await file.readBytes();
  if (bytes.isEmpty) throw StateError('${file.filename} 文件为空');

  final archive = ZipDecoder().decodeBytes(bytes);
  final items = <StickerUploadItem>[];
  for (final entry in archive.files) {
    final entryName = entry.name;
    if (!entry.isFile ||
        _isIgnoredZipEntry(entryName) ||
        !_isStickerImageFilename(entryName)) {
      continue;
    }
    if (entry.size > maxStickerImageBytes) {
      throw StateError('${_basename(entryName)} 超过 25MB');
    }
    final content = entry.readBytes();
    if (content == null) continue;
    items.add(
      await _stickerUploadItemFromBytes(
        _basename(entryName),
        content,
        decodeImageDimensions: decodeImageDimensions,
      ),
    );
    if (items.length > maxStickerUploadsPerBatch) {
      throw StateError('一次最多上传 $maxStickerUploadsPerBatch 个表情');
    }
  }
  return items;
}

Future<StickerUploadItem> _stickerUploadItemFromBytes(
  String filename,
  Uint8List bytes, {
  required StickerImageDecoder decodeImageDimensions,
}) async {
  if (bytes.isEmpty) throw StateError('$filename 文件为空');
  if (bytes.length > maxStickerImageBytes) {
    throw StateError('$filename 超过 25MB');
  }
  try {
    await decodeImageDimensions(bytes);
  } catch (_) {
    throw StateError('$filename 不是可识别的图片');
  }
  return StickerUploadItem(filename: filename, bytes: bytes);
}

bool _isStickerImageFilename(String filename) {
  return stickerImageExtensions.contains(_extensionOf(filename));
}

bool _isZipFilename(String filename) => _extensionOf(filename) == 'zip';

bool _isIgnoredZipEntry(String name) {
  final normalized = name.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty);
  if (parts.any((part) => part == '__MACOSX')) return true;
  return _basename(normalized).startsWith('.');
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty);
  final name = parts.isEmpty ? '' : parts.last;
  return name.isEmpty ? 'sticker' : name;
}

String _extensionOf(String filename) {
  final name = _basename(filename).toLowerCase();
  final index = name.lastIndexOf('.');
  if (index < 0 || index == name.length - 1) return '';
  return name.substring(index + 1);
}
