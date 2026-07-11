import '../app/live_presence_announcement.dart';
import 'live_presence_sound_service.dart';

/// Serializes presence audio so bursts of joins/leaves remain intelligible.
///
/// Each item always starts with the existing cue. When an announcement is
/// supplied, speech starts only after the short cue has finished.
class LivePresenceAudioCoordinator {
  LivePresenceAudioCoordinator({
    required LivePresenceSoundPlayer soundPlayer,
    required LivePresenceSpeechPlayer speechPlayer,
    this.cueDuration = const Duration(milliseconds: 330),
    this.itemGap = const Duration(milliseconds: 90),
  }) : _soundPlayer = soundPlayer,
       _speechPlayer = speechPlayer;

  final LivePresenceSoundPlayer _soundPlayer;
  final LivePresenceSpeechPlayer _speechPlayer;
  final Duration cueDuration;
  final Duration itemGap;

  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  Future<void> play(
    LivePresenceSound sound, {
    required double volume,
    LivePresenceAnnouncement? announcement,
  }) {
    if (_disposed || volume <= 0) return Future<void>.value();
    final normalizedVolume = volume.clamp(0.0, 1.0).toDouble();
    final completion = _tail
        .then((_) async {
          if (_disposed) return;
          await _soundPlayer.play(sound, volume: normalizedVolume);
          await Future<void>.delayed(cueDuration);
          if (_disposed) return;
          if (announcement != null) {
            await _speechPlayer.speak(announcement, volume: normalizedVolume);
          }
          if (itemGap > Duration.zero) {
            await Future<void>.delayed(itemGap);
          }
        })
        .catchError((_) {});
    _tail = completion;
    return completion;
  }

  void dispose() {
    _disposed = true;
  }
}
