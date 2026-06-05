import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/file_display.dart';
import 'package:client/src/app/file_transfer_state.dart';
import 'package:client/src/protocol/api_client.dart';
import 'package:client/src/protocol/models.dart';

void main() {
  test('basename removes folders query and fragment', () {
    expect(basename(r'C:\Users\kai\report.pdf?download=1#top'), 'report.pdf');
    expect(basename('/tmp/'), 'file');
    expect(basename('  image.png  '), 'image.png');
  });

  test('normalizedFilePaths trims empty and duplicate file paths', () {
    expect(
      normalizedFilePaths([
        ' /tmp/a.png ',
        '',
        ' /tmp/b.png',
        '/tmp/a.png',
        '   ',
      ]),
      ['/tmp/a.png', '/tmp/b.png'],
    );
  });

  test('file interaction notices and download url parsing stay outside UI', () {
    expect(
      clipboardFilesReadFailureMessage('denied'),
      'Unable to read clipboard files: denied',
    );
    expect(
      filePickerOpenFailureMessage('blocked'),
      'Unable to open file picker: blocked',
    );
    expect(fileReadFailureMessage('missing'), 'Unable to read file: missing');
    expect(fileEmptyMessage(), 'File is empty');
    expect(
      fileDownloadUri('https://example.test/file.txt')?.host,
      'example.test',
    );
    expect(fileDownloadUri('://bad'), isNull);
    expect(fileDownloadUnavailableMessage(), 'Cannot download file');
    expect(fileDownloadedNotice(), 'File downloaded');
  });

  test('extension and mime type are inferred from normalized basename', () {
    expect(extensionOf('/tmp/photo.JPEG?token=1'), 'jpeg');
    expect(mimeTypeFromFilename('/tmp/photo.JPEG?token=1'), 'image/jpeg');
    expect(mimeTypeFromFilename('archive.unknown'), 'application/octet-stream');
  });

  test('fileAttachmentTitle falls back from explicit name to asset fields', () {
    expect(
      fileAttachmentTitle(
        MessageAttachment(
          type: 'file',
          name: ' explicit.txt ',
          asset: _asset(filename: 'asset.txt', url: '/ignored/url.txt'),
        ),
      ),
      'explicit.txt',
    );
    expect(
      fileAttachmentTitle(
        MessageAttachment(
          type: 'file',
          asset: _asset(filename: ' asset-name.txt ', url: '/ignored/url.txt'),
        ),
      ),
      'asset-name.txt',
    );
    expect(
      fileAttachmentTitle(
        MessageAttachment(
          type: 'file',
          asset: _asset(
            filename: null,
            url: '/uploads/final%20name.txt?download=1',
          ),
        ),
      ),
      'final name.txt',
    );
  });

  test('fileAttachmentMeta combines mime type and formatted size', () {
    expect(
      fileAttachmentMeta(_asset(mimeType: 'application/pdf', sizeBytes: 1536)),
      'application/pdf - 1.5 KB',
    );
    expect(
      fileAttachmentMeta(_asset(mimeType: '', sizeBytes: 1048576)),
      '1.0 MB',
    );
    expect(fileAttachmentMeta(null), '');
  });

  test('fileAttachmentPreviewPath uses image thumbnail or asset URL only', () {
    expect(
      fileAttachmentPreviewPath(
        _asset(
          url: '/uploads/image.png',
          mimeType: 'image/png',
          thumbnailUrl: '/uploads/thumb.png',
        ),
      ),
      '/uploads/thumb.png',
    );
    expect(
      fileAttachmentPreviewPath(
        _asset(url: '/uploads/image.png', mimeType: 'image/png'),
      ),
      '/uploads/image.png',
    );
    expect(
      fileAttachmentPreviewPath(
        _asset(url: '/uploads/file.pdf', mimeType: 'application/pdf'),
      ),
      isNull,
    );
  });

  test('isImageMimeType normalizes mime casing', () {
    expect(isImageMimeType('IMAGE/PNG'), isTrue);
    expect(isImageMimeType('text/plain'), isFalse);
    expect(isImageMimeType(null), isFalse);
  });

  test('fileTransferLabel reflects state progress and speed', () {
    final transfer =
        FileTransferState.upload(
            controller: UploadTransferController(),
            totalBytes: 4096,
          )
          ..sentBytes = 2048
          ..bytesPerSecond = 2048;

    expect(fileTransferLabel(transfer), 'Uploading 50% - 2.0 KB/s');

    transfer.pauseTransfer();
    expect(fileTransferLabel(transfer), 'Paused 50%');

    transfer.resumeTransfer();
    transfer.markFailed('network failed');
    expect(fileTransferLabel(transfer), 'Failed');
  });

  test('fileTransferProgressState exposes progress label and error state', () {
    final transfer = FileTransferState.upload(
      controller: UploadTransferController(),
      totalBytes: 100,
    )..sentBytes = 25;

    var state = fileTransferProgressState(transfer);
    expect(state.value, 0.25);
    expect(state.label, 'Uploading 25%');
    expect(state.failed, isFalse);

    transfer.markSendingMessage();
    state = fileTransferProgressState(transfer);
    expect(state.value, 1);
    expect(state.label, 'Sending');

    final failedTransfer = FileTransferState.upload(
      controller: UploadTransferController(),
      totalBytes: 100,
    )..sentBytes = 25;
    failedTransfer.markFailed('network failed');
    state = fileTransferProgressState(failedTransfer);
    expect(state.value, 0.25);
    expect(state.label, 'network failed');
    expect(state.failed, isTrue);
  });

  test('fileDownloadKey is stable from client message and asset identity', () {
    final attachment = MessageAttachment(
      type: 'file',
      name: 'fallback.txt',
      asset: _asset(id: 'asset_1'),
    );

    expect(fileDownloadKey(_message(), attachment, 2), 'client_1:2:asset_1');
  });

  test('fileAttachmentTransferSlot binds upload only to first attachment', () {
    final message = _message();
    final first = _attachment(id: 'first');
    final second = _attachment(id: 'second');
    final upload = FileTransferState.upload(
      controller: UploadTransferController(),
      totalBytes: 100,
    );
    final download = FileTransferState.download(
      controller: UploadTransferController(),
      totalBytes: 200,
      destinationPath: '/tmp/second.txt',
    );
    final secondKey = fileDownloadKey(message, second, 1);

    final firstSlot = fileAttachmentTransferSlot(
      message: message,
      attachment: first,
      index: 0,
      uploadTransfer: upload,
      downloads: {secondKey: download},
    );
    expect(firstSlot.transfer, same(upload));
    expect(firstSlot.usesUploadTransfer, isTrue);

    final secondSlot = fileAttachmentTransferSlot(
      message: message,
      attachment: second,
      index: 1,
      uploadTransfer: upload,
      downloads: {secondKey: download},
    );
    expect(secondSlot.transfer, same(download));
    expect(secondSlot.usesUploadTransfer, isFalse);
    expect(secondSlot.downloadKey, secondKey);
  });

  test(
    'fileAttachmentInteractionState allows download only without transfer',
    () {
      expect(
        fileAttachmentInteractionState(
          title: 'report.pdf',
          url: '/uploads/report.pdf',
          transfer: null,
        ).canDownload,
        isTrue,
      );
      expect(
        fileAttachmentInteractionState(
          title: 'report.pdf',
          url: null,
          transfer: null,
        ).tooltip,
        'report.pdf',
      );
      expect(
        fileAttachmentInteractionState(
          title: 'report.pdf',
          url: '/uploads/report.pdf',
          transfer: FileTransferState.upload(
            controller: UploadTransferController(),
            totalBytes: 100,
          ),
        ).canDownload,
        isFalse,
      );
    },
  );

  test('fileAttachmentTrailingState describes transfer actions', () {
    final upload = FileTransferState.upload(
      controller: UploadTransferController(),
      totalBytes: 100,
    );
    var state = fileAttachmentTrailingState(
      transfer: upload,
      canDownload: false,
    );
    expect(state.kind, FileAttachmentTrailingKind.activeTransfer);
    expect(state.pauseResumeTooltip, 'Pause upload');
    expect(state.pauseResumeIsResume, isFalse);
    expect(state.cancelTooltip, 'Cancel upload');

    upload.pauseTransfer();
    state = fileAttachmentTrailingState(transfer: upload, canDownload: false);
    expect(state.pauseResumeTooltip, 'Resume upload');
    expect(state.pauseResumeIsResume, isTrue);

    upload.resumeTransfer();
    upload.markSendingMessage();
    expect(
      fileAttachmentTrailingState(transfer: upload, canDownload: false).kind,
      FileAttachmentTrailingKind.sending,
    );
  });

  test('fileAttachmentTrailingState separates failed and idle states', () {
    final upload = FileTransferState.upload(
      controller: UploadTransferController(),
      totalBytes: 100,
    )..markFailed('upload failed');
    final download = FileTransferState.download(
      controller: UploadTransferController(),
      totalBytes: 100,
      destinationPath: '/tmp/file.txt',
    )..markFailed('download failed');

    var state = fileAttachmentTrailingState(
      transfer: upload,
      canDownload: false,
    );
    expect(state.kind, FileAttachmentTrailingKind.failed);
    expect(state.showDismiss, isFalse);

    state = fileAttachmentTrailingState(transfer: download, canDownload: false);
    expect(state.kind, FileAttachmentTrailingKind.failed);
    expect(state.showDismiss, isTrue);

    expect(
      fileAttachmentTrailingState(transfer: null, canDownload: false).kind,
      FileAttachmentTrailingKind.placeholder,
    );
    expect(
      fileAttachmentTrailingState(transfer: null, canDownload: true).kind,
      FileAttachmentTrailingKind.download,
    );
  });

  test('file transfer action guards follow active paused and failed state', () {
    final transfer = FileTransferState.upload(
      controller: UploadTransferController(),
      totalBytes: 100,
    );

    expect(canPauseFileTransfer(transfer), isTrue);
    expect(canResumeFileTransfer(transfer), isFalse);
    expect(canCancelActiveFileTransfer(transfer), isTrue);

    transfer.pauseTransfer();
    expect(canPauseFileTransfer(transfer), isFalse);
    expect(canResumeFileTransfer(transfer), isTrue);
    expect(canCancelActiveFileTransfer(transfer), isTrue);

    transfer.resumeTransfer();
    transfer.markFailed('network failed');
    expect(canPauseFileTransfer(transfer), isFalse);
    expect(canResumeFileTransfer(transfer), isFalse);
    expect(canCancelActiveFileTransfer(transfer), isFalse);

    final sending = FileTransferState.upload(
      controller: UploadTransferController(),
      totalBytes: 100,
    )..markSendingMessage();
    expect(canCancelActiveFileTransfer(sending), isFalse);

    expect(canPauseFileTransfer(null), isFalse);
    expect(canResumeFileTransfer(null), isFalse);
    expect(canCancelActiveFileTransfer(null), isFalse);
  });
}

UploadedAsset _asset({
  String id = 'asset',
  String url = '/uploads/file.txt',
  String? thumbnailUrl,
  String? filename = 'file.txt',
  String mimeType = 'text/plain',
  int? sizeBytes,
}) {
  return UploadedAsset(
    id: id,
    url: url,
    thumbnailUrl: thumbnailUrl,
    mimeType: mimeType,
    filename: filename,
    sizeBytes: sizeBytes,
  );
}

Message _message() {
  return Message(
    id: 'message_1',
    roomId: 'room_1',
    sender: const UserSummary(
      id: 'user_1',
      username: 'logan',
      displayName: 'Logan',
      avatarUrl: null,
      defaultAvatarKey: 'blue-3',
    ),
    clientMessageId: 'client_1',
    body: '',
    createdAt: DateTime.utc(2026, 6, 4),
  );
}

MessageAttachment _attachment({required String id}) {
  return MessageAttachment(
    type: 'file',
    name: '$id.txt',
    asset: _asset(id: id),
  );
}
