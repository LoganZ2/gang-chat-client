import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class ClipboardImageFile {
  const ClipboardImageFile({
    required this.bytes,
    this.filename = 'clipboard-image.png',
    this.mimeType = 'image/png',
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

class ClipboardService {
  const ClipboardService();

  static const _clipboardFilesChannel = MethodChannel('gang_chat/clipboard');

  Future<List<String>> readFilePaths() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS)) {
      return const <String>[];
    }
    return await _clipboardFilesChannel.invokeListMethod<String>(
          'readFilePaths',
        ) ??
        const <String>[];
  }

  Future<ClipboardImageFile?> readImageFile() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS)) return null;
    final result = await _clipboardFilesChannel
        .invokeMapMethod<Object?, Object?>('readImageFile');
    if (result == null) return null;
    final bytes = result['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) return null;
    final filename = result['filename'];
    final mimeType = result['mime_type'];
    return ClipboardImageFile(
      bytes: bytes,
      filename: filename is String && filename.isNotEmpty
          ? filename
          : 'clipboard-image.png',
      mimeType: mimeType is String && mimeType.isNotEmpty
          ? mimeType
          : 'image/png',
    );
  }

  Future<String?> readText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    return text == null || text.isEmpty ? null : text;
  }

  Future<void> writeText(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }
}
