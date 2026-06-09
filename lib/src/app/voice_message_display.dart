/// Pure logic for the voice-message recorder shown in the chat composer.
///
/// The widget layer drives an [AudioRecorder] and a ticking timer; this module
/// owns the state machine and formatting so the transitions can be unit-tested
/// without a microphone. The flow is click-to-start (not press-and-hold):
///
///   idle ──start──▶ recording ──stop──▶ review ──send──▶ sending ──▶ idle
///     ▲                  │                  │                          │
///     └────── cancel ────┴────── cancel ────┴────────── failed ────────┘
///
/// "review" is the state after recording stops where the user decides whether
/// to send or discard the clip.
enum VoiceRecorderPhase { idle, recording, review, sending }

class VoiceRecorderState {
  const VoiceRecorderState({
    this.phase = VoiceRecorderPhase.idle,
    this.elapsed = Duration.zero,
    this.recordingPath,
    this.error,
  });

  final VoiceRecorderPhase phase;

  /// How long the current (or just-finished) clip runs.
  final Duration elapsed;

  /// Filesystem path of the captured clip, set once recording stops.
  final String? recordingPath;

  final String? error;

  bool get isRecording => phase == VoiceRecorderPhase.recording;
  bool get isReviewing => phase == VoiceRecorderPhase.review;
  bool get isSending => phase == VoiceRecorderPhase.sending;
  bool get isIdle => phase == VoiceRecorderPhase.idle;

  /// A clip is only worth sending once it has a path and some duration.
  bool get canSend =>
      phase == VoiceRecorderPhase.review &&
      recordingPath != null &&
      elapsed > Duration.zero;

  VoiceRecorderState copyWith({
    VoiceRecorderPhase? phase,
    Duration? elapsed,
    Object? recordingPath = _unchanged,
    Object? error = _unchanged,
  }) {
    return VoiceRecorderState(
      phase: phase ?? this.phase,
      elapsed: elapsed ?? this.elapsed,
      recordingPath: identical(recordingPath, _unchanged)
          ? this.recordingPath
          : recordingPath as String?,
      error: identical(error, _unchanged) ? this.error : error as String?,
    );
  }
}

const Object _unchanged = Object();

/// Hard cap so an abandoned recording cannot grow without bound. The widget
/// layer is expected to call [voiceRecordingStopped] when this is reached.
const Duration kVoiceRecordingMaxDuration = Duration(minutes: 5);

/// Below this a clip is treated as an accidental tap and discarded on stop.
const Duration kVoiceRecordingMinDuration = Duration(milliseconds: 800);

VoiceRecorderState voiceRecorderReset() => const VoiceRecorderState();

VoiceRecorderState voiceRecordingStarted() {
  return const VoiceRecorderState(phase: VoiceRecorderPhase.recording);
}

/// Advances the displayed duration while recording. Ignored in other phases so
/// a late timer tick cannot resurrect a cancelled clip.
VoiceRecorderState voiceRecordingTicked(
  VoiceRecorderState state,
  Duration elapsed,
) {
  if (state.phase != VoiceRecorderPhase.recording) return state;
  return state.copyWith(elapsed: elapsed);
}

bool voiceRecordingReachedLimit(Duration elapsed) {
  return elapsed >= kVoiceRecordingMaxDuration;
}

/// Recording finished. A clip shorter than [kVoiceRecordingMinDuration] is
/// discarded back to idle; otherwise we move to review with the captured path.
VoiceRecorderState voiceRecordingStopped({
  required VoiceRecorderState state,
  required String? path,
  required Duration elapsed,
}) {
  if (path == null || elapsed < kVoiceRecordingMinDuration) {
    return voiceRecorderReset();
  }
  return VoiceRecorderState(
    phase: VoiceRecorderPhase.review,
    elapsed: elapsed,
    recordingPath: path,
  );
}

VoiceRecorderState voiceRecordingCancelled() => voiceRecorderReset();

VoiceRecorderState voiceSendStarted(VoiceRecorderState state) {
  return state.copyWith(phase: VoiceRecorderPhase.sending, error: null);
}

VoiceRecorderState voiceSendSucceeded() => voiceRecorderReset();

VoiceRecorderState voiceSendFailed({
  required VoiceRecorderState state,
  required Object failure,
}) {
  // Drop back to review so the user can retry sending the same clip.
  return state.copyWith(
    phase: VoiceRecorderPhase.review,
    error: failure.toString(),
  );
}

/// `m:ss` for the composer timer. Minutes are not zero-padded so a short clip
/// reads "0:04" rather than "00:04".
String formatVoiceDuration(Duration duration) {
  final clamped = duration.isNegative ? Duration.zero : duration;
  final minutes = clamped.inMinutes;
  final seconds = clamped.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Filename for an outgoing voice clip. Voice messages ride the regular file
/// attachment path, so they need a stable name and an audio mime the server and
/// renderer can recognise.
const String kVoiceMessageMimeType = 'audio/mp4';
const String kVoiceMessageExtension = 'm4a';

String voiceMessageFilename(DateTime timestamp) {
  final stamp = timestamp.toUtc().millisecondsSinceEpoch;
  return 'voice_$stamp.$kVoiceMessageExtension';
}
