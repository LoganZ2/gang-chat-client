import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/live_display.dart' as live_display;
import '../live/live_session.dart';
import '../ui/ui.dart';

class LiveScreenSharePicker extends StatefulWidget {
  const LiveScreenSharePicker({
    super.key,
    required this.loadSources,
    required this.refreshThumbnails,
  });

  final Future<List<ScreenSource>> Function() loadSources;
  final Future<void> Function() refreshThumbnails;

  @override
  State<LiveScreenSharePicker> createState() => _LiveScreenSharePickerState();
}

class _LiveScreenSharePickerState extends State<LiveScreenSharePicker> {
  live_display.LiveScreenSourcePickerState<ScreenSource> _state =
      const live_display.LiveScreenSourcePickerState();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(widget.refreshThumbnails());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!live_display.canLoadLiveScreenSources(_state)) return;
    setState(() {
      _state = live_display.liveScreenSourceLoadStarted(_state);
    });

    try {
      final sources = await widget.loadSources();
      if (!mounted) return;
      setState(() {
        _state = live_display.liveScreenSourceLoadSucceeded(
          state: _state,
          sources: sources,
          sourceId: (source) => source.id,
        );
      });
      unawaited(widget.refreshThumbnails());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = live_display.liveScreenSourceLoadFailed(
          state: _state,
          failure: error,
        );
      });
    }
  }

  void _confirm() {
    final source = live_display.liveScreenSourceById(
      _state.sources,
      selectedId: _state.selectedId,
      sourceId: (source) => source.id,
    );
    if (source == null) return;
    Navigator.of(context).pop(source);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: UiColors.surfaceLow,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiRadii.lg),
        side: const BorderSide(color: UiColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('选择共享内容', style: UiTypography.title),
              const SizedBox(height: 16),
              Flexible(child: _buildSourceList(_state.sources)),
              if (_state.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _state.error!,
                  style: UiTypography.label.copyWith(color: UiColors.danger),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    height: 40,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  Button(
                    height: 40,
                    tone: ButtonTone.primary,
                    onPressed:
                        live_display.canConfirmLiveScreenSourceSelection(
                          _state.selectedId,
                        )
                        ? _confirm
                        : null,
                    child: const Text('共享'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceList(List<ScreenSource>? sources) {
    final state = live_display.liveScreenSourceListBodyState(sources);
    return switch (state) {
      live_display.LiveScreenSourceListBodyState.loading => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(color: UiColors.accent)),
      ),
      live_display.LiveScreenSourceListBodyState.empty => SizedBox(
        height: 200,
        child: Center(
          child: Text(
            '没有可共享的屏幕或窗口',
            style: UiTypography.body.copyWith(color: UiColors.textMuted),
          ),
        ),
      ),
      live_display.LiveScreenSourceListBodyState.results => GridView.builder(
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          // The tile is a 158px PressableSurface, whose raised base/shadow adds
          // hoverLift + baseDepth (8px) below the cap. Give the cell that extra
          // room so the base isn't clipped, matching the dialog's buttons.
          mainAxisExtent: 166,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: sources!.length,
        itemBuilder: (context, index) {
          final source = sources[index];
          final selected = live_display.liveScreenSourceSelected(
            source,
            selectedId: _state.selectedId,
            sourceId: (source) => source.id,
          );
          return _ScreenSourceTile(
            source: source,
            selected: selected,
            onPressed: () {
              setState(() {
                _state = live_display.liveScreenSourceSelectedChanged(
                  _state,
                  source.id,
                );
              });
            },
          );
        },
      ),
    };
  }
}

class _ScreenSourceTile extends StatelessWidget {
  const _ScreenSourceTile({
    required this.source,
    required this.selected,
    required this.onPressed,
  });

  final ScreenSource source;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableSurface(
      height: 158,
      selected: selected,
      onPressed: onPressed,
      backgroundColor: UiColors.surface,
      selectedBackgroundColor: UiColors.selected,
      borderColor: UiColors.border,
      selectedBorderColor: UiColors.accentBorder,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _ScreenSourceThumbnail(source: source)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                source.isWindow
                    ? Icons.web_asset_outlined
                    : Icons.desktop_windows_outlined,
                size: 14,
                color: selected ? UiColors.accent : UiColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: UiTypography.label.copyWith(
                    color: selected ? UiColors.text : UiColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScreenSourceThumbnail extends StatefulWidget {
  const _ScreenSourceThumbnail({required this.source});

  final ScreenSource source;

  @override
  State<_ScreenSourceThumbnail> createState() => _ScreenSourceThumbnailState();
}

class _ScreenSourceThumbnailState extends State<_ScreenSourceThumbnail> {
  Uint8List? _thumbnail;
  Object? _imageError;
  StreamSubscription<Uint8List>? _thumbnailSubscription;

  @override
  void initState() {
    super.initState();
    _bindSource(widget.source);
  }

  @override
  void didUpdateWidget(_ScreenSourceThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) _bindSource(widget.source);
  }

  @override
  void dispose() {
    unawaited(_thumbnailSubscription?.cancel());
    super.dispose();
  }

  void _bindSource(ScreenSource source) {
    unawaited(_thumbnailSubscription?.cancel());
    _thumbnail = source.thumbnail;
    _imageError = null;
    _thumbnailSubscription = source.thumbnailUpdates?.listen((thumbnail) {
      if (!mounted) return;
      setState(() {
        _thumbnail = thumbnail;
        _imageError = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final thumbnail = live_display.visibleLiveScreenSourceThumbnail(
      thumbnail: _thumbnail,
      imageError: _imageError,
    );
    if (thumbnail == null) return const _ScreenSourceThumbnailFallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(UiRadii.sm),
      child: ColoredBox(
        color: UiColors.surfacePressed,
        child: Image.memory(
          thumbnail,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _imageError = error);
            });
            return const _ScreenSourceThumbnailFallback();
          },
        ),
      ),
    );
  }
}

class _ScreenSourceThumbnailFallback extends StatelessWidget {
  const _ScreenSourceThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surfacePressed,
        borderRadius: BorderRadius.circular(UiRadii.sm),
      ),
      child: const Center(
        child: Icon(
          Icons.desktop_windows_outlined,
          color: UiColors.textMuted,
          size: 32,
        ),
      ),
    );
  }
}
