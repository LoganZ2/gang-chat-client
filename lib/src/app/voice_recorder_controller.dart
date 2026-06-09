import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'voice_message_display.dart';

class VoiceRecorderPermissionException implements Exception {
  const VoiceRecorderPermissionException();

  @override
  String toString() => '麦克风权限被拒绝';
}

/// Thin wrapper around the `record` plugin that captures a single voice clip to
/// a temp file. The recorder phase/timer state machine lives in
/// [voice_message_display]; this class only owns the device side: permission,
/// start/stop/cancel, and reading the captured bytes for upload.
class VoiceRecorderController {
  VoiceRecorderController({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _currentPath;

  /// Records mono AAC-LC at a speech-friendly bitrate — small files that still
  /// sound clean for voice, wrapped in an m4a/[kVoiceMessageMimeType] container.
  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 64000,
    sampleRate: 44100,
    numChannels: 1,
  );

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Begins recording to a fresh temp file. Throws
  /// [VoiceRecorderPermissionException] if the mic is denied.
  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw const VoiceRecorderPermissionException();
    }
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final path = '${dir.path}/voice_$stamp.$kVoiceMessageExtension';
    _currentPath = path;
    await _recorder.start(_config, path: path);
  }

  /// Stops recording and returns the captured file path, or null if nothing was
  /// written.
  Future<String?> stop() async {
    final path = await _recorder.stop();
    _currentPath = null;
    return path;
  }

  /// Stops and discards the recording, deleting the temp file.
  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } finally {
      await _deleteTemp(_currentPath);
      _currentPath = null;
    }
  }

  /// Live microphone amplitude for an optional level meter while recording.
  Stream<Amplitude> amplitudeStream({
    Duration interval = const Duration(milliseconds: 200),
  }) {
    return _recorder.onAmplitudeChanged(interval);
  }

  /// Reads a clip's bytes for upload. Does not delete the file, so a failed
  /// send can retry from the same path; call [discardClip] once the clip is no
  /// longer needed.
  Future<Uint8List> readClip(String path) async {
    final file = File(path);
    return file.readAsBytes();
  }

  /// Deletes a finished clip's temp file. Safe to call with a stale path.
  Future<void> discardClip(String? path) => _deleteTemp(path);

  Future<void> _deleteTemp(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover temp clip in the OS temp dir is harmless; never let cleanup
      // failure surface to the user.
    }
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
