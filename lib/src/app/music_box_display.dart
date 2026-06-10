import '../protocol/models.dart';

/// Pure presentation logic for the room music box. No Flutter imports: every
/// rendering decision (progress, status text, delete permission, formatting)
/// lives here so it can be unit-tested without a widget tree, mirroring
/// `live_display.dart`.

/// The live playback position. The server records [MusicBoxPlayback.positionMs]
/// only at state changes and never pushes it per second, so while playing we
/// advance it locally from the snapshot's [MusicBoxPlayback.updatedAt] and
/// recalibrate whenever a fresh snapshot arrives.
class MusicBoxProgress {
  const MusicBoxProgress({required this.positionMs, required this.durationMs});

  final int positionMs;
  final int durationMs;

  /// 0.0–1.0 for a progress bar; 0 when the duration is unknown.
  double get fraction {
    if (durationMs <= 0) return 0;
    final ratio = positionMs / durationMs;
    if (ratio.isNaN) return 0;
    return ratio.clamp(0.0, 1.0);
  }
}

/// Computes the playback position to render at wall-clock [now]. While playing,
/// adds the elapsed time since the snapshot was recorded; paused/stopped hold at
/// the recorded position. The result is clamped to the track duration so it
/// never overruns the end while waiting for the next snapshot.
MusicBoxProgress musicBoxProgress(
  MusicBoxState state, {
  required DateTime now,
}) {
  final current = state.currentItem;
  final durationMs = current?.durationMs ?? 0;
  final playback = state.playback;
  var positionMs = playback.positionMs;
  if (playback.state == MusicBoxPlaybackState.playing) {
    final updatedAt = playback.updatedAt;
    if (updatedAt != null) {
      final elapsed = now.difference(updatedAt).inMilliseconds;
      if (elapsed > 0) positionMs += elapsed;
    }
  }
  if (positionMs < 0) positionMs = 0;
  if (durationMs > 0 && positionMs > durationMs) positionMs = durationMs;
  return MusicBoxProgress(positionMs: positionMs, durationMs: durationMs);
}

/// Whether a local ticker should run to advance the progress bar: only while a
/// track is actually playing.
bool musicBoxShouldTick(MusicBoxState state) {
  return state.playback.state == MusicBoxPlaybackState.playing &&
      state.currentItem != null;
}

/// The play/pause toggle the primary transport button should drive, given the
/// current state. `play` resumes from pause, starts a stopped queue, and is a
/// no-op target only when the queue is empty.
enum MusicBoxTransportAction { play, pause, resume }

MusicBoxTransportAction musicBoxPrimaryTransport(MusicBoxState state) {
  return switch (state.playback.state) {
    MusicBoxPlaybackState.playing => MusicBoxTransportAction.pause,
    MusicBoxPlaybackState.paused => MusicBoxTransportAction.resume,
    MusicBoxPlaybackState.stopped => MusicBoxTransportAction.play,
  };
}

String musicBoxTransportApiAction(MusicBoxTransportAction action) {
  return switch (action) {
    MusicBoxTransportAction.play => 'play',
    MusicBoxTransportAction.pause => 'pause',
    MusicBoxTransportAction.resume => 'resume',
  };
}

/// Whether the spinning vinyl should rotate: it spins while playing and freezes
/// otherwise, giving an at-a-glance read of playback.
bool musicBoxRecordSpinning(MusicBoxState state) {
  return state.playback.state == MusicBoxPlaybackState.playing;
}

/// A short status label for a queue item, reflecting its download/transcode
/// lifecycle. Returns null for [MusicBoxQueueItemStatus.ready], which renders
/// normally with no badge.
String? musicBoxQueueStatusLabel(MusicBoxQueueItem item) {
  return switch (item.status) {
    MusicBoxQueueItemStatus.pending => '排队中，等待下载',
    MusicBoxQueueItemStatus.downloading => '下载中',
    MusicBoxQueueItemStatus.failed => musicBoxQueueErrorLabel(item),
    MusicBoxQueueItemStatus.ready => null,
  };
}

/// The error line for a failed item, falling back to a generic message when the
/// server didn't supply one.
String musicBoxQueueErrorLabel(MusicBoxQueueItem item) {
  final error = item.error.trim();
  return error.isEmpty ? '处理失败' : error;
}

/// A spinning vinyl is only meaningful once a track is current; tiles still in
/// the queue show artwork without rotation.
bool musicBoxIsCurrent(MusicBoxState state, MusicBoxQueueItem item) {
  return state.playback.currentItemId == item.id && item.id.isNotEmpty;
}

/// A near-limit hint for the usage meter, or null when there's comfortable
/// headroom. Triggers at 90%. Over the limit, new songs aren't rejected — they
/// queue as `pending` and download once earlier tracks finish playing.
String? musicBoxUsageHint(MusicBoxUsage usage) {
  if (usage.limitBytes <= 0) return null;
  final ratio = usage.usedBytes / usage.limitBytes;
  if (ratio < 0.9) return null;
  if (ratio >= 1.0) return '空间已满，新歌将排队等待下载';
  return '空间已接近上限';
}

double musicBoxUsageFraction(MusicBoxUsage usage) {
  if (usage.limitBytes <= 0) return 0;
  return (usage.usedBytes / usage.limitBytes).clamp(0.0, 1.0);
}

/// Joins a search hit's artist list for display, e.g. `林俊杰、孙燕姿`.
String musicBoxArtistsLabel(List<String> artists) {
  return artists.where((a) => a.trim().isNotEmpty).join('、');
}

/// `mm:ss` (or `h:mm:ss`) for a millisecond duration; em dash when unknown.
String musicBoxFormatDuration(int milliseconds) {
  if (milliseconds <= 0) return '--:--';
  final totalSeconds = milliseconds ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// Human-readable byte size, e.g. `3.7 MB`.
String musicBoxFormatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final text = unit == 0 || value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  // Drop a trailing `.0` so whole values read `5 MB`, not `5.0 MB`.
  final trimmed = text.endsWith('.0')
      ? text.substring(0, text.length - 2)
      : text;
  return '$trimmed ${units[unit]}';
}

String musicBoxUsageLabel(MusicBoxUsage usage) {
  return '${musicBoxFormatBytes(usage.usedBytes)} / '
      '${musicBoxFormatBytes(usage.limitBytes)}';
}
