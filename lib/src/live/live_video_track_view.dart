import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'live_session.dart';

enum LiveVideoTrackFit { cover, contain }

typedef LiveVideoTrackRendererBuilder =
    Widget Function(
      LiveVideoTrack track,
      LiveVideoTrackFit fit,
      bool mirrorLocal,
    );

@visibleForTesting
LiveVideoTrackRendererBuilder? liveVideoTrackRendererForTest;

@visibleForTesting
void resetLiveVideoTrackRendererForTest() {
  liveVideoTrackRendererForTest = null;
}

class LiveVideoTrackView extends StatelessWidget {
  const LiveVideoTrackView({
    super.key,
    required this.track,
    this.fit = LiveVideoTrackFit.contain,
    this.mirrorLocal = false,
  });

  final LiveVideoTrack track;
  final LiveVideoTrackFit fit;
  final bool mirrorLocal;

  @override
  Widget build(BuildContext context) {
    final testRenderer = liveVideoTrackRendererForTest;
    if (testRenderer != null) {
      return testRenderer(track, fit, mirrorLocal);
    }

    final mirrorMode = track.isScreenShare
        ? lk.VideoViewMirrorMode.off
        : mirrorLocal && track.isLocal
        ? lk.VideoViewMirrorMode.mirror
        : lk.VideoViewMirrorMode.auto;
    return lk.VideoTrackRenderer(
      track.track,
      fit: switch (fit) {
        LiveVideoTrackFit.cover => lk.VideoViewFit.cover,
        LiveVideoTrackFit.contain => lk.VideoViewFit.contain,
      },
      mirrorMode: mirrorMode,
    );
  }
}
