import 'dart:typed_data';

import 'package:client/src/app/sticker_management.dart' as sticker_management;
import 'package:client/src/protocol/api_client.dart';
import 'package:client/src/protocol/models.dart';
import 'package:client/src/shell/file_selection_service.dart';
import 'package:client/src/ui/ui.dart' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: ui.uiTheme(),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: SizedBox.expand(child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('room sticker panel keeps read-only actions disabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final backend = _FakeStickerBackend(
      capabilities:
          const sticker_management.StickerManagementCapabilities.readOnlyDownloads(),
      packs: [
        _pack('room_pack', ['alpha', 'beta']),
      ],
    );
    final files = _FakeFileSelectionService();

    await tester.pumpWidget(
      _host(
        ui.StickerManagerPanel(
          backend: backend,
          fileSelectionService: files,
          title: '房间表情包',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_buttonEnabled(tester, '本地上传'), isFalse);
    expect(_buttonEnabled(tester, '批量管理'), isTrue);
    expect(_buttonEnabled(tester, '筛选'), isTrue);

    await tester.tap(find.text('批量管理'));
    await tester.pumpAndSettle();

    expect(_buttonEnabled(tester, '删除'), isFalse);
    expect(_buttonEnabled(tester, '下载'), isFalse);
    expect(_buttonEnabled(tester, '置顶'), isFalse);
    expect(_buttonEnabled(tester, '全选'), isTrue);
    expect(_buttonSelected(tester, '全选'), isFalse);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    expect(_buttonEnabled(tester, '全选'), isTrue);
    expect(_buttonSelected(tester, '全选'), isTrue);
    expect(_buttonEnabled(tester, '删除'), isFalse);
    expect(_buttonEnabled(tester, '下载'), isTrue);
    expect(_buttonEnabled(tester, '置顶'), isFalse);

    await tester.tap(find.byTooltip('alpha'));
    await tester.pumpAndSettle();

    expect(_buttonEnabled(tester, '全选'), isTrue);
    expect(_buttonSelected(tester, '全选'), isFalse);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(_buttonSelected(tester, '全选'), isTrue);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    expect(_buttonEnabled(tester, '全选'), isTrue);
    expect(_buttonSelected(tester, '全选'), isFalse);

    await tester.tap(find.text('取消管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.image_not_supported_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('表情预览'), findsOneWidget);
    expect(_buttonEnabled(tester, '下载'), isTrue);
    expect(_buttonEnabled(tester, '保存名称'), isFalse);
    expect(_buttonEnabled(tester, '置顶'), isFalse);
    expect(_buttonEnabled(tester, '上移一位'), isFalse);
    expect(_buttonEnabled(tester, '下移一位'), isFalse);
    expect(_buttonEnabled(tester, '删除'), isFalse);

    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();

    expect(backend.downloads, 1);
    expect(files.saved, 1);
    expect(backend.mutations, 0);
    expect(tester.takeException(), isNull);
  });
}

bool _buttonEnabled(WidgetTester tester, String label) {
  final surfaceFinder = find.ancestor(
    of: find.text(label),
    matching: find.byType(ui.PressableSurface),
  );
  expect(surfaceFinder, findsOneWidget, reason: label);
  return tester.widget<ui.PressableSurface>(surfaceFinder).enabled;
}

bool _buttonSelected(WidgetTester tester, String label) {
  final surfaceFinder = find.ancestor(
    of: find.text(label),
    matching: find.byType(ui.PressableSurface),
  );
  expect(surfaceFinder, findsOneWidget, reason: label);
  return tester.widget<ui.PressableSurface>(surfaceFinder).selected;
}

StickerPack _pack(String id, List<String> stickerIds) {
  return StickerPack(
    id: id,
    scope: 'room',
    roomId: 'room_1',
    name: id,
    sortOrder: 10,
    updatedAt: DateTime.utc(2026, 6, 9),
    stickers: [
      for (final entry in stickerIds.asMap().entries)
        Sticker(
          id: entry.value,
          name: entry.value,
          sortOrder: (entry.key + 1) * 10,
          asset: UploadedAsset(
            id: 'asset_${entry.value}',
            url: '/assets/${entry.value}.png',
            thumbnailUrl: '',
            mimeType: 'image/png',
          ),
        ),
    ],
  );
}

class _FakeStickerBackend extends ui.StickerManagerBackend {
  _FakeStickerBackend({required this.capabilities, required this.packs});

  @override
  final sticker_management.StickerManagementCapabilities capabilities;

  final List<StickerPack> packs;
  int downloads = 0;
  int mutations = 0;

  @override
  sticker_management.StickerManagementScope get scope =>
      sticker_management.StickerManagementScope.room;

  @override
  bool get hasApi => true;

  @override
  Future<List<StickerPack>> loadPacks() async => packs;

  @override
  Future<StickerPack> createDefaultPack({int? sortOrder}) async {
    mutations += 1;
    throw StateError('disabled');
  }

  @override
  Future<String> uploadImageAsset({
    required Uint8List bytes,
    required String filename,
    required String purpose,
  }) async {
    mutations += 1;
    throw StateError('disabled');
  }

  @override
  Future<void> addSticker({
    required String packId,
    required String assetId,
    required String name,
    int? sortOrder,
  }) async {
    mutations += 1;
  }

  @override
  Future<void> deleteSticker({
    required String packId,
    required String stickerId,
  }) async {
    mutations += 1;
  }

  @override
  Future<String?> renameSticker({
    required String packId,
    required String stickerId,
    required String name,
  }) async {
    mutations += 1;
    return name;
  }

  @override
  Future<void> reorderStickers({
    required String packId,
    required List<String> stickerIds,
  }) async {
    mutations += 1;
  }

  @override
  Future<DownloadedFile> downloadStickers({
    required List<String> stickerIds,
  }) async {
    downloads += 1;
    return DownloadedFile(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'stickers.zip',
      mimeType: 'application/zip',
    );
  }
}

class _FakeFileSelectionService extends FileSelectionService {
  int saved = 0;

  @override
  Future<SaveFileLocation?> getSaveLocation({
    required String suggestedName,
    List<FileTypeGroup> acceptedTypeGroups = const [],
    String? confirmButtonText,
  }) async {
    return SaveFileLocation(path: suggestedName);
  }

  @override
  Future<void> saveBytesToPath({
    required Uint8List bytes,
    required String path,
    required String filename,
    String? mimeType,
  }) async {
    saved += 1;
  }
}
