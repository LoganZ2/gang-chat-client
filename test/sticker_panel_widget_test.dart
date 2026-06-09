import 'package:client/src/app/sticker_display.dart' as sticker_display;
import 'package:client/src/home/chat_pane.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: ui.uiTheme(),
    home: Scaffold(
      body: Center(child: SizedBox(width: 560, height: 300, child: child)),
    ),
  );
}

void main() {
  testWidgets('sticker panel flattens packs without pack headers', (
    tester,
  ) async {
    final sent = <String>[];

    await tester.pumpWidget(
      _host(
        StickerPanelForTest(
          state: sticker_display.StickerPanelLoadState(
            loaded: true,
            personalPacks: [
              _pack('saved', 'Saved Stickers', ['saved_1']),
              _pack('mine', '我的表情包', ['mine_1']),
            ],
          ),
          onSendSticker: (sticker) => sent.add(sticker.id),
          onRefresh: () {},
          onSourceChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Saved Stickers'), findsNothing);
    expect(find.text('我的表情包'), findsOneWidget);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.image_not_supported_outlined).first);

    expect(sent, ['saved_1']);
    expect(tester.takeException(), isNull);
  });
}

StickerPack _pack(String id, String name, List<String> stickerIds) {
  return StickerPack(
    id: id,
    scope: 'personal',
    roomId: null,
    name: name,
    sortOrder: 10,
    updatedAt: DateTime.utc(2026, 6, 9),
    stickers: [
      for (final entry in stickerIds.asMap().entries)
        Sticker(
          id: entry.value,
          name: entry.value,
          sortOrder: (entry.key + 1) * 10,
          asset: _asset(entry.value),
        ),
    ],
  );
}

UploadedAsset _asset(String id) {
  return UploadedAsset(
    id: 'asset_$id',
    url: '',
    thumbnailUrl: null,
    mimeType: 'image/png',
    filename: '$id.png',
    sizeBytes: 128,
  );
}
