part of 'settings_page.dart';

class _StickerActionRow extends StatelessWidget {
  const _StickerActionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in children.asMap().entries) ...[
          if (entry.key > 0) const SizedBox(width: 10),
          Expanded(child: entry.value),
        ],
      ],
    );
  }
}

class _StickerGrid extends StatelessWidget {
  const _StickerGrid({
    required this.items,
    required this.managing,
    required this.selectionNumbers,
    required this.busy,
    required this.onTap,
  });

  final List<ManagedSticker> items;
  final bool managing;
  final Map<String, int> selectionNumbers;
  final bool busy;
  final ValueChanged<ManagedSticker> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final columns = (width / 92).floor().clamp(3, 9);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _StickerGridTile(
              item: item,
              managing: managing,
              selectionNumber: selectionNumbers[item.sticker.id],
              busy: busy,
              onTap: () => onTap(item),
            );
          },
        );
      },
    );
  }
}

class _StickerGridTile extends StatelessWidget {
  const _StickerGridTile({
    required this.item,
    required this.managing,
    required this.selectionNumber,
    required this.busy,
    required this.onTap,
  });

  final ManagedSticker item;
  final bool managing;
  final int? selectionNumber;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = selectionNumber != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileHeight = constraints.maxHeight.isFinite
            ? math.max(54.0, constraints.maxHeight - 6)
            : 86.0;
        return Tooltip(
          message: item.sticker.name,
          child: PressableSurface(
            onPressed: busy ? null : onTap,
            selected: selected,
            height: tileHeight,
            padding: const EdgeInsets.all(7),
            backgroundColor: _primaryDark,
            selectedBackgroundColor: const Color(0xFF1F2D27),
            pressedBackgroundColor: _primaryDarkLow,
            borderColor: selected ? _cyan : _borderColor,
            selectedBorderColor: _cyan,
            hoverLift: 2,
            baseDepth: 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: _StickerThumbnail(
                    sticker: item.sticker,
                    size: math.min(62, tileHeight - 18),
                  ),
                ),
                if (managing && selected)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.24),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          margin: const EdgeInsets.all(5),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _cyan,
                            border: Border.all(color: _primaryDark, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '$selectionNumber',
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: const TextStyle(
                                color: _primaryDark,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StickerThumbnail extends StatelessWidget {
  const _StickerThumbnail({required this.sticker, required this.size});

  final Sticker sticker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = sticker.asset;
    final imageUrl = AppConfigScope.of(
      context,
    ).resolveAssetUrl(asset.thumbnailUrl ?? asset.url);
    final fallback = ColoredBox(
      color: _primaryDarkLow,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: _textMuted,
          size: size * 0.38,
        ),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: _borderColor)),
        child: ClipRect(
          child: imageUrl == null
              ? fallback
              : Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _StickerFilterDialog extends StatefulWidget {
  const _StickerFilterDialog({required this.keyword, required this.mimeType});

  final String keyword;
  final String mimeType;

  @override
  State<_StickerFilterDialog> createState() => _StickerFilterDialogState();
}

class _StickerFilterDialogState extends State<_StickerFilterDialog> {
  late final TextEditingController _keywordController;
  late String _mimeType;

  static const _filters = [
    _StickerMimeFilter('', '全部'),
    _StickerMimeFilter('image/png', 'PNG'),
    _StickerMimeFilter('image/jpeg', 'JPG'),
    _StickerMimeFilter('image/webp', 'WebP'),
    _StickerMimeFilter('image/gif', 'GIF'),
  ];

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController(text: widget.keyword);
    _mimeType = widget.mimeType;
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  void _applyStickerFilterDraftPatch(StickerFilterDraftPatch patch) {
    _mimeType = patch.mimeType;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _primaryDarkLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '筛选',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _keywordController,
                autofocus: true,
                cursorColor: _textSecondary,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '名称关键字',
                ),
              ),
              const SizedBox(height: 16),
              const _FieldLabel('图片类型'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in _filters)
                    SizedBox(
                      width: 72,
                      child: PressableSurface(
                        onPressed: () => setState(
                          () => _applyStickerFilterDraftPatch(
                            stickerFilterMimeTypeChanged(
                              mimeType: filter.mimeType,
                            ),
                          ),
                        ),
                        selected: _mimeType == filter.mimeType,
                        height: 36,
                        padding: EdgeInsets.zero,
                        backgroundColor: _primaryDark,
                        selectedBackgroundColor: const Color(0xFF1F2D27),
                        pressedBackgroundColor: _primaryDarkLow,
                        borderColor: _mimeType == filter.mimeType
                            ? _cyan
                            : _borderColor,
                        selectedBorderColor: _cyan,
                        child: Center(
                          child: Text(
                            filter.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _mimeType == filter.mimeType
                                  ? _cyan
                                  : _textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Button(
                      onPressed: () {
                        _keywordController.clear();
                        setState(
                          () => _applyStickerFilterDraftPatch(
                            stickerFilterDraftReset(),
                          ),
                        );
                      },
                      width: double.infinity,
                      icon: const Icon(Icons.restart_alt),
                      child: const Text('重置'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Button(
                      onPressed: () => Navigator.of(context).pop(),
                      width: double.infinity,
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Button(
                      onPressed: () => Navigator.of(context).pop(
                        StickerFilterDraft(
                          keyword: _keywordController.text.trim(),
                          mimeType: _mimeType,
                        ),
                      ),
                      width: double.infinity,
                      tone: ButtonTone.primary,
                      icon: const Icon(Icons.check),
                      child: const Text('确认'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickerMimeFilter {
  const _StickerMimeFilter(this.mimeType, this.label);

  final String mimeType;
  final String label;
}

class _ConfirmActionDialog extends StatelessWidget {
  const _ConfirmActionDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.confirmIcon,
    this.danger = false,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final IconData confirmIcon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _primaryDarkLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(
          color: danger ? const Color(0xFF3A2A2E) : _borderColor,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: danger ? _danger : _textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  Button(
                    onPressed: () => Navigator.of(context).pop(true),
                    tone: danger ? ButtonTone.danger : ButtonTone.primary,
                    icon: Icon(confirmIcon),
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickerPreviewDialog extends StatefulWidget {
  const _StickerPreviewDialog({
    required this.item,
    required this.imageUrl,
    required this.clipboardService,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canPin,
    required this.onRename,
    required this.onSetAvatar,
    required this.onDownload,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onPin,
  });

  final ManagedSticker item;
  final String imageUrl;
  final ClipboardService clipboardService;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canPin;
  final Future<String?> Function(String name) onRename;
  final Future<void> Function() onSetAvatar;
  final Future<void> Function() onDownload;
  final Future<bool> Function() onDelete;
  final Future<sticker_ordering.StickerPlacementData?> Function() onMoveUp;
  final Future<sticker_ordering.StickerPlacementData?> Function() onMoveDown;
  final Future<sticker_ordering.StickerPlacementData?> Function() onPin;

  @override
  State<_StickerPreviewDialog> createState() => _StickerPreviewDialogState();
}

class _StickerPreviewDialogState extends State<_StickerPreviewDialog> {
  late final TextEditingController _nameController;
  late StickerPreviewState _previewState;

  Sticker get _sticker => widget.item.sticker;
  bool get _busy => _previewState.busy;
  bool get _canMoveUp => _previewState.canMoveUp;
  bool get _canMoveDown => _previewState.canMoveDown;
  bool get _canPin => _previewState.canPin;
  bool get _savingName => _previewState.savingName;
  bool get _settingAvatar => _previewState.settingAvatar;
  bool get _downloading => _previewState.downloading;
  bool get _deleting => _previewState.deleting;
  bool get _movingUp => _previewState.movingUp;
  bool get _movingDown => _previewState.movingDown;
  bool get _pinning => _previewState.pinning;
  String? get _error => _previewState.error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _sticker.name);
    _previewState = StickerPreviewState.initial(
      canMoveUp: widget.canMoveUp,
      canMoveDown: widget.canMoveDown,
      canPin: widget.canPin,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = stickerRenameName(_nameController.text);
    if (name == null) return;
    await _runPreviewAction<String?>(
      actionKind: StickerPreviewActionKind.rename,
      name: _nameController.text,
      action: () => widget.onRename(name),
      onSuccess: (actualName) {
        if (actualName == null) {
          setState(
            () => _previewState = stickerPreviewActionFailed(
              state: _previewState,
              action: StickerPreviewActionKind.rename,
              failure: '名称保存失败',
            ),
          );
        } else {
          _nameController.text = actualName;
          Navigator.of(context).pop();
        }
      },
    );
  }

  Future<void> _setAvatar() async {
    await _runPreviewAction<bool>(
      actionKind: StickerPreviewActionKind.setAvatar,
      action: () async {
        await widget.onSetAvatar();
        return true;
      },
    );
  }

  Future<void> _download() async {
    await _runPreviewAction<bool>(
      actionKind: StickerPreviewActionKind.download,
      action: () async {
        await widget.onDownload();
        return true;
      },
    );
  }

  Future<void> _delete() async {
    await _runPreviewAction<bool>(
      actionKind: StickerPreviewActionKind.delete,
      action: widget.onDelete,
      onSuccess: (deleted) {
        if (deleted && mounted) Navigator.of(context).pop();
      },
    );
  }

  Future<void> _move({
    required Future<sticker_ordering.StickerPlacementData?> Function() action,
    required StickerPreviewActionKind actionKind,
  }) async {
    await _runPreviewAction<sticker_ordering.StickerPlacementData?>(
      actionKind: actionKind,
      action: action,
      onSuccess: (placement) {
        if (placement == null) return;
        setState(
          () => _previewState = stickerPreviewMoveSucceeded(
            state: _previewState,
            action: actionKind,
            canMoveUp: placement.canMoveUp,
            canMoveDown: placement.canMoveDown,
            canPin: placement.canPin,
          ),
        );
      },
    );
  }

  Future<T?> _runPreviewAction<T>({
    required StickerPreviewActionKind actionKind,
    String? name,
    required Future<T> Function() action,
    void Function(T result)? onSuccess,
  }) async {
    final started = stickerPreviewActionRequested(
      state: _previewState,
      action: actionKind,
      name: name,
    );
    if (started == null) return null;
    setState(() => _previewState = started);
    try {
      final result = await action();
      if (!mounted) return result;
      onSuccess?.call(result);
      return result;
    } catch (e) {
      if (mounted) {
        setState(
          () => _previewState = stickerPreviewActionFailed(
            state: _previewState,
            action: actionKind,
            failure: e,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(
          () => _previewState = stickerPreviewActionFinished(
            state: _previewState,
            action: actionKind,
          ),
        );
      }
    }
  }

  Future<void> _copyName() async {
    await widget.clipboardService.writeText(_nameController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final asset = _sticker.asset;
    return Dialog(
      backgroundColor: _primaryDarkLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '表情预览',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  ButtonIcon(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '关闭预览',
                    icon: const Icon(Icons.close),
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 320,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _primaryDark,
                    border: Border.all(color: _borderColor),
                  ),
                  child: ClipRect(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: Center(
                        child: Image.network(
                          widget.imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: _textMuted,
                            size: 42,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                cursorColor: _textSecondary,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: '名称',
                  suffixIcon: ButtonIcon(
                    onPressed: _copyName,
                    tooltip: '复制名称',
                    icon: const Icon(Icons.copy),
                    size: 30,
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 38,
                    minHeight: 38,
                  ),
                ),
                onSubmitted: (_) => unawaited(_saveName()),
              ),
              const SizedBox(height: 8),
              _StickerDimensionsLine(asset: asset, imageUrl: widget.imageUrl),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _SettingsError(message: _error!),
              ],
              const SizedBox(height: 16),
              _StickerPreviewActionRow(
                children: [
                  Button(
                    onPressed: _busy ? null : _download,
                    loading: _downloading,
                    icon: const Icon(Icons.download_outlined),
                    width: double.infinity,
                    child: const Text('下载'),
                  ),
                  Button(
                    onPressed: _busy ? null : _setAvatar,
                    loading: _settingAvatar,
                    icon: const Icon(Icons.account_circle_outlined),
                    width: double.infinity,
                    child: const Text('设为头像'),
                  ),
                  Button(
                    onPressed:
                        canStartStickerRename(
                          busy: _busy,
                          name: _nameController.text,
                        )
                        ? _saveName
                        : null,
                    loading: _savingName,
                    tone: ButtonTone.primary,
                    icon: const Icon(Icons.save_outlined),
                    width: double.infinity,
                    child: const Text('保存名称'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _StickerPreviewActionRow(
                children: [
                  Button(
                    onPressed: _busy || !_canPin
                        ? null
                        : () => _move(
                            action: widget.onPin,
                            actionKind: StickerPreviewActionKind.pin,
                          ),
                    loading: _pinning,
                    icon: const Icon(Icons.vertical_align_top),
                    width: double.infinity,
                    child: const Text('置顶'),
                  ),
                  Button(
                    onPressed: _busy || !_canMoveUp
                        ? null
                        : () => _move(
                            action: widget.onMoveUp,
                            actionKind: StickerPreviewActionKind.moveUp,
                          ),
                    loading: _movingUp,
                    icon: const Icon(Icons.arrow_upward),
                    width: double.infinity,
                    child: const Text('上移一位'),
                  ),
                  Button(
                    onPressed: _busy || !_canMoveDown
                        ? null
                        : () => _move(
                            action: widget.onMoveDown,
                            actionKind: StickerPreviewActionKind.moveDown,
                          ),
                    loading: _movingDown,
                    icon: const Icon(Icons.arrow_downward),
                    width: double.infinity,
                    child: const Text('下移一位'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Button(
                onPressed: _busy ? null : _delete,
                loading: _deleting,
                tone: ButtonTone.danger,
                icon: const Icon(Icons.delete_outline),
                width: double.infinity,
                child: const Text('删除'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickerDimensionsLine extends StatefulWidget {
  const _StickerDimensionsLine({required this.asset, required this.imageUrl});

  final UploadedAsset asset;
  final String imageUrl;

  @override
  State<_StickerDimensionsLine> createState() => _StickerDimensionsLineState();
}

class _StickerDimensionsLineState extends State<_StickerDimensionsLine> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  StickerImageDimensions? _resolvedDimensions;
  bool _resolving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolveIfNeeded();
  }

  @override
  void didUpdateWidget(_StickerDimensionsLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset ||
        oldWidget.imageUrl != widget.imageUrl) {
      _resolvedDimensions = null;
      _failed = false;
      _resolveIfNeeded();
    }
  }

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }

  void _resolveIfNeeded() {
    if (widget.asset.width != null && widget.asset.height != null) {
      _removeListener();
      if (_resolving || _resolvedDimensions != null || _failed) {
        setState(() {
          _resolving = false;
          _resolvedDimensions = null;
          _failed = false;
        });
      }
      return;
    }
    _removeListener();
    _resolving = true;
    final stream = NetworkImage(
      widget.imageUrl,
    ).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (image, _) {
        if (!mounted) return;
        setState(() {
          _resolvedDimensions = StickerImageDimensions(
            width: image.image.width,
            height: image.image.height,
          );
          _resolving = false;
          _failed = false;
        });
      },
      onError: (_, _) {
        if (!mounted) return;
        setState(() {
          _resolving = false;
          _failed = true;
        });
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _removeListener() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    final dimensions = stickerDimensionsText(
      widget.asset,
      resolved: _resolvedDimensions,
      resolving: _resolving,
      failed: _failed,
    );
    return Text(
      '${widget.asset.mimeType} · $dimensions',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _StickerPreviewActionRow extends StatelessWidget {
  const _StickerPreviewActionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in children.asMap().entries) ...[
          if (entry.key > 0) const SizedBox(width: 10),
          Expanded(child: entry.value),
        ],
      ],
    );
  }
}
