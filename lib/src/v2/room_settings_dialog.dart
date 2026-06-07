part of 'room_management.dart';

class RoomSettingsDialog extends StatefulWidget {
  const RoomSettingsDialog({
    super.key,
    required this.controller,
    required this.room,
    required this.currentUser,
    required this.isInLive,
    required this.onLeaveLive,
    required this.onRoomUpdated,
    this.embedded = false,
    this.onClose,
    this.onResult,
  });

  final RoomsController controller;
  final RoomDetail room;
  final CurrentUser currentUser;
  final bool isInLive;
  final Future<void> Function() onLeaveLive;
  final ValueChanged<RoomDetail> onRoomUpdated;
  final bool embedded;
  final VoidCallback? onClose;
  final ValueChanged<RoomManagementResult>? onResult;

  @override
  State<RoomSettingsDialog> createState() => _RoomSettingsDialogState();
}

class _RoomSettingsDialogState extends State<RoomSettingsDialog> {
  late RoomDetail _room;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _visibility;
  late String _joinPolicy;
  late bool _aiVoiceAnnouncementsEnabled;

  late String _defaultAvatarKey;
  late bool _usingPresetAvatar;
  String? _pendingAvatarAssetId;
  String? _pendingAvatarUrl;
  bool _uploadingAvatar = false;

  bool _saving = false;
  bool _leaving = false;
  bool _deleting = false;
  bool _changed = false;
  String? _error;
  String? _notice;

  bool get _canManageRoom => room_display
      .roomAccessState(room: _room, currentUser: widget.currentUser)
      .canManageRoom;

  bool get _canDeleteRoom => room_display
      .roomManagementPermissionState(
        room: _room,
        currentUser: widget.currentUser,
      )
      .canDeleteRoom;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _nameController = TextEditingController(text: _room.name);
    _descriptionController = TextEditingController(text: _room.description);
    _visibility = room_display.normalizeRoomVisibility(_room.visibility);
    _joinPolicy = room_display.normalizeRoomJoinPolicy(_room.joinPolicy);
    _aiVoiceAnnouncementsEnabled = _room.aiVoiceAnnouncementsEnabled;
    _defaultAvatarKey = _room.defaultAvatarKey;
    _usingPresetAvatar = _room.avatarUrl == null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _close() {
    if (widget.embedded) {
      if (_changed) widget.onResult?.call(RoomManagementResult.updated(_room));
      widget.onClose?.call();
      return;
    }
    Navigator.of(
      context,
    ).pop(_changed ? RoomManagementResult.updated(_room) : null);
  }

  void _emitResult(RoomManagementResult result) {
    if (widget.embedded) {
      widget.onResult?.call(result);
      widget.onClose?.call();
      return;
    }
    Navigator.of(context).pop(result);
  }

  Future<void> _save() async {
    if (_saving || _leaving || _deleting || !_canManageRoom) return;
    final draft = room_forms.roomInfoUpdateDraftFromForm(
      name: _nameController.text,
      description: _descriptionController.text,
      visibility: _visibility,
      joinPolicy: _joinPolicy,
      aiVoiceAnnouncementsEnabled: _aiVoiceAnnouncementsEnabled,
      pendingAvatarAssetId: _pendingAvatarAssetId,
      usingPresetAvatar: _usingPresetAvatar,
      defaultAvatarKey: _defaultAvatarKey,
    );
    if (!draft.isValid) {
      setState(() {
        _error = draft.error;
        _notice = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final updated = await widget.controller.updateRoom(
        roomId: _room.id,
        name: draft.name,
        description: draft.description,
        visibility: draft.visibility,
        joinPolicy: draft.joinPolicy,
        aiVoiceAnnouncementsEnabled: draft.aiVoiceAnnouncementsEnabled,
        avatarAssetId: draft.avatarAssetId,
        defaultAvatarKey: draft.defaultAvatarKey,
      );
      if (!mounted) return;
      setState(() {
        _room = updated;
        _defaultAvatarKey = updated.defaultAvatarKey;
        _usingPresetAvatar = updated.avatarUrl == null;
        _pendingAvatarAssetId = null;
        _pendingAvatarUrl = null;
        _saving = false;
        _changed = true;
        _notice = room_display.roomInfoSavedNotice();
      });
      widget.onRoomUpdated(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar || _saving) return;
    _CroppedRoomAvatar? cropped;
    try {
      cropped = await _pickAndCropRoomAvatar(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _notice = null;
      });
      return;
    }
    if (cropped == null || !mounted) return;
    setState(() {
      _uploadingAvatar = true;
      _error = null;
      _notice = null;
    });
    try {
      final asset = await widget.controller.uploadImageAsset(
        bytes: cropped.bytes,
        filename: cropped.filename,
        purpose: 'avatar',
      );
      if (!mounted) return;
      setState(() {
        _uploadingAvatar = false;
        _usingPresetAvatar = false;
        _pendingAvatarAssetId = asset.id;
        _pendingAvatarUrl = asset.url;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploadingAvatar = false;
        _error = error.toString();
      });
    }
  }

  void _selectPreset(String key) {
    setState(() {
      _usingPresetAvatar = true;
      _defaultAvatarKey = key;
      _pendingAvatarAssetId = null;
      _pendingAvatarUrl = null;
      _error = null;
    });
  }

  String? _avatarPreviewUrl(AppConfig appConfig) {
    return appConfig.resolveAssetUrl(
      room_display.roomManagementAvatarPath(
        usingPresetAvatar: _usingPresetAvatar,
        pendingAvatarUrl: _pendingAvatarUrl,
        roomAvatarUrl: _room.avatarUrl,
      ),
    );
  }

  Future<void> _leaveRoom() async {
    if (_saving || _leaving || _deleting) return;
    final confirmation = room_display.roomLeaveConfirmationSpec(
      room: _room,
      isInLive: widget.isInLive,
    );
    final confirmed = confirmation.requiresStrongConfirmation
        ? await showDialog<bool>(
            context: context,
            builder: (context) => _StrongConfirmDialog(
              title: confirmation.title,
              message: confirmation.body,
              expectedText: confirmation.expectedText!,
              confirmLabel: confirmation.confirmLabel,
            ),
          )
        : await showDialog<bool>(
            context: context,
            builder: (context) => _ConfirmDialog(
              title: confirmation.title,
              message: confirmation.body,
              confirmLabel: confirmation.confirmLabel,
              danger: true,
            ),
          );
    if (confirmed != true || !mounted) return;
    setState(() {
      _leaving = true;
      _error = null;
      _notice = null;
    });
    try {
      if (widget.isInLive) await widget.onLeaveLive();
      await widget.controller.leaveRoom(
        roomId: _room.id,
        confirmDeleteIfEmpty: confirmation.confirmDeleteIfEmpty,
      );
      if (!mounted) return;
      _emitResult(const RoomManagementResult.left());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _leaving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _deleteRoom() async {
    if (!_canDeleteRoom || _saving || _leaving || _deleting) return;
    final confirmation = room_display.roomDeletionConfirmationSpec(_room);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _StrongConfirmDialog(
        title: confirmation.title,
        message: confirmation.body,
        expectedText: confirmation.expectedText,
        confirmLabel: confirmation.confirmLabel,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
      _notice = null;
    });
    try {
      if (widget.isInLive) await widget.onLeaveLive();
      await widget.controller.deleteRoom(
        roomId: _room.id,
        confirmName: _room.name,
      );
      if (!mounted) return;
      _emitResult(const RoomManagementResult.deleted());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RoomDialogShell(
      title: 'Room settings',
      icon: Icons.tune,
      maxWidth: _dialogMaxWidth,
      maxHeight: _dialogMaxHeight,
      embedded: widget.embedded,
      onClose: _close,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (_notice != null) ...[
            _NoticeStrip(message: _notice!, icon: Icons.check_circle_outline),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            _NoticeStrip(message: _error!, danger: true),
            const SizedBox(height: 10),
          ],
          _SectionBox(
            title: 'Room info',
            child: Column(
              children: [
                const SizedBox(height: 6),
                AvatarPicker(
                  label: 'Room avatar',
                  displayName: _nameController.text.trim().isEmpty
                      ? room_display.roomDisplayName(_room)
                      : _nameController.text,
                  imageUrl: _avatarPreviewUrl(AppConfigScope.of(context)),
                  defaultAvatarKey: _defaultAvatarKey,
                  usingPreset: _usingPresetAvatar,
                  uploading: _uploadingAvatar,
                  enabled: _canManageRoom && !_saving,
                  onUpload: _pickAvatar,
                  onPresetSelected: _selectPreset,
                  presetKeys: const ['room-1', ...kAvatarPresetKeys],
                ),
                const SizedBox(height: 14),
                Input(
                  controller: _nameController,
                  hintText: 'Room name',
                  enabled: _canManageRoom && !_saving,
                  prefixIcon: Icons.tag_outlined,
                ),
                const SizedBox(height: 10),
                Input(
                  controller: _descriptionController,
                  hintText: 'Description',
                  enabled: _canManageRoom && !_saving,
                  prefixIcon: Icons.notes_outlined,
                  maxLines: null,
                ),
                const SizedBox(height: 12),
                _LabeledSegmented<String>(
                  label: 'Visibility',
                  value: _visibility,
                  enabled: _canManageRoom && !_saving,
                  segments: const [
                    Segment(value: 'private', label: 'Private'),
                    Segment(value: 'public', label: 'Public'),
                  ],
                  onChanged: (value) => setState(() => _visibility = value),
                ),
                const SizedBox(height: 12),
                _LabeledSegmented<String>(
                  label: 'Join policy',
                  value: _joinPolicy,
                  enabled: _canManageRoom && !_saving,
                  segments: const [
                    Segment(value: 'approval_required', label: 'Approval'),
                    Segment(value: 'open', label: 'Open'),
                    Segment(value: 'closed', label: 'Closed'),
                  ],
                  onChanged: (value) => setState(() => _joinPolicy = value),
                ),
                const SizedBox(height: 12),
                _ToggleRow(
                  label: 'AI voice announcements',
                  value: _aiVoiceAnnouncementsEnabled,
                  enabled: _canManageRoom && !_saving,
                  onChanged: (value) =>
                      setState(() => _aiVoiceAnnouncementsEnabled = value),
                ),
                const SizedBox(height: 14),
                Button(
                  width: double.infinity,
                  tone: ButtonTone.primary,
                  loading: _saving,
                  onPressed: _canManageRoom ? _save : null,
                  icon: const Icon(Icons.save_outlined),
                  child: const Text('Save room settings'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionBox(
            title: 'Leave room',
            child: Button(
              width: double.infinity,
              tone: ButtonTone.danger,
              loading: _leaving,
              onPressed: _leaveRoom,
              icon: const Icon(Icons.logout),
              child: const Text('Leave room'),
            ),
          ),
          if (_canDeleteRoom) ...[
            const SizedBox(height: 14),
            _SectionBox(
              title: 'Delete room',
              danger: true,
              child: Button(
                width: double.infinity,
                tone: ButtonTone.danger,
                loading: _deleting,
                onPressed: _deleteRoom,
                icon: const Icon(Icons.delete_forever_outlined),
                child: const Text('Delete room'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
