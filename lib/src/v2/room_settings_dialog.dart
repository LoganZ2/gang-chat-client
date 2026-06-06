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
  });

  final RoomsController controller;
  final RoomDetail room;
  final CurrentUser currentUser;
  final bool isInLive;
  final Future<void> Function() onLeaveLive;
  final ValueChanged<RoomDetail> onRoomUpdated;

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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(
      context,
    ).pop(_changed ? RoomManagementResult.updated(_room) : null);
  }

  Future<void> _save() async {
    if (_saving || _leaving || _deleting || !_canManageRoom) return;
    final draft = room_forms.roomInfoUpdateDraftFromForm(
      name: _nameController.text,
      description: _descriptionController.text,
      visibility: _visibility,
      joinPolicy: _joinPolicy,
      aiVoiceAnnouncementsEnabled: _aiVoiceAnnouncementsEnabled,
      usingPresetAvatar: false,
      defaultAvatarKey: _room.defaultAvatarKey,
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
      );
      if (!mounted) return;
      setState(() {
        _room = updated;
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
      Navigator.of(context).pop(const RoomManagementResult.left());
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
      Navigator.of(context).pop(const RoomManagementResult.deleted());
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
      maxWidth: 680,
      maxHeight: _dialogMaxHeight,
      onClose: _close,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _RoomSummaryLine(
            title: room_display.roomDisplayName(_room),
            subtitle: room_display.roomMemberSummary(_room),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 10),
            _NoticeStrip(message: _notice!, icon: Icons.check_circle_outline),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            _NoticeStrip(message: _error!, danger: true),
          ],
          const SizedBox(height: 14),
          _SectionBox(
            title: 'Room info',
            child: Column(
              children: [
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
