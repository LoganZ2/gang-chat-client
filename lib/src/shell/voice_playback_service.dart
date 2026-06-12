import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class VoicePlaybackSnapshot {
  const VoicePlaybackSnapshot({
    this.activeMessageId,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  final String? activeMessageId;
  final bool playing;
  final Duration position;
  final Duration duration;

  bool isPlaying(String messageId) {
    return playing && activeMessageId == messageId;
  }
}

class VoicePlaybackService {
  VoicePlaybackService({AudioPlayer? player})
    : _player = player ?? AudioPlayer() {
    _stateSubscription = _player.onPlayerStateChanged.listen(_handleState);
    _positionSubscription = _player.onPositionChanged.listen(_handlePosition);
    _durationSubscription = _player.onDurationChanged.listen(_handleDuration);
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      state.value = const VoicePlaybackSnapshot();
    });
  }

  final AudioPlayer _player;
  final ValueNotifier<VoicePlaybackSnapshot> state = ValueNotifier(
    const VoicePlaybackSnapshot(),
  );
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<void>? _completeSubscription;

  Future<void> toggle({
    required String messageId,
    required String resolvedUrl,
  }) async {
    if (state.value.isPlaying(messageId)) {
      await stop();
      return;
    }
    await play(messageId: messageId, resolvedUrl: resolvedUrl);
  }

  Future<void> play({
    required String messageId,
    required String resolvedUrl,
  }) async {
    await _player.stop();
    state.value = VoicePlaybackSnapshot(
      activeMessageId: messageId,
      playing: true,
      position: Duration.zero,
      duration: Duration.zero,
    );
    try {
      await _player.play(UrlSource(resolvedUrl));
    } catch (_) {
      if (state.value.activeMessageId == messageId) {
        state.value = const VoicePlaybackSnapshot();
      }
      rethrow;
    }
  }

  Future<void> stop() async {
    await _player.stop();
    state.value = const VoicePlaybackSnapshot();
  }

  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _completeSubscription?.cancel();
    state.dispose();
    await _player.dispose();
  }

  void _handlePosition(Duration position) {
    final current = state.value;
    if (current.activeMessageId == null) return;
    state.value = VoicePlaybackSnapshot(
      activeMessageId: current.activeMessageId,
      playing: current.playing,
      position: position,
      duration: current.duration,
    );
  }

  void _handleDuration(Duration duration) {
    final current = state.value;
    if (current.activeMessageId == null) return;
    state.value = VoicePlaybackSnapshot(
      activeMessageId: current.activeMessageId,
      playing: current.playing,
      position: current.position,
      duration: duration,
    );
  }

  void _handleState(PlayerState playerState) {
    if (playerState == PlayerState.completed ||
        playerState == PlayerState.stopped ||
        playerState == PlayerState.disposed) {
      state.value = const VoicePlaybackSnapshot();
    }
  }
}
