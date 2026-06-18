import 'dart:io';

import 'package:flutter/material.dart';

import '../app/media_cache_controller.dart';
import '../ui/ui.dart';

typedef CachedMediaImageErrorBuilder =
    Widget Function(BuildContext context, Object error, StackTrace? stackTrace);

class CachedMediaImage extends StatefulWidget {
  const CachedMediaImage({
    super.key,
    required this.cache,
    required this.request,
    this.width,
    this.height,
    this.fit,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final MediaCacheController cache;
  final MediaCacheRequest request;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final WidgetBuilder? loadingBuilder;
  final CachedMediaImageErrorBuilder? errorBuilder;

  @override
  State<CachedMediaImage> createState() => _CachedMediaImageState();
}

class _CachedMediaImageState extends State<CachedMediaImage> {
  late Future<File> _file;

  @override
  void initState() {
    super.initState();
    _file = widget.cache.getOrDownload(request: widget.request);
  }

  @override
  void didUpdateWidget(CachedMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cache, widget.cache) ||
        oldWidget.request.cacheKey != widget.request.cacheKey) {
      _file = widget.cache.getOrDownload(request: widget.request);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file != null) {
          return Image.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
          );
        }
        final error = snapshot.error;
        if (error != null) {
          return widget.errorBuilder?.call(
                context,
                error,
                snapshot.stackTrace,
              ) ??
              _DefaultCachedMediaError(
                width: widget.width,
                height: widget.height,
              );
        }
        return widget.loadingBuilder?.call(context) ??
            _DefaultCachedMediaLoading(
              width: widget.width,
              height: widget.height,
            );
      },
    );
  }
}

class _DefaultCachedMediaLoading extends StatelessWidget {
  const _DefaultCachedMediaLoading({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: UiColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _DefaultCachedMediaError extends StatelessWidget {
  const _DefaultCachedMediaError({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: UiColors.textMuted,
          size: 32,
        ),
      ),
    );
  }
}
