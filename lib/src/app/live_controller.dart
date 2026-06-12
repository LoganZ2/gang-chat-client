import '../protocol/api_client.dart';
import '../protocol/models.dart';
import 'room_live_state.dart' as room_live_state;

class LiveDeparturePatch {
  const LiveDeparturePatch({required this.live, required this.rooms});

  final LiveState? live;
  final List<RoomCard> rooms;
}

class LiveLocalDeparturePatch {
  const LiveLocalDeparturePatch({
    required this.live,
    required this.rooms,
    required this.joinedLiveRoomId,
    required this.joiningLive,
    required this.cameraOn,
    required this.screenSharing,
    required this.voiceBlocked,
  });

  final LiveState? live;
  final List<RoomCard> rooms;
  final String? joinedLiveRoomId;
  final bool joiningLive;
  final bool cameraOn;
  final bool screenSharing;
  final bool voiceBlocked;
}

class LivePublishPermissionPatch {
  const LivePublishPermissionPatch({
    required this.micMuted,
    required this.voiceBlocked,
  });

  final bool micMuted;
  final bool voiceBlocked;
}

class LiveOutputMutePatch {
  const LiveOutputMutePatch({required this.headphonesMuted});

  final bool headphonesMuted;
}

class LiveJoinResultPatch {
  const LiveJoinResultPatch({
    required this.micMuted,
    required this.cameraOn,
    required this.screenSharing,
    required this.voiceBlocked,
    required this.live,
    required this.rooms,
  });

  final bool micMuted;
  final bool cameraOn;
  final bool screenSharing;
  final bool voiceBlocked;
  final LiveState live;
  final List<RoomCard> rooms;
}

class LiveStateUpdatePatch {
  const LiveStateUpdatePatch({
    required this.micMuted,
    required this.cameraOn,
    required this.screenSharing,
    required this.voiceBlocked,
    required this.live,
  });

  final bool micMuted;
  final bool cameraOn;
  final bool screenSharing;
  final bool voiceBlocked;
  final LiveState? live;
}

class LiveJoinStatePatch {
  const LiveJoinStatePatch({
    required this.joinedLiveRoomId,
    required this.joiningLive,
    required this.livePanelOpen,
    required this.error,
  });

  final String? joinedLiveRoomId;
  final bool joiningLive;
  final bool livePanelOpen;
  final String? error;
}

class LiveJoinPreviousRoomDisconnectedPatch {
  const LiveJoinPreviousRoomDisconnectedPatch({
    required this.live,
    required this.rooms,
    required this.joinedLiveRoomId,
    required this.joiningLive,
    required this.livePanelOpen,
    required this.error,
  });

  final LiveState? live;
  final List<RoomCard> rooms;
  final String? joinedLiveRoomId;
  final bool joiningLive;
  final bool livePanelOpen;
  final String? error;
}

String? joinedLiveRoomToDisconnectBeforeJoin({
  required String? joinedLiveRoomId,
  required String targetRoomId,
}) {
  if (joinedLiveRoomId == null || joinedLiveRoomId == targetRoomId) {
    return null;
  }
  return joinedLiveRoomId;
}

bool canPatchSelectedLiveState({
  required String? joinedLiveRoomId,
  required String? selectedRoomId,
}) {
  return joinedLiveRoomId != null && joinedLiveRoomId == selectedRoomId;
}

bool canApplyPickedScreenShareSource({
  required String pickedForRoomId,
  required String? joinedLiveRoomId,
  required String? selectedRoomId,
}) {
  return joinedLiveRoomId == pickedForRoomId &&
      selectedRoomId == pickedForRoomId;
}

bool isBenignGoneLiveStatePatch(Object error) {
  return error is ApiException && error.statusCode == 409;
}

bool shouldSyncLiveKitMicAfterServerPatch({
  required bool? requestedMicMuted,
  required bool serverMicMuted,
}) {
  return requestedMicMuted != null && serverMicMuted != requestedMicMuted;
}

LiveOutputMutePatch liveOutputMuteToggled({required bool headphonesMuted}) {
  return LiveOutputMutePatch(headphonesMuted: !headphonesMuted);
}

class LiveController {
  LiveController({required this.api});

  final GangApi api;

  Future<LiveJoinResult> joinLive({
    required String roomId,
    required String source,
  }) {
    return api.joinLive(
      roomId: roomId,
      clientLiveSessionId: newClientId('clive'),
      source: source,
    );
  }

  Future<LiveParticipant> updateMyState({
    required String roomId,
    bool? micMuted,
    bool? headphonesMuted,
    bool? cameraOn,
    bool? screenSharing,
  }) {
    return api.updateMyLiveState(
      roomId: roomId,
      micMuted: micMuted,
      headphonesMuted: headphonesMuted,
      cameraOn: cameraOn,
      screenSharing: screenSharing,
    );
  }

  Future<LiveParticipant> leaveLive({required String roomId}) {
    return api.updateMyLiveState(roomId: roomId, connectionState: 'left');
  }

  LiveJoinStatePatch patchJoinStarted({required String? joinedLiveRoomId}) {
    return LiveJoinStatePatch(
      joinedLiveRoomId: joinedLiveRoomId,
      joiningLive: true,
      livePanelOpen: true,
      error: null,
    );
  }

  LiveJoinPreviousRoomDisconnectedPatch patchJoinPreviousRoomDisconnected({
    required LiveState? live,
    required List<RoomCard> rooms,
    required String previousRoomId,
    required String userId,
    required bool livePanelOpen,
    required String? error,
  }) {
    final departure = removeUserFromLive(
      live: live,
      rooms: rooms,
      roomId: previousRoomId,
      userId: userId,
    );
    return LiveJoinPreviousRoomDisconnectedPatch(
      live: departure.live,
      rooms: departure.rooms,
      joinedLiveRoomId: null,
      joiningLive: true,
      livePanelOpen: livePanelOpen,
      error: error,
    );
  }

  LiveJoinStatePatch patchJoinConnected({
    required String roomId,
    required bool livePanelOpen,
    required String? error,
  }) {
    return LiveJoinStatePatch(
      joinedLiveRoomId: roomId,
      joiningLive: true,
      livePanelOpen: livePanelOpen,
      error: error,
    );
  }

  LiveJoinStatePatch patchJoinFinished({
    required String? joinedLiveRoomId,
    required bool livePanelOpen,
    required String? error,
  }) {
    return LiveJoinStatePatch(
      joinedLiveRoomId: joinedLiveRoomId,
      joiningLive: false,
      livePanelOpen: livePanelOpen,
      error: error,
    );
  }

  LiveLocalDeparturePatch patchLocalDeparture({
    required LiveState? live,
    required List<RoomCard> rooms,
    required String? joinedLiveRoomId,
    required String userId,
    required bool joiningLive,
  }) {
    final roomId = joinedLiveRoomId;
    final departure = roomId == null
        ? LiveDeparturePatch(live: live, rooms: rooms)
        : removeUserFromLive(
            live: live,
            rooms: rooms,
            roomId: roomId,
            userId: userId,
          );
    return LiveLocalDeparturePatch(
      live: departure.live,
      rooms: departure.rooms,
      joinedLiveRoomId: null,
      joiningLive: joiningLive,
      cameraOn: false,
      screenSharing: false,
      voiceBlocked: false,
    );
  }

  LivePublishPermissionPatch patchPublishPermission({
    required bool canPublish,
    required bool micMuted,
  }) {
    return LivePublishPermissionPatch(
      micMuted: canPublish ? micMuted : true,
      voiceBlocked: !canPublish,
    );
  }

  LiveJoinResultPatch patchJoinResult({
    required List<RoomCard> rooms,
    required LiveJoinResult result,
  }) {
    return LiveJoinResultPatch(
      micMuted: result.participant.micMuted,
      cameraOn: result.participant.cameraOn,
      screenSharing: result.participant.screenSharing,
      voiceBlocked: result.participant.voiceBlocked,
      live: result.live,
      rooms: room_live_state.patchRoomLiveCount(
        rooms: rooms,
        roomId: result.live.roomId,
        live: result.live,
      ),
    );
  }

  LiveStateUpdatePatch patchStateUpdate({
    required LiveState? live,
    required LiveParticipant participant,
  }) {
    return LiveStateUpdatePatch(
      micMuted: participant.micMuted,
      cameraOn: participant.cameraOn,
      screenSharing: participant.screenSharing,
      voiceBlocked: participant.voiceBlocked,
      live: mergeParticipant(live, participant),
    );
  }

  LiveDeparturePatch removeUserFromLive({
    required LiveState? live,
    required List<RoomCard> rooms,
    required String roomId,
    required String userId,
  }) {
    return LiveDeparturePatch(
      live: _removeUserFromLiveState(
        live: live,
        roomId: roomId,
        userId: userId,
      ),
      rooms: _removeUserFromRoomLivePreview(
        rooms: rooms,
        roomId: roomId,
        userId: userId,
      ),
    );
  }

  LiveState? mergeParticipant(LiveState? live, LiveParticipant participant) {
    if (live == null) return null;
    var replaced = false;
    final participants = live.participants.map((item) {
      if (item.liveSessionId != participant.liveSessionId) return item;
      replaced = true;
      return participant;
    }).toList();
    return LiveState(
      roomId: live.roomId,
      participantCount: replaced
          ? live.participantCount
          : live.participantCount + 1,
      participants: replaced ? participants : [...participants, participant],
      updatedAt: DateTime.now().toUtc(),
    );
  }

  LiveState? _removeUserFromLiveState({
    required LiveState? live,
    required String roomId,
    required String userId,
  }) {
    if (live == null || live.roomId != roomId) return live;
    final remaining = live.participants
        .where((participant) => participant.user.id != userId)
        .toList();
    if (remaining.length == live.participants.length) return live;
    return LiveState(
      roomId: live.roomId,
      participantCount: remaining.length,
      participants: remaining,
      updatedAt: live.updatedAt,
    );
  }

  List<RoomCard> _removeUserFromRoomLivePreview({
    required List<RoomCard> rooms,
    required String roomId,
    required String userId,
  }) {
    final idx = rooms.indexWhere((room) => room.id == roomId);
    if (idx < 0) return rooms;

    final existing = rooms[idx];
    final remainingPreview = existing.liveAvatarPreview
        .where((user) => user.id != userId)
        .toList();
    final nextCount = existing.liveParticipantCount > 0
        ? existing.liveParticipantCount - 1
        : 0;
    if (remainingPreview.length == existing.liveAvatarPreview.length &&
        nextCount == existing.liveParticipantCount) {
      return rooms;
    }
    final next = [...rooms];
    next[idx] = RoomCard(
      id: existing.id,
      name: existing.name,
      rid: existing.rid,
      visibility: existing.visibility,
      remarkName: existing.remarkName,
      description: existing.description,
      notificationPolicy: existing.notificationPolicy,
      avatarUrl: existing.avatarUrl,
      defaultAvatarKey: existing.defaultAvatarKey,
      memberCount: existing.memberCount,
      onlineMemberCount: existing.onlineMemberCount,
      liveParticipantCount: nextCount,
      liveAvatarPreview: remainingPreview,
      lastMessage: existing.lastMessage,
      unreadCount: existing.unreadCount,
      updatedAt: existing.updatedAt,
    );
    return next;
  }
}
