abstract interface class LivePresenceSpeechPlayer {
  Future<void> speak(
    LivePresenceAnnouncement announcement, {
    required double volume,
  });

  Future<void> dispose();
}

enum LivePresenceAnnouncementAction { joined, left, removed }

bool shouldSpeakLivePresenceAnnouncement({
  required bool enabled,
  required String? participantIdentity,
  required String currentUserIdentity,
}) {
  final identity = participantIdentity?.trim();
  return enabled &&
      identity != null &&
      identity.isNotEmpty &&
      identity != currentUserIdentity;
}

class LivePresenceAnnouncement {
  const LivePresenceAnnouncement({
    required this.roleLabel,
    required this.roomDisplayName,
    required this.action,
  });

  final String roleLabel;
  final String roomDisplayName;
  final LivePresenceAnnouncementAction action;

  String get actionLabel => switch (action) {
    LivePresenceAnnouncementAction.joined => '进入了语音频道',
    LivePresenceAnnouncementAction.left => '离开了语音频道',
    LivePresenceAnnouncementAction.removed => '被踢出了语音频道',
  };

  /// Separate segments let the platform TTS adapter insert real pauses instead
  /// of relying on punctuation, whose timing varies between installed voices.
  List<String> get segments => [roleLabel, roomDisplayName, actionLabel];
}
