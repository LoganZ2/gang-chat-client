import 'dart:io' show Platform;

import 'package:client/src/shell/clipboard_service.dart';
import 'package:client/src/shell/file_selection_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'SelectedFile.fromBytes keeps clipboard image bytes uploadable',
    () async {
      final source = Uint8List.fromList(<int>[1, 2, 3]);
      final file = SelectedFile.fromBytes(
        name: 'clipboard-image.png',
        mimeType: 'image/png',
        bytes: source,
      );

      source[0] = 9;
      final firstRead = await file.readAsBytes();
      firstRead[1] = 8;

      expect(file.name, 'clipboard-image.png');
      expect(file.mimeType, 'image/png');
      expect(await file.length(), 3);
      expect(await file.readAsBytes(), <int>[1, 2, 3]);
    },
  );

  test(
    'ClipboardService.readImageFile parses native image payload',
    () async {
      const channel = MethodChannel('gang_chat/clipboard');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'readImageFile');
        return <String, Object>{
          'filename': 'screenshot.png',
          'mime_type': 'image/png',
          'bytes': Uint8List.fromList(<int>[137, 80, 78, 71]),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final image = await const ClipboardService().readImageFile();

      expect(image, isNotNull);
      expect(image!.filename, 'screenshot.png');
      expect(image.mimeType, 'image/png');
      expect(image.bytes, <int>[137, 80, 78, 71]);
    },
    skip: !Platform.isWindows,
  );
}
