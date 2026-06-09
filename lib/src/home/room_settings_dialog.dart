part of 'room_management.dart';

enum _RoomSettingsDialogMode { create, edit }

/// 房间设置的分段:基础设置与房间表情包管理。
enum _RoomSettingsSection { settings, stickers }

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
    bool createMode = false,
  }) : _mode = createMode
           ? _RoomSettingsDialogMode.create
           : _RoomSettingsDialogMode.edit;

  factory RoomSettingsDialog.create({
    Key? key,
    required RoomsController controller,
    required CurrentUser currentUser,
    bool embedded = false,
    VoidCallback? onClose,
    ValueChanged<RoomManagementResult>? onResult,
  }) {
    return RoomSettingsDialog(
      key: key,
      controller: controller,
      room: _draftCreateRoom(currentUser),
      currentUser: currentUser,
      isInLive: false,
      onLeaveLive: () async {},
      onRoomUpdated: (_) {},
      embedded: embedded,
      onClose: onClose,
      onResult: onResult,
      createMode: true,
    );
  }

  final RoomsController controller;
  final RoomDetail room;
  final CurrentUser currentUser;
  final bool isInLive;
  final Future<void> Function() onLeaveLive;
  final ValueChanged<RoomDetail> onRoomUpdated;
  final bool embedded;
  final VoidCallback? onClose;
  final ValueChanged<RoomManagementResult>? onResult;
  final _RoomSettingsDialogMode _mode;

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

  bool get _creating => widget._mode == _RoomSettingsDialogMode.create;

  _RoomSettingsSection _section = _RoomSettingsSection.settings;

  bool get _canManageRoom =>
      _creating ||
      room_display
          .roomAccessState(room: _room, currentUser: widget.currentUser)
          .canManageRoom;

  bool get _canDeleteRoom =>
      !_creating &&
      room_display
          .roomManagementPermissionState(
            room: _room,
            currentUser: widget.currentUser,
          )
          .canDeleteRoom;

  String get _avatarDisplayName {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) return name;
    return _creating ? '房间' : room_display.roomDisplayName(_room);
  }

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
      if (!_creating && _changed) {
        widget.onResult?.call(RoomManagementResult.updated(_room));
      }
      widget.onClose?.call();
      return;
    }
    Navigator.of(
      context,
    ).pop(!_creating && _changed ? RoomManagementResult.updated(_room) : null);
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
      final updated = _creating
          ? await widget.controller.createRoom(
              name: draft.name!,
              description: draft.description,
              visibility: draft.visibility,
              joinPolicy: draft.joinPolicy,
              aiVoiceAnnouncementsEnabled: draft.aiVoiceAnnouncementsEnabled,
              avatarAssetId: draft.avatarAssetId,
              defaultAvatarKey: draft.defaultAvatarKey,
            )
          : await widget.controller.updateRoom(
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
      if (_creating) {
        _emitResult(RoomManagementResult.created(updated));
        return;
      }
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
      title: _creating ? '创建房间' : '房间设置',
      icon: _creating ? Icons.add_circle_outline : Icons.tune,
      maxWidth: _dialogMaxWidth,
      maxHeight: _dialogMaxHeight,
      embedded: widget.embedded,
      onClose: _close,
      pinned: _creating
          ? null
          : SegmentedControl<_RoomSettingsSection>(
              expanded: true,
              value: _section,
              onChanged: (section) => setState(() => _section = section),
              segments: const [
                Segment(
                  value: _RoomSettingsSection.settings,
                  label: '设置',
                  icon: Icons.tune,
                ),
                Segment(
                  value: _RoomSettingsSection.stickers,
                  label: '表情包',
                  icon: Icons.emoji_emotions_outlined,
                ),
              ],
            ),
      child: _creating
          ? _buildSettingsBody(context)
          : switch (_section) {
              _RoomSettingsSection.settings => _buildSettingsBody(context),
              _RoomSettingsSection.stickers => StickerManagerPanel(
                backend: _RoomStickerBackend(
                  controller: widget.controller,
                  roomId: _room.id,
                ),
                title: '房间表情包',
                unavailableText: '房间表情包需要登录后从服务端读取',
              ),
            },
    );
  }

  Widget _buildSettingsBody(BuildContext context) {
    return SettingsList(
      children: [
        if (_notice != null)
          _NoticeStrip(message: _notice!, icon: Icons.check_circle_outline),
        if (_error != null) _NoticeStrip(message: _error!, danger: true),
        SettingsCard(
          title: '房间信息',
          children: [
            AvatarPicker(
              label: '房间图标',
              displayName: _avatarDisplayName,
              imageUrl: _avatarPreviewUrl(AppConfigScope.of(context)),
              defaultAvatarKey: _defaultAvatarKey,
              usingPreset: _usingPresetAvatar,
              uploading: _uploadingAvatar,
              enabled: _canManageRoom && !_saving,
              onUpload: _pickAvatar,
              onPresetSelected: _selectPreset,
              presetKeys: const ['room-1', ...kAvatarPresetKeys],
              uploadLabel: '上传图标',
            ),
            Input(
              controller: _nameController,
              hintText: '房间名称',
              enabled: _canManageRoom && !_saving,
              prefixIcon: Icons.tag_outlined,
            ),
            Input(
              controller: _descriptionController,
              hintText: '简介',
              enabled: _canManageRoom && !_saving,
              prefixIcon: Icons.notes_outlined,
              maxLines: null,
            ),
            _LabeledSegmented<String>(
              label: '可见性',
              value: _visibility,
              enabled: _canManageRoom && !_saving,
              segments: const [
                Segment(value: 'private', label: '私密'),
                Segment(value: 'public', label: '公开'),
              ],
              onChanged: (value) => setState(() => _visibility = value),
            ),
            _LabeledSegmented<String>(
              label: '加入方式',
              value: _joinPolicy,
              enabled: _canManageRoom && !_saving,
              segments: const [
                Segment(value: 'approval_required', label: '需审批'),
                Segment(value: 'open', label: '开放'),
                Segment(value: 'closed', label: '关闭'),
              ],
              onChanged: (value) => setState(() => _joinPolicy = value),
            ),
            _ToggleRow(
              label: 'AI 语音播报',
              value: _aiVoiceAnnouncementsEnabled,
              enabled: _canManageRoom && !_saving,
              onChanged: (value) =>
                  setState(() => _aiVoiceAnnouncementsEnabled = value),
            ),
            Button(
              width: double.infinity,
              tone: ButtonTone.primary,
              loading: _saving,
              onPressed: _canManageRoom ? _save : null,
              icon: Icon(
                _creating ? Icons.check_circle_outline : Icons.save_outlined,
              ),
              child: Text(_creating ? '确定' : '保存房间设置'),
            ),
          ],
        ),
        if (!_creating)
          SettingsCard(
            title: '离开房间',
            children: [
              Button(
                width: double.infinity,
                tone: ButtonTone.danger,
                loading: _leaving,
                onPressed: _leaveRoom,
                icon: const Icon(Icons.logout),
                child: const Text('离开房间'),
              ),
            ],
          ),
        if (_canDeleteRoom)
          SettingsCard(
            title: '删除房间',
            danger: true,
            children: [
              Button(
                width: double.infinity,
                tone: ButtonTone.danger,
                loading: _deleting,
                onPressed: _deleteRoom,
                icon: const Icon(Icons.delete_forever_outlined),
                child: const Text('删除房间'),
              ),
            ],
          ),
      ],
    );
  }
}

RoomDetail _draftCreateRoom(CurrentUser currentUser) {
  final now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return RoomDetail(
    id: '__new_room__',
    name: '',
    visibility: 'public',
    joinPolicy: 'approval_required',
    avatarUrl: null,
    defaultAvatarKey: 'room-1',
    memberCount: 1,
    onlineMemberCount: 1,
    createdBy: currentUser.toSummary(),
    myMembership: RoomMembership(joinedAt: now, role: 'owner'),
    live: LiveState(
      roomId: '__new_room__',
      participantCount: 0,
      participants: const [],
      updatedAt: now,
    ),
    createdAt: now,
    updatedAt: now,
  );
}

/// 房间表情包的数据来源:把 [RoomsController] 的房间作用域接口适配到
/// 通用的 [StickerManagerPanel]。
class _RoomStickerBackend extends StickerManagerBackend {
  _RoomStickerBackend({required this.controller, required this.roomId});

  final RoomsController controller;
  final String roomId;

  @override
  StickerManagementScope get scope => StickerManagementScope.room;

  @override
  bool get hasApi => true;

  @override
  Future<List<StickerPack>> loadPacks() {
    return controller.listRoomStickerPacks(roomId);
  }

  @override
  Future<StickerPack> createDefaultPack({int? sortOrder}) {
    return controller.createRoomStickerPack(
      roomId: roomId,
      name: defaultStickerPackName(StickerManagementScope.room),
      sortOrder: sortOrder,
    );
  }

  @override
  Future<String> uploadImageAsset({
    required Uint8List bytes,
    required String filename,
    required String purpose,
  }) async {
    final asset = await controller.uploadImageAsset(
      bytes: bytes,
      filename: filename,
      purpose: purpose,
    );
    return asset.id;
  }

  @override
  Future<void> addSticker({
    required String packId,
    required String assetId,
    required String name,
    int? sortOrder,
  }) {
    return controller.addRoomSticker(
      roomId: roomId,
      packId: packId,
      assetId: assetId,
      name: name,
      sortOrder: sortOrder,
    );
  }

  @override
  Future<void> deleteSticker({
    required String packId,
    required String stickerId,
  }) {
    return controller.deleteRoomSticker(
      roomId: roomId,
      packId: packId,
      stickerId: stickerId,
    );
  }

  @override
  Future<String?> renameSticker({
    required String packId,
    required String stickerId,
    required String name,
  }) async {
    final updated = await controller.updateSticker(
      packId: packId,
      stickerId: stickerId,
      name: name,
    );
    return updated.name;
  }

  @override
  Future<void> reorderStickers({
    required String packId,
    required List<String> stickerIds,
  }) {
    return controller.reorderStickers(packId: packId, stickerIds: stickerIds);
  }

  @override
  Future<DownloadedFile> downloadStickers({required List<String> stickerIds}) {
    return controller.downloadStickers(stickerIds: stickerIds);
  }
}
