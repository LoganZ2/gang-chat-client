import '../protocol/models.dart';

class JoinedLiveRoomSummary {
  const JoinedLiveRoomSummary({
    required this.roomId,
    required this.displayName,
    required this.avatarUrl,
    required this.defaultAvatarKey,
  });

  final String roomId;
  final String displayName;
  final String? avatarUrl;
  final String defaultAvatarKey;
}

class LiveParticipantTileState {
  const LiveParticipantTileState({
    required this.broadcasting,
    required this.highlighted,
    required this.micMutedForDisplay,
    required this.micActive,
  });

  final bool broadcasting;
  final bool highlighted;
  final bool micMutedForDisplay;
  final bool micActive;
}

class LiveMicControlState {
  const LiveMicControlState({
    required this.mutedForDisplay,
    required this.active,
    required this.enabled,
  });

  final bool mutedForDisplay;
  final bool active;
  final bool enabled;
}

enum LiveScreenSourceListBodyState { loading, empty, results }

class LiveScreenSourcePickerState<T> {
  const LiveScreenSourcePickerState({
    this.sources,
    this.selectedId,
    this.loading = false,
    this.error,
  });

  final List<T>? sources;
  final String? selectedId;
  final bool loading;
  final String? error;

  LiveScreenSourcePickerState<T> copyWith({
    List<T>? sources,
    Object? selectedId = _liveScreenSourceSelectedIdUnchanged,
    bool? loading,
    Object? error = _liveScreenSourceErrorUnchanged,
  }) {
    return LiveScreenSourcePickerState<T>(
      sources: sources ?? this.sources,
      selectedId: identical(selectedId, _liveScreenSourceSelectedIdUnchanged)
          ? this.selectedId
          : selectedId as String?,
      loading: loading ?? this.loading,
      error: identical(error, _liveScreenSourceErrorUnchanged)
          ? this.error
          : error as String?,
    );
  }
}

const Object _liveScreenSourceSelectedIdUnchanged = Object();
const Object _liveScreenSourceErrorUnchanged = Object();

LiveParticipant? liveParticipantByUserId(LiveState? live, String userId) {
  if (live == null) return null;
  for (final participant in live.participants) {
    if (participant.user.id == userId) return participant;
  }
  return null;
}

String liveParticipantDisplayName(
  LiveState? live,
  String userId, {
  String fallback = '',
}) {
  return liveParticipantByUserId(live, userId)?.user.displayName ?? fallback;
}

List<LiveParticipant> visibleLiveParticipantsForStage(
  Iterable<LiveParticipant> participants, {
  required String currentUserId,
  required bool localParticipantReady,
}) {
  return [
    for (final participant in participants)
      if (localParticipantReady || participant.user.id != currentUserId)
        participant,
  ];
}

LiveParticipantTileState liveParticipantTileState(
  LiveParticipant participant, {
  required bool speaking,
}) {
  final broadcasting = participant.cameraOn || participant.screenSharing;
  final micMutedForDisplay =
      participant.micBlocked ||
      participant.voiceBlocked ||
      participant.micMuted;
  return LiveParticipantTileState(
    broadcasting: broadcasting,
    highlighted: speaking || broadcasting,
    micMutedForDisplay: micMutedForDisplay,
    micActive: !micMutedForDisplay && speaking,
  );
}

T? pickLiveStageShare<T>(
  Iterable<T> tracks, {
  required bool Function(T track) isScreenShare,
  required bool Function(T track) isLocal,
}) {
  T? localShare;
  for (final track in tracks) {
    if (!isScreenShare(track)) continue;
    if (!isLocal(track)) return track;
    localShare ??= track;
  }
  return localShare;
}

T? liveScreenShareByIdentity<T>(
  Iterable<T> tracks, {
  required String? identity,
  required String Function(T track) trackIdentity,
  required bool Function(T track) isScreenShare,
}) {
  if (identity == null) return null;
  for (final track in tracks) {
    if (isScreenShare(track) && trackIdentity(track) == identity) return track;
  }
  return null;
}

bool shouldExitMissingFullScreenShare({
  required String? fullScreenShareIdentity,
  required Object? fullScreenShare,
}) {
  return fullScreenShareIdentity != null && fullScreenShare == null;
}

bool shouldPatchEndedLocalScreenShare({
  required bool localScreenSharing,
  required bool sessionScreenSharing,
  required String? joinedLiveRoomId,
  required String? selectedRoomId,
}) {
  return localScreenSharing &&
      !sessionScreenSharing &&
      joinedLiveRoomId != null &&
      joinedLiveRoomId == selectedRoomId;
}

JoinedLiveRoomSummary? joinedLiveRoomSummary({
  required String? joinedLiveRoomId,
  required RoomDetail? selectedRoom,
  required Iterable<RoomCard> rooms,
}) {
  final roomId = _nonEmpty(joinedLiveRoomId);
  if (roomId == null) return null;

  final selected = selectedRoom;
  if (selected != null && selected.id == roomId) {
    return JoinedLiveRoomSummary(
      roomId: selected.id,
      displayName: _roomDetailDisplayName(selected),
      avatarUrl: selected.avatarUrl,
      defaultAvatarKey: selected.defaultAvatarKey,
    );
  }

  for (final room in rooms) {
    if (room.id != roomId) continue;
    return JoinedLiveRoomSummary(
      roomId: room.id,
      displayName: room.displayName,
      avatarUrl: room.avatarUrl,
      defaultAvatarKey: room.defaultAvatarKey,
    );
  }

  return null;
}

String? reconcileLiveScreenSourceSelection<T>(
  Iterable<T> sources, {
  required String? selectedId,
  required String Function(T source) sourceId,
}) {
  T? firstSource;
  for (final source in sources) {
    firstSource ??= source;
    if (sourceId(source) == selectedId) return selectedId;
  }
  return firstSource == null ? null : sourceId(firstSource);
}

T? liveScreenSourceById<T>(
  Iterable<T>? sources, {
  required String? selectedId,
  required String Function(T source) sourceId,
}) {
  if (selectedId == null || sources == null) return null;
  for (final source in sources) {
    if (sourceId(source) == selectedId) return source;
  }
  return null;
}

LiveScreenSourceListBodyState liveScreenSourceListBodyState<T>(
  Iterable<T>? sources,
) {
  if (sources == null) return LiveScreenSourceListBodyState.loading;
  if (sources.isEmpty) return LiveScreenSourceListBodyState.empty;
  return LiveScreenSourceListBodyState.results;
}

bool liveScreenSourceSelected<T>(
  T source, {
  required String? selectedId,
  required String Function(T source) sourceId,
}) {
  return selectedId != null && sourceId(source) == selectedId;
}

bool canConfirmLiveScreenSourceSelection(String? selectedId) {
  return selectedId != null;
}

bool canLoadLiveScreenSources<T>(LiveScreenSourcePickerState<T> state) {
  return !state.loading;
}

LiveScreenSourcePickerState<T> liveScreenSourceLoadStarted<T>(
  LiveScreenSourcePickerState<T> state,
) {
  return state.copyWith(loading: true, error: null);
}

LiveScreenSourcePickerState<T> liveScreenSourceLoadSucceeded<T>({
  required LiveScreenSourcePickerState<T> state,
  required Iterable<T> sources,
  required String Function(T source) sourceId,
}) {
  final nextSources = sources.toList();
  return state.copyWith(
    sources: nextSources,
    selectedId: reconcileLiveScreenSourceSelection(
      nextSources,
      selectedId: state.selectedId,
      sourceId: sourceId,
    ),
    loading: false,
    error: null,
  );
}

LiveScreenSourcePickerState<T> liveScreenSourceLoadFailed<T>({
  required LiveScreenSourcePickerState<T> state,
  required Object failure,
}) {
  return state.copyWith(loading: false, error: failure.toString());
}

LiveScreenSourcePickerState<T> liveScreenSourceSelectedChanged<T>(
  LiveScreenSourcePickerState<T> state,
  String? selectedId,
) {
  return state.copyWith(selectedId: selectedId);
}

T? visibleLiveScreenSourceThumbnail<T extends Iterable<int>>({
  required T? thumbnail,
  required Object? imageError,
}) {
  if (thumbnail == null || thumbnail.isEmpty || imageError != null) {
    return null;
  }
  return thumbnail;
}

bool canOpenLiveStageShareFullScreen({
  required String stageShareIdentity,
  required String localUserId,
}) {
  return stageShareIdentity != localUserId;
}

String liveScreenShareStageLabel(String displayName) {
  return displayName.isEmpty ? '屏幕共享' : '$displayName 的屏幕';
}

LiveMicControlState liveMicControlState({
  required bool micMuted,
  required bool voiceBlocked,
}) {
  if (voiceBlocked) {
    return const LiveMicControlState(
      mutedForDisplay: true,
      active: false,
      enabled: false,
    );
  }
  return LiveMicControlState(
    mutedForDisplay: micMuted,
    active: !micMuted,
    enabled: true,
  );
}

String liveForciblyRemovedNotice() {
  return '你已被移出语音';
}

String liveVoiceConnectFailureMessage(Object error) {
  return '无法连接语音：$error';
}

String liveCameraOpenFailureMessage(Object error) {
  return '无法打开摄像头: $error';
}

String liveScreenShareFailureMessage(Object error) {
  return '无法共享屏幕: $error';
}

String _roomDetailDisplayName(RoomDetail room) {
  final remark = _nonEmpty(room.remarkName);
  if (remark == null) return room.name;
  return '$remark (${room.name})';
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
