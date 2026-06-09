import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/voice_message_display.dart';

void main() {
  test('start moves from idle to recording with a zeroed timer', () {
    final state = voiceRecordingStarted();
    expect(state.phase, VoiceRecorderPhase.recording);
    expect(state.isRecording, isTrue);
    expect(state.elapsed, Duration.zero);
    expect(state.recordingPath, isNull);
  });

  test('ticks advance the timer only while recording', () {
    final recording = voiceRecordingStarted();
    final ticked = voiceRecordingTicked(
      recording,
      const Duration(seconds: 3),
    );
    expect(ticked.elapsed, const Duration(seconds: 3));

    // A stray tick after reset must not resurrect the timer.
    final idle = voiceRecorderReset();
    final ignored = voiceRecordingTicked(idle, const Duration(seconds: 9));
    expect(ignored.elapsed, Duration.zero);
    expect(ignored.phase, VoiceRecorderPhase.idle);
  });

  test('stop moves a long-enough clip into review', () {
    final state = voiceRecordingStopped(
      state: voiceRecordingStarted(),
      path: '/tmp/voice_1.m4a',
      elapsed: const Duration(seconds: 4),
    );
    expect(state.phase, VoiceRecorderPhase.review);
    expect(state.isReviewing, isTrue);
    expect(state.recordingPath, '/tmp/voice_1.m4a');
    expect(state.elapsed, const Duration(seconds: 4));
    expect(state.canSend, isTrue);
  });

  test('stop discards a too-short or pathless clip back to idle', () {
    final tooShort = voiceRecordingStopped(
      state: voiceRecordingStarted(),
      path: '/tmp/voice_1.m4a',
      elapsed: const Duration(milliseconds: 200),
    );
    expect(tooShort.phase, VoiceRecorderPhase.idle);
    expect(tooShort.recordingPath, isNull);

    final noPath = voiceRecordingStopped(
      state: voiceRecordingStarted(),
      path: null,
      elapsed: const Duration(seconds: 5),
    );
    expect(noPath.phase, VoiceRecorderPhase.idle);
  });

  test('cancel always returns to a clean idle state', () {
    expect(voiceRecordingCancelled().phase, VoiceRecorderPhase.idle);
    expect(voiceRecordingCancelled().recordingPath, isNull);
    expect(voiceRecordingCancelled().error, isNull);
  });

  test('send transitions review -> sending -> idle on success', () {
    final review = voiceRecordingStopped(
      state: voiceRecordingStarted(),
      path: '/tmp/voice_1.m4a',
      elapsed: const Duration(seconds: 4),
    );
    final sending = voiceSendStarted(review);
    expect(sending.phase, VoiceRecorderPhase.sending);
    expect(sending.isSending, isTrue);
    expect(sending.error, isNull);

    expect(voiceSendSucceeded().phase, VoiceRecorderPhase.idle);
  });

  test('send failure returns to review and keeps the clip for retry', () {
    final review = voiceRecordingStopped(
      state: voiceRecordingStarted(),
      path: '/tmp/voice_1.m4a',
      elapsed: const Duration(seconds: 4),
    );
    final failed = voiceSendFailed(
      state: voiceSendStarted(review),
      failure: Exception('network down'),
    );
    expect(failed.phase, VoiceRecorderPhase.review);
    expect(failed.recordingPath, '/tmp/voice_1.m4a');
    expect(failed.error, contains('network down'));
    expect(failed.canSend, isTrue);
  });

  test('reachedLimit fires at the max duration', () {
    expect(
      voiceRecordingReachedLimit(const Duration(minutes: 4, seconds: 59)),
      isFalse,
    );
    expect(voiceRecordingReachedLimit(kVoiceRecordingMaxDuration), isTrue);
  });

  test('duration formats as m:ss without zero-padded minutes', () {
    expect(formatVoiceDuration(Duration.zero), '0:00');
    expect(formatVoiceDuration(const Duration(seconds: 4)), '0:04');
    expect(formatVoiceDuration(const Duration(seconds: 65)), '1:05');
    expect(formatVoiceDuration(const Duration(minutes: 12, seconds: 9)), '12:09');
    expect(formatVoiceDuration(const Duration(seconds: -3)), '0:00');
  });

  test('voice filename carries an audio extension and timestamp', () {
    final name = voiceMessageFilename(
      DateTime.utc(2026, 6, 1, 12, 0, 0),
    );
    expect(name, startsWith('voice_'));
    expect(name, endsWith('.m4a'));
    expect(kVoiceMessageMimeType, 'audio/mp4');
  });
}
