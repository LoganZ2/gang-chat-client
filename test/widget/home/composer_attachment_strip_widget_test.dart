import 'package:client/src/app/composer_attachment_display.dart' as ca;
import 'package:client/src/home/chat_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, child: child)),
    ),
  );
}

void main() {
  testWidgets('strip lists each staged file with its name', (tester) async {
    await tester.pumpWidget(
      _host(
        ComposerAttachmentStripForTest(
          attachments: const [
            ca.ComposerAttachmentView(
              id: '1',
              filename: 'report.pdf',
              status: ca.ComposerAttachmentStatus.uploaded,
              sizeBytes: 2048,
              mimeType: 'application/pdf',
            ),
            ca.ComposerAttachmentView(
              id: '2',
              filename: 'photo.png',
              status: ca.ComposerAttachmentStatus.uploaded,
              mimeType: 'image/png',
            ),
          ],
          onRemove: (_) {},
        ),
      ),
    );

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('photo.png'), findsOneWidget);
    expect(find.byTooltip('report.pdf'), findsOneWidget);
    expect(find.byTooltip('photo.png'), findsOneWidget);
    // Size shows only when the picker reported one.
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(2));
  });

  testWidgets('the remove button reports the chip id', (tester) async {
    String? removed;
    await tester.pumpWidget(
      _host(
        ComposerAttachmentStripForTest(
          attachments: const [
            ca.ComposerAttachmentView(
              id: 'abc',
              filename: 'a.txt',
              status: ca.ComposerAttachmentStatus.uploaded,
            ),
          ],
          onRemove: (id) => removed = id,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close));
    expect(removed, 'abc');
  });

  testWidgets('an uploading chip shows progress and no type glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ComposerAttachmentStripForTest(
          attachments: const [
            ca.ComposerAttachmentView(
              id: '1',
              filename: 'clip.mp4',
              status: ca.ComposerAttachmentStatus.uploading,
              progress: 0.42,
              mimeType: 'video/mp4',
            ),
          ],
          onRemove: (_) {},
        ),
      ),
    );

    expect(find.text('上传中 42%'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsNothing);
  });

  testWidgets('a failed chip exposes a tappable retry', (tester) async {
    String? retried;
    await tester.pumpWidget(
      _host(
        ComposerAttachmentStripForTest(
          attachments: const [
            ca.ComposerAttachmentView(
              id: 'x',
              filename: 'doc.pdf',
              status: ca.ComposerAttachmentStatus.failed,
            ),
          ],
          onRemove: (_) {},
          onRetry: (id) => retried = id,
        ),
      ),
    );

    expect(find.text('上传失败，点击重试'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    expect(retried, 'x');
  });
}
