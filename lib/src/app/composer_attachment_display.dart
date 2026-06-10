import 'package:flutter/material.dart';

import 'file_display.dart' as file_display;

/// Lifecycle of a file staged in the composer. Files now upload as soon as they
/// are picked, so the chip reflects in-flight progress, success, or failure
/// before the message is ever sent.
enum ComposerAttachmentStatus { uploading, uploaded, failed }

/// A file staged in the composer, waiting to ride the next outgoing message as
/// an attachment. This is the view model handed to the composer's chip strip;
/// the raw picked file (and its in-flight upload) is held by the shell and
/// matched back by [id].
class ComposerAttachmentView {
  const ComposerAttachmentView({
    required this.id,
    required this.filename,
    required this.status,
    this.sizeBytes,
    this.mimeType,
    this.progress,
  });

  final String id;
  final String filename;
  final ComposerAttachmentStatus status;
  final int? sizeBytes;
  final String? mimeType;

  /// Upload progress in the range 0..1, or null when the total size is not yet
  /// known (the chip then shows an indeterminate spinner).
  final double? progress;

  bool get isUploading => status == ComposerAttachmentStatus.uploading;
  bool get isUploaded => status == ComposerAttachmentStatus.uploaded;
  bool get hasFailed => status == ComposerAttachmentStatus.failed;

  /// Human-readable size, or null when the picker could not report one.
  String? get sizeLabel =>
      sizeBytes == null ? null : file_display.formatFileSize(sizeBytes!);
}

/// Pick a representative glyph for a staged file from its mime type, with a
/// small extension fallback so common types still read sensibly when the picker
/// reports no mime.
IconData composerAttachmentGlyph({String? mimeType, required String filename}) {
  final mime = (mimeType ?? '').toLowerCase();
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.startsWith('video/')) return Icons.movie_outlined;
  if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mime.startsWith('text/')) return Icons.description_outlined;

  final dot = filename.lastIndexOf('.');
  final ext = dot >= 0 ? filename.substring(dot + 1).toLowerCase() : '';
  const archive = {'zip', 'rar', '7z', 'tar', 'gz'};
  if (archive.contains(ext)) return Icons.folder_zip_outlined;
  return Icons.insert_drive_file_outlined;
}
