import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/composer_attachment_display.dart';

void main() {
  test('size label is null when the picker reports no size', () {
    const view = ComposerAttachmentView(
      id: 'a',
      filename: 'a.txt',
      status: ComposerAttachmentStatus.uploaded,
    );
    expect(view.sizeLabel, isNull);
  });

  test('size label formats a known size', () {
    const view = ComposerAttachmentView(
      id: 'a',
      filename: 'a.txt',
      status: ComposerAttachmentStatus.uploaded,
      sizeBytes: 2048,
    );
    expect(view.sizeLabel, '2.0 KB');
  });

  test('glyph follows the mime type family', () {
    expect(
      composerAttachmentGlyph(mimeType: 'image/png', filename: 'p.png'),
      Icons.image_outlined,
    );
    expect(
      composerAttachmentGlyph(mimeType: 'video/mp4', filename: 'v.mp4'),
      Icons.movie_outlined,
    );
    expect(
      composerAttachmentGlyph(mimeType: 'audio/mpeg', filename: 's.mp3'),
      Icons.audiotrack_outlined,
    );
    expect(
      composerAttachmentGlyph(mimeType: 'application/pdf', filename: 'd.pdf'),
      Icons.picture_as_pdf_outlined,
    );
    expect(
      composerAttachmentGlyph(mimeType: 'text/plain', filename: 'n.txt'),
      Icons.description_outlined,
    );
  });

  test('glyph falls back to the extension when no mime is reported', () {
    expect(
      composerAttachmentGlyph(mimeType: null, filename: 'bundle.zip'),
      Icons.folder_zip_outlined,
    );
    expect(
      composerAttachmentGlyph(mimeType: '', filename: 'archive.tar.gz'),
      Icons.folder_zip_outlined,
    );
    expect(
      composerAttachmentGlyph(mimeType: null, filename: 'mystery'),
      Icons.insert_drive_file_outlined,
    );
  });
}
