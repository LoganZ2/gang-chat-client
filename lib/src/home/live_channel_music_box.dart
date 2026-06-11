part of 'live_channel_pane.dart';

/// The in-pane music box console: a spinning vinyl for the current track, a
/// progress bar with transport controls, the queue, and a search-to-queue
/// field. Audio is delivered separately via the LiveKit session; this is purely
/// the control surface and status display.
class LiveMusicBoxPanel extends StatelessWidget {
  const LiveMusicBoxPanel({
    super.key,
    required this.state,
    required this.searchController,
    required this.searchResults,
    required this.searching,
    required this.searchError,
    required this.onTogglePlayback,
    required this.onSkip,
    required this.onStop,
    required this.onQueueResult,
    required this.onRemoveItem,
  });

  final MusicBoxState state;
  final TextEditingController searchController;
  final List<MusicBoxSearchResult> searchResults;
  final bool searching;
  final String? searchError;
  final VoidCallback onTogglePlayback;
  final VoidCallback onSkip;
  final VoidCallback onStop;
  final ValueChanged<MusicBoxSearchResult> onQueueResult;
  final ValueChanged<MusicBoxQueueItem> onRemoveItem;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(_liveRoomRadius),
        border: Border.all(color: UiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MusicBoxHeader(usage: state.usage),
            const SizedBox(height: 16),
            _MusicBoxNowPlaying(
              state: state,
              onTogglePlayback: onTogglePlayback,
              onSkip: onSkip,
              onStop: onStop,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _MusicBoxBody(
                state: state,
                searchController: searchController,
                searchResults: searchResults,
                searching: searching,
                searchError: searchError,
                onQueueResult: onQueueResult,
                onRemoveItem: onRemoveItem,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicBoxHeader extends StatelessWidget {
  const _MusicBoxHeader({required this.usage});

  final MusicBoxUsage usage;

  @override
  Widget build(BuildContext context) {
    final hint = music_box_display.musicBoxUsageHint(usage);
    return Row(
      children: [
        const Icon(Icons.library_music, size: 18, color: UiColors.accent),
        const SizedBox(width: 8),
        const Text(
          '音乐盒',
          style: TextStyle(
            color: UiColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            hint ?? music_box_display.musicBoxUsageLabel(usage),
            style: TextStyle(
              color: hint == null ? UiColors.textMuted : UiColors.amber,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The now-playing strip: spinning vinyl, title/artist, progress bar, and
/// transport controls.
class _MusicBoxNowPlaying extends StatelessWidget {
  const _MusicBoxNowPlaying({
    required this.state,
    required this.onTogglePlayback,
    required this.onSkip,
    required this.onStop,
  });

  final MusicBoxState state;
  final VoidCallback onTogglePlayback;
  final VoidCallback onSkip;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final current = state.currentItem;
    final spinning = music_box_display.musicBoxRecordSpinning(state);
    final transport = music_box_display.musicBoxPrimaryTransport(state);
    final hasQueue = state.queue.isNotEmpty;

    return Row(
      children: [
        _VinylRecord(spinning: spinning, label: current?.title),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                current?.title ?? '未在播放',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: current == null ? UiColors.textMuted : UiColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                current?.artist.isNotEmpty == true
                    ? current!.artist
                    : '点一首歌开始播放',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: UiColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _MusicBoxProgressBar(state: state),
              const SizedBox(height: 10),
              Row(
                children: [
                  ButtonIcon(
                    tooltip:
                        transport ==
                            music_box_display.MusicBoxTransportAction.pause
                        ? '暂停'
                        : '播放',
                    icon: Icon(
                      transport ==
                              music_box_display.MusicBoxTransportAction.pause
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    tone: ButtonTone.primary,
                    onPressed: hasQueue ? onTogglePlayback : null,
                    size: 40,
                  ),
                  const SizedBox(width: 8),
                  ButtonIcon(
                    tooltip: '下一首',
                    icon: const Icon(Icons.skip_next),
                    onPressed: hasQueue ? onSkip : null,
                    size: 40,
                  ),
                  const SizedBox(width: 8),
                  ButtonIcon(
                    tooltip: '停止',
                    icon: const Icon(Icons.stop),
                    onPressed:
                        state.playback.state != MusicBoxPlaybackState.stopped
                        ? onStop
                        : null,
                    size: 40,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A spinning black vinyl record. Rotates continuously while [spinning], and
/// freezes its current angle when paused/stopped — an at-a-glance read of
/// whether the music box is playing.
class _VinylRecord extends StatefulWidget {
  const _VinylRecord({required this.spinning, this.label});

  final bool spinning;
  final String? label;

  @override
  State<_VinylRecord> createState() => _VinylRecordState();
}

class _VinylRecordState extends State<_VinylRecord>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _controller.repeat();
  }

  @override
  void didUpdateWidget(_VinylRecord oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.spinning && _controller.isAnimating) {
      // Freeze at the current angle rather than snapping back to zero.
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: CustomPaint(size: const Size(64, 64), painter: _VinylPainter()),
    );
  }
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Disc body.
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF12151A));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF2A2F38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Grooves.
    final groovePaint = Paint()
      ..color = const Color(0xFF20242C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = radius - 6; r > radius * 0.34; r -= 5) {
      canvas.drawCircle(center, r, groovePaint);
    }

    // Accent label and spindle hole.
    canvas.drawCircle(center, radius * 0.30, Paint()..color = UiColors.accent);
    canvas.drawCircle(
      center,
      radius * 0.30,
      Paint()
        ..color = const Color(0xFF14171D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      center,
      radius * 0.07,
      Paint()..color = const Color(0xFF14171D),
    );
  }

  @override
  bool shouldRepaint(_VinylPainter oldDelegate) => false;
}

/// Client-authoritative progress bar. The server snapshot only supplies the
/// *base* position (`position_ms`); from the moment a snapshot is applied this
/// widget steps the position forward on its own [Stopwatch], one second at a
/// time, and re-anchors only when the base changes (track switch, play/pause
/// flip, or the server pushing a corrected position). This removes any reliance
/// on the server's wall clock, so client/server clock skew can't make the bar
/// jump.
class _MusicBoxProgressBar extends StatefulWidget {
  const _MusicBoxProgressBar({required this.state});

  final MusicBoxState state;

  @override
  State<_MusicBoxProgressBar> createState() => _MusicBoxProgressBarState();
}

class _MusicBoxProgressBarState extends State<_MusicBoxProgressBar> {
  // Measures elapsed time since the current snapshot was anchored. Used instead
  // of DateTime.now() so the stepping is immune to wall-clock adjustments.
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _anchor();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_MusicBoxProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_baseChanged(oldWidget.state, widget.state)) {
      _anchor();
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Whether the playback base — what we step forward from — moved. A change in
  /// the current track, the play/pause state, or the server-reported position
  /// means we must reset the stopwatch and start stepping from the new base.
  bool _baseChanged(MusicBoxState a, MusicBoxState b) {
    return a.playback.currentItemId != b.playback.currentItemId ||
        a.playback.state != b.playback.state ||
        a.playback.positionMs != b.playback.positionMs;
  }

  /// Resets the stopwatch so stepping starts fresh from the snapshot's base
  /// position, running it only while actually playing.
  void _anchor() {
    _stopwatch
      ..reset()
      ..stop();
    if (widget.state.playback.state == MusicBoxPlaybackState.playing) {
      _stopwatch.start();
    }
  }

  /// Runs a 1s repaint ticker only while playing; the bar is static otherwise.
  void _syncTicker() {
    final shouldTick = music_box_display.musicBoxShouldTick(widget.state);
    if (shouldTick) {
      _ticker ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) {
          if (mounted) setState(() {});
        },
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = music_box_display.musicBoxProgress(
      widget.state,
      elapsed: _stopwatch.elapsed,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 4,
            backgroundColor: UiColors.surfaceRaised,
            valueColor: const AlwaysStoppedAnimation(UiColors.accent),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              music_box_display.musicBoxFormatDuration(progress.positionMs),
              style: const TextStyle(
                color: UiColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              music_box_display.musicBoxFormatDuration(progress.durationMs),
              style: const TextStyle(
                color: UiColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Tabbed lower body: the queue, plus a search field that adds hits to it.
class _MusicBoxBody extends StatelessWidget {
  const _MusicBoxBody({
    required this.state,
    required this.searchController,
    required this.searchResults,
    required this.searching,
    required this.searchError,
    required this.onQueueResult,
    required this.onRemoveItem,
  });

  final MusicBoxState state;
  final TextEditingController searchController;
  final List<MusicBoxSearchResult> searchResults;
  final bool searching;
  final String? searchError;
  final ValueChanged<MusicBoxSearchResult> onQueueResult;
  final ValueChanged<MusicBoxQueueItem> onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final hasQuery = searchController.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Input(
          controller: searchController,
          hintText: '搜索歌曲点歌',
          prefixIcon: Icons.search,
          maxLines: 1,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: hasQuery
              ? _MusicBoxSearchList(
                  results: searchResults,
                  searching: searching,
                  error: searchError,
                  onQueueResult: onQueueResult,
                )
              : _MusicBoxQueueList(state: state, onRemoveItem: onRemoveItem),
        ),
      ],
    );
  }
}

class _MusicBoxQueueList extends StatelessWidget {
  const _MusicBoxQueueList({required this.state, required this.onRemoveItem});

  final MusicBoxState state;
  final ValueChanged<MusicBoxQueueItem> onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final queue = state.queue;
    if (queue.isEmpty) {
      return const _MusicBoxEmpty(
        icon: Icons.queue_music,
        message: '队列空空如也，搜索点歌吧',
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: queue.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = queue[index];
        return _MusicBoxQueueTile(
          item: item,
          isCurrent: music_box_display.musicBoxIsCurrent(state, item),
          onRemove: () => onRemoveItem(item),
        );
      },
    );
  }
}

class _MusicBoxQueueTile extends StatelessWidget {
  const _MusicBoxQueueTile({
    required this.item,
    required this.isCurrent,
    required this.onRemove,
  });

  final MusicBoxQueueItem item;
  final bool isCurrent;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final statusLabel = music_box_display.musicBoxQueueStatusLabel(item);
    final failed = item.status == MusicBoxQueueItemStatus.failed;
    final loading =
        item.status == MusicBoxQueueItemStatus.pending ||
        item.status == MusicBoxQueueItemStatus.downloading;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isCurrent ? UiColors.selected : UiColors.surfaceLow,
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(
          color: isCurrent ? UiColors.selectedBorder : UiColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            _MusicBoxArtwork(playing: isCurrent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? UiColors.accent : UiColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (statusLabel != null) ...[
                        if (loading)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.6),
                          ),
                        if (loading) const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: failed
                                  ? UiColors.danger
                                  : UiColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ] else
                        Expanded(
                          child: Text(
                            item.artist.isEmpty ? '未知艺人' : item.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: UiColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (item.durationMs > 0) ...[
              const SizedBox(width: 8),
              Text(
                music_box_display.musicBoxFormatDuration(item.durationMs),
                style: const TextStyle(
                  color: UiColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(width: 4),
            ButtonIcon(
              tooltip: '移除',
              icon: const Icon(Icons.close),
              tone: ButtonTone.danger,
              onPressed: onRemove,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicBoxSearchList extends StatelessWidget {
  const _MusicBoxSearchList({
    required this.results,
    required this.searching,
    required this.error,
    required this.onQueueResult,
  });

  final List<MusicBoxSearchResult> results;
  final bool searching;
  final String? error;
  final ValueChanged<MusicBoxSearchResult> onQueueResult;

  @override
  Widget build(BuildContext context) {
    if (searching && results.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (error != null) {
      return _MusicBoxEmpty(icon: Icons.error_outline, message: error!);
    }
    if (results.isEmpty) {
      return const _MusicBoxEmpty(icon: Icons.search_off, message: '没有找到相关歌曲');
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final result = results[index];
        return _MusicBoxSearchTile(
          result: result,
          onQueue: () => onQueueResult(result),
        );
      },
    );
  }
}

class _MusicBoxSearchTile extends StatelessWidget {
  const _MusicBoxSearchTile({required this.result, required this.onQueue});

  final MusicBoxSearchResult result;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final artists = music_box_display.musicBoxArtistsLabel(result.artists);
    return PressableSurface(
      width: double.infinity,
      height: 56,
      hoverLift: 2,
      baseDepth: 4,
      backgroundColor: UiColors.surfaceLow,
      pressedBackgroundColor: UiColors.surfacePressed,
      borderColor: UiColors.border,
      borderRadius: UiRadii.md,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tooltip: '点歌',
      onPressed: onQueue,
      child: Row(
        children: [
          const _MusicBoxArtwork(playing: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UiColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  artists.isEmpty ? '未知艺人' : artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UiColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A placeholder cover tile. The server doesn't yet expose a `pic_id` -> URL
/// resolver, so we render a music-note glyph instead of guessing a third-party
/// image address.
class _MusicBoxArtwork extends StatelessWidget {
  const _MusicBoxArtwork({required this.playing});

  final bool playing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: UiColors.surfaceRaised,
        borderRadius: BorderRadius.circular(UiRadii.sm),
      ),
      alignment: Alignment.center,
      child: Icon(
        playing ? Icons.graphic_eq : Icons.music_note,
        size: 18,
        color: playing ? UiColors.accent : UiColors.textMuted,
      ),
    );
  }
}

class _MusicBoxEmpty extends StatelessWidget {
  const _MusicBoxEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: UiColors.textMuted),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: UiColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
