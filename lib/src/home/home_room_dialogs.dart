part of 'home_page.dart';

class _UserInfoDialog extends StatelessWidget {
  const _UserInfoDialog({
    required this.user,
    required this.room,
    required this.roomsSectionTitle,
    required this.commonRooms,
    required this.onOpenRoom,
    required this.onCopyUid,
  });

  final UserSummary user;
  final RoomDetail room;
  final String? roomsSectionTitle;
  final List<UserCommonRoom> commonRooms;
  final ValueChanged<String> onOpenRoom;
  final ValueChanged<String> onCopyUid;

  @override
  Widget build(BuildContext context) {
    final appConfig = AppConfigScope.of(context);
    final roleLabel = room_display.roomRoleLabel(
      user,
      ownerUserId: room.createdBy?.id,
    );
    final primaryName = room_display.userPrimaryName(user);
    final uidValue = room_display.userUidLabel(user);
    final signature = room_display.userSignatureText(user);
    final presenceLabel = room_display.userPresenceLabel(user);
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(
                    label: primaryName,
                    imageUrl: appConfig.resolveAssetUrl(user.avatarUrl),
                    defaultAvatarKey: user.defaultAvatarKey,
                    size: 72,
                    borderColor: _cyan,
                    borderWidth: 1.4,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _NameWithGender(
                            name: primaryName,
                            gender: user.gender,
                            maxLines: 2,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            room_display.userUsernameLabel(user),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _UserBadgesRow(
                            roleLabel: roleLabel,
                            presenceLabel: presenceLabel,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ButtonIcon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Divider(height: 1, color: _borderColor),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _UserInfoField(
                        label: 'UID',
                        value: uidValue,
                        trailing: ButtonIcon(
                          onPressed: () => onCopyUid(uidValue),
                          icon: const Icon(Icons.copy),
                          tooltip: '复制 UID',
                          size: 30,
                        ),
                      ),
                      if (signature != null)
                        _UserInfoField(label: '签名', value: signature),
                      if (roomsSectionTitle != null && commonRooms.isNotEmpty)
                        _CommonRoomsSection(
                          title: roomsSectionTitle!,
                          rooms: commonRooms,
                          onOpenRoom: (roomId) {
                            onOpenRoom(roomId);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BasicUserInfoDialog extends StatelessWidget {
  const _BasicUserInfoDialog({required this.user, required this.onCopyUid});

  final UserSummary user;
  final ValueChanged<String> onCopyUid;

  @override
  Widget build(BuildContext context) {
    final appConfig = AppConfigScope.of(context);
    final uidValue = room_display.userUidLabel(user);
    final primaryName = room_display.userPrimaryName(user);
    final signature = room_display.userSignatureText(user);
    final presenceLabel = room_display.userPresenceLabel(user);
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(
                    label: primaryName,
                    imageUrl: appConfig.resolveAssetUrl(user.avatarUrl),
                    defaultAvatarKey: user.defaultAvatarKey,
                    size: 64,
                    borderColor: _cyan,
                    borderWidth: 1.4,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NameWithGender(
                          name: primaryName,
                          gender: user.gender,
                          maxLines: 2,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          room_display.userUsernameLabel(user),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (presenceLabel != null) ...[
                          const SizedBox(height: 10),
                          _UserPresenceBadge(label: presenceLabel),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ButtonIcon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: _borderColor),
              _UserInfoField(
                label: 'UID',
                value: uidValue,
                trailing: ButtonIcon(
                  onPressed: () => onCopyUid(uidValue),
                  icon: const Icon(Icons.copy),
                  tooltip: '复制 UID',
                  size: 30,
                ),
              ),
              if (signature != null)
                _UserInfoField(label: '签名', value: signature),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameWithGender extends StatelessWidget {
  const _NameWithGender({
    required this.name,
    required this.gender,
    required this.style,
    this.maxLines = 1,
  });

  final String name;
  final String? gender;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final mark = genderMark(gender);
    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: name),
          if (mark != null)
            TextSpan(
              text: ' ${mark.symbol}',
              style: style.copyWith(color: mark.color),
            ),
        ],
      ),
    );
  }
}

class _CommonRoomsSection extends StatelessWidget {
  const _CommonRoomsSection({
    required this.title,
    required this.rooms,
    required this.onOpenRoom,
  });

  final String title;
  final List<UserCommonRoom> rooms;
  final ValueChanged<String> onOpenRoom;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 102,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in rooms.asMap().entries) ...[
                    if (entry.key > 0) const SizedBox(height: 8),
                    _CommonRoomLink(
                      room: entry.value,
                      onOpen: () => onOpenRoom(entry.value.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommonRoomLink extends StatelessWidget {
  const _CommonRoomLink({required this.room, required this.onOpen});

  final UserCommonRoom room;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final appConfig = AppConfigScope.of(context);
    final title = room_display.commonRoomDisplayName(room);
    final avatarLabel = room_display.commonRoomAvatarLabel(room);
    final rid = room.rid.trim().isEmpty ? room.id : room.rid;
    final meta = room_display.commonRoomMeta(room);
    return Tooltip(
      message: '查看房间信息',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(
                label: avatarLabel,
                imageUrl: appConfig.resolveAssetUrl(room.avatarUrl),
                defaultAvatarKey: room.defaultAvatarKey,
                size: 30,
                borderColor: _borderColor,
                borderWidth: 1,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _cyan,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rid,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (meta != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserBadgesRow extends StatelessWidget {
  const _UserBadgesRow({required this.roleLabel, required this.presenceLabel});

  final String roleLabel;
  final String? presenceLabel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _UserRoleBadge(label: roleLabel),
        if (presenceLabel != null) _UserPresenceBadge(label: presenceLabel!),
      ],
    );
  }
}

class _UserRoleBadge extends StatelessWidget {
  const _UserRoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _selectedSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF22332B)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _cyan,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _UserPresenceBadge extends StatelessWidget {
  const _UserPresenceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final online = label == '在线';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: online ? const Color(0xFF153327) : const Color(0xFF2A2C34),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: online ? const Color(0xFF2C6F51) : const Color(0xFF3A3E4A),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: online ? _cyan : _textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _UserInfoField extends StatelessWidget {
  const _UserInfoField({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 102,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: SelectableText(
                value,
                maxLines: 3,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 14,
                  height: 1.36,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class _RoomInfoDialog extends StatefulWidget {
  const _RoomInfoDialog({
    required this.controller,
    required this.room,
    required this.currentUser,
    required this.clipboardService,
    required this.fileSelectionService,
    required this.isInLive,
    required this.onLeaveLive,
    required this.onOpenUserInfo,
  });

  final RoomsController controller;
  final RoomDetail room;
  final CurrentUser currentUser;
  final ClipboardService clipboardService;
  final FileSelectionService fileSelectionService;
  final bool isInLive;
  final Future<void> Function() onLeaveLive;
  final ValueChanged<UserSummary> onOpenUserInfo;

  @override
  State<_RoomInfoDialog> createState() => _RoomInfoDialogState();
}

class _RoomInfoDialogState extends State<_RoomInfoDialog> {
  late final TextEditingController _remarkController;
  late final TextEditingController _roomDisplayNameController;
  late String _notificationPolicy;
  late String _defaultAvatarKey;
  String? _pendingAvatarAssetId;
  String? _pendingAvatarUrl;
  bool _usingGlobalProfile = false;
  late bool _usingProfilePresetAvatar;
  bool _saving = false;
  bool _leaving = false;
  bool _uploadingAvatar = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    final profile = widget.room.personalProfile;
    _remarkController = TextEditingController(
      text: widget.room.remarkName ?? '',
    );
    _roomDisplayNameController = TextEditingController(
      text: profile.displayName ?? '',
    );
    _notificationPolicy = room_display.normalizeRoomNotificationPolicy(
      widget.room.notificationPolicy,
    );
    _defaultAvatarKey =
        profile.defaultAvatarKey ?? widget.currentUser.defaultAvatarKey;
    _usingProfilePresetAvatar =
        profile.avatarUrl == null && profile.defaultAvatarKey != null;
  }

  @override
  void dispose() {
    _remarkController.dispose();
    _roomDisplayNameController.dispose();
    super.dispose();
  }

  void _applyRoomProfileDialogPatch(RoomProfileDialogStatePatch patch) {
    _pendingAvatarAssetId = patch.pendingAvatarAssetId;
    _pendingAvatarUrl = patch.pendingAvatarUrl;
    _usingGlobalProfile = patch.usingGlobalProfile;
    _usingProfilePresetAvatar = patch.usingProfilePresetAvatar;
    _defaultAvatarKey = patch.defaultAvatarKey;
    _saving = patch.saving;
    _leaving = patch.leaving;
    _uploadingAvatar = patch.uploadingAvatar;
    _error = patch.error;
    _notice = patch.notice;
  }

  void _applyRoomProfileNotificationPolicyPatch(
    RoomProfileNotificationPolicyPatch patch,
  ) {
    _notificationPolicy = patch.notificationPolicy;
  }

  Future<void> _copyText(String value, String label) async {
    try {
      await widget.clipboardService.writeText(value);
      if (!mounted) return;
      setState(() {
        _applyRoomProfileDialogPatch(
          roomProfileCopySucceeded(
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            usingGlobalProfile: _usingGlobalProfile,
            usingProfilePresetAvatar: _usingProfilePresetAvatar,
            defaultAvatarKey: _defaultAvatarKey,
            saving: _saving,
            leaving: _leaving,
            uploadingAvatar: _uploadingAvatar,
            label: label,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomProfileDialogPatch(
          roomProfileCopyFailed(
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            usingGlobalProfile: _usingGlobalProfile,
            usingProfilePresetAvatar: _usingProfilePresetAvatar,
            defaultAvatarKey: _defaultAvatarKey,
            saving: _saving,
            leaving: _leaving,
            uploadingAvatar: _uploadingAvatar,
            notice: _notice,
            failure: e,
          ),
        );
      });
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    _CroppedAvatarFile? cropped;
    try {
      cropped = await _pickAndCropAvatarFile(
        context,
        fileSelectionService: widget.fileSelectionService,
        title: '裁剪房间内头像',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomProfileDialogPatch(
          roomProfileAvatarPickFailed(
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            usingGlobalProfile: _usingGlobalProfile,
            usingProfilePresetAvatar: _usingProfilePresetAvatar,
            defaultAvatarKey: _defaultAvatarKey,
            saving: _saving,
            leaving: _leaving,
            uploadingAvatar: _uploadingAvatar,
            notice: _notice,
            failure: e,
          ),
        );
      });
      return;
    }
    if (cropped == null) return;

    setState(() {
      _applyRoomProfileDialogPatch(
        roomProfileAvatarUploadStarted(
          pendingAvatarAssetId: _pendingAvatarAssetId,
          pendingAvatarUrl: _pendingAvatarUrl,
          usingGlobalProfile: _usingGlobalProfile,
          usingProfilePresetAvatar: _usingProfilePresetAvatar,
          defaultAvatarKey: _defaultAvatarKey,
          saving: _saving,
          leaving: _leaving,
        ),
      );
    });
    try {
      final asset = await widget.controller.uploadImageAsset(
        bytes: cropped.bytes,
        filename: cropped.filename,
        purpose: 'avatar',
      );
      if (!mounted) return;
      setState(() {
        _applyRoomProfileDialogPatch(
          roomProfileAvatarUploadSucceeded(
            assetId: asset.id,
            assetUrl: asset.url,
            defaultAvatarKey: _defaultAvatarKey,
            saving: _saving,
            leaving: _leaving,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomProfileDialogPatch(
          roomProfileAvatarUploadFailed(
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            usingGlobalProfile: _usingGlobalProfile,
            usingProfilePresetAvatar: _usingProfilePresetAvatar,
            defaultAvatarKey: _defaultAvatarKey,
            saving: _saving,
            leaving: _leaving,
            failure: e,
          ),
        );
      });
    }
  }

  void _useGlobalProfile() {
    setState(() {
      _roomDisplayNameController.clear();
      _applyRoomProfileDialogPatch(
        roomProfileUseGlobalProfile(
          currentUserDefaultAvatarKey: widget.currentUser.defaultAvatarKey,
          saving: _saving,
          leaving: _leaving,
          uploadingAvatar: _uploadingAvatar,
        ),
      );
    });
  }

  Future<void> _save() async {
    if (!canStartRoomProfileSave(saving: _saving, leaving: _leaving)) return;
    final draft = roomProfileUpdateDraftFromForm(
      remarkName: _remarkController.text,
      notificationPolicy: _notificationPolicy,
      usingGlobalProfile: _usingGlobalProfile,
      roomDisplayName: _roomDisplayNameController.text,
      pendingAvatarAssetId: _pendingAvatarAssetId,
      usingProfilePresetAvatar: _usingProfilePresetAvatar,
      defaultAvatarKey: _defaultAvatarKey,
    );
    setState(() {
      _applyRoomProfileDialogPatch(
        roomProfileSaveStarted(
          pendingAvatarAssetId: _pendingAvatarAssetId,
          pendingAvatarUrl: _pendingAvatarUrl,
          usingGlobalProfile: _usingGlobalProfile,
          usingProfilePresetAvatar: _usingProfilePresetAvatar,
          defaultAvatarKey: _defaultAvatarKey,
          leaving: _leaving,
          uploadingAvatar: _uploadingAvatar,
        ),
      );
    });
    try {
      final updated = await widget.controller.updateMyRoomSettings(
        roomId: widget.room.id,
        remarkName: draft.remarkName,
        notificationPolicy: draft.notificationPolicy,
        roomDisplayName: draft.roomDisplayName,
        avatarAssetId: draft.avatarAssetId,
        defaultAvatarKey: draft.defaultAvatarKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomProfileDialogPatch(
          roomProfileSaveFailed(
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            usingGlobalProfile: _usingGlobalProfile,
            usingProfilePresetAvatar: _usingProfilePresetAvatar,
            defaultAvatarKey: _defaultAvatarKey,
            leaving: _leaving,
            uploadingAvatar: _uploadingAvatar,
            failure: e,
          ),
        );
      });
    }
  }

  Future<void> _leaveRoom() async {
    if (!canStartRoomLeave(saving: _saving, leaving: _leaving)) return;
    final confirmation = room_display.roomLeaveConfirmationSpec(
      room: widget.room,
      isInLive: widget.isInLive,
    );
    final confirmed = confirmation.requiresStrongConfirmation
        ? await showDialog<bool>(
            context: context,
            builder: (context) => _StrongConfirmDialog(
              title: confirmation.title,
              body: confirmation.body,
              expectedText: confirmation.expectedText!,
              confirmLabel: confirmation.confirmLabel,
              confirmIcon: Icons.logout,
            ),
          )
        : await showDialog<bool>(
            context: context,
            builder: (context) => _ConfirmActionDialog(
              title: confirmation.title,
              body: confirmation.body,
              confirmLabel: confirmation.confirmLabel,
              confirmIcon: Icons.logout,
              danger: true,
            ),
          );
    if (confirmed != true || !mounted) return;

    setState(() {
      _applyRoomProfileDialogPatch(
        roomProfileLeaveStarted(
          pendingAvatarAssetId: _pendingAvatarAssetId,
          pendingAvatarUrl: _pendingAvatarUrl,
          usingGlobalProfile: _usingGlobalProfile,
          usingProfilePresetAvatar: _usingProfilePresetAvatar,
          defaultAvatarKey: _defaultAvatarKey,
          saving: _saving,
          uploadingAvatar: _uploadingAvatar,
        ),
      );
    });
    try {
      if (widget.isInLive) {
        await widget.onLeaveLive();
      }
      await widget.controller.leaveRoom(
        roomId: widget.room.id,
        confirmDeleteIfEmpty: confirmation.confirmDeleteIfEmpty,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_RoomDialogCloseResult.left);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomProfileDialogPatch(
          roomProfileLeaveFailed(
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            usingGlobalProfile: _usingGlobalProfile,
            usingProfilePresetAvatar: _usingProfilePresetAvatar,
            defaultAvatarKey: _defaultAvatarKey,
            saving: _saving,
            uploadingAvatar: _uploadingAvatar,
            failure: e,
          ),
        );
      });
    }
  }

  String? _profileAvatarPreviewUrl(AppConfig appConfig) {
    return appConfig.resolveAssetUrl(
      room_display.roomProfileAvatarPath(
        usingGlobalProfile: _usingGlobalProfile,
        currentUserAvatarUrl: widget.currentUser.avatarUrl,
        pendingAvatarUrl: _pendingAvatarUrl,
        usingPresetAvatar: _usingProfilePresetAvatar,
        personalAvatarUrl: widget.room.personalProfile.avatarUrl,
      ),
    );
  }

  bool get _profileUploadedAvatarSelected {
    return room_display.roomProfileUploadedAvatarSelected(
      usingGlobalProfile: _usingGlobalProfile,
      usingPresetAvatar: _usingProfilePresetAvatar,
      pendingAvatarUrl: _pendingAvatarUrl,
      personalAvatarUrl: widget.room.personalProfile.avatarUrl,
    );
  }

  bool get _profilePresetAvatarSelected {
    return room_display.roomProfilePresetAvatarSelected(
      usingGlobalProfile: _usingGlobalProfile,
      usingPresetAvatar: _usingProfilePresetAvatar,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = AppConfigScope.of(context);
    final resolvedProfileAvatar = _profileAvatarPreviewUrl(appConfig);
    final profileName = room_display.roomProfileDisplayName(
      usingGlobalProfile: _usingGlobalProfile,
      currentUserDisplayName: widget.currentUser.displayName,
      roomDisplayNameText: _roomDisplayNameController.text,
    );
    final roomDescription = room_display.roomDescriptionValue(widget.room);

    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Column(
          children: [
            _RoomDialogHeader(
              title: '房间信息',
              onClose: () => Navigator.of(context).pop(),
            ),
            _RoomDialogRoomSummary(
              roomName: room_display.roomDisplayName(widget.room),
              subtitle: room_display.roomMemberSummary(widget.room),
              avatarLabel: widget.room.name,
              avatarUrl: appConfig.resolveAssetUrl(widget.room.avatarUrl),
              defaultAvatarKey: widget.room.defaultAvatarKey,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                children: [
                  if (_notice != null) ...[
                    _RoomNotice(message: _notice!),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null) ...[
                    _RoomError(message: _error!),
                    const SizedBox(height: 12),
                  ],
                  _RoomSettingsGroup(
                    title: '基础信息',
                    children: [
                      if (widget.room.createdBy != null) ...[
                        _RoomCreatorField(
                          user: widget.room.createdBy!,
                          onOpen: () {
                            widget.onOpenUserInfo(widget.room.createdBy!);
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      _CopyableRoomField(
                        label: '房间永久 RID',
                        value: room_display.roomIdentifier(widget.room),
                        onCopy: () => _copyText(
                          room_display.roomIdentifier(widget.room),
                          'RID',
                        ),
                      ),
                      if (roomDescription != null) ...[
                        const SizedBox(height: 14),
                        _CopyableRoomField(
                          label: '房间介绍',
                          value: roomDescription,
                          maxLines: 3,
                          onCopy: () => _copyText(roomDescription, '房间介绍'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  _RoomSettingsGroup(
                    title: '我的房间设置',
                    children: [
                      _RoomTextField(
                        label: '房间备注名',
                        controller: _remarkController,
                        helperText: '仅影响你的房间列表，显示为“备注名 (原房间名)”。',
                      ),
                      const SizedBox(height: 14),
                      _RoomTextField(
                        label: '房间内昵称',
                        controller: _roomDisplayNameController,
                        helperText: '为空时使用全局默认用户名。',
                      ),
                      const SizedBox(height: 14),
                      _RoomAvatarPicker(
                        label: '房间内头像',
                        displayName: profileName,
                        avatarUrl: resolvedProfileAvatar,
                        defaultAvatarKey: _defaultAvatarKey,
                        uploadedSelected: _profileUploadedAvatarSelected,
                        presetSelected: _profilePresetAvatarSelected,
                        uploading: _uploadingAvatar,
                        avatarKeys: _RoomAvatarPicker.profileKeys,
                        uploadLabel: '上传头像',
                        presetLabel: '预设头像',
                        onUpload: _pickAvatar,
                        onPresetChanged: (key) => setState(() {
                          _applyRoomProfileDialogPatch(
                            roomProfileUsePresetAvatar(
                              defaultAvatarKey: key,
                              saving: _saving,
                              leaving: _leaving,
                              uploadingAvatar: _uploadingAvatar,
                              error: _error,
                              notice: _notice,
                            ),
                          );
                        }),
                        onUsePreset: () => setState(() {
                          _applyRoomProfileDialogPatch(
                            roomProfileUsePresetAvatar(
                              defaultAvatarKey: _defaultAvatarKey,
                              saving: _saving,
                              leaving: _leaving,
                              uploadingAvatar: _uploadingAvatar,
                              error: _error,
                              notice: _notice,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Button(
                          onPressed: _useGlobalProfile,
                          height: 34,
                          icon: const Icon(Icons.person_outline),
                          child: const Text('使用全局默认资料'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _RoomSegmentedSetting(
                        label: '消息通知',
                        value: _notificationPolicy,
                        options: const [
                          _RoomOption('all', '全部消息'),
                          _RoomOption('mentions', '仅提及'),
                          _RoomOption('muted', '免打扰'),
                        ],
                        onChanged: (value) => setState(
                          () => _applyRoomProfileNotificationPolicyPatch(
                            roomProfileNotificationPolicyChanged(
                              notificationPolicy: value,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _RoomSettingsGroup(
                    title: '退出房间',
                    danger: true,
                    children: [
                      Button(
                        onPressed:
                            canStartRoomLeave(
                              saving: _saving,
                              leaving: _leaving,
                            )
                            ? _leaveRoom
                            : null,
                        loading: _leaving,
                        tone: ButtonTone.danger,
                        icon: const Icon(Icons.logout),
                        width: double.infinity,
                        child: const Text('退出房间'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _RoomDialogFooter(
              saving: _saving,
              onCancel: () => Navigator.of(context).pop(),
              onSave: _save,
              saveLabel: '保存房间信息',
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomManagementDialog extends StatefulWidget {
  const _RoomManagementDialog({
    required this.controller,
    required this.room,
    required this.currentUser,
    required this.fileSelectionService,
  });

  final RoomsController controller;
  final RoomDetail room;
  final CurrentUser currentUser;
  final FileSelectionService fileSelectionService;

  @override
  State<_RoomManagementDialog> createState() => _RoomManagementDialogState();
}

class _RoomManagementDialogState extends State<_RoomManagementDialog> {
  late RoomDetail _room;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _visibility;
  late String _joinPolicy;
  late bool _aiVoiceAnnouncementsEnabled;
  late String _defaultAvatarKey;
  String? _pendingAvatarAssetId;
  String? _pendingAvatarUrl;
  late bool _usingPresetAvatar;
  bool _uploadingAvatar = false;
  bool _saving = false;
  bool _deleting = false;
  bool _loadingMembers = false;
  bool _changed = false;
  String? _error;
  String? _notice;
  RoomManagementSection _section = RoomManagementSection.info;
  List<RoomMember> _members = const [];
  final Set<String> _busyMemberIds = <String>{};

  bool get _canEditCreatorOnly => room_display
      .roomManagementPermissionState(
        room: _room,
        currentUser: widget.currentUser,
      )
      .canEditCreatorOnly;

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
    _loadMembers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop(_changed ? _room : null);

  void _applyRoomMemberManagementPatch(
    member_filter.RoomMemberManagementPatch patch,
  ) {
    _room = patch.room;
    _members = patch.members;
    _busyMemberIds
      ..clear()
      ..addAll(patch.busyMemberIds);
    _changed = patch.changed;
    _error = patch.error;
    _notice = patch.notice;
  }

  void _applyRoomMemberLoadPatch(member_filter.RoomMemberLoadPatch patch) {
    _members = patch.members;
    _loadingMembers = patch.loading;
    _error = patch.error;
  }

  void _applyRoomManagementDialogPatch(RoomManagementDialogStatePatch patch) {
    _section = patch.section;
    _room = patch.room;
    _pendingAvatarAssetId = patch.pendingAvatarAssetId;
    _pendingAvatarUrl = patch.pendingAvatarUrl;
    _usingPresetAvatar = patch.usingPresetAvatar;
    _defaultAvatarKey = patch.defaultAvatarKey;
    _uploadingAvatar = patch.uploadingAvatar;
    _saving = patch.saving;
    _deleting = patch.deleting;
    _changed = patch.changed;
    _error = patch.error;
    _notice = patch.notice;
  }

  void _applyRoomManagementInfoFieldsPatch(
    RoomManagementInfoFieldsPatch patch,
  ) {
    _visibility = patch.visibility;
    _joinPolicy = patch.joinPolicy;
    _aiVoiceAnnouncementsEnabled = patch.aiVoiceAnnouncementsEnabled;
  }

  Future<void> _loadMembers() async {
    if (_loadingMembers) return;
    setState(() {
      _applyRoomMemberLoadPatch(
        member_filter.roomMembersLoadStarted(members: _members),
      );
    });
    try {
      final members = await widget.controller.loadAllRoomMembers(_room.id);
      if (!mounted) return;
      setState(() {
        _applyRoomMemberLoadPatch(
          member_filter.roomMembersLoadSucceeded(members: members),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomMemberLoadPatch(
          member_filter.roomMembersLoadFailed(members: _members, failure: e),
        );
      });
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    _CroppedAvatarFile? cropped;
    try {
      cropped = await _pickAndCropAvatarFile(
        context,
        fileSelectionService: widget.fileSelectionService,
        title: '裁剪房间图标',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomManagementDialogPatch(
          roomManagementAvatarPickFailed(
            section: _section,
            room: _room,
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            usingPresetAvatar: _usingPresetAvatar,
            defaultAvatarKey: _defaultAvatarKey,
            uploadingAvatar: _uploadingAvatar,
            saving: _saving,
            deleting: _deleting,
            changed: _changed,
            notice: _notice,
            failure: e,
          ),
        );
      });
      return;
    }
    if (cropped == null) return;
    setState(() {
      _applyRoomManagementDialogPatch(
        roomManagementAvatarUploadStarted(
          section: _section,
          room: _room,
          pendingAvatarAssetId: _pendingAvatarAssetId,
          pendingAvatarUrl: _pendingAvatarUrl,
          usingPresetAvatar: _usingPresetAvatar,
          defaultAvatarKey: _defaultAvatarKey,
          saving: _saving,
          deleting: _deleting,
          changed: _changed,
        ),
      );
    });
    try {
      final asset = await widget.controller.uploadImageAsset(
        bytes: cropped.bytes,
        filename: cropped.filename,
        purpose: 'avatar',
      );
      if (!mounted) return;
      setState(() {
        _applyRoomManagementDialogPatch(
          roomManagementAvatarUploadSucceeded(
            section: _section,
            room: _room,
            assetId: asset.id,
            assetUrl: asset.url,
            defaultAvatarKey: _defaultAvatarKey,
            saving: _saving,
            deleting: _deleting,
            changed: _changed,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomManagementDialogPatch(
          roomManagementAvatarUploadFailed(
            section: _section,
            room: _room,
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            usingPresetAvatar: _usingPresetAvatar,
            defaultAvatarKey: _defaultAvatarKey,
            saving: _saving,
            deleting: _deleting,
            changed: _changed,
            failure: e,
          ),
        );
      });
    }
  }

  Future<void> _saveInfo() async {
    if (!canStartRoomInfoSave(saving: _saving, deleting: _deleting)) return;
    final draft = roomInfoUpdateDraftFromForm(
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
        _applyRoomManagementDialogPatch(
          roomManagementInfoDraftInvalid(
            section: _section,
            room: _room,
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            usingPresetAvatar: _usingPresetAvatar,
            defaultAvatarKey: _defaultAvatarKey,
            uploadingAvatar: _uploadingAvatar,
            saving: _saving,
            deleting: _deleting,
            changed: _changed,
            notice: _notice,
            error: draft.error,
          ),
        );
      });
      return;
    }
    setState(() {
      _applyRoomManagementDialogPatch(
        roomManagementInfoSaveStarted(
          section: _section,
          room: _room,
          pendingAvatarAssetId: _pendingAvatarAssetId,
          pendingAvatarUrl: _pendingAvatarUrl,
          usingPresetAvatar: _usingPresetAvatar,
          defaultAvatarKey: _defaultAvatarKey,
          uploadingAvatar: _uploadingAvatar,
          deleting: _deleting,
          changed: _changed,
        ),
      );
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
        _applyRoomManagementDialogPatch(
          roomManagementInfoSaveSucceeded(
            section: _section,
            updatedRoom: updated,
            defaultAvatarKey: _defaultAvatarKey,
            uploadingAvatar: _uploadingAvatar,
            deleting: _deleting,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomManagementDialogPatch(
          roomManagementInfoSaveFailed(
            section: _section,
            room: _room,
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            usingPresetAvatar: _usingPresetAvatar,
            defaultAvatarKey: _defaultAvatarKey,
            uploadingAvatar: _uploadingAvatar,
            deleting: _deleting,
            changed: _changed,
            failure: e,
          ),
        );
      });
    }
  }

  Future<void> _deleteRoom() async {
    if (!canStartRoomDeletion(
      canDeleteRoom: _canDeleteRoom,
      saving: _saving,
      deleting: _deleting,
    )) {
      return;
    }
    final confirmation = room_display.roomDeletionConfirmationSpec(_room);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _StrongConfirmDialog(
        title: confirmation.title,
        body: confirmation.body,
        expectedText: confirmation.expectedText,
        confirmLabel: confirmation.confirmLabel,
        confirmIcon: Icons.delete_forever_outlined,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _applyRoomManagementDialogPatch(
        roomManagementDeletionStarted(
          section: _section,
          room: _room,
          pendingAvatarAssetId: _pendingAvatarAssetId,
          pendingAvatarUrl: _pendingAvatarUrl,
          usingPresetAvatar: _usingPresetAvatar,
          defaultAvatarKey: _defaultAvatarKey,
          uploadingAvatar: _uploadingAvatar,
          saving: _saving,
          changed: _changed,
        ),
      );
    });
    try {
      await widget.controller.deleteRoom(
        roomId: _room.id,
        confirmName: _room.name,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_RoomDialogCloseResult.deleted);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomManagementDialogPatch(
          roomManagementDeletionFailed(
            section: _section,
            room: _room,
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            usingPresetAvatar: _usingPresetAvatar,
            defaultAvatarKey: _defaultAvatarKey,
            uploadingAvatar: _uploadingAvatar,
            saving: _saving,
            changed: _changed,
            failure: e,
          ),
        );
      });
    }
  }

  Future<void> _setMemberRole(RoomMember member, String role) async {
    if (!member_filter.canStartRoomMemberAction(
      userId: member.user.id,
      busyMemberIds: _busyMemberIds,
    )) {
      return;
    }
    setState(() {
      _applyRoomMemberManagementPatch(
        member_filter.roomMemberManagementActionStarted(
          room: _room,
          members: _members,
          changed: _changed,
          userId: member.user.id,
          busyMemberIds: _busyMemberIds,
        ),
      );
    });
    try {
      final updated = await widget.controller.updateRoomMemberRole(
        roomId: _room.id,
        userId: member.user.id,
        role: role,
      );
      if (!mounted) return;
      setState(() {
        _applyRoomMemberManagementPatch(
          member_filter.roomMemberRoleUpdateSucceeded(
            room: _room,
            members: _members,
            updated: updated,
            role: role,
            busyMemberIds: _busyMemberIds,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomMemberManagementPatch(
          member_filter.roomMemberRoleUpdateFailed(
            room: _room,
            members: _members,
            changed: _changed,
            userId: member.user.id,
            busyMemberIds: _busyMemberIds,
            failure: e,
          ),
        );
      });
    }
  }

  Future<void> _transferCreator(RoomMember member) async {
    if (!member_filter.canStartRoomMemberAction(
      userId: member.user.id,
      busyMemberIds: _busyMemberIds,
    )) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmActionDialog(
        title: member_filter.transferCreatorDialogTitle(),
        body: member_filter.transferCreatorConfirmBody(member),
        confirmLabel: member_filter.transferCreatorConfirmLabel(),
        confirmIcon: Icons.swap_horiz,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _applyRoomMemberManagementPatch(
        member_filter.roomMemberManagementActionStarted(
          room: _room,
          members: _members,
          changed: _changed,
          userId: member.user.id,
          busyMemberIds: _busyMemberIds,
        ),
      );
    });
    try {
      final updated = await widget.controller.transferRoomCreator(
        roomId: _room.id,
        userId: member.user.id,
      );
      if (!mounted) return;
      setState(() {
        _applyRoomMemberManagementPatch(
          member_filter.transferCreatorSucceeded(
            updatedRoom: updated,
            members: _members,
            userId: member.user.id,
            busyMemberIds: _busyMemberIds,
          ),
        );
      });
      unawaited(_loadMembers());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyRoomMemberManagementPatch(
          member_filter.transferCreatorFailed(
            room: _room,
            members: _members,
            changed: _changed,
            userId: member.user.id,
            busyMemberIds: _busyMemberIds,
            failure: e,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = AppConfigScope.of(context);
    final roomAvatarUrl = _roomAvatarPreviewUrl(appConfig);
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: Column(
          children: [
            _RoomDialogHeader(title: '房间管理', onClose: _close),
            _RoomDialogRoomSummary(
              roomName: _room.name,
              avatarLabel: _room.name,
              avatarUrl: roomAvatarUrl,
              defaultAvatarKey: _defaultAvatarKey,
            ),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 170,
                    child: _RoomManagementNav(
                      selected: _section,
                      onChanged: (section) => setState(() {
                        _applyRoomManagementDialogPatch(
                          roomManagementSectionChanged(
                            section: section,
                            room: _room,
                            pendingAvatarAssetId: _pendingAvatarAssetId,
                            pendingAvatarUrl: _pendingAvatarUrl,
                            usingPresetAvatar: _usingPresetAvatar,
                            defaultAvatarKey: _defaultAvatarKey,
                            uploadingAvatar: _uploadingAvatar,
                            saving: _saving,
                            deleting: _deleting,
                            changed: _changed,
                            error: _error,
                            notice: _notice,
                          ),
                        );
                      }),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: _borderColor),
                  Expanded(child: _buildSection(appConfig)),
                ],
              ),
            ),
            if (_section == RoomManagementSection.info)
              _RoomDialogFooter(
                saving: _saving,
                onCancel: _close,
                onSave: _saveInfo,
                saveLabel: '保存房间管理',
              ),
          ],
        ),
      ),
    );
  }

  String? _roomAvatarPreviewUrl(AppConfig appConfig) {
    return appConfig.resolveAssetUrl(
      room_display.roomManagementAvatarPath(
        usingPresetAvatar: _usingPresetAvatar,
        pendingAvatarUrl: _pendingAvatarUrl,
        roomAvatarUrl: _room.avatarUrl,
      ),
    );
  }

  bool get _uploadedAvatarSelected =>
      room_display.roomManagementUploadedAvatarSelected(
        usingPresetAvatar: _usingPresetAvatar,
      );

  Widget _buildSection(AppConfig appConfig) {
    return switch (_section) {
      RoomManagementSection.info => _buildInfoSection(appConfig),
      RoomManagementSection.stickers => _RoomStickerManager(
        controller: widget.controller,
        roomId: _room.id,
        fileSelectionService: widget.fileSelectionService,
      ),
    };
  }

  Widget _buildInfoSection(AppConfig appConfig) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
      children: [
        if (_notice != null) ...[
          _RoomNotice(message: _notice!),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          _RoomError(message: _error!),
          const SizedBox(height: 12),
        ],
        _RoomSettingsGroup(
          title: '房间信息',
          children: [
            _RoomTextField(label: '房间重命名', controller: _nameController),
            const SizedBox(height: 14),
            _RoomAvatarPicker(
              label: '房间图标',
              displayName: _nameController.text,
              avatarUrl: _roomAvatarPreviewUrl(appConfig),
              defaultAvatarKey: _defaultAvatarKey,
              uploadedSelected: _uploadedAvatarSelected,
              presetSelected: _usingPresetAvatar,
              uploading: _uploadingAvatar,
              onUpload: _pickAvatar,
              onPresetChanged: (key) => setState(() {
                _applyRoomManagementDialogPatch(
                  roomManagementUsePresetAvatar(
                    section: _section,
                    room: _room,
                    defaultAvatarKey: key,
                    uploadingAvatar: _uploadingAvatar,
                    saving: _saving,
                    deleting: _deleting,
                    changed: _changed,
                    error: _error,
                    notice: _notice,
                  ),
                );
              }),
              onUsePreset: () => setState(() {
                _applyRoomManagementDialogPatch(
                  roomManagementUsePresetAvatar(
                    section: _section,
                    room: _room,
                    defaultAvatarKey: _defaultAvatarKey,
                    uploadingAvatar: _uploadingAvatar,
                    saving: _saving,
                    deleting: _deleting,
                    changed: _changed,
                    error: _error,
                    notice: _notice,
                  ),
                );
              }),
            ),
            const SizedBox(height: 14),
            _RoomTextField(
              label: '房间介绍',
              controller: _descriptionController,
              maxLines: 4,
            ),
            const SizedBox(height: 14),
            _RoomSegmentedSetting(
              label: '房间公开性',
              value: _visibility,
              options: const [
                _RoomOption('public', '公开'),
                _RoomOption('private', '私密'),
              ],
              onChanged: (value) => setState(
                () => _applyRoomManagementInfoFieldsPatch(
                  roomManagementVisibilityChanged(
                    visibility: value,
                    joinPolicy: _joinPolicy,
                    aiVoiceAnnouncementsEnabled: _aiVoiceAnnouncementsEnabled,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _RoomSegmentedSetting(
              label: '加入策略',
              value: _joinPolicy,
              options: const [
                _RoomOption('approval_required', '管理员审批'),
                _RoomOption('open', '任何人加入'),
                _RoomOption('closed', '不允许加入'),
              ],
              onChanged: (value) => setState(
                () => _applyRoomManagementInfoFieldsPatch(
                  roomManagementJoinPolicyChanged(
                    visibility: _visibility,
                    joinPolicy: value,
                    aiVoiceAnnouncementsEnabled: _aiVoiceAnnouncementsEnabled,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _RoomSwitchSetting(
              label: 'AI 语音自动播报',
              value: _aiVoiceAnnouncementsEnabled,
              onChanged: (value) => setState(
                () => _applyRoomManagementInfoFieldsPatch(
                  roomManagementAiVoiceAnnouncementsChanged(
                    visibility: _visibility,
                    joinPolicy: _joinPolicy,
                    aiVoiceAnnouncementsEnabled: value,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _RoomSettingsGroup(
          title: '成员权限',
          trailing: _loadingMembers
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    color: _cyan,
                    strokeWidth: 2,
                  ),
                )
              : ButtonIcon(
                  tooltip: '刷新成员',
                  onPressed: _loadMembers,
                  icon: const Icon(Icons.refresh),
                  size: 30,
                ),
          children: [
            if (_members.isEmpty && _loadingMembers)
              const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator(color: _cyan)),
              )
            else if (_members.isEmpty)
              const _RoomEmptyState(text: '暂无成员')
            else
              for (final member in _members) ...[
                _RoomMemberPermissionTile(
                  member: member,
                  room: _room,
                  currentUser: widget.currentUser,
                  busy: member_filter.roomMemberActionBusy(
                    member: member,
                    busyMemberIds: _busyMemberIds,
                  ),
                  canEditCreatorOnly: _canEditCreatorOnly,
                  onSetAdmin: () => _setMemberRole(member, 'admin'),
                  onUnsetAdmin: () => _setMemberRole(member, 'member'),
                  onTransferCreator: () => _transferCreator(member),
                ),
                if (member != _members.last) const SizedBox(height: 8),
              ],
          ],
        ),
        if (_canDeleteRoom) ...[
          const SizedBox(height: 16),
          _RoomSettingsGroup(
            title: '删除房间',
            danger: true,
            children: [
              Button(
                onPressed:
                    canStartRoomDeletion(
                      canDeleteRoom: _canDeleteRoom,
                      saving: _saving,
                      deleting: _deleting,
                    )
                    ? _deleteRoom
                    : null,
                loading: _deleting,
                tone: ButtonTone.danger,
                icon: const Icon(Icons.delete_forever_outlined),
                width: double.infinity,
                child: const Text('删除房间'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RoomStickerManager extends StatefulWidget {
  const _RoomStickerManager({
    required this.controller,
    required this.roomId,
    required this.fileSelectionService,
  });

  final RoomsController controller;
  final String roomId;
  final FileSelectionService fileSelectionService;

  @override
  State<_RoomStickerManager> createState() => _RoomStickerManagerState();
}

class _RoomStickerManagerState extends State<_RoomStickerManager> {
  List<StickerPack> _packs = const [];
  bool _loading = true;
  bool _uploading = false;
  bool _deleting = false;
  bool _savingOrder = false;
  bool _downloading = false;
  bool _managing = false;
  String _filterKeyword = '';
  String _filterMimeType = '';
  List<String> _selectedStickerIds = <String>[];
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<ManagedSticker> get _allItems {
    return managedStickerItems(_packs);
  }

  List<ManagedSticker> get _filteredItems {
    return filteredManagedStickerItems(
      _allItems,
      keyword: _filterKeyword,
      mimeType: _filterMimeType,
    );
  }

  bool get _filterActive =>
      stickerFilterActive(keyword: _filterKeyword, mimeType: _filterMimeType);

  bool get _stickerManagementBusy => stickerManagementBusy(
    uploading: _uploading,
    deleting: _deleting,
    savingOrder: _savingOrder,
    downloading: _downloading,
  );

  Map<String, int> _selectionNumbers() {
    return stickerSelectionNumbers(_selectedStickerIds);
  }

  void _applyStickerPackLoadPatch(StickerPackLoadPatch patch) {
    _packs = patch.packs;
    _selectedStickerIds = patch.selectedStickerIds;
    _loading = patch.loading;
    _error = patch.error;
  }

  void _applyStickerSelectionPatch(StickerSelectionPatch patch) {
    _managing = patch.managing;
    _filterKeyword = patch.filterKeyword;
    _filterMimeType = patch.filterMimeType;
    _selectedStickerIds = patch.selectedStickerIds;
  }

  void _applyStickerActionPatch(StickerActionPatch patch) {
    _uploading = patch.uploading;
    _deleting = patch.deleting;
    _savingOrder = patch.savingOrder;
    _downloading = patch.downloading;
    _selectedStickerIds = patch.selectedStickerIds;
    _error = patch.error;
    _notice = patch.notice;
  }

  Future<void> _load() async {
    setState(
      () => _applyStickerPackLoadPatch(
        stickerPacksLoadStarted(
          packs: _packs,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      final packs = await widget.controller.listRoomStickerPacks(widget.roomId);
      if (!mounted) return;
      setState(
        () => _applyStickerPackLoadPatch(
          stickerPacksLoadSucceeded(
            packs: packs,
            selectedStickerIds: _selectedStickerIds,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyStickerPackLoadPatch(
          stickerPacksLoadFailed(
            packs: _packs,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<StickerPack> _ensurePack() async {
    if (_packs.isNotEmpty) return _packs.first;
    final created = await widget.controller.createRoomStickerPack(
      name: defaultStickerPackName(StickerManagementScope.room),
      roomId: widget.roomId,
      sortOrder: 10,
    );
    if (mounted) {
      setState(
        () => _applyStickerPackLoadPatch(
          stickerPackUpserted(
            packs: _packs,
            selectedStickerIds: _selectedStickerIds,
            pack: created,
            loading: _loading,
            error: _error,
          ),
        ),
      );
    }
    return created;
  }

  Future<void> _upload() async {
    if (_stickerManagementBusy) return;
    List<SelectedFile> files;
    try {
      files = await widget.fileSelectionService.openFiles(
        acceptedTypeGroups: const [
          FileTypeGroup(
            label: '图片和 ZIP',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'zip'],
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionErrorShown(
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            failure: stickerPickerOpenFailureMessage(e),
            notice: _notice,
          ),
        ),
      );
      return;
    }
    if (files.isEmpty) return;
    setState(
      () => _applyStickerActionPatch(
        stickerActionStarted(
          action: StickerActionKind.upload,
          uploading: _uploading,
          deleting: _deleting,
          savingOrder: _savingOrder,
          downloading: _downloading,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    var uploadedCount = 0;
    try {
      final uploadItems = await stickerUploadItemsFromFiles(
        stickerUploadSourcesFromSelectedFiles(files),
        decodeImageDimensions: decodeStickerImageDimensions,
      );
      if (uploadItems.isEmpty) {
        throw StateError(stickerNoUploadableImagesMessage());
      }
      final pack = await _ensurePack();
      final uploadedAssetIds = <String>[];
      var sortIndex = pack.stickers.length;
      for (final entry in uploadItems.asMap().entries) {
        final item = entry.value;
        final asset = await widget.controller.uploadImageAsset(
          bytes: item.bytes,
          filename: stickerUploadFilename(item.filename, entry.key),
          purpose: 'sticker',
        );
        uploadedAssetIds.add(asset.id);
        await widget.controller.addRoomSticker(
          packId: pack.id,
          assetId: asset.id,
          name: stickerNameFromFilename(item.filename),
          sortOrder: (++sortIndex) * 10,
          roomId: widget.roomId,
        );
        uploadedCount += 1;
      }
      await _load();
      await _pinUploadedStickerAssetsToFront(
        packId: pack.id,
        assetIds: uploadedAssetIds,
      );
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.upload,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            error: _error,
            notice: stickerUploadNotice(
              scope: StickerManagementScope.room,
              count: uploadedCount,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionFailed(
            action: StickerActionKind.upload,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<void> _pinUploadedStickerAssetsToFront({
    required String packId,
    required List<String> assetIds,
  }) async {
    if (assetIds.isEmpty) return;
    final pack = sticker_ordering.stickerPackById(_packs, packId);
    if (pack == null) return;

    final nextOrder = sticker_ordering.stickerOrderWithAssetIdsPinnedToFront(
      pack,
      assetIds,
    );
    if (nextOrder == null) return;

    await widget.controller.reorderStickers(
      packId: pack.id,
      stickerIds: nextOrder,
    );
    await _load();
  }

  Future<void> _delete(Sticker sticker) async {
    final item = _itemForSticker(sticker.id);
    if (item == null) return;
    await _deleteItem(item);
  }

  Future<bool> _deleteItem(ManagedSticker item) async {
    if (_stickerManagementBusy) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmActionDialog(
        title: stickerDeleteDialogTitle(StickerManagementScope.room),
        body: stickerSingleDeleteConfirmBody(
          scope: StickerManagementScope.room,
          stickerName: item.sticker.name,
        ),
        confirmLabel: '删除',
        confirmIcon: Icons.delete_outline,
        danger: true,
      ),
    );
    if (confirmed != true || !mounted) return false;
    setState(
      () => _applyStickerActionPatch(
        stickerActionStarted(
          action: StickerActionKind.delete,
          uploading: _uploading,
          deleting: _deleting,
          savingOrder: _savingOrder,
          downloading: _downloading,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      await widget.controller.deleteRoomSticker(
        packId: item.pack.id,
        stickerId: item.sticker.id,
        roomId: widget.roomId,
      );
      await _load();
      if (!mounted) return false;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.delete,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            error: _error,
            notice: stickerDeletedNotice(scope: StickerManagementScope.room),
          ),
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(
        () => _applyStickerActionPatch(
          stickerActionFailed(
            action: StickerActionKind.delete,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _rename(Sticker sticker, String name) async {
    final pack = _packForSticker(sticker.id);
    final trimmed = stickerRenameName(name);
    if (pack == null || trimmed == null) return;
    try {
      await widget.controller.updateSticker(
        packId: pack.id,
        stickerId: sticker.id,
        name: trimmed,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionErrorShown(
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
            notice: _notice,
          ),
        ),
      );
    }
  }

  Future<void> _move(Sticker sticker, int delta) async {
    final item = _itemForSticker(sticker.id);
    if (item == null) return;
    await _moveItem(item, delta);
  }

  Future<sticker_ordering.StickerPlacementData?> _moveItem(
    ManagedSticker item,
    int delta,
  ) async {
    final placement = _placementForSticker(item.sticker.id);
    if (_filterActive) return placement;
    if (placement == null || _stickerManagementBusy) return placement;
    final ids = sticker_ordering.movedStickerOrder(
      placement.pack,
      item.sticker.id,
      delta,
    );
    if (ids == null) return placement;
    setState(
      () => _applyStickerActionPatch(
        stickerActionStarted(
          action: StickerActionKind.order,
          uploading: _uploading,
          deleting: _deleting,
          savingOrder: _savingOrder,
          downloading: _downloading,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      await widget.controller.reorderStickers(
        packId: placement.pack.id,
        stickerIds: ids,
      );
      await _load();
      if (!mounted) return placement;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.order,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            error: _error,
            notice: stickerMoveNotice(
              scope: StickerManagementScope.room,
              delta: delta,
            ),
          ),
        ),
      );
      return _placementForSticker(item.sticker.id);
    } catch (e) {
      if (!mounted) return placement;
      setState(
        () => _applyStickerActionPatch(
          stickerActionFailed(
            action: StickerActionKind.order,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
      return placement;
    }
  }

  Future<sticker_ordering.StickerPlacementData?> _pinItem(
    ManagedSticker item,
  ) async {
    final placement = _placementForSticker(item.sticker.id);
    if (placement == null || placement.index == 0 || _stickerManagementBusy) {
      return placement;
    }

    final ids = sticker_ordering.pinnedStickerOrder(
      placement.pack,
      item.sticker.id,
    );
    if (ids == null) return placement;
    setState(
      () => _applyStickerActionPatch(
        stickerActionStarted(
          action: StickerActionKind.order,
          uploading: _uploading,
          deleting: _deleting,
          savingOrder: _savingOrder,
          downloading: _downloading,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      await widget.controller.reorderStickers(
        packId: placement.pack.id,
        stickerIds: ids,
      );
      await _load();
      if (!mounted) return placement;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.order,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            error: _error,
            notice: stickerPinnedNotice(scope: StickerManagementScope.room),
          ),
        ),
      );
      return _placementForSticker(item.sticker.id);
    } catch (e) {
      if (!mounted) return placement;
      setState(
        () => _applyStickerActionPatch(
          stickerActionFailed(
            action: StickerActionKind.order,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
      return placement;
    }
  }

  Future<void> _download(Sticker sticker) async {
    await _downloadStickerIds([sticker.id]);
  }

  Future<void> _downloadStickerIds(List<String> stickerIds) async {
    if (!canStartStickerSelectionAction(
      busy: _stickerManagementBusy,
      selectedStickerIds: stickerIds,
    )) {
      return;
    }
    setState(
      () => _applyStickerActionPatch(
        stickerActionStarted(
          action: StickerActionKind.download,
          uploading: _uploading,
          deleting: _deleting,
          savingOrder: _savingOrder,
          downloading: _downloading,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      final file = await widget.controller.downloadStickers(
        stickerIds: stickerIds,
      );
      final location = await widget.fileSelectionService.getSaveLocation(
        suggestedName: file.filename,
        acceptedTypeGroups: const [
          FileTypeGroup(
            label: '图片和 ZIP',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'zip'],
          ),
        ],
        confirmButtonText: '保存',
      );
      if (location == null) {
        if (!mounted) return;
        setState(
          () => _applyStickerActionPatch(
            stickerActionCancelled(
              action: StickerActionKind.download,
              uploading: _uploading,
              deleting: _deleting,
              savingOrder: _savingOrder,
              downloading: _downloading,
              selectedStickerIds: _selectedStickerIds,
            ),
          ),
        );
        return;
      }
      await widget.fileSelectionService.saveBytesToPath(
        bytes: file.bytes,
        path: location.path,
        filename: file.filename,
        mimeType: file.mimeType,
      );
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.download,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            error: _error,
            notice: stickerDownloadNotice(
              scope: StickerManagementScope.room,
              count: stickerIds.length,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionFailed(
            action: StickerActionKind.download,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
    }
  }

  StickerPack? _packForSticker(String stickerId) {
    return sticker_ordering.stickerPackForSticker(_packs, stickerId);
  }

  ManagedSticker? _itemForSticker(String stickerId) {
    return managedStickerById(_allItems, stickerId);
  }

  sticker_ordering.StickerPlacementData? _placementForSticker(
    String stickerId,
  ) {
    return sticker_ordering.stickerPlacement(_packs, stickerId);
  }

  void _toggleManageMode() {
    setState(
      () => _applyStickerSelectionPatch(
        stickerManagementModeToggled(
          managing: _managing,
          filterKeyword: _filterKeyword,
          filterMimeType: _filterMimeType,
        ),
      ),
    );
  }

  void _toggleSelection(String stickerId) {
    setState(
      () => _applyStickerSelectionPatch(
        stickerSelectionToggled(
          managing: _managing,
          filterKeyword: _filterKeyword,
          filterMimeType: _filterMimeType,
          selectedStickerIds: _selectedStickerIds,
          stickerId: stickerId,
        ),
      ),
    );
  }

  void _selectAllVisible(List<ManagedSticker> items) {
    setState(
      () => _applyStickerSelectionPatch(
        stickerVisibleSelectionToggled(
          managing: _managing,
          busy: _stickerManagementBusy,
          filterKeyword: _filterKeyword,
          filterMimeType: _filterMimeType,
          selectedStickerIds: _selectedStickerIds,
          visibleItems: items,
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final selectedIds = List<String>.from(_selectedStickerIds);
    if (!canStartStickerSelectionAction(
      busy: _stickerManagementBusy,
      selectedStickerIds: selectedIds,
    )) {
      return;
    }
    final byStickerId = {for (final item in _allItems) item.sticker.id: item};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmActionDialog(
        title: stickerDeleteDialogTitle(StickerManagementScope.room),
        body: stickerBulkDeleteConfirmBody(
          scope: StickerManagementScope.room,
          count: selectedIds.length,
        ),
        confirmLabel: '删除',
        confirmIcon: Icons.delete_outline,
        danger: true,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(
      () => _applyStickerActionPatch(
        stickerActionStarted(
          action: StickerActionKind.delete,
          uploading: _uploading,
          deleting: _deleting,
          savingOrder: _savingOrder,
          downloading: _downloading,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      var deletedCount = 0;
      for (final stickerId in selectedIds) {
        final item = byStickerId[stickerId];
        if (item == null) continue;
        await widget.controller.deleteRoomSticker(
          packId: item.pack.id,
          stickerId: stickerId,
          roomId: widget.roomId,
        );
        deletedCount += 1;
      }
      await _load();
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.delete,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            error: _error,
            notice: stickerDeletedNotice(
              scope: StickerManagementScope.room,
              count: deletedCount,
            ),
            clearSelection: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionFailed(
            action: StickerActionKind.delete,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<void> _downloadSelected() async {
    await _downloadStickerIds(List<String>.from(_selectedStickerIds));
  }

  Future<void> _pinSelected() async {
    final selectedIds = List<String>.from(_selectedStickerIds);
    if (!canStartStickerSelectionAction(
      busy: _stickerManagementBusy,
      selectedStickerIds: selectedIds,
    )) {
      return;
    }
    final selectedByPack = sticker_ordering.selectedStickerIdsByPack(
      _packs,
      selectedIds,
    );
    if (selectedByPack.isEmpty) {
      setState(
        () => _applyStickerActionPatch(
          stickerActionNoticeShown(
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            error: _error,
            notice: stickerNoOrderChangeNotice(StickerManagementScope.room),
          ),
        ),
      );
      return;
    }

    setState(
      () => _applyStickerActionPatch(
        stickerActionStarted(
          action: StickerActionKind.order,
          uploading: _uploading,
          deleting: _deleting,
          savingOrder: _savingOrder,
          downloading: _downloading,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      for (final pack in _packs) {
        final selectedInPack = selectedByPack[pack.id];
        if (selectedInPack == null || selectedInPack.isEmpty) continue;
        final nextOrder = sticker_ordering
            .stickerOrderWithStickerIdsPinnedToFront(pack, selectedInPack);
        if (nextOrder == null) continue;
        await widget.controller.reorderStickers(
          packId: pack.id,
          stickerIds: nextOrder,
        );
      }
      await _load();
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.order,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            error: _error,
            notice: stickerPinnedNotice(
              scope: StickerManagementScope.room,
              count: selectedIds.length,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionFailed(
            action: StickerActionKind.order,
            uploading: _uploading,
            deleting: _deleting,
            savingOrder: _savingOrder,
            downloading: _downloading,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<void> _openFilter() async {
    final value = await showDialog<StickerFilterDraft>(
      context: context,
      builder: (context) => _RoomStickerFilterDialog(
        keyword: _filterKeyword,
        mimeType: _filterMimeType,
      ),
    );
    if (value == null || !mounted) return;
    setState(
      () => _applyStickerSelectionPatch(
        stickerFilterApplied(
          managing: _managing,
          keyword: value.keyword,
          mimeType: value.mimeType,
        ),
      ),
    );
  }

  void _preview(Sticker sticker) {
    final item = _itemForSticker(sticker.id);
    if (item == null) return;
    final imageUrl = AppConfigScope.of(
      context,
    ).resolveAssetUrl(sticker.asset.url);
    if (imageUrl == null) return;
    final placement = _placementForSticker(sticker.id);
    showDialog<void>(
      context: context,
      builder: (context) => _RoomStickerPreviewDialog(
        sticker: sticker,
        imageUrl: imageUrl,
        canMoveUp: !_filterActive && (placement?.canMoveUp ?? false),
        canMoveDown: !_filterActive && (placement?.canMoveDown ?? false),
        canPin: placement?.canPin ?? false,
        onRename: _rename,
        onDelete: _delete,
        onMoveUp: () => _move(sticker, -1),
        onMoveDown: () => _move(sticker, 1),
        onPin: () async {
          await _pinItem(item);
        },
        onDownload: () => _download(sticker),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    final totalCount = _allItems.length;
    final selectionNumbers = _selectionNumbers();
    final busy = _stickerManagementBusy;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
      children: [
        if (_notice != null) ...[
          _RoomNotice(message: _notice!),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          _RoomError(message: _error!),
          const SizedBox(height: 12),
        ],
        _RoomSettingsGroup(
          title: '房间表情包',
          trailing: Text(
            stickerManagementCountText(
              filterActive: _filterActive,
              visibleCount: items.length,
              totalCount: totalCount,
            ),
            style: const TextStyle(
              color: _textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          children: [
            _RoomStickerActionRow(
              children: [
                Button(
                  onPressed: canStartStickerPrimaryAction(busy: busy)
                      ? _managing
                            ? _deleteSelected
                            : _upload
                      : null,
                  loading: _managing ? _deleting : _uploading,
                  tone: _managing ? ButtonTone.danger : ButtonTone.primary,
                  icon: Icon(
                    _managing ? Icons.delete_outline : Icons.upload_file,
                  ),
                  width: double.infinity,
                  child: Text(_managing ? '删除' : '本地上传'),
                ),
                Button(
                  onPressed: canUseStickerManagementControl(busy: busy)
                      ? _toggleManageMode
                      : null,
                  selected: _managing,
                  tone: _managing ? ButtonTone.primary : ButtonTone.neutral,
                  icon: Icon(_managing ? Icons.close : Icons.checklist_rtl),
                  width: double.infinity,
                  child: Text(_managing ? '取消管理' : '批量管理'),
                ),
                Button(
                  onPressed: canUseStickerManagementControl(busy: busy)
                      ? _openFilter
                      : null,
                  selected: _filterActive,
                  tone: _filterActive ? ButtonTone.primary : ButtonTone.neutral,
                  icon: const Icon(Icons.filter_alt_outlined),
                  width: double.infinity,
                  child: const Text('筛选'),
                ),
              ],
            ),
            if (_managing) ...[
              const SizedBox(height: 10),
              _RoomStickerActionRow(
                children: [
                  Button(
                    onPressed:
                        canStartStickerSelectionAction(
                          busy: busy,
                          selectedStickerIds: _selectedStickerIds,
                        )
                        ? _downloadSelected
                        : null,
                    loading: _downloading,
                    icon: const Icon(Icons.download_outlined),
                    width: double.infinity,
                    child: const Text('下载'),
                  ),
                  Button(
                    onPressed:
                        canStartStickerSelectionAction(
                          busy: busy,
                          selectedStickerIds: _selectedStickerIds,
                        )
                        ? _pinSelected
                        : null,
                    loading: _savingOrder,
                    icon: const Icon(Icons.vertical_align_top),
                    width: double.infinity,
                    child: const Text('置顶'),
                  ),
                  Button(
                    onPressed:
                        canSelectVisibleStickers(
                          busy: busy,
                          visibleItems: items,
                        )
                        ? () => _selectAllVisible(items)
                        : null,
                    icon: const Icon(Icons.select_all),
                    width: double.infinity,
                    child: const Text('全选'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            if (_loading && totalCount == 0)
              const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator(color: _cyan)),
              )
            else if (totalCount == 0)
              const _RoomEmptyState(text: '暂无表情，点击本地上传会自动创建')
            else if (items.isEmpty)
              const _RoomEmptyState(text: '没有匹配的房间表情')
            else
              _RoomStickerGrid(
                items: items,
                managing: _managing,
                selectionNumbers: selectionNumbers,
                busy: busy,
                onTap: (item) {
                  if (_managing) {
                    _toggleSelection(item.sticker.id);
                  } else {
                    _preview(item.sticker);
                  }
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _RoomDialogHeader extends StatelessWidget {
  const _RoomDialogHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ButtonIcon(
            tooltip: '关闭',
            onPressed: onClose,
            icon: const Icon(Icons.close),
            size: 32,
          ),
        ],
      ),
    );
  }
}

class _RoomDialogRoomSummary extends StatelessWidget {
  const _RoomDialogRoomSummary({
    required this.roomName,
    required this.avatarLabel,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    this.subtitle,
  });

  final String roomName;
  final String avatarLabel;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 20, 18),
        child: Row(
          children: [
            _Avatar(
              label: avatarLabel,
              imageUrl: avatarUrl,
              defaultAvatarKey: defaultAvatarKey,
              size: 56,
              borderColor: _cyan,
              borderWidth: 1.2,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomDialogFooter extends StatelessWidget {
  const _RoomDialogFooter({
    required this.saving,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Button(
              onPressed: saving ? null : onCancel,
              child: const Text('取消'),
            ),
            const SizedBox(width: 10),
            Button(
              onPressed: saving ? null : onSave,
              loading: saving,
              tone: ButtonTone.primary,
              icon: const Icon(Icons.save_outlined),
              child: Text(saveLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomSettingsGroup extends StatelessWidget {
  const _RoomSettingsGroup({
    required this.title,
    required this.children,
    this.trailing,
    this.danger = false,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _primaryDarkLow,
        border: Border.all(
          color: danger ? const Color(0xFF3A2A2E) : _borderColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: danger ? _danger : _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _RoomNotice extends StatelessWidget {
  const _RoomNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _RoomBanner(
      message: message,
      icon: Icons.check_circle_outline,
      color: _cyan,
    );
  }
}

class _RoomError extends StatelessWidget {
  const _RoomError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _RoomBanner(
      message: message,
      icon: Icons.error_outline,
      color: _danger,
    );
  }
}

class _RoomBanner extends StatelessWidget {
  const _RoomBanner({
    required this.message,
    required this.icon,
    required this.color,
  });

  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _primaryDark,
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomFieldLabel extends StatelessWidget {
  const _RoomFieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _CopyableRoomField extends StatelessWidget {
  const _CopyableRoomField({
    required this.label,
    required this.value,
    required this.onCopy,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomFieldLabel(label),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _primaryDark,
            border: Border.all(color: _borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    value,
                    maxLines: maxLines,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ButtonIcon(
                  tooltip: '复制',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy),
                  size: 30,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomCreatorField extends StatelessWidget {
  const _RoomCreatorField({required this.user, required this.onOpen});

  final UserSummary user;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final appConfig = AppConfigScope.of(context);
    final name = room_display.userPrimaryName(user);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _RoomFieldLabel('创建者'),
        const SizedBox(height: 8),
        Tooltip(
          message: '查看用户信息',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _primaryDark,
                  border: Border.all(color: _borderColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      _Avatar(
                        label: name,
                        imageUrl: appConfig.resolveAssetUrl(user.avatarUrl),
                        defaultAvatarKey: user.defaultAvatarKey,
                        size: 34,
                        borderColor: _borderColor,
                        borderWidth: 1,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              room_display.userUsernameLabel(user),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomTextField extends StatelessWidget {
  const _RoomTextField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.helperText,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomFieldLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          cursorColor: _textSecondary,
          contextMenuBuilder: buildTextFieldContextMenu,
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          decoration: const InputDecoration(isDense: true),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText!,
            style: const TextStyle(color: _textMuted, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _RoomOption {
  const _RoomOption(this.value, this.label);

  final String value;
  final String label;
}

class _RoomSegmentedSetting extends StatelessWidget {
  const _RoomSegmentedSetting({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<_RoomOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomFieldLabel(label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              Button(
                onPressed: () => onChanged(option.value),
                selected: option.value == value,
                tone: option.value == value
                    ? ButtonTone.primary
                    : ButtonTone.neutral,
                height: 34,
                child: Text(option.label),
              ),
          ],
        ),
      ],
    );
  }
}

class _RoomSwitchSetting extends StatelessWidget {
  const _RoomSwitchSetting({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _RoomFieldLabel(label)),
        Switch(
          value: value,
          activeThumbColor: _cyan,
          activeTrackColor: _cyan.withValues(alpha: 0.28),
          inactiveThumbColor: _textMuted,
          inactiveTrackColor: _borderColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RoomAvatarPicker extends StatelessWidget {
  const _RoomAvatarPicker({
    required this.label,
    required this.displayName,
    required this.avatarUrl,
    required this.defaultAvatarKey,
    required this.uploadedSelected,
    required this.presetSelected,
    required this.uploading,
    required this.onUpload,
    required this.onPresetChanged,
    required this.onUsePreset,
    this.avatarKeys = roomKeys,
    this.uploadLabel = '上传图片',
    this.presetLabel = '预设图标',
  });

  static const roomKeys = [
    'room-1',
    'blue-3',
    'sky-2',
    'cyan-2',
    'mint-2',
    'green-2',
    'lime-2',
    'amber-2',
    'orange-2',
    'coral-2',
    'pink-2',
    'violet-2',
    'indigo-2',
    'rose-2',
    'teal-2',
    'olive-2',
    'slate-2',
    'steel-2',
    'graphite-2',
  ];

  static const profileKeys = [
    'blue-3',
    'sky-2',
    'cyan-2',
    'mint-2',
    'green-2',
    'lime-2',
    'amber-2',
    'orange-2',
    'coral-2',
    'pink-2',
    'violet-2',
    'indigo-2',
    'rose-2',
    'teal-2',
    'olive-2',
    'slate-2',
    'steel-2',
    'graphite-2',
  ];

  final String label;
  final String displayName;
  final String? avatarUrl;
  final String defaultAvatarKey;
  final bool uploadedSelected;
  final bool presetSelected;
  final bool uploading;
  final VoidCallback onUpload;
  final ValueChanged<String> onPresetChanged;
  final VoidCallback onUsePreset;
  final List<String> avatarKeys;
  final String uploadLabel;
  final String presetLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomFieldLabel(label),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Center(
                child: _Avatar(
                  label: displayName,
                  imageUrl: avatarUrl,
                  defaultAvatarKey: defaultAvatarKey,
                  size: 88,
                  borderColor: _cyan,
                  borderWidth: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final key in avatarKeys)
                    _AvatarSwatch(
                      keyName: key,
                      selected: presetSelected && key == defaultAvatarKey,
                      onPressed: () => onPresetChanged(key),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Button(
                onPressed: uploading ? null : onUpload,
                loading: uploading,
                icon: const Icon(Icons.upload_file),
                tone: uploadedSelected
                    ? ButtonTone.primary
                    : ButtonTone.neutral,
                selected: uploadedSelected,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                width: double.infinity,
                child: Text(uploadLabel),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Button(
                onPressed: uploading ? null : onUsePreset,
                icon: const Icon(Icons.restart_alt),
                tone: presetSelected ? ButtonTone.primary : ButtonTone.neutral,
                selected: presetSelected,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                width: double.infinity,
                child: Text(presetLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AvatarSwatch extends StatelessWidget {
  const _AvatarSwatch({
    required this.keyName,
    required this.selected,
    required this.onPressed,
  });

  final String keyName;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: keyName,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: avatarFallbackColor(keyName),
            border: Border.all(
              color: selected ? UiColors.selectedBorder : _borderColor,
              width: selected ? 2 : 1,
            ),
          ),
          child: const SizedBox.square(dimension: 30),
        ),
      ),
    );
  }
}

class _CroppedAvatarFile {
  const _CroppedAvatarFile({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

class _AvatarPickException implements Exception {
  const _AvatarPickException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<_CroppedAvatarFile?> _pickAndCropAvatarFile(
  BuildContext context, {
  required FileSelectionService fileSelectionService,
  required String title,
}) async {
  SelectedFile? file;
  try {
    file = await fileSelectionService.openFile(
      acceptedTypeGroups: const [
        FileTypeGroup(
          label: '图片',
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
        ),
      ],
    );
  } catch (e) {
    throw _AvatarPickException('无法打开文件选择器：$e');
  }
  if (file == null) return null;

  Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (e) {
    throw _AvatarPickException('无法读取图片：$e');
  }
  if (bytes.isEmpty) {
    throw const _AvatarPickException('图片文件为空');
  }
  if (!context.mounted) return null;

  final cropped = await showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AvatarCropDialog(bytes: bytes, title: title),
  );
  if (cropped == null) return null;
  return _CroppedAvatarFile(
    bytes: cropped,
    filename: account_display.avatarUploadFilename(file.name),
  );
}

class _RoomManagementNav extends StatelessWidget {
  const _RoomManagementNav({required this.selected, required this.onChanged});

  final RoomManagementSection selected;
  final ValueChanged<RoomManagementSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _primaryDark,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        children: [
          _RoomNavButton(
            selected: selected == RoomManagementSection.info,
            icon: Icons.info_outline,
            label: '房间信息',
            onPressed: () => onChanged(RoomManagementSection.info),
          ),
          const SizedBox(height: 8),
          _RoomNavButton(
            selected: selected == RoomManagementSection.stickers,
            icon: Icons.emoji_emotions_outlined,
            label: '房间表情包',
            onPressed: () => onChanged(RoomManagementSection.stickers),
          ),
        ],
      ),
    );
  }
}

class _RoomNavButton extends StatelessWidget {
  const _RoomNavButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: onPressed,
      selected: selected,
      tone: selected ? ButtonTone.primary : ButtonTone.neutral,
      icon: Icon(icon),
      width: double.infinity,
      mainAxisSize: MainAxisSize.max,
      child: Text(label),
    );
  }
}

class _RoomMemberPermissionTile extends StatelessWidget {
  const _RoomMemberPermissionTile({
    required this.member,
    required this.room,
    required this.currentUser,
    required this.busy,
    required this.canEditCreatorOnly,
    required this.onSetAdmin,
    required this.onUnsetAdmin,
    required this.onTransferCreator,
  });

  final RoomMember member;
  final RoomDetail room;
  final CurrentUser currentUser;
  final bool busy;
  final bool canEditCreatorOnly;
  final VoidCallback onSetAdmin;
  final VoidCallback onUnsetAdmin;
  final VoidCallback onTransferCreator;

  @override
  Widget build(BuildContext context) {
    final name = member_filter.roomMemberDisplayName(member);
    final permission = member_filter.roomMemberPermissionState(
      member: member,
      currentUser: currentUser,
      canEditCreatorOnly: canEditCreatorOnly,
      ownerUserId: room.createdBy?.id,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _primaryDark,
        border: Border.all(color: _borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            _Avatar(
              label: name,
              imageUrl: AppConfigScope.of(
                context,
              ).resolveAssetUrl(member.user.avatarUrl),
              defaultAvatarKey: member.user.defaultAvatarKey,
              size: 38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    room_display.roomRoleLabel(
                      member.user.copyWith(roomRole: member.role),
                      ownerUserId: room.createdBy?.id,
                    ),
                    style: const TextStyle(color: _textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(color: _cyan, strokeWidth: 2),
              )
            else if (permission.canRoleEdit) ...[
              Button(
                onPressed: permission.canUnsetAdmin ? onUnsetAdmin : onSetAdmin,
                height: 32,
                icon: Icon(
                  permission.canUnsetAdmin
                      ? Icons.person_remove_alt_1_outlined
                      : Icons.admin_panel_settings_outlined,
                ),
                child: Text(permission.adminActionLabel),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: permission.canTransferCreator
                    ? onTransferCreator
                    : null,
                height: 32,
                icon: const Icon(Icons.swap_horiz),
                child: const Text('设为创建者'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoomStickerActionRow extends StatelessWidget {
  const _RoomStickerActionRow({required this.children});

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

class _RoomStickerGrid extends StatelessWidget {
  const _RoomStickerGrid({
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
            return _RoomStickerTile(
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

class _RoomStickerTile extends StatelessWidget {
  const _RoomStickerTile({
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
            selectedBackgroundColor: _selectedSurface,
            pressedBackgroundColor: _primaryDarkLow,
            borderColor: selected ? UiColors.selectedBorder : _borderColor,
            selectedBorderColor: UiColors.selectedBorder,
            hoverLift: 2,
            baseDepth: 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: _RoomStickerThumbnail(
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

class _RoomStickerThumbnail extends StatelessWidget {
  const _RoomStickerThumbnail({required this.sticker, required this.size});

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

class _RoomStickerFilterDialog extends StatefulWidget {
  const _RoomStickerFilterDialog({
    required this.keyword,
    required this.mimeType,
  });

  final String keyword;
  final String mimeType;

  @override
  State<_RoomStickerFilterDialog> createState() =>
      _RoomStickerFilterDialogState();
}

class _RoomStickerFilterDialogState extends State<_RoomStickerFilterDialog> {
  late final TextEditingController _keywordController;
  late String _mimeType;

  static const _filters = [
    _RoomStickerMimeFilter('', '全部'),
    _RoomStickerMimeFilter('image/png', 'PNG'),
    _RoomStickerMimeFilter('image/jpeg', 'JPG'),
    _RoomStickerMimeFilter('image/webp', 'WebP'),
    _RoomStickerMimeFilter('image/gif', 'GIF'),
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
                contextMenuBuilder: buildTextFieldContextMenu,
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
              const _RoomFieldLabel('图片类型'),
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
                        selectedBackgroundColor: _selectedSurface,
                        pressedBackgroundColor: _primaryDarkLow,
                        borderColor: _mimeType == filter.mimeType
                            ? UiColors.selectedBorder
                            : _borderColor,
                        selectedBorderColor: UiColors.selectedBorder,
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

class _RoomStickerMimeFilter {
  const _RoomStickerMimeFilter(this.mimeType, this.label);

  final String mimeType;
  final String label;
}

class _RoomStickerPreviewDialog extends StatefulWidget {
  const _RoomStickerPreviewDialog({
    required this.sticker,
    required this.imageUrl,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.canPin,
    required this.onRename,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onPin,
    required this.onDownload,
  });

  final Sticker sticker;
  final String imageUrl;
  final bool canMoveUp;
  final bool canMoveDown;
  final bool canPin;
  final Future<void> Function(Sticker sticker, String name) onRename;
  final Future<void> Function(Sticker sticker) onDelete;
  final Future<void> Function() onMoveUp;
  final Future<void> Function() onMoveDown;
  final Future<void> Function() onPin;
  final Future<void> Function() onDownload;

  @override
  State<_RoomStickerPreviewDialog> createState() =>
      _RoomStickerPreviewDialogState();
}

class _RoomStickerPreviewDialogState extends State<_RoomStickerPreviewDialog> {
  late final TextEditingController _nameController;
  late StickerPreviewState _previewState;

  bool get _busy => _previewState.busy;
  bool get _canMoveUp => _previewState.canMoveUp;
  bool get _canMoveDown => _previewState.canMoveDown;
  bool get _canPin => _previewState.canPin;
  String? get _error => _previewState.error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.sticker.name);
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

  Future<void> _run(
    Future<void> Function() action, {
    required StickerPreviewActionKind actionKind,
    bool close = false,
  }) async {
    if (!canStartStickerPreviewAction(
      state: _previewState,
      action: actionKind,
      name: _nameController.text,
    )) {
      return;
    }
    setState(
      () => _previewState = stickerPreviewActionStarted(
        state: _previewState,
        action: actionKind,
      ),
    );
    try {
      await action();
      if (close && mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _previewState = stickerPreviewActionFailed(
          state: _previewState,
          action: actionKind,
          failure: e,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _primaryDarkRaised,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.sticker.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  ButtonIcon(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _primaryDark,
                    border: Border.all(color: _borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Image.network(widget.imageUrl, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _RoomTextField(label: '表情名称', controller: _nameController),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _RoomError(message: _error!),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Button(
                    onPressed:
                        canStartStickerPreviewAction(
                          state: _previewState,
                          action: StickerPreviewActionKind.rename,
                          name: _nameController.text,
                        )
                        ? () => _run(
                            () => widget.onRename(
                              widget.sticker,
                              _nameController.text,
                            ),
                            actionKind: StickerPreviewActionKind.rename,
                          )
                        : null,
                    loading: _previewState.savingName,
                    icon: const Icon(Icons.drive_file_rename_outline),
                    child: const Text('重命名'),
                  ),
                  Button(
                    onPressed: _busy || !_canMoveUp
                        ? null
                        : () => _run(
                            widget.onMoveUp,
                            actionKind: StickerPreviewActionKind.moveUp,
                          ),
                    loading: _previewState.movingUp,
                    icon: const Icon(Icons.keyboard_arrow_up),
                    child: const Text('上移'),
                  ),
                  Button(
                    onPressed: _busy || !_canMoveDown
                        ? null
                        : () => _run(
                            widget.onMoveDown,
                            actionKind: StickerPreviewActionKind.moveDown,
                          ),
                    loading: _previewState.movingDown,
                    icon: const Icon(Icons.keyboard_arrow_down),
                    child: const Text('下移'),
                  ),
                  Button(
                    onPressed: _busy || !_canPin
                        ? null
                        : () => _run(
                            widget.onPin,
                            actionKind: StickerPreviewActionKind.pin,
                          ),
                    loading: _previewState.pinning,
                    icon: const Icon(Icons.vertical_align_top),
                    child: const Text('置顶'),
                  ),
                  Button(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            widget.onDownload,
                            actionKind: StickerPreviewActionKind.download,
                          ),
                    loading: _previewState.downloading,
                    icon: const Icon(Icons.download_outlined),
                    child: const Text('下载'),
                  ),
                  Button(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.onDelete(widget.sticker),
                            actionKind: StickerPreviewActionKind.delete,
                            close: true,
                          ),
                    loading: _previewState.deleting,
                    tone: ButtonTone.danger,
                    icon: const Icon(Icons.delete_outline),
                    child: const Text('删除'),
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

class _RoomEmptyState extends StatelessWidget {
  const _RoomEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _textMuted, fontSize: 13),
        ),
      ),
    );
  }
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
      backgroundColor: _primaryDarkRaised,
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
              Text(
                title,
                style: TextStyle(
                  color: danger ? _danger : _textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: const TextStyle(
                  color: _textSecondary,
                  height: 1.4,
                  fontSize: 14,
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
                  const SizedBox(width: 10),
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

class _StrongConfirmDialog extends StatefulWidget {
  const _StrongConfirmDialog({
    required this.title,
    required this.body,
    required this.expectedText,
    required this.confirmLabel,
    required this.confirmIcon,
  });

  final String title;
  final String body;
  final String expectedText;
  final String confirmLabel;
  final IconData confirmIcon;

  @override
  State<_StrongConfirmDialog> createState() => _StrongConfirmDialogState();
}

class _StrongConfirmDialogState extends State<_StrongConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matched = matchesConfirmationText(
      _controller.text,
      widget.expectedText,
    );
    return Dialog(
      backgroundColor: _primaryDarkRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  color: _danger,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.body,
                style: const TextStyle(
                  color: _textSecondary,
                  height: 1.4,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 14),
              _RoomTextField(
                label: '输入房间名确认：${widget.expectedText}',
                controller: _controller,
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Button(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  Button(
                    onPressed: matched
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    tone: ButtonTone.danger,
                    icon: Icon(widget.confirmIcon),
                    child: Text(widget.confirmLabel),
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
