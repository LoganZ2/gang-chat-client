import 'dart:typed_data';
import 'dart:ui' as ui;

import '../app/sticker_uploads.dart';
import '../shell/file_selection_service.dart';

List<StickerUploadSource> stickerUploadSourcesFromSelectedFiles(
  Iterable<SelectedFile> files,
) {
  return files
      .map(
        (file) => StickerUploadSource(
          filename: file.name,
          readBytes: file.readAsBytes,
        ),
      )
      .toList(growable: false);
}

Future<StickerImageDimensions> decodeStickerImageDimensions(
  Uint8List bytes,
) async {
  ui.Codec? codec;
  ui.FrameInfo? frame;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    frame = await codec.getNextFrame();
    return StickerImageDimensions(
      width: frame.image.width,
      height: frame.image.height,
    );
  } finally {
    frame?.image.dispose();
    codec?.dispose();
  }
}
