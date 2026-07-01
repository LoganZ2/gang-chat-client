import 'package:flutter/widgets.dart';

import '../app/media_cache_controller.dart';

final MediaCacheController _fallbackMediaCacheController =
    MediaCacheController();

class MediaCacheScope extends InheritedWidget {
  const MediaCacheScope({super.key, required this.cache, required super.child});

  final MediaCacheController cache;

  static MediaCacheController of(BuildContext context) {
    return maybeOf(context) ?? _fallbackMediaCacheController;
  }

  static MediaCacheController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MediaCacheScope>()?.cache;
  }

  @override
  bool updateShouldNotify(MediaCacheScope oldWidget) =>
      !identical(oldWidget.cache, cache);
}
