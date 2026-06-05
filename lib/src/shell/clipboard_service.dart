import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class ClipboardService {
  const ClipboardService();

  static const _clipboardFilesChannel = MethodChannel('gang_chat/clipboard');

  Future<List<String>> readFilePaths() async {
    if (kIsWeb || !Platform.isWindows) return const <String>[];
    return await _clipboardFilesChannel.invokeListMethod<String>(
          'readFilePaths',
        ) ??
        const <String>[];
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
