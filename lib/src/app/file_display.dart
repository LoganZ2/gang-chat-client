import 'dart:math' as math;

import '../protocol/models.dart';
import 'file_transfer_state.dart';

enum FileAttachmentTrailingKind {
  sending,
  failed,
  activeTransfer,
  placeholder,
  download,
}

class FileAttachmentTransferSlot {
  const FileAttachmentTransferSlot({
    required this.downloadKey,
    required this.transfer,
    required this.usesUploadTransfer,
  });

  final String downloadKey;
  final FileTransferState? transfer;
  final bool usesUploadTransfer;
}

class FileAttachmentInteractionState {
  const FileAttachmentInteractionState({
    required this.canDownload,
    required this.tooltip,
  });

  final bool canDownload;
  final String tooltip;
}

class FileTransferProgressState {
  const FileTransferProgressState({
    required this.value,
    required this.label,
    required this.failed,
  });

  final double? value;
  final String label;
  final bool failed;
}

class FileAttachmentTrailingState {
  const FileAttachmentTrailingState({
    required this.kind,
    this.showDismiss = false,
    this.pauseResumeTooltip,
    this.pauseResumeIsResume = false,
    this.cancelTooltip,
  });

  final FileAttachmentTrailingKind kind;
  final bool showDismiss;
  final String? pauseResumeTooltip;
  final bool pauseResumeIsResume;
  final String? cancelTooltip;
}

class FileImagePreviewSize {
  const FileImagePreviewSize({required this.width, required this.height});

  final double width;
  final double height;
}

String basename(String value) {
  final normalized = value.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) return 'file';
  final slash = normalized.lastIndexOf('/');
  final name = slash >= 0 ? normalized.substring(slash + 1) : normalized;
  final query = name.indexOf('?');
  final fragment = name.indexOf('#');
  final end = [
    if (query >= 0) query,
    if (fragment >= 0) fragment,
  ].fold<int>(name.length, (min, value) => value < min ? value : min);
  final clean = name.substring(0, end).trim();
  return clean.isEmpty ? 'file' : clean;
}

List<String> normalizedFilePaths(Iterable<String> paths) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final path in paths) {
    final trimmed = path.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) continue;
    normalized.add(trimmed);
  }
  return normalized;
}

String clipboardFilesReadFailureMessage(Object error) {
  return 'Unable to read clipboard files: $error';
}

String filePickerOpenFailureMessage(Object error) {
  return '无法打开文件选择器：$error';
}

String fileReadFailureMessage(Object error) {
  return '无法读取文件：$error';
}

String fileEmptyMessage() {
  return '文件为空';
}

Uri? fileDownloadUri(String url) {
  return Uri.tryParse(url);
}

String fileDownloadUnavailableMessage() {
  return '无法下载文件';
}

String fileDownloadedNotice() {
  return '文件已下载';
}

String extensionOf(String filename) {
  final name = basename(filename).toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1);
}

String mimeTypeFromFilename(String filename) {
  return switch (extensionOf(filename)) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'json' => 'application/json',
    'zip' => 'application/zip',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'mp4' => 'video/mp4',
    _ => 'application/octet-stream',
  };
}

String fileAttachmentTitle(MessageAttachment attachment) {
  final explicitName = attachment.name?.trim();
  if (explicitName != null && explicitName.isNotEmpty) return explicitName;
  final assetName = attachment.asset?.filename?.trim();
  if (assetName != null && assetName.isNotEmpty) return assetName;
  return filenameFromAssetUrl(attachment.asset?.url) ?? 'file';
}

String? filenameFromAssetUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final uri = Uri.tryParse(url);
  final raw = uri != null && uri.pathSegments.isNotEmpty
      ? uri.pathSegments.last
      : url;
  final decoded = Uri.decodeComponent(raw);
  final name = basename(decoded);
  return name.trim().isEmpty ? null : name;
}

String fileAttachmentMeta(UploadedAsset? asset) {
  if (asset == null) return '';
  final parts = <String>[];
  final mimeType = asset.mimeType.trim();
  if (mimeType.isNotEmpty) parts.add(mimeType);
  final sizeBytes = asset.sizeBytes;
  if (sizeBytes != null) parts.add(formatFileSize(sizeBytes));
  return parts.join(' - ');
}

bool isImageMimeType(String? mimeType) {
  return (mimeType ?? '').toLowerCase().startsWith('image/');
}

bool canPauseFileTransfer(FileTransferState? transfer) {
  return transfer != null && transfer.active && !transfer.paused;
}

bool canResumeFileTransfer(FileTransferState? transfer) {
  return transfer != null && transfer.paused;
}

bool canCancelActiveFileTransfer(FileTransferState? transfer) {
  return transfer != null && transfer.active;
}

String? fileAttachmentPreviewPath(UploadedAsset? asset) {
  if (asset == null || !isImageMimeType(asset.mimeType)) return null;
  return asset.thumbnailUrl ?? asset.url;
}

FileImagePreviewSize fileAttachmentPreviewSize(
  UploadedAsset? asset, {
  double maxWidth = 320,
  double maxHeight = 240,
  double fallbackWidth = 220,
  double fallbackHeight = 150,
}) {
  final fallback = FileImagePreviewSize(
    width: fallbackWidth,
    height: fallbackHeight,
  );
  final sourceWidth = asset?.width;
  final sourceHeight = asset?.height;
  if (sourceWidth == null ||
      sourceHeight == null ||
      sourceWidth <= 0 ||
      sourceHeight <= 0 ||
      maxWidth <= 0 ||
      maxHeight <= 0) {
    return fallback;
  }

  final scale = math.min(maxWidth / sourceWidth, maxHeight / sourceHeight);
  final safeScale = scale.isFinite && scale > 0 ? math.min(1.0, scale) : 1.0;
  return FileImagePreviewSize(
    width: sourceWidth * safeScale,
    height: sourceHeight * safeScale,
  );
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final digits = value < 10 ? 1 : 0;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

String formatFileSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 B/s';
  return '${formatFileSize(bytesPerSecond.round())}/s';
}

String formatPercent(double value) {
  return '${(value.clamp(0.0, 1.0) * 100).round()}%';
}

String fileTransferLabel(FileTransferState transfer) {
  if (transfer.failed) return '传输失败';
  if (transfer.sendingMessage) return '发送中';

  final status = transfer.paused
      ? '已暂停'
      : transfer.isDownload
      ? '下载中'
      : '上传中';
  final progress = transfer.hasKnownTotal
      ? formatPercent(transfer.progress)
      : formatFileSize(transfer.sentBytes);
  final speed = transfer.paused || transfer.bytesPerSecond <= 0
      ? ''
      : ' · ${formatFileSpeed(transfer.bytesPerSecond)}';
  return '$status $progress$speed';
}

FileTransferProgressState fileTransferProgressState(
  FileTransferState transfer,
) {
  return FileTransferProgressState(
    value: transfer.sendingMessage
        ? 1
        : transfer.hasKnownTotal
        ? transfer.progress
        : null,
    label: transfer.error ?? fileTransferLabel(transfer),
    failed: transfer.failed,
  );
}

String fileDownloadKey(
  Message message,
  MessageAttachment attachment,
  int index,
) {
  final asset = attachment.asset;
  final assetKey =
      asset?.id ??
      asset?.url ??
      attachment.name ??
      fileAttachmentTitle(attachment);
  return '${message.clientMessageId}:$index:$assetKey';
}

FileAttachmentTransferSlot fileAttachmentTransferSlot({
  required Message message,
  required MessageAttachment attachment,
  required int index,
  required FileTransferState? uploadTransfer,
  required Map<String, FileTransferState> downloads,
}) {
  final downloadKey = fileDownloadKey(message, attachment, index);
  final activeUploadTransfer = index == 0 ? uploadTransfer : null;
  final activeDownloadTransfer = downloads[downloadKey];
  final transfer = activeUploadTransfer ?? activeDownloadTransfer;
  return FileAttachmentTransferSlot(
    downloadKey: downloadKey,
    transfer: transfer,
    usesUploadTransfer: activeUploadTransfer != null,
  );
}

FileAttachmentInteractionState fileAttachmentInteractionState({
  required String title,
  required String? url,
  required FileTransferState? transfer,
}) {
  final canDownload = url != null && transfer == null;
  return FileAttachmentInteractionState(
    canDownload: canDownload,
    tooltip: canDownload ? '下载文件' : title,
  );
}

FileAttachmentTrailingState fileAttachmentTrailingState({
  required FileTransferState? transfer,
  required bool canDownload,
}) {
  if (transfer != null) {
    if (transfer.sendingMessage) {
      return const FileAttachmentTrailingState(
        kind: FileAttachmentTrailingKind.sending,
      );
    }
    if (transfer.failed) {
      return FileAttachmentTrailingState(
        kind: FileAttachmentTrailingKind.failed,
        showDismiss: transfer.isDownload,
      );
    }

    final action = transfer.isDownload ? '下载' : '上传';
    return FileAttachmentTrailingState(
      kind: FileAttachmentTrailingKind.activeTransfer,
      pauseResumeTooltip: transfer.paused ? '继续$action' : '暂停$action',
      pauseResumeIsResume: transfer.paused,
      cancelTooltip: '取消$action',
    );
  }

  return FileAttachmentTrailingState(
    kind: canDownload
        ? FileAttachmentTrailingKind.download
        : FileAttachmentTrailingKind.placeholder,
  );
}
