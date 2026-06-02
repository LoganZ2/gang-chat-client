import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'audio_device_store.dart';
import '../config/app_config.dart';
import '../protocol/api_client.dart';
import '../protocol/models.dart';
import '../ui/key_button.dart';
import '../ui/title_bar.dart';

const _primaryDark = Color(0xFF14171D);
const _primaryDarkLow = Color(0xFF181C24);
const _borderColor = Color(0xFF2A2F38);
const _cyan = Color(0xFF6FCFA6);
const _textPrimary = Color(0xFFECEFF1);
const _textSecondary = Color(0xFFB0B8C0);
const _textMuted = Color(0xFF6F7785);
const _danger = Color(0xFFE58383);

enum _SettingsSection { profile, security, voice, stickers }

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.isSubWindow = false,
    this.audioDeviceStore = const AudioDeviceStore(),
    this.api,
    this.currentUser,
    this.onUserUpdated,
    this.onDeviceSelected,
    this.onVolumeChanged,
    this.onAccountDeleted,
    this.onClose,
  });

  final bool isSubWindow;
  final AudioDeviceStore audioDeviceStore;
  final GangApi? api;
  final CurrentUser? currentUser;
  final ValueChanged<CurrentUser>? onUserUpdated;
  final void Function(String kind, String deviceId)? onDeviceSelected;
  final void Function(String kind, double volume)? onVolumeChanged;
  final Future<void> Function()? onAccountDeleted;
  final VoidCallback? onClose;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _SettingsSection _section = _SettingsSection.profile;
  CurrentUser? _user;
  List<UserSession> _sessions = const [];
  String _gender = 'secret';
  String _defaultAvatarKey = 'blue-3';
  bool _emailPublic = false;
  bool _phonePublic = false;
  bool _loadingAccount = false;
  bool _loadingSessions = false;
  bool _savingAccount = false;
  bool _savingProfile = false;
  bool _uploadingAvatar = false;
  bool _clearUploadedAvatar = false;
  String? _pendingAvatarAssetId;
  String? _pendingAvatarUrl;
  bool _changingPassword = false;
  bool _deletingAccount = false;
  List<StickerPack> _stickerPacks = const [];
  String? _activeStickerPackId;
  Set<String> _selectedStickerIds = <String>{};
  final Map<String, List<String>> _stickerOrderDrafts = {};
  bool _loadingStickers = false;
  bool _uploadingStickers = false;
  bool _deletingStickers = false;
  bool _savingStickerOrder = false;
  String? _stickerError;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _accountError;
  String? _securityError;
  String? _notice;

  StreamSubscription<List<lk.MediaDevice>>? _deviceSubscription;
  List<lk.MediaDevice> _audioInputs = const [];
  List<lk.MediaDevice> _audioOutputs = const [];
  lk.MediaDevice? _selectedInput;
  lk.MediaDevice? _selectedOutput;
  String? _busyDeviceId;
  double _inputVolume = 1.0;
  double _outputVolume = 1.0;
  double _inputLevel = 0.0;
  double _outputLevel = 0.0;
  bool _testingInput = false;
  bool _testingOutput = false;
  bool _voiceInitialized = false;
  bool _requestedDeviceAccess = false;
  String? _error;
  bool _loading = false;
  lk.LocalAudioTrack? _inputTestTrack;
  lk.AudioVisualizer? _inputVisualizer;
  lk.EventsListener<lk.AudioVisualizerEvent>? _inputVisualizerListener;
  lk.LocalAudioTrack? _outputTestTrack;
  lk.AudioVisualizer? _outputVisualizer;
  lk.EventsListener<lk.AudioVisualizerEvent>? _outputVisualizerListener;
  rtc.RTCVideoRenderer? _outputRenderer;

  @override
  void initState() {
    super.initState();
    _user = widget.currentUser;
    _syncUserFields(widget.currentUser);
    unawaited(_loadAccount());
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser != widget.currentUser) {
      _user = widget.currentUser;
      _syncUserFields(widget.currentUser);
    }
  }

  @override
  void dispose() {
    unawaited(_stopInputTest(updateState: false));
    unawaited(_stopOutputTest(updateState: false));
    unawaited(_deviceSubscription?.cancel());
    _usernameController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _syncUserFields(CurrentUser? user) {
    if (user == null) return;
    _usernameController.text = user.username;
    _displayNameController.text = user.displayName;
    _bioController.text = user.bio;
    _emailController.text = user.email ?? '';
    _phoneController.text = user.phoneNumber ?? '';
    _gender = _normalizedGender(user.gender);
    _defaultAvatarKey = user.defaultAvatarKey;
    _emailPublic = user.emailPublic;
    _phonePublic = user.phoneNumberPublic;
    _clearUploadedAvatar = false;
    _pendingAvatarAssetId = null;
    _pendingAvatarUrl = null;
  }

  Future<void> _loadAccount() async {
    final api = widget.api;
    if (api == null) return;
    setState(() {
      _loadingAccount = true;
      _accountError = null;
    });
    try {
      final user = await api.me();
      if (!mounted) return;
      setState(() {
        _user = user;
        _syncUserFields(user);
      });
      widget.onUserUpdated?.call(user);
    } catch (e) {
      if (!mounted) return;
      setState(() => _accountError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingAccount = false);
    }
  }

  Future<void> _loadSessions() async {
    final api = widget.api;
    if (api == null) return;
    setState(() {
      _loadingSessions = true;
      _securityError = null;
    });
    try {
      final sessions = await api.listSessions();
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (e) {
      if (!mounted) return;
      setState(() => _securityError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingSessions = false);
    }
  }

  Future<void> _ensureStickersLoaded({bool forceReload = false}) async {
    if (_loadingStickers) return;
    if (!forceReload && _stickerPacks.isNotEmpty) return;
    await _loadStickers();
  }

  Future<void> _loadStickers() async {
    final api = widget.api;
    if (api == null) return;
    setState(() {
      _loadingStickers = true;
      _stickerError = null;
    });
    try {
      final packs = await api.listStickerPacks(scope: 'personal');
      if (!mounted) return;
      final nextActiveId = _activeStickerPackId;
      final activeExists =
          nextActiveId != null && packs.any((pack) => pack.id == nextActiveId);
      setState(() {
        _stickerPacks = packs;
        _activeStickerPackId = activeExists
            ? nextActiveId
            : packs.isEmpty
            ? null
            : packs.first.id;
        _selectedStickerIds = <String>{};
        _stickerOrderDrafts
          ..clear()
          ..addEntries(
            packs.map(
              (pack) => MapEntry(
                pack.id,
                pack.stickers.map((sticker) => sticker.id).toList(),
              ),
            ),
          );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _stickerError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingStickers = false);
    }
  }

  Future<void> _refreshActiveSection() async {
    switch (_section) {
      case _SettingsSection.profile:
        await _loadAccount();
        break;
      case _SettingsSection.stickers:
        await _loadStickers();
        break;
      case _SettingsSection.security:
        await Future.wait([_loadAccount(), _loadSessions()]);
        break;
      case _SettingsSection.voice:
        await _ensureVoiceInitialized(forceReload: true);
        break;
    }
  }

  Future<void> _ensureVoiceInitialized({bool forceReload = false}) async {
    if (_voiceInitialized && !forceReload) return;
    if (!_voiceInitialized) {
      _voiceInitialized = true;
      _deviceSubscription ??= lk.Hardware.instance.onDeviceChange.stream.listen(
        (devices) {
          unawaited(_applyDevices(devices));
        },
      );
      unawaited(_loadStoredAudioSettings());
    }
    await _loadDevices();
  }

  Future<void> _saveAccount() async {
    final api = widget.api;
    final user = _user;
    if (api == null || user == null || _savingAccount) return;

    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    if (username.isEmpty) {
      setState(() => _accountError = 'Username 不能为空');
      return;
    }
    if (email.isEmpty) {
      setState(() => _accountError = '邮箱不能为空');
      return;
    }

    final nextUsername = username == user.username ? null : username;
    final nextEmail = email == (user.email ?? '') ? null : email;
    final nextEmailPublic = _emailPublic == user.emailPublic
        ? null
        : _emailPublic;
    final nextPhone = phone == (user.phoneNumber ?? '') ? null : phone;
    final nextPhonePublic = _phonePublic == user.phoneNumberPublic
        ? null
        : _phonePublic;
    if (nextUsername == null &&
        nextEmail == null &&
        nextEmailPublic == null &&
        nextPhone == null &&
        nextPhonePublic == null) {
      _showNotice('没有账号绑定变更');
      return;
    }

    setState(() {
      _savingAccount = true;
      _accountError = null;
      _notice = null;
    });
    try {
      final updated = await api.updateAccount(
        username: nextUsername,
        email: nextEmail,
        emailPublic: nextEmailPublic,
        phoneNumber: nextPhone,
        phoneNumberPublic: nextPhonePublic,
      );
      if (!mounted) return;
      setState(() {
        _user = updated;
        _syncUserFields(updated);
      });
      widget.onUserUpdated?.call(updated);
      _showNotice('账号绑定已保存');
    } catch (e) {
      if (!mounted) return;
      setState(() => _accountError = e.toString());
    } finally {
      if (mounted) setState(() => _savingAccount = false);
    }
  }

  Future<void> _saveProfile() async {
    final api = widget.api;
    final user = _user;
    if (api == null || user == null || _savingProfile) return;

    final displayName = _displayNameController.text.trim();
    final bio = _bioController.text.trim();
    if (displayName.isEmpty) {
      setState(() => _accountError = '用户名不能为空');
      return;
    }

    final nextDisplayName = displayName == user.displayName
        ? null
        : displayName;
    final nextBio = bio == user.bio ? null : bio;
    final nextGender = _gender == _normalizedGender(user.gender)
        ? null
        : _gender;
    final nextAvatarKey = _defaultAvatarKey == user.defaultAvatarKey
        ? null
        : _defaultAvatarKey;
    final nextAvatarAssetId =
        _pendingAvatarAssetId ?? (_clearUploadedAvatar ? '' : null);
    if (nextDisplayName == null &&
        nextBio == null &&
        nextGender == null &&
        nextAvatarKey == null &&
        nextAvatarAssetId == null) {
      _showNotice('没有用户资料变更');
      return;
    }

    setState(() {
      _savingProfile = true;
      _accountError = null;
      _notice = null;
    });
    try {
      final updated = await api.updateProfile(
        displayName: nextDisplayName,
        bio: nextBio,
        gender: nextGender,
        defaultAvatarKey: nextAvatarKey,
        avatarAssetId: nextAvatarAssetId,
      );
      if (!mounted) return;
      setState(() {
        _user = updated;
        _syncUserFields(updated);
      });
      widget.onUserUpdated?.call(updated);
      _showNotice('用户资料已保存');
    } catch (e) {
      if (!mounted) return;
      setState(() => _accountError = e.toString());
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final api = widget.api;
    if (api == null || _uploadingAvatar) return;
    setState(() {
      _accountError = null;
      _notice = null;
    });

    XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _accountError = '无法打开文件选择器：$e');
      return;
    }
    if (file == null) return;

    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      if (!mounted) return;
      setState(() => _accountError = '无法读取图片：$e');
      return;
    }
    if (bytes.isEmpty) {
      setState(() => _accountError = '图片文件为空');
      return;
    }
    if (!mounted) return;

    final cropped = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AvatarCropDialog(bytes: bytes),
    );
    if (cropped == null || !mounted) return;

    setState(() {
      _uploadingAvatar = true;
      _accountError = null;
      _notice = null;
    });
    try {
      final asset = await api.uploadImageAsset(
        bytes: cropped,
        filename: _avatarUploadFilename(file.name),
        purpose: 'avatar',
      );
      if (!mounted) return;
      setState(() {
        _pendingAvatarAssetId = asset.id;
        _pendingAvatarUrl = asset.url;
        _clearUploadedAvatar = false;
      });
      _showNotice('头像已上传，保存用户资料后生效');
    } catch (e) {
      if (!mounted) return;
      setState(() => _accountError = e.toString());
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  StickerPack? _selectedStickerPack() {
    if (_stickerPacks.isEmpty) return null;
    final activeId = _activeStickerPackId;
    if (activeId != null) {
      for (final pack in _stickerPacks) {
        if (pack.id == activeId) return pack;
      }
    }
    return _stickerPacks.first;
  }

  List<Sticker> _orderedStickers(StickerPack pack) {
    final remaining = {
      for (final sticker in pack.stickers) sticker.id: sticker,
    };
    final draftOrder =
        _stickerOrderDrafts[pack.id] ??
        pack.stickers.map((sticker) => sticker.id).toList();
    final ordered = <Sticker>[];
    for (final stickerId in draftOrder) {
      final sticker = remaining.remove(stickerId);
      if (sticker != null) ordered.add(sticker);
    }
    ordered.addAll(remaining.values);
    return ordered;
  }

  bool _stickerOrderDirty(StickerPack pack) {
    final original = pack.stickers.map((sticker) => sticker.id).toList();
    final draft = _orderedStickers(pack).map((sticker) => sticker.id).toList();
    if (original.length != draft.length) return true;
    for (var i = 0; i < original.length; i++) {
      if (original[i] != draft[i]) return true;
    }
    return false;
  }

  void _selectStickerPack(String packId) {
    if (_activeStickerPackId == packId) return;
    setState(() {
      _activeStickerPackId = packId;
      _selectedStickerIds = <String>{};
    });
  }

  Future<StickerPack> _ensureActiveStickerPack() async {
    final existing = _selectedStickerPack();
    if (existing != null) return existing;

    final api = widget.api;
    if (api == null) {
      throw StateError('表情包需要登录后从服务端读取');
    }
    final created = await api.createStickerPack(
      name: '我的表情包',
      sortOrder: (_stickerPacks.length + 1) * 10,
    );
    if (mounted) {
      setState(() {
        _stickerPacks = [..._stickerPacks, created];
        _activeStickerPackId = created.id;
        _stickerOrderDrafts[created.id] = <String>[];
      });
    }
    return created;
  }

  Future<void> _pickAndUploadStickers() async {
    final api = widget.api;
    if (api == null || _uploadingStickers) return;

    List<XFile> files;
    try {
      files = await openFiles(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _stickerError = '无法打开文件选择器：$e');
      return;
    }
    if (files.isEmpty) return;

    setState(() {
      _uploadingStickers = true;
      _stickerError = null;
      _notice = null;
    });
    var uploadedCount = 0;
    try {
      final pack = await _ensureActiveStickerPack();
      var sortIndex = pack.stickers.length;
      for (final entry in files.asMap().entries) {
        final file = entry.value;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          throw StateError('${file.name} 文件为空');
        }
        final asset = await api.uploadImageAsset(
          bytes: bytes,
          filename: _stickerUploadFilename(file.name, entry.key),
          purpose: 'sticker',
        );
        await api.addSticker(
          packId: pack.id,
          assetId: asset.id,
          name: _stickerNameFromFilename(file.name),
          sortOrder: (++sortIndex) * 10,
        );
        uploadedCount += 1;
      }
      await _loadStickers();
      _showNotice('已添加 $uploadedCount 个表情');
    } catch (e) {
      if (!mounted) return;
      setState(() => _stickerError = e.toString());
    } finally {
      if (mounted) setState(() => _uploadingStickers = false);
    }
  }

  void _toggleStickerSelection(String stickerId, bool selected) {
    setState(() {
      final next = Set<String>.from(_selectedStickerIds);
      if (selected) {
        next.add(stickerId);
      } else {
        next.remove(stickerId);
      }
      _selectedStickerIds = next;
    });
  }

  void _toggleSelectAllStickers() {
    final pack = _selectedStickerPack();
    if (pack == null) return;
    final allIds = _orderedStickers(pack).map((sticker) => sticker.id).toSet();
    setState(() {
      _selectedStickerIds = _selectedStickerIds.length == allIds.length
          ? <String>{}
          : allIds;
    });
  }

  Future<void> _deleteSelectedStickers() async {
    final api = widget.api;
    final pack = _selectedStickerPack();
    final selectedIds = Set<String>.from(_selectedStickerIds);
    if (api == null ||
        pack == null ||
        selectedIds.isEmpty ||
        _deletingStickers) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmActionDialog(
        title: '删除表情',
        body: '将从服务端删除选中的 ${selectedIds.length} 个表情，删除后不会再出现在你的表情包里。',
        confirmLabel: '删除',
        confirmIcon: Icons.delete_outline,
        danger: true,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deletingStickers = true;
      _stickerError = null;
      _notice = null;
    });
    try {
      for (final stickerId in selectedIds) {
        await api.deleteSticker(packId: pack.id, stickerId: stickerId);
      }
      await _loadStickers();
      _showNotice('已删除 ${selectedIds.length} 个表情');
    } catch (e) {
      if (!mounted) return;
      setState(() => _stickerError = e.toString());
    } finally {
      if (mounted) setState(() => _deletingStickers = false);
    }
  }

  void _moveSticker(StickerPack pack, String stickerId, int delta) {
    final ordered = _orderedStickers(pack);
    final from = ordered.indexWhere((sticker) => sticker.id == stickerId);
    if (from < 0) return;
    final to = (from + delta).clamp(0, ordered.length - 1).toInt();
    if (from == to) return;
    final ids = ordered.map((sticker) => sticker.id).toList();
    final moving = ids.removeAt(from);
    ids.insert(to, moving);
    setState(() => _stickerOrderDrafts[pack.id] = ids);
  }

  Future<void> _saveStickerOrder() async {
    final api = widget.api;
    final pack = _selectedStickerPack();
    if (api == null || pack == null || _savingStickerOrder) return;
    if (!_stickerOrderDirty(pack)) {
      _showNotice('表情排序没有变化');
      return;
    }

    final ordered = _orderedStickers(pack);
    setState(() {
      _savingStickerOrder = true;
      _stickerError = null;
      _notice = null;
    });
    try {
      // The server currently accepts sticker sort_order only when creating a
      // sticker, so persisting a reordered pack rebuilds the pack contents.
      for (final entry in ordered.asMap().entries) {
        final sticker = entry.value;
        await api.addSticker(
          packId: pack.id,
          assetId: sticker.asset.id,
          name: sticker.name,
          sortOrder: (entry.key + 1) * 10,
        );
      }
      for (final sticker in pack.stickers) {
        await api.deleteSticker(packId: pack.id, stickerId: sticker.id);
      }
      await _loadStickers();
      _showNotice('表情排序已保存');
    } catch (e) {
      if (!mounted) return;
      setState(() => _stickerError = e.toString());
    } finally {
      if (mounted) setState(() => _savingStickerOrder = false);
    }
  }

  void _previewSticker(Sticker sticker) {
    final imageUrl = AppConfigScope.of(
      context,
    ).resolveAssetUrl(sticker.asset.url);
    if (imageUrl == null) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) =>
            _StickerPreviewDialog(sticker: sticker, imageUrl: imageUrl),
      ),
    );
  }

  void _usePresetAvatar() {
    _selectDefaultAvatarKey(_defaultAvatarKey);
  }

  void _selectDefaultAvatarKey(String value) {
    setState(() {
      _defaultAvatarKey = value;
      _pendingAvatarAssetId = null;
      _pendingAvatarUrl = null;
      _clearUploadedAvatar = _user?.avatarUrl != null;
      _notice = _clearUploadedAvatar ? '保存用户资料后将使用预设头像' : null;
    });
  }

  Future<void> _changePassword() async {
    final api = widget.api;
    if (api == null || _changingPassword) return;
    final current = _currentPasswordController.text;
    final next = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      setState(() => _securityError = '请完整填写当前密码、新密码和确认密码');
      return;
    }
    if (next.length < 8) {
      setState(() => _securityError = '新密码至少需要 8 个字符');
      return;
    }
    if (next != confirm) {
      setState(() => _securityError = '两次输入的新密码不一致');
      return;
    }

    setState(() {
      _changingPassword = true;
      _securityError = null;
      _notice = null;
    });
    try {
      await api.changePassword(currentPassword: current, newPassword: next);
      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _showNotice('密码已更新');
      unawaited(_loadSessions());
    } catch (e) {
      if (!mounted) return;
      setState(() => _securityError = e.toString());
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final api = widget.api;
    final user = _user;
    if (api == null || user == null || _deletingAccount) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteAccountDialog(username: user.username),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deletingAccount = true;
      _securityError = null;
      _notice = null;
    });
    try {
      await api.deleteMyAccount(confirm: true);
      if (!mounted) return;
      await widget.onAccountDeleted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _securityError = e.toString());
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    setState(() => _notice = message);
  }

  Future<void> _loadStoredAudioSettings() async {
    try {
      final stored = await widget.audioDeviceStore.read();
      if (!mounted) return;
      setState(() {
        _inputVolume = stored.inputVolume;
        _outputVolume = stored.outputVolume;
      });
      widget.onVolumeChanged?.call('audioinput', stored.inputVolume);
      widget.onVolumeChanged?.call('audiooutput', stored.outputVolume);
    } catch (_) {}
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _ensureDeviceAccess();
      final devices = await lk.Hardware.instance.enumerateDevices();
      await _applyDevices(devices);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _ensureDeviceAccess() async {
    if (_requestedDeviceAccess) return;
    _requestedDeviceAccess = true;
    try {
      final track = await lk.LocalAudioTrack.create();
      await track.start();
      await track.stop();
    } catch (_) {
      // Device enumeration below will surface the usable state. This call is
      // only here to trigger OS media permission before enumerateDevices().
    }
  }

  Future<void> _applyDevices(List<lk.MediaDevice> devices) async {
    if (!mounted) return;
    final inputs = devices
        .where((device) => device.kind == 'audioinput')
        .toList();
    final outputs = devices
        .where((device) => device.kind == 'audiooutput')
        .toList();
    RestoredAudioDevices restored = const RestoredAudioDevices();
    try {
      restored = await restoreStoredAudioDevices(
        widget.audioDeviceStore,
        devices: devices,
      );
    } catch (_) {
      // Device choices are a local convenience. If storage or OS routing fails,
      // keep rendering the current device list and let the user re-select.
    }
    if (!mounted) return;
    setState(() {
      _audioInputs = inputs;
      _audioOutputs = outputs;
      _selectedInput = _selectedFrom(inputs, [
        restored.input,
        lk.Hardware.instance.selectedAudioInput,
        _selectedInput,
      ]);
      _selectedOutput = _selectedFrom(outputs, [
        restored.output,
        lk.Hardware.instance.selectedAudioOutput,
        _selectedOutput,
      ]);
      _loading = false;
    });
  }

  lk.MediaDevice? _selectedFrom(
    List<lk.MediaDevice> devices,
    Iterable<lk.MediaDevice?> candidates,
  ) {
    if (devices.isEmpty) return null;
    for (final candidate in candidates) {
      if (candidate == null) continue;
      for (final device in devices) {
        if (device.deviceId == candidate.deviceId &&
            device.kind == candidate.kind) {
          return device;
        }
      }
    }
    return devices.first;
  }

  Future<void> _selectInput(lk.MediaDevice device) async {
    final wasTestingInput = _testingInput;
    final wasTestingOutput = _testingOutput;
    final didSelect = await _selectDevice(
      device,
      () => lk.Hardware.instance.selectAudioInput(device),
      () => widget.audioDeviceStore.writeInputDeviceId(device.deviceId),
      () => _selectedInput = device,
    );
    if (!didSelect) return;
    if (wasTestingInput) await _restartInputTest();
    if (wasTestingOutput) await _restartOutputTest();
  }

  Future<void> _selectOutput(lk.MediaDevice device) async {
    final didSelect = await _selectDevice(
      device,
      () => lk.Hardware.instance.selectAudioOutput(device),
      () => widget.audioDeviceStore.writeOutputDeviceId(device.deviceId),
      () => _selectedOutput = device,
    );
    if (didSelect && _testingOutput) await _routeOutputTest();
  }

  Future<bool> _selectDevice(
    lk.MediaDevice device,
    Future<void> Function() select,
    Future<void> Function() rememberSelection,
    VoidCallback applySelection,
  ) async {
    if (_busyDeviceId != null) return false;
    setState(() {
      _busyDeviceId = '${device.kind}:${device.deviceId}';
      _error = null;
    });
    var didSelect = false;
    try {
      await select();
      Object? storageError;
      try {
        await rememberSelection();
      } catch (e) {
        storageError = e;
      }
      if (!mounted) return false;
      setState(() {
        applySelection();
        if (storageError != null) {
          _error = 'Could not save audio device preference: $storageError';
        }
      });
      widget.onDeviceSelected?.call(device.kind, device.deviceId);
      didSelect = true;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyDeviceId = null);
    }
    return didSelect;
  }

  Future<void> _setInputVolume(double volume) async {
    final next = _normalizedVolume(volume);
    setState(() => _inputVolume = next);
    widget.onVolumeChanged?.call('audioinput', next);
    unawaited(widget.audioDeviceStore.writeInputVolume(next));
    final track = _inputTestTrack;
    if (track != null) {
      try {
        await rtc.Helper.setVolume(next, track.mediaStreamTrack);
      } catch (_) {}
    }
  }

  Future<void> _setOutputVolume(double volume) async {
    final next = _normalizedVolume(volume);
    setState(() => _outputVolume = next);
    widget.onVolumeChanged?.call('audiooutput', next);
    unawaited(widget.audioDeviceStore.writeOutputVolume(next));
    final renderer = _outputRenderer;
    if (renderer != null) {
      try {
        await renderer.setVolume(next);
      } catch (_) {}
    }
  }

  Future<void> _toggleInputTest() async {
    if (_testingInput) {
      await _stopInputTest();
    } else {
      await _startInputTest();
    }
  }

  Future<void> _toggleOutputTest() async {
    if (_testingOutput) {
      await _stopOutputTest();
    } else {
      await _startOutputTest();
    }
  }

  Future<void> _restartInputTest() async {
    await _stopInputTest();
    if (mounted) await _startInputTest();
  }

  Future<void> _restartOutputTest() async {
    await _stopOutputTest();
    if (mounted) await _startOutputTest();
  }

  Future<void> _startInputTest() async {
    if (_testingInput) return;
    setState(() {
      _testingInput = true;
      _inputLevel = 0;
      _error = null;
    });
    lk.LocalAudioTrack? track;
    try {
      track = await _createTestAudioTrack();
      await rtc.Helper.setVolume(_inputVolume, track.mediaStreamTrack);
      final visualizer = await _startVisualizer(
        track,
        (level) => _inputLevel = level * _inputVolume,
      );
      if (!mounted) {
        await _disposeTestTrack(track);
        return;
      }
      _inputTestTrack = track;
      _inputVisualizer = visualizer.visualizer;
      _inputVisualizerListener = visualizer.listener;
    } catch (e) {
      await _disposeTestTrack(track);
      if (!mounted) return;
      setState(() {
        _testingInput = false;
        _inputLevel = 0;
        _error = e.toString();
      });
    }
  }

  Future<void> _stopInputTest({bool updateState = true}) async {
    final track = _inputTestTrack;
    final visualizer = _inputVisualizer;
    final listener = _inputVisualizerListener;
    _inputTestTrack = null;
    _inputVisualizer = null;
    _inputVisualizerListener = null;
    await _stopVisualizer(visualizer, listener);
    await _disposeTestTrack(track);
    if (updateState && mounted) {
      setState(() {
        _testingInput = false;
        _inputLevel = 0;
      });
    }
  }

  Future<void> _startOutputTest() async {
    if (_testingOutput) return;
    setState(() {
      _testingOutput = true;
      _outputLevel = 0;
      _error = null;
    });
    lk.LocalAudioTrack? track;
    rtc.RTCVideoRenderer? renderer;
    try {
      track = await _createTestAudioTrack();
      renderer = rtc.RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = track.mediaStream;
      await renderer.setVolume(_outputVolume);
      _outputRenderer = renderer;
      await _routeOutputTest();
      final visualizer = await _startVisualizer(
        track,
        (level) => _outputLevel = level * _outputVolume,
      );
      if (!mounted) {
        await _disposeRenderer(renderer);
        await _disposeTestTrack(track);
        return;
      }
      _outputTestTrack = track;
      _outputVisualizer = visualizer.visualizer;
      _outputVisualizerListener = visualizer.listener;
    } catch (e) {
      if (_outputRenderer == renderer) _outputRenderer = null;
      await _disposeRenderer(renderer);
      await _disposeTestTrack(track);
      if (!mounted) return;
      setState(() {
        _testingOutput = false;
        _outputLevel = 0;
        _error = e.toString();
      });
    }
  }

  Future<void> _stopOutputTest({bool updateState = true}) async {
    final track = _outputTestTrack;
    final visualizer = _outputVisualizer;
    final listener = _outputVisualizerListener;
    final renderer = _outputRenderer;
    _outputTestTrack = null;
    _outputVisualizer = null;
    _outputVisualizerListener = null;
    _outputRenderer = null;
    await _stopVisualizer(visualizer, listener);
    await _disposeRenderer(renderer);
    await _disposeTestTrack(track);
    if (updateState && mounted) {
      setState(() {
        _testingOutput = false;
        _outputLevel = 0;
      });
    }
  }

  Future<lk.LocalAudioTrack> _createTestAudioTrack() async {
    await _ensureDeviceAccess();
    final track = await lk.LocalAudioTrack.create(
      lk.AudioCaptureOptions(deviceId: _selectedInput?.deviceId),
    );
    await track.start();
    return track;
  }

  Future<void> _routeOutputTest() async {
    final renderer = _outputRenderer;
    final device = _selectedOutput;
    if (renderer == null || device == null) return;
    try {
      await renderer.audioOutput(device.deviceId);
    } catch (_) {}
  }

  Future<_StartedVisualizer> _startVisualizer(
    lk.LocalAudioTrack track,
    void Function(double level) applyLevel,
  ) async {
    final visualizer = lk.createVisualizer(
      track,
      options: const lk.AudioVisualizerOptions(
        barCount: 14,
        centeredBands: false,
      ),
    );
    final listener = visualizer.createListener();
    listener.on<lk.AudioVisualizerEvent>((event) {
      if (!mounted) return;
      setState(() => applyLevel(_levelFromVisualizerEvent(event)));
    });
    try {
      await visualizer.start();
    } catch (_) {
      await _stopVisualizer(visualizer, listener);
      rethrow;
    }
    return _StartedVisualizer(visualizer, listener);
  }

  Future<void> _stopVisualizer(
    lk.AudioVisualizer? visualizer,
    lk.EventsListener<lk.AudioVisualizerEvent>? listener,
  ) async {
    try {
      await visualizer?.stop();
    } catch (_) {}
    try {
      await visualizer?.dispose();
    } catch (_) {}
    try {
      await listener?.dispose();
    } catch (_) {}
  }

  Future<void> _disposeTestTrack(lk.LocalAudioTrack? track) async {
    if (track == null) return;
    try {
      await track.stop();
    } catch (_) {}
    try {
      await track.dispose();
    } catch (_) {}
  }

  Future<void> _disposeRenderer(rtc.RTCVideoRenderer? renderer) async {
    if (renderer == null) return;
    try {
      renderer.srcObject = null;
    } catch (_) {}
    try {
      await renderer.dispose();
    } catch (_) {}
  }

  bool get _isRefreshing {
    return switch (_section) {
      _SettingsSection.profile => _loadingAccount,
      _SettingsSection.stickers => _loadingStickers,
      _SettingsSection.security => _loadingAccount || _loadingSessions,
      _SettingsSection.voice => _loading,
    };
  }

  String get _activeTitle {
    return switch (_section) {
      _SettingsSection.profile => '用户资料',
      _SettingsSection.stickers => '我的表情包',
      _SettingsSection.security => '隐私和安全',
      _SettingsSection.voice => '默认语音源',
    };
  }

  Widget _buildSectionContent() {
    return switch (_section) {
      _SettingsSection.profile => _buildProfileContent(),
      _SettingsSection.stickers => _buildStickersContent(),
      _SettingsSection.security => _buildSecurityContent(),
      _SettingsSection.voice => _buildVoiceContent(),
    };
  }

  Widget _buildStickersContent() {
    final unavailable = widget.api == null;
    final pack = _selectedStickerPack();
    final stickers = pack == null ? const <Sticker>[] : _orderedStickers(pack);
    final allSelected =
        stickers.isNotEmpty && _selectedStickerIds.length == stickers.length;
    final orderDirty = pack != null && _stickerOrderDirty(pack);

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 30, 32),
      children: [
        _ContentTitle(title: '我的表情包', loading: _loadingStickers),
        if (_notice != null) ...[
          const SizedBox(height: 12),
          _SettingsNotice(message: _notice!),
        ],
        if (_stickerError != null) ...[
          const SizedBox(height: 12),
          _SettingsError(message: _stickerError!),
        ],
        const SizedBox(height: 18),
        if (unavailable)
          const _SettingsEmptyState(text: '表情包需要登录后从服务端读取')
        else
          _SettingsGroup(
            title: '服务端表情',
            trailing: Text(
              '${stickers.length} 个',
              style: const TextStyle(
                color: _textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            children: [
              _StickerPackSelector(
                packs: _stickerPacks,
                selectedPackId: pack?.id,
                loading: _loadingStickers,
                onSelected: _selectStickerPack,
              ),
              const SizedBox(height: 14),
              _StickerToolbar(
                selectedCount: _selectedStickerIds.length,
                allSelected: allSelected,
                hasStickers: stickers.isNotEmpty,
                orderDirty: orderDirty,
                uploading: _uploadingStickers,
                deleting: _deletingStickers,
                savingOrder: _savingStickerOrder,
                onUpload: _pickAndUploadStickers,
                onToggleAll: _toggleSelectAllStickers,
                onDeleteSelected: _deleteSelectedStickers,
                onSaveOrder: _saveStickerOrder,
              ),
              const SizedBox(height: 14),
              if (_loadingStickers && _stickerPacks.isEmpty)
                const SizedBox(
                  height: 128,
                  child: Center(child: CircularProgressIndicator(color: _cyan)),
                )
              else if (pack == null)
                const _SettingsEmptyState(text: '暂无表情包，批量上传会自动创建')
              else if (stickers.isEmpty)
                const _SettingsEmptyState(text: '当前表情包为空')
              else
                _StickerManagementList(
                  stickers: stickers,
                  selectedIds: _selectedStickerIds,
                  busy:
                      _uploadingStickers ||
                      _deletingStickers ||
                      _savingStickerOrder,
                  onToggleSelected: _toggleStickerSelection,
                  onMoveUp: (sticker) => _moveSticker(pack, sticker.id, -1),
                  onMoveDown: (sticker) => _moveSticker(pack, sticker.id, 1),
                  onPreview: _previewSticker,
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildProfileContent() {
    final user = _user;
    final unavailable = widget.api == null || user == null;
    final appConfig = AppConfigScope.of(context);
    final avatarPreviewUrl = _clearUploadedAvatar
        ? null
        : appConfig.resolveAssetUrl(_pendingAvatarUrl ?? user?.avatarUrl);
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 30, 32),
      children: [
        _ContentTitle(title: '用户资料', loading: _loadingAccount),
        if (_notice != null) ...[
          const SizedBox(height: 12),
          _SettingsNotice(message: _notice!),
        ],
        if (_accountError != null) ...[
          const SizedBox(height: 12),
          _SettingsError(message: _accountError!),
        ],
        const SizedBox(height: 18),
        if (unavailable)
          const _SettingsEmptyState(text: '账号资料需要登录后从服务端读取')
        else ...[
          _SettingsGroup(
            title: '账号标识',
            children: [
              _CopyableField(
                label: '个人 UID',
                value: user.uid,
                tooltip: '复制 UID',
                onCopy: () => _copyText(user.uid, 'UID 已复制'),
              ),
              const SizedBox(height: 14),
              _LabeledTextField(
                label: '登录 Username',
                controller: _usernameController,
                enabled: _canEditUsername(user),
                suffixIcon: _copyControllerButton(
                  _usernameController,
                  '复制 Username',
                  'Username 已复制',
                ),
                helperText: _usernameHelper(user),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsGroup(
            title: '默认资料',
            children: [
              _LabeledTextField(
                label: '用户名',
                controller: _displayNameController,
                suffixIcon: _copyControllerButton(
                  _displayNameController,
                  '复制用户名',
                  '用户名已复制',
                ),
                helperText: '没有房间个人资料覆盖时展示。',
              ),
              const SizedBox(height: 14),
              _SegmentedSetting(
                label: '性别',
                value: _gender,
                options: const [
                  _SegmentOption(value: 'male', label: '男'),
                  _SegmentOption(value: 'female', label: '女'),
                  _SegmentOption(value: 'secret', label: '保密'),
                ],
                onChanged: (value) => setState(() => _gender = value),
              ),
              const SizedBox(height: 14),
              _AvatarKeyPicker(
                value: _defaultAvatarKey,
                displayName: _displayNameController.text,
                avatarUrl: avatarPreviewUrl,
                uploading: _uploadingAvatar,
                onChanged: _selectDefaultAvatarKey,
                onUpload: _pickAndUploadAvatar,
                onUsePreset: _usePresetAvatar,
              ),
              const SizedBox(height: 14),
              _LabeledTextField(
                label: '签名',
                controller: _bioController,
                maxLines: 4,
                suffixIcon: _copyControllerButton(
                  _bioController,
                  '复制签名',
                  '签名已复制',
                ),
                helperText: '用于个人资料面板展示。',
              ),
            ],
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: KeyButton(
              onPressed: _savingProfile ? null : _saveProfile,
              loading: _savingProfile,
              icon: const Icon(Icons.save_outlined),
              tone: KeyButtonTone.primary,
              child: const Text('保存用户资料'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSecurityContent() {
    final user = _user;
    final unavailable = widget.api == null || user == null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 30, 32),
      children: [
        _ContentTitle(title: '隐私和安全', loading: _loadingAccount),
        if (_notice != null) ...[
          const SizedBox(height: 12),
          _SettingsNotice(message: _notice!),
        ],
        if (_securityError != null) ...[
          const SizedBox(height: 12),
          _SettingsError(message: _securityError!),
        ],
        const SizedBox(height: 18),
        if (unavailable)
          const _SettingsEmptyState(text: '安全设置需要登录后从服务端读取')
        else ...[
          _SettingsGroup(
            title: '绑定信息',
            children: [
              _LabeledTextField(
                label: '邮箱绑定',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                suffixIcon: _copyControllerButton(
                  _emailController,
                  '复制邮箱',
                  '邮箱已复制',
                ),
                helperText: '用于登录、账号找回和安全通知。',
              ),
              const SizedBox(height: 10),
              _ToggleSetting(
                label: '公开邮箱',
                value: _emailPublic,
                onChanged: (value) => setState(() => _emailPublic = value),
              ),
              const SizedBox(height: 14),
              _LabeledTextField(
                label: '手机号绑定',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                suffixIcon: _copyControllerButton(
                  _phoneController,
                  '复制手机号',
                  '手机号已复制',
                ),
                helperText: '用于账号找回和安全通知，留空表示解绑。',
              ),
              const SizedBox(height: 10),
              _ToggleSetting(
                label: '公开手机号',
                value: _phonePublic,
                onChanged: (value) => setState(() => _phonePublic = value),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: KeyButton(
                  onPressed: _savingAccount ? null : _saveAccount,
                  loading: _savingAccount,
                  icon: const Icon(Icons.save_outlined),
                  tone: KeyButtonTone.primary,
                  child: const Text('保存绑定信息'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsGroup(
            title: '重置密码',
            children: [
              _LabeledTextField(
                label: '当前密码',
                controller: _currentPasswordController,
                obscureText: _obscureCurrentPassword,
                onTogglePasswordVisibility: () {
                  setState(() {
                    _obscureCurrentPassword = !_obscureCurrentPassword;
                  });
                },
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                label: '新密码',
                controller: _newPasswordController,
                obscureText: _obscureNewPassword,
                onTogglePasswordVisibility: () {
                  setState(() {
                    _obscureNewPassword = !_obscureNewPassword;
                  });
                },
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                label: '确认新密码',
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                onTogglePasswordVisibility: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: KeyButton(
                      onPressed: null,
                      icon: const Icon(Icons.help_outline),
                      child: const Text('忘记密码'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KeyButton(
                      onPressed: _changingPassword ? null : _changePassword,
                      loading: _changingPassword,
                      icon: const Icon(Icons.lock_reset),
                      tone: KeyButtonTone.primary,
                      child: const Text('更新密码'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsGroup(
            title: '账号活动',
            trailing: KeyIconButton(
              tooltip: '刷新账号活动',
              onPressed: _loadingSessions ? null : _loadSessions,
              icon: const Icon(Icons.refresh),
              size: 30,
            ),
            children: [
              _ReadOnlyLine(
                label: '账号创建时间',
                value: _formatDateTime(user.createdAt),
              ),
              const SizedBox(height: 14),
              _SessionList(sessions: _sessions, loading: _loadingSessions),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsGroup(
            title: '注销账号',
            danger: true,
            children: [
              Text(
                user.isSuperuser
                    ? '超级用户账号不能被注销。'
                    : '注销后账号不能继续登录，当前会话会失效，服务端将删除和该账号有关的信息。',
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: KeyButton(
                  onPressed: user.isSuperuser || _deletingAccount
                      ? null
                      : _confirmDeleteAccount,
                  loading: _deletingAccount,
                  icon: const Icon(Icons.delete_outline),
                  tone: KeyButtonTone.danger,
                  child: const Text('注销账号'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildVoiceContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 30, 32),
      children: [
        _ContentTitle(title: '默认语音源', loading: _loading),
        const SizedBox(height: 18),
        _SettingsGroup(
          title: '输入',
          children: [
            _SettingsSubPanel(
              child: _DeviceSection(
                title: '输入源',
                icon: Icons.mic,
                devices: _audioInputs,
                selectedDevice: _selectedInput,
                busyDeviceId: _busyDeviceId,
                emptyText: _loading ? '正在加载输入源' : '未找到输入源',
                fallbackLabel: '麦克风',
                onSelect: _selectInput,
              ),
            ),
            const SizedBox(height: 12),
            _SettingsSubPanel(
              child: _AudioControlPanel(
                title: '输入音量',
                icon: Icons.graphic_eq,
                volume: _inputVolume,
                level: _inputLevel,
                testing: _testingInput,
                testTooltip: _testingInput ? '停止输入测试' : '测试输入音量',
                disabled: _audioInputs.isEmpty,
                onVolumeChanged: (value) => unawaited(_setInputVolume(value)),
                onToggleTest: _toggleInputTest,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsGroup(
          title: '输出',
          children: [
            _SettingsSubPanel(
              child: _DeviceSection(
                title: '输出源',
                icon: Icons.headphones,
                devices: _audioOutputs,
                selectedDevice: _selectedOutput,
                busyDeviceId: _busyDeviceId,
                emptyText: _loading ? '正在加载输出源' : '未找到输出源',
                fallbackLabel: '输出',
                onSelect: _selectOutput,
              ),
            ),
            const SizedBox(height: 12),
            _SettingsSubPanel(
              child: _AudioControlPanel(
                title: '输出音量',
                icon: Icons.volume_up,
                volume: _outputVolume,
                level: _outputLevel,
                testing: _testingOutput,
                testTooltip: _testingOutput ? '停止输出测试' : '测试输出音量',
                disabled: _audioOutputs.isEmpty,
                onVolumeChanged: (value) => unawaited(_setOutputVolume(value)),
                onToggleTest: _toggleOutputTest,
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 28),
          _SettingsError(message: _error!),
        ],
      ],
    );
  }

  bool _canEditUsername(CurrentUser user) {
    final canAt = user.canChangeUsernameAt;
    return canAt == null || !canAt.isAfter(DateTime.now());
  }

  String _usernameHelper(CurrentUser user) {
    final canAt = user.canChangeUsernameAt;
    if (canAt == null || !canAt.isAfter(DateTime.now())) {
      return '用于登录和账号识别；同一账号一天只能修改一次。';
    }
    return '下次可修改时间：${_formatDateTime(canAt)}';
  }

  Future<void> _copyText(String value, String notice) async {
    await Clipboard.setData(ClipboardData(text: value));
    _showNotice(notice);
  }

  Widget _copyControllerButton(
    TextEditingController controller,
    String tooltip,
    String notice,
  ) {
    return KeyIconButton(
      tooltip: tooltip,
      onPressed: () => _copyText(controller.text.trim(), notice),
      icon: const Icon(Icons.copy),
      size: 30,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _primaryDarkLow,
      body: Column(
        children: [
          Container(
            // Drop the header below the window-controls strip so the title and
            // refresh button clear the drag band and window buttons.
            height: 48 + titleBarHeight,
            padding: const EdgeInsets.fromLTRB(22, titleBarHeight, 22, 0),
            color: _primaryDarkLow,
            child: Row(
              children: [
                if (!widget.isSubWindow) ...[
                  KeyIconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    size: 38,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Text(
                      'Settings · $_activeTitle',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: KeySurface(
                    onPressed: _isRefreshing ? null : _refreshActiveSection,
                    tooltip: 'Refresh settings',
                    enabled: !_isRefreshing,
                    height: 34,
                    padding: EdgeInsets.zero,
                    backgroundColor: _primaryDarkLow,
                    selectedBackgroundColor: _primaryDarkLow,
                    pressedBackgroundColor: _primaryDark,
                    borderColor: _primaryDarkLow,
                    selectedBorderColor: _primaryDarkLow,
                    hoverLift: 3,
                    pressDepth: 3,
                    baseDepth: 5,
                    child: IconTheme.merge(
                      data: const IconThemeData(
                        color: _textSecondary,
                        size: 16,
                      ),
                      child: const Center(child: Icon(Icons.refresh)),
                    ),
                  ),
                ),
                if (widget.onClose != null) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 34,
                    child: KeySurface(
                      onPressed: widget.onClose,
                      tooltip: 'Close settings',
                      height: 34,
                      padding: EdgeInsets.zero,
                      backgroundColor: _primaryDarkLow,
                      selectedBackgroundColor: _primaryDarkLow,
                      pressedBackgroundColor: _primaryDark,
                      borderColor: _primaryDarkLow,
                      selectedBorderColor: _primaryDarkLow,
                      hoverLift: 3,
                      pressDepth: 3,
                      baseDepth: 5,
                      child: IconTheme.merge(
                        data: const IconThemeData(
                          color: _textSecondary,
                          size: 16,
                        ),
                        child: const Center(child: Icon(Icons.close)),
                      ),
                    ),
                  ),
                ],
                // Pull the refresh button further inward from the edge.
                const SizedBox(width: 16),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                _SettingsNavigation(
                  selected: _section,
                  onChanged: (section) {
                    setState(() {
                      _section = section;
                      _notice = null;
                    });
                    if (section == _SettingsSection.stickers) {
                      unawaited(_ensureStickersLoaded());
                    }
                    if (section == _SettingsSection.security &&
                        _sessions.isEmpty &&
                        !_loadingSessions) {
                      unawaited(_loadSessions());
                    }
                    if (section == _SettingsSection.voice) {
                      unawaited(_ensureVoiceInitialized());
                    }
                  },
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: _borderColor,
                ),
                Expanded(child: _buildSectionContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation({required this.selected, required this.onChanged});

  final _SettingsSection selected;
  final ValueChanged<_SettingsSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 188,
      child: ColoredBox(
        color: _primaryDarkLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NavItem(
                title: '用户资料',
                icon: Icons.badge_outlined,
                selected: selected == _SettingsSection.profile,
                onPressed: () => onChanged(_SettingsSection.profile),
              ),
              const SizedBox(height: 8),
              _NavItem(
                title: '隐私和安全',
                icon: Icons.shield_outlined,
                selected: selected == _SettingsSection.security,
                onPressed: () => onChanged(_SettingsSection.security),
              ),
              const SizedBox(height: 8),
              _NavItem(
                title: '默认语音源',
                icon: Icons.graphic_eq,
                selected: selected == _SettingsSection.voice,
                onPressed: () => onChanged(_SettingsSection.voice),
              ),
              const SizedBox(height: 8),
              _NavItem(
                title: '我的表情包',
                icon: Icons.emoji_emotions_outlined,
                selected: selected == _SettingsSection.stickers,
                onPressed: () => onChanged(_SettingsSection.stickers),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return KeySurface(
      onPressed: onPressed,
      selected: selected,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      backgroundColor: _primaryDarkLow,
      selectedBackgroundColor: const Color(0xFF1F2D27),
      pressedBackgroundColor: _primaryDark,
      borderColor: selected ? _cyan : _borderColor,
      selectedBorderColor: _cyan,
      hoverLift: 2,
      pressDepth: 2,
      baseDepth: 4,
      child: Row(
        children: [
          Icon(icon, color: selected ? _cyan : _textMuted, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? _textPrimary : _textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentTitle extends StatelessWidget {
  const _ContentTitle({required this.title, required this.loading});

  final String title;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (loading)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
          ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
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
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
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

class _SettingsSubPanel extends StatelessWidget {
  const _SettingsSubPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _primaryDark,
        border: Border.all(color: _borderColor),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.controller,
    this.enabled = true,
    this.maxLines = 1,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.helperText,
    this.onTogglePasswordVisibility,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final int maxLines;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? helperText;
  final VoidCallback? onTogglePasswordVisibility;

  @override
  Widget build(BuildContext context) {
    final effectiveSuffixIcon = onTogglePasswordVisibility == null
        ? suffixIcon
        : _PasswordVisibilityToggle(
            obscure: obscureText,
            enabled: enabled,
            onPressed: onTogglePasswordVisibility!,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: obscureText ? 1 : maxLines,
          obscureText: obscureText,
          keyboardType: keyboardType,
          cursorColor: _textSecondary,
          style: TextStyle(
            color: enabled ? _textPrimary : _textMuted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            isDense: true,
            suffixIcon: effectiveSuffixIcon,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 38,
            ),
          ),
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

class _CopyableField extends StatelessWidget {
  const _CopyableField({
    required this.label,
    required this.value,
    required this.tooltip,
    required this.onCopy,
  });

  final String label;
  final String value;
  final String tooltip;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _primaryDark,
            border: Border.all(color: _borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 7, 8, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                KeyIconButton(
                  tooltip: tooltip,
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

class _ReadOnlyLine extends StatelessWidget {
  const _ReadOnlyLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 110, child: _FieldLabel(label)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleSetting extends StatelessWidget {
  const _ToggleSetting({
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
        Expanded(child: _FieldLabel(label)),
        Switch(
          value: value,
          activeThumbColor: _cyan,
          activeTrackColor: _cyan.withValues(alpha: 0.26),
          inactiveThumbColor: _textMuted,
          inactiveTrackColor: _borderColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SegmentOption {
  const _SegmentOption({required this.value, required this.label});

  final String value;
  final String label;
}

class _SegmentedSetting extends StatelessWidget {
  const _SegmentedSetting({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<_SegmentOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final option in options) ...[
              Expanded(
                child: KeySurface(
                  onPressed: () => onChanged(option.value),
                  selected: value == option.value,
                  height: 36,
                  backgroundColor: _primaryDark,
                  selectedBackgroundColor: const Color(0xFF1F2D27),
                  pressedBackgroundColor: _primaryDarkLow,
                  borderColor: _borderColor,
                  selectedBorderColor: _cyan,
                  hoverLift: 2,
                  pressDepth: 2,
                  baseDepth: 4,
                  child: Center(
                    child: Text(
                      option.label,
                      style: TextStyle(
                        color: value == option.value ? _cyan : _textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              if (option != options.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

class _AvatarKeyPicker extends StatelessWidget {
  const _AvatarKeyPicker({
    required this.value,
    required this.displayName,
    required this.avatarUrl,
    required this.uploading,
    required this.onChanged,
    required this.onUpload,
    required this.onUsePreset,
  });

  static const _keys = [
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

  final String value;
  final String displayName;
  final String? avatarUrl;
  final bool uploading;
  final ValueChanged<String> onChanged;
  final VoidCallback onUpload;
  final VoidCallback onUsePreset;

  @override
  Widget build(BuildContext context) {
    final uploadedSelected = avatarUrl != null;
    final presetSelected = !uploadedSelected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel('头像'),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Center(
                child: _AvatarPreview(
                  label: displayName,
                  imageUrl: avatarUrl,
                  defaultAvatarKey: value,
                  size: 88,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final key in _keys)
                    Tooltip(
                      message: key,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(key),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _avatarColor(key),
                            border: Border.all(
                              color: presetSelected && value == key
                                  ? _cyan
                                  : _borderColor,
                              width: presetSelected && value == key ? 2 : 1,
                            ),
                          ),
                          child: const SizedBox.square(dimension: 30),
                        ),
                      ),
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
              child: KeyButton(
                onPressed: uploading ? null : onUpload,
                loading: uploading,
                icon: const Icon(Icons.upload_file),
                tone: uploadedSelected
                    ? KeyButtonTone.primary
                    : KeyButtonTone.neutral,
                selected: uploadedSelected,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                width: double.infinity,
                child: const Text('上传头像'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: KeyButton(
                onPressed: uploading ? null : onUsePreset,
                icon: const Icon(Icons.restart_alt),
                tone: presetSelected
                    ? KeyButtonTone.primary
                    : KeyButtonTone.neutral,
                selected: presetSelected,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                width: double.infinity,
                child: const Text('预设头像'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.label,
    required this.imageUrl,
    required this.defaultAvatarKey,
    required this.size,
  });

  final String label;
  final String? imageUrl;
  final String defaultAvatarKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: _avatarColor(defaultAvatarKey),
      child: Center(
        child: Text(
          _initials(label),
          style: TextStyle(
            color: _textPrimary,
            fontSize: (size * 0.36).clamp(12, 28).toDouble(),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
    final imageUrl = this.imageUrl;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: _borderColor)),
        child: ClipRect(
          child: imageUrl == null
              ? fallback
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.sessions, required this.loading});

  final List<UserSession> sessions;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading && sessions.isEmpty) {
      return const SizedBox(
        height: 82,
        child: Center(child: CircularProgressIndicator(color: _cyan)),
      );
    }
    if (sessions.isEmpty) {
      return const _SettingsEmptyState(text: '暂无近期账号活动');
    }
    return Column(
      children: [
        for (final session in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _primaryDark,
                border: Border.all(color: _borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          session.isCurrent
                              ? Icons.radio_button_checked
                              : Icons.devices_other,
                          color: session.isCurrent ? _cyan : _textMuted,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            session.userAgent?.trim().isEmpty == false
                                ? session.userAgent!
                                : 'Unknown device',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _sessionStateText(session),
                          style: TextStyle(
                            color: session.isActive ? _cyan : _textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${session.location} · ${session.ipAddress ?? 'Unknown IP'} · ${_formatDateTime(session.lastUsedAt)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StickerPackSelector extends StatelessWidget {
  const _StickerPackSelector({
    required this.packs,
    required this.selectedPackId,
    required this.loading,
    required this.onSelected,
  });

  final List<StickerPack> packs;
  final String? selectedPackId;
  final bool loading;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (packs.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final pack in packs)
          _StickerPackChip(
            pack: pack,
            selected: pack.id == selectedPackId,
            loading: loading,
            onPressed: () => onSelected(pack.id),
          ),
      ],
    );
  }
}

class _StickerPackChip extends StatelessWidget {
  const _StickerPackChip({
    required this.pack,
    required this.selected,
    required this.loading,
    required this.onPressed,
  });

  final StickerPack pack;
  final bool selected;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178,
      child: KeySurface(
        onPressed: loading ? null : onPressed,
        selected: selected,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: _primaryDark,
        selectedBackgroundColor: const Color(0xFF1F2D27),
        pressedBackgroundColor: _primaryDarkLow,
        borderColor: selected ? _cyan : _borderColor,
        selectedBorderColor: _cyan,
        child: Row(
          children: [
            Icon(
              Icons.emoji_emotions_outlined,
              color: selected ? _cyan : _textMuted,
              size: 17,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                pack.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? _textPrimary : _textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${pack.stickers.length}',
              style: TextStyle(
                color: selected ? _cyan : _textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickerToolbar extends StatelessWidget {
  const _StickerToolbar({
    required this.selectedCount,
    required this.allSelected,
    required this.hasStickers,
    required this.orderDirty,
    required this.uploading,
    required this.deleting,
    required this.savingOrder,
    required this.onUpload,
    required this.onToggleAll,
    required this.onDeleteSelected,
    required this.onSaveOrder,
  });

  final int selectedCount;
  final bool allSelected;
  final bool hasStickers;
  final bool orderDirty;
  final bool uploading;
  final bool deleting;
  final bool savingOrder;
  final VoidCallback onUpload;
  final VoidCallback onToggleAll;
  final VoidCallback onDeleteSelected;
  final VoidCallback onSaveOrder;

  @override
  Widget build(BuildContext context) {
    final busy = uploading || deleting || savingOrder;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        KeyButton(
          onPressed: busy ? null : onUpload,
          loading: uploading,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          tone: KeyButtonTone.primary,
          child: const Text('批量添加'),
        ),
        KeyButton(
          onPressed: busy || !hasStickers ? null : onToggleAll,
          icon: Icon(allSelected ? Icons.deselect_outlined : Icons.select_all),
          child: Text(allSelected ? '取消全选' : '全选'),
        ),
        KeyButton(
          onPressed: busy || selectedCount == 0 ? null : onDeleteSelected,
          loading: deleting,
          icon: const Icon(Icons.delete_outline),
          tone: KeyButtonTone.danger,
          child: Text(selectedCount == 0 ? '批量删除' : '删除 $selectedCount 个'),
        ),
        KeyButton(
          onPressed: busy || !orderDirty ? null : onSaveOrder,
          loading: savingOrder,
          icon: const Icon(Icons.swap_vert),
          child: const Text('保存排序'),
        ),
      ],
    );
  }
}

class _StickerManagementList extends StatelessWidget {
  const _StickerManagementList({
    required this.stickers,
    required this.selectedIds,
    required this.busy,
    required this.onToggleSelected,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onPreview,
  });

  final List<Sticker> stickers;
  final Set<String> selectedIds;
  final bool busy;
  final void Function(String stickerId, bool selected) onToggleSelected;
  final ValueChanged<Sticker> onMoveUp;
  final ValueChanged<Sticker> onMoveDown;
  final ValueChanged<Sticker> onPreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final entry in stickers.asMap().entries)
          Padding(
            padding: EdgeInsets.only(
              bottom: entry.key == stickers.length - 1 ? 0 : 8,
            ),
            child: _StickerRow(
              sticker: entry.value,
              index: entry.key,
              total: stickers.length,
              selected: selectedIds.contains(entry.value.id),
              busy: busy,
              onToggleSelected: (selected) {
                onToggleSelected(entry.value.id, selected);
              },
              onMoveUp: () => onMoveUp(entry.value),
              onMoveDown: () => onMoveDown(entry.value),
              onPreview: () => onPreview(entry.value),
            ),
          ),
      ],
    );
  }
}

class _StickerRow extends StatelessWidget {
  const _StickerRow({
    required this.sticker,
    required this.index,
    required this.total,
    required this.selected,
    required this.busy,
    required this.onToggleSelected,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onPreview,
  });

  final Sticker sticker;
  final int index;
  final int total;
  final bool selected;
  final bool busy;
  final ValueChanged<bool> onToggleSelected;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final asset = sticker.asset;
    final dimensions = asset.width != null && asset.height != null
        ? '${asset.width}x${asset.height}'
        : '未知尺寸';
    return SizedBox(
      width: double.infinity,
      child: KeySurface(
        onPressed: onPreview,
        selected: selected,
        height: 76,
        padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
        backgroundColor: _primaryDark,
        selectedBackgroundColor: const Color(0xFF1F2D27),
        pressedBackgroundColor: _primaryDarkLow,
        borderColor: selected ? _cyan : _borderColor,
        selectedBorderColor: _cyan,
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: busy
                  ? null
                  : (value) => onToggleSelected(value ?? false),
              activeColor: _cyan,
              checkColor: _primaryDark,
              side: const BorderSide(color: _borderColor),
            ),
            _StickerThumbnail(sticker: sticker, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sticker.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${asset.mimeType} · $dimensions · #${index + 1}',
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
            const SizedBox(width: 10),
            KeyIconButton(
              tooltip: '预览表情',
              onPressed: onPreview,
              icon: const Icon(Icons.visibility_outlined),
              size: 32,
            ),
            const SizedBox(width: 8),
            KeyIconButton(
              tooltip: '上移',
              onPressed: busy || index == 0 ? null : onMoveUp,
              icon: const Icon(Icons.keyboard_arrow_up),
              size: 32,
            ),
            const SizedBox(width: 8),
            KeyIconButton(
              tooltip: '下移',
              onPressed: busy || index == total - 1 ? null : onMoveDown,
              icon: const Icon(Icons.keyboard_arrow_down),
              size: 32,
            ),
          ],
        ),
      ),
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
                  KeyButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  KeyButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    tone: danger ? KeyButtonTone.danger : KeyButtonTone.primary,
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

class _StickerPreviewDialog extends StatelessWidget {
  const _StickerPreviewDialog({required this.sticker, required this.imageUrl});

  final Sticker sticker;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final asset = sticker.asset;
    final dimensions = asset.width != null && asset.height != null
        ? '${asset.width}x${asset.height}'
        : '未知尺寸';
    return Dialog(
      backgroundColor: _primaryDarkLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: _borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
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
                      sticker.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  KeyIconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '关闭预览',
                    icon: const Icon(Icons.close),
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 360,
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
                          imageUrl,
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
              const SizedBox(height: 12),
              Text(
                '${asset.mimeType} · $dimensions',
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
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.username});

  final String username;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _controller.text.trim() == widget.username;
    return Dialog(
      backgroundColor: _primaryDarkLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: Color(0xFF3A2A2E)),
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
                '确认注销账号',
                style: TextStyle(
                  color: _danger,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '注销后账号不能继续登录，当前会话会失效，服务端将删除和该账号有关的信息。',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                cursorColor: _textSecondary,
                style: const TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '输入 ${widget.username} 确认',
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  KeyButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  KeyButton(
                    onPressed: matches
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    tone: KeyButtonTone.danger,
                    icon: const Icon(Icons.delete_outline),
                    child: const Text('确认注销'),
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

class _AvatarCropDialog extends StatefulWidget {
  const _AvatarCropDialog({required this.bytes});

  final Uint8List bytes;

  @override
  State<_AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<_AvatarCropDialog> {
  static const _workSize = 320.0;
  static const _frameSize = 280.0;
  static const _outputSize = 512;
  static const _minZoom = 0.25;
  static const _maxZoom = 4.0;

  late final Future<ui.Image> _imageFuture = _decodeImage();
  ui.Image? _image;
  double _baseScale = 1;
  double _zoom = 1;
  Offset _offset = Offset.zero;
  bool _rendering = false;
  bool _dragging = false;
  int? _dragPointer;

  Future<ui.Image> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    _image = image;
    _baseScale = math.max(_frameSize / image.width, _frameSize / image.height);
    return image;
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _handleWheel(PointerSignalEvent event, ui.Image image) {
    if (event is! PointerScrollEvent) return;
    final direction = event.scrollDelta.dy < 0 ? 1 : -1;
    _setZoom(
      (_zoom + direction * 0.1).clamp(_minZoom, _maxZoom).toDouble(),
      image,
    );
  }

  void _startDrag(PointerDownEvent event, ui.Image image) {
    if (_rendering) return;
    if (event.kind == ui.PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    setState(() {
      _dragging = true;
      _dragPointer = event.pointer;
    });
  }

  void _moveDrag(PointerMoveEvent event, ui.Image image) {
    if (!_dragging || _dragPointer != event.pointer) return;
    setState(() {
      _offset = _clampOffset(_offset + event.delta, image);
    });
  }

  void _endDrag(PointerEvent event) {
    if (!_dragging || _dragPointer != event.pointer) return;
    setState(() {
      _dragging = false;
      _dragPointer = null;
    });
  }

  void _setZoom(double value, ui.Image image) {
    setState(() {
      _zoom = value.clamp(_minZoom, _maxZoom).toDouble();
      _offset = _clampOffset(_offset, image);
    });
  }

  double _zoomSliderValue() {
    if (_zoom <= 1) {
      final normalized = (_zoom - _minZoom) / (1 - _minZoom);
      return (normalized * 0.5).clamp(0.0, 0.5).toDouble();
    }
    final normalized = (_zoom - 1) / (_maxZoom - 1);
    return (0.5 + normalized * 0.5).clamp(0.5, 1.0).toDouble();
  }

  void _setZoomFromSlider(double value, ui.Image image) {
    if (value <= 0.5) {
      _setZoom(_minZoom + (value / 0.5) * (1 - _minZoom), image);
      return;
    }
    _setZoom(1 + ((value - 0.5) / 0.5) * (_maxZoom - 1), image);
  }

  void _adjustZoom(double delta, ui.Image image) {
    _setZoom((_zoom + delta).clamp(_minZoom, _maxZoom).toDouble(), image);
  }

  Offset _clampOffset(Offset value, ui.Image image) {
    final displayWidth = image.width * _baseScale * _zoom;
    final displayHeight = image.height * _baseScale * _zoom;
    final maxX = (displayWidth - _frameSize).abs() / 2;
    final maxY = (displayHeight - _frameSize).abs() / 2;
    return Offset(
      value.dx.clamp(-maxX, maxX).toDouble(),
      value.dy.clamp(-maxY, maxY).toDouble(),
    );
  }

  Future<void> _confirm() async {
    final image = _image;
    if (image == null || _rendering) return;
    setState(() => _rendering = true);
    try {
      final bytes = await _renderCrop(image);
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _rendering = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('裁剪图片失败：$e')));
    }
  }

  Future<Uint8List> _renderCrop(ui.Image image) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final outputScale = _outputSize / _frameSize;
    final scale = _baseScale * _zoom;
    final displayedWidth = image.width * scale;
    final displayedHeight = image.height * scale;
    final imageLeft = _workSize / 2 + _offset.dx - displayedWidth / 2;
    final imageTop = _workSize / 2 + _offset.dy - displayedHeight / 2;
    final cropLeft = (_workSize - _frameSize) / 2;
    final cropTop = (_workSize - _frameSize) / 2;
    final dest = Rect.fromLTWH(
      (imageLeft - cropLeft) * outputScale,
      (imageTop - cropTop) * outputScale,
      displayedWidth * outputScale,
      displayedHeight * outputScale,
    );

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dest,
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(_outputSize, _outputSize);
    final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
    cropped.dispose();
    if (data == null) {
      throw StateError('no image data');
    }
    return data.buffer.asUint8List();
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
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: FutureBuilder<ui.Image>(
            future: _imageFuture,
            builder: (context, snapshot) {
              final image = snapshot.data;
              final zoomPercent = (_zoom * 100).round();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '裁剪头像',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      KeyIconButton(
                        onPressed: _rendering
                            ? null
                            : () => Navigator.of(context).pop(),
                        tooltip: 'Close crop',
                        icon: const Icon(Icons.close),
                        size: 32,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (snapshot.hasError)
                    _SettingsError(message: '无法读取图片：${snapshot.error}')
                  else if (image == null)
                    const SizedBox(
                      height: 180,
                      child: Center(
                        child: CircularProgressIndicator(color: _cyan),
                      ),
                    )
                  else ...[
                    Center(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerSignal: (event) => _handleWheel(event, image),
                        onPointerDown: (event) => _startDrag(event, image),
                        onPointerMove: (event) => _moveDrag(event, image),
                        onPointerUp: _endDrag,
                        onPointerCancel: _endDrag,
                        child: MouseRegion(
                          cursor: _dragging
                              ? SystemMouseCursors.grabbing
                              : SystemMouseCursors.grab,
                          child: SizedBox.square(
                            dimension: _workSize,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ColoredBox(color: _primaryDark),
                                ),
                                Positioned.fill(
                                  child: ClipRect(
                                    child: Center(
                                      child: Transform.translate(
                                        offset: _offset,
                                        child: Transform.scale(
                                          scale: _zoom,
                                          child: RawImage(
                                            image: image,
                                            width: image.width * _baseScale,
                                            height: image.height * _baseScale,
                                            fit: BoxFit.contain,
                                            filterQuality: FilterQuality.high,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _CropShadePainter(
                                      frameSize: _frameSize,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        KeyIconButton(
                          onPressed: _rendering
                              ? null
                              : () => _adjustZoom(-0.15, image),
                          tooltip: '缩小 15%',
                          icon: const Icon(Icons.zoom_out),
                          size: 30,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: _cyan,
                              inactiveTrackColor: _borderColor,
                              thumbColor: _textPrimary,
                              overlayColor: _cyan.withValues(alpha: 0.14),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: _zoomSliderValue(),
                              min: 0,
                              max: 1,
                              onChanged: _rendering
                                  ? null
                                  : (value) => _setZoomFromSlider(value, image),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        KeyIconButton(
                          onPressed: _rendering
                              ? null
                              : () => _adjustZoom(0.6, image),
                          tooltip: '放大 60%',
                          icon: const Icon(Icons.zoom_in),
                          size: 30,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        '$zoomPercent%',
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      KeyButton(
                        onPressed: _rendering
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 12),
                      KeyButton(
                        onPressed: image == null || _rendering
                            ? null
                            : _confirm,
                        loading: _rendering,
                        tone: KeyButtonTone.primary,
                        icon: const Icon(Icons.crop),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CropShadePainter extends CustomPainter {
  const _CropShadePainter({required this.frameSize});

  final double frameSize;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: frameSize,
      height: frameSize,
    );
    final overlay = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(frame);
    canvas.drawPath(
      overlay,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.34)
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.srcOver,
    );
    canvas.drawRect(
      frame,
      Paint()
        ..color = _cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_CropShadePainter oldDelegate) =>
      oldDelegate.frameSize != frameSize;
}

class _PasswordVisibilityToggle extends StatelessWidget {
  const _PasswordVisibilityToggle({
    required this.obscure,
    required this.enabled,
    required this.onPressed,
  });

  final bool obscure;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? _textSecondary : _textMuted;
    return Tooltip(
      message: obscure ? 'Show password' : 'Hide password',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: obscure ? 'Show password' : 'Hide password',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 17,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
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

class _SettingsNotice extends StatelessWidget {
  const _SettingsNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF1F2D27),
        border: Border.fromBorderSide(BorderSide(color: Color(0xFF22332B))),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: _cyan, size: 17),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: _textPrimary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsEmptyState extends StatelessWidget {
  const _SettingsEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
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

class _StartedVisualizer {
  const _StartedVisualizer(this.visualizer, this.listener);

  final lk.AudioVisualizer visualizer;
  final lk.EventsListener<lk.AudioVisualizerEvent> listener;
}

double _levelFromVisualizerEvent(lk.AudioVisualizerEvent event) {
  return _levelFromVisualizerBands(event.event);
}

double _levelFromVisualizerBands(Iterable<Object?> bands) {
  const noiseFloor = 0.04;
  const displayGain = 1.45;
  var peak = 0.0;
  var squareSum = 0.0;
  var count = 0;

  for (final value in bands) {
    if (value is! num) continue;
    final raw = value.toDouble();
    if (!raw.isFinite) continue;
    final clamped = raw.clamp(0.0, 1.0).toDouble();
    final sample = clamped <= noiseFloor
        ? 0.0
        : (clamped - noiseFloor) / (1 - noiseFloor);
    if (sample > peak) peak = sample;
    squareSum += sample * sample;
    count++;
  }

  if (count == 0 || peak <= 0) return 0;
  final rms = math.sqrt(squareSum / count);
  final energy = (rms * 0.82) + (peak * 0.18);
  return (energy * displayGain).clamp(0.0, 1.0).toDouble();
}

double levelFromVisualizerBandsForTest(Iterable<Object?> bands) {
  return _levelFromVisualizerBands(bands);
}

double _normalizedVolume(double volume) {
  return volume.clamp(0.0, 1.0).toDouble();
}

String _normalizedGender(String value) {
  return switch (value) {
    'male' || 'female' || 'secret' => value,
    _ => 'secret',
  };
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '未知';
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

String _avatarUploadFilename(String originalName) {
  final cleaned = originalName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
  final stem = cleaned.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
  final safeStem = stem.isEmpty ? 'avatar' : stem;
  return '$safeStem-${DateTime.now().millisecondsSinceEpoch}.png';
}

String _stickerUploadFilename(String originalName, int index) {
  final cleaned = originalName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
  final extensionMatch = RegExp(r'\.([A-Za-z0-9]+)$').firstMatch(cleaned);
  final extension = extensionMatch == null
      ? 'png'
      : extensionMatch.group(1)!.toLowerCase();
  final stem = cleaned.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '');
  final safeStem = stem.isEmpty ? 'sticker' : stem;
  return '$safeStem-${DateTime.now().millisecondsSinceEpoch}-$index.$extension';
}

String _stickerNameFromFilename(String originalName) {
  final stem = originalName.trim().replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
  if (stem.isEmpty) return 'sticker';
  final chars = stem.characters.take(32).toList().join();
  return chars.isEmpty ? 'sticker' : chars;
}

String _sessionStateText(UserSession session) {
  if (session.isCurrent) return '当前会话';
  if (session.revokedAt != null) return '已失效';
  if (!session.expiresAt.isAfter(DateTime.now())) return '已过期';
  return '有效';
}

String _initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part.characters.first).join();
  return initials.toUpperCase();
}

Color _avatarColor(String key) {
  return switch (key) {
    'blue-3' => const Color(0xFF526C9F),
    'sky-2' => const Color(0xFF4F7F92),
    'cyan-2' => const Color(0xFF47777A),
    'mint-2' => const Color(0xFF4F7A67),
    'green-2' => const Color(0xFF46695B),
    'lime-2' => const Color(0xFF687A47),
    'amber-2' => const Color(0xFF71614E),
    'orange-2' => const Color(0xFF7A6046),
    'coral-2' => const Color(0xFF7A5952),
    'pink-2' => const Color(0xFF75566F),
    'violet-2' => const Color(0xFF665B7D),
    'indigo-2' => const Color(0xFF5B638A),
    'rose-2' => const Color(0xFF7A5961),
    'teal-2' => const Color(0xFF536E73),
    'olive-2' => const Color(0xFF6A704B),
    'slate-2' => const Color(0xFF5E6472),
    'steel-2' => const Color(0xFF4F6672),
    'graphite-2' => const Color(0xFF5B5D63),
    _ => const Color(0xFF526C9F),
  };
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({
    required this.title,
    required this.icon,
    required this.devices,
    required this.selectedDevice,
    required this.busyDeviceId,
    required this.emptyText,
    required this.fallbackLabel,
    required this.onSelect,
  });

  final String title;
  final IconData icon;
  final List<lk.MediaDevice> devices;
  final lk.MediaDevice? selectedDevice;
  final String? busyDeviceId;
  final String emptyText;
  final String fallbackLabel;
  final ValueChanged<lk.MediaDevice> onSelect;

  @override
  Widget build(BuildContext context) {
    final labels = _deviceLabels();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _cyan, size: 18),
            const SizedBox(width: 9),
            Text(
              title,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        devices.isEmpty
            ? _EmptyDeviceRow(text: emptyText)
            : Column(
                children: [
                  for (final entry in devices.asMap().entries)
                    _DeviceRow(
                      device: entry.value,
                      label: labels[entry.key],
                      selected:
                          selectedDevice?.deviceId == entry.value.deviceId &&
                          selectedDevice?.kind == entry.value.kind,
                      busy:
                          busyDeviceId ==
                          '${entry.value.kind}:${entry.value.deviceId}',
                      onTap: () => onSelect(entry.value),
                    ),
                ],
              ),
      ],
    );
  }

  List<String> _deviceLabels() {
    final baseLabels = [
      for (final entry in devices.asMap().entries)
        _deviceLabel(entry.value, entry.key, fallbackLabel),
    ];
    final totals = <String, int>{};
    for (final label in baseLabels) {
      totals[label] = (totals[label] ?? 0) + 1;
    }
    final seen = <String, int>{};
    return [
      for (final label in baseLabels)
        if (totals[label] == 1)
          label
        else
          _labelWithDuplicateSuffix(label, seen),
    ];
  }

  String _labelWithDuplicateSuffix(String label, Map<String, int> seen) {
    final count = (seen[label] ?? 0) + 1;
    seen[label] = count;
    if (count == 1) return label;
    return '$label #$count';
  }

  String _deviceLabel(lk.MediaDevice device, int index, String fallbackLabel) {
    final label = device.label.trim();
    if (label.isNotEmpty) return label;
    if (device.deviceId == 'default') return 'System default';
    if (device.deviceId == 'communications') return 'Communications';
    return '$fallbackLabel ${index + 1}';
  }
}

class _AudioControlPanel extends StatelessWidget {
  const _AudioControlPanel({
    required this.title,
    required this.icon,
    required this.volume,
    required this.level,
    required this.testing,
    required this.testTooltip,
    required this.disabled,
    required this.onVolumeChanged,
    required this.onToggleTest,
  });

  final String title;
  final IconData icon;
  final double volume;
  final double level;
  final bool testing;
  final String testTooltip;
  final bool disabled;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleTest;

  @override
  Widget build(BuildContext context) {
    final percent = (volume * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _cyan, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _cyan,
                  inactiveTrackColor: _borderColor,
                  thumbColor: _textPrimary,
                  overlayColor: _cyan.withValues(alpha: 0.14),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: volume,
                  min: 0,
                  max: 1,
                  onChanged: disabled ? null : onVolumeChanged,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 96,
              child: KeyButton(
                onPressed: disabled ? null : onToggleTest,
                tooltip: testTooltip,
                height: 42,
                width: double.infinity,
                tone: testing ? KeyButtonTone.primary : KeyButtonTone.neutral,
                selected: testing,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  testing ? '停止测试' : '测试',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _LevelMeter(level: level, active: testing),
            ),
          ],
        ),
      ],
    );
  }
}

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level, required this.active});

  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final normalized = level.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _primaryDark),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentCount = (constraints.maxWidth / 12).floor().clamp(
                24,
                56,
              );
              final activeCount = active
                  ? (normalized * segmentCount).ceil().clamp(0, segmentCount)
                  : 0;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < segmentCount; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      width: 5,
                      height: 22,
                      decoration: BoxDecoration(
                        color: i < activeCount
                            ? _cyan
                            : const Color(0xFF2A2F38),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.label,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final lk.MediaDevice device;
  final String label;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KeySurface(
      onPressed: busy ? null : onTap,
      height: 50,
      width: double.infinity,
      selected: selected,
      backgroundColor: _primaryDarkLow,
      selectedBackgroundColor: _primaryDarkLow,
      pressedBackgroundColor: _primaryDark,
      borderColor: _borderColor,
      selectedBorderColor: selected ? _cyan : _borderColor,
      hoverLift: 3,
      pressDepth: 3,
      baseDepth: 5,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? _textPrimary : _textSecondary,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (busy)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
            )
          else if (selected)
            const Icon(Icons.check, color: _cyan, size: 18)
          else
            Icon(
              device.kind == 'audioinput' ? Icons.mic_none : Icons.volume_up,
              color: _textMuted,
              size: 18,
            ),
        ],
      ),
    );
  }
}

class _EmptyDeviceRow extends StatelessWidget {
  const _EmptyDeviceRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            text,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsError extends StatelessWidget {
  const _SettingsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF2E1F22),
        border: Border.fromBorderSide(BorderSide(color: Color(0xFF3A2A2E))),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber, color: _danger, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: _danger, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
