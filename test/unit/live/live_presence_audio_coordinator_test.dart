import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/live_presence_announcement.dart';
import 'package:client/src/live/live_presence_audio_coordinator.dart';
import 'package:client/src/live/live_presence_sound_service.dart';

void main() {
  test('presence audio keeps cue and speech items strictly ordered', () async {
    final events = <String>[];
    final sound = _SoundPlayer(events);
    final speech = _SpeechPlayer(events);
    final coordinator = LivePresenceAudioCoordinator(
      soundPlayer: sound,
      speechPlayer: speech,
      cueDuration: Duration.zero,
      itemGap: Duration.zero,
    );
    const joined = LivePresenceAnnouncement(
      roleLabel: '管理员',
      roomDisplayName: '小林',
      action: LivePresenceAnnouncementAction.joined,
    );
    const removed = LivePresenceAnnouncement(
      roleLabel: '成员',
      roomDisplayName: '小周',
      action: LivePresenceAnnouncementAction.removed,
    );

    await Future.wait([
      coordinator.play(
        LivePresenceSound.joined,
        volume: 0.7,
        announcement: joined,
      ),
      coordinator.play(
        LivePresenceSound.left,
        volume: 0.7,
        announcement: removed,
      ),
    ]);

    expect(events, [
      'sound:joined',
      'speech:管理员|小林|进入了语音频道',
      'sound:left',
      'speech:成员|小周|被踢出了语音频道',
    ]);
  });

  test('presence audio without announcement only plays the cue', () async {
    final events = <String>[];
    final coordinator = LivePresenceAudioCoordinator(
      soundPlayer: _SoundPlayer(events),
      speechPlayer: _SpeechPlayer(events),
      cueDuration: Duration.zero,
      itemGap: Duration.zero,
    );

    await coordinator.play(LivePresenceSound.joined, volume: 0.7);

    expect(events, ['sound:joined']);
  });
}

class _SoundPlayer implements LivePresenceSoundPlayer {
  _SoundPlayer(this.events);

  final List<String> events;

  @override
  Future<void> play(LivePresenceSound sound, {required double volume}) async {
    events.add('sound:${sound.name}');
  }

  @override
  Future<void> dispose() async {}
}

class _SpeechPlayer implements LivePresenceSpeechPlayer {
  _SpeechPlayer(this.events);

  final List<String> events;

  @override
  Future<void> speak(
    LivePresenceAnnouncement announcement, {
    required double volume,
  }) async {
    events.add('speech:${announcement.segments.join('|')}');
  }

  @override
  Future<void> dispose() async {}
}
