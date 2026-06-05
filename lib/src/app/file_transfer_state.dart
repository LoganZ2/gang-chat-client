import 'package:http/http.dart' as http;

import '../protocol/api_client.dart';

enum FileTransferDirection { upload, download }

class FileTransferState {
  FileTransferState.upload({required this.controller, required this.totalBytes})
    : direction = FileTransferDirection.upload,
      destinationPath = null;

  FileTransferState.download({
    required this.controller,
    required this.totalBytes,
    required this.destinationPath,
  }) : direction = FileTransferDirection.download;

  final FileTransferDirection direction;
  final UploadTransferController controller;
  final String? destinationPath;
  int sentBytes = 0;
  int totalBytes;
  double bytesPerSecond = 0;
  http.Client? downloadClient;
  bool wroteDestination = false;
  bool sendingMessage = false;
  bool failed = false;
  String? error;
  DateTime? _speedSampleAt;
  int _speedSampleBytes = 0;

  bool get isDownload => direction == FileTransferDirection.download;
  bool get paused => controller.isPaused;
  bool get cancelled => controller.isCancelled;
  bool get active => !failed && !cancelled && !sendingMessage;
  bool get hasKnownTotal => totalBytes > 0;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (sentBytes / totalBytes).clamp(0.0, 1.0).toDouble();
  }

  void updateProgress({required int sentBytes, required int totalBytes}) {
    final now = DateTime.now();
    if (_speedSampleAt == null) {
      _speedSampleAt = now;
      _speedSampleBytes = this.sentBytes;
    } else {
      final elapsed = now.difference(_speedSampleAt!).inMilliseconds;
      if (elapsed >= 400 || sentBytes >= totalBytes && totalBytes > 0) {
        final deltaBytes = sentBytes - _speedSampleBytes;
        bytesPerSecond = elapsed > 0 ? deltaBytes * 1000 / elapsed : 0;
        _speedSampleAt = now;
        _speedSampleBytes = sentBytes;
      }
    }

    this.sentBytes = sentBytes;
    this.totalBytes = totalBytes;
  }

  void markSendingMessage() {
    sendingMessage = true;
    updateProgress(sentBytes: totalBytes, totalBytes: totalBytes);
  }

  void markFailed(Object failure, {bool stopTransferSpeed = false}) {
    failed = true;
    sendingMessage = false;
    error = failure.toString();
    if (stopTransferSpeed) stopSpeed();
  }

  bool pauseTransfer() {
    if (!active || paused) return false;
    controller.pause();
    stopSpeed();
    return true;
  }

  bool resumeTransfer() {
    if (!paused) return false;
    controller.resume();
    return true;
  }

  bool cancelTransfer() {
    if (!active) return false;
    controller.cancel();
    downloadClient?.close();
    return true;
  }

  void stopSpeed() {
    bytesPerSecond = 0;
    _speedSampleAt = null;
    _speedSampleBytes = sentBytes;
  }
}
