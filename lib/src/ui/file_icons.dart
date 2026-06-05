import 'package:flutter/material.dart';

IconData fileIconForMime(String? mimeType) {
  final value = (mimeType ?? '').toLowerCase();
  if (value.startsWith('image/')) return Icons.image_outlined;
  if (value == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (value.startsWith('audio/')) return Icons.audio_file_outlined;
  if (value.startsWith('video/')) return Icons.video_file_outlined;
  if (value.contains('zip') ||
      value.contains('tar') ||
      value.contains('compressed')) {
    return Icons.folder_zip_outlined;
  }
  if (value.startsWith('text/') || value.contains('json')) {
    return Icons.description_outlined;
  }
  return Icons.insert_drive_file_outlined;
}
