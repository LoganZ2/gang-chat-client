import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/account_display.dart' as account_display;
import '../app/account_forms.dart';
import '../app/account_sessions.dart';
import '../app/account_state.dart';
import '../app/audio_device_display.dart';
import '../app/audio_device_info.dart';
import '../app/audio_device_state.dart';
import '../app/audio_device_store.dart';
import '../app/audio_levels.dart';
import '../app/confirmation.dart';
import '../app/settings_controller.dart';
import '../app/settings_shell_state.dart';
import '../app/sticker_management.dart';
import '../app/sticker_ordering.dart' as sticker_ordering;
import '../app/sticker_uploads.dart';
import '../live/audio_device_restorer.dart';
import '../live/audio_device_service.dart';
import '../live/audio_test_service.dart';
import '../live/system_default_audio_input.dart';
import '../protocol/api_client.dart';
import '../protocol/models.dart';
import '../protocol/sticker_pack_store.dart';
import '../shell/clipboard_service.dart';
import '../shell/file_selection_service.dart';
import '../shell/secure_audio_device_store.dart';
import '../ui/avatar_crop_dialog.dart';
import '../ui/sticker_upload_adapter.dart';
import '../ui/ui.dart';

part 'settings_components.dart';
part 'settings_profile_widgets.dart';
part 'settings_audio_widgets.dart';

const _primaryDark = Color(0xFF14171D);
const _primaryDarkLow = Color(0xFF181C24);
const _borderColor = Color(0xFF2A2F38);
const _cyan = Color(0xFF6FCFA6);
const _textPrimary = Color(0xFFECEFF1);
const _textSecondary = Color(0xFFB0B8C0);
const _textMuted = Color(0xFF6F7785);
const _danger = Color(0xFFE58383);

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.isSubWindow = false,
    this.audioDeviceStore = const SecureAudioDeviceStore(),
    this.audioDeviceService = const LiveAudioDeviceService(),
    this.systemDefaultAudioInput,
    this.controller,
    this.api,
    this.apiBaseUrl = '',
    this.stickerPackStore = const StickerPackStore(),
    this.clipboardService = const ClipboardService(),
    this.fileSelectionService = const FileSelectionService(),
    this.currentUser,
    this.onUserUpdated,
    this.onDeviceSelected,
    this.onVolumeChanged,
    this.onAccountDeleted,
    this.onClose,
  });

  final bool isSubWindow;
  final AudioDeviceStore audioDeviceStore;
  final LiveAudioDeviceService audioDeviceService;
  final SystemDefaultAudioInput? systemDefaultAudioInput;
  final SettingsController? controller;
  final GangApi? api;
  final String apiBaseUrl;
  final StickerPackStore stickerPackStore;
  final ClipboardService clipboardService;
  final FileSelectionService fileSelectionService;
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

  SettingsSection _section = SettingsSection.profile;
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
  List<String> _selectedStickerIds = <String>[];
  final Map<String, List<String>> _stickerOrderDrafts = {};
  bool _managingStickers = false;
  bool _loadingStickers = false;
  bool _uploadingStickers = false;
  bool _deletingStickers = false;
  bool _savingStickerOrder = false;
  bool _downloadingStickers = false;
  String _stickerFilterKeyword = '';
  String _stickerFilterMimeType = '';
  String? _stickerError;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _accountError;
  String? _securityError;
  String? _notice;

  StreamSubscription<List<AudioDeviceInfo>>? _deviceSubscription;
  List<AudioDeviceInfo> _audioInputs = const [];
  List<AudioDeviceInfo> _audioOutputs = const [];
  AudioDeviceInfo? _selectedInput;
  AudioDeviceInfo? _selectedOutput;
  String? _busyDeviceId;
  double _inputVolume = 1.0;
  double _outputVolume = 1.0;
  double _inputLevel = 0.0;
  double _outputLevel = 0.0;
  bool _testingInput = false;
  bool _testingOutput = false;
  bool _voiceInitialized = false;
  String? _error;
  bool _loading = false;
  String _language = 'zh-Hans';
  final _audioTestService = AudioTestService();
  AudioTestHandle? _inputTest;
  AudioTestHandle? _outputTest;
  SystemDefaultAudioInput? _systemDefaultAudioInput;
  StreamSubscription<String?>? _systemDefaultInputSubscription;
  String? _systemDefaultInputId;

  SystemDefaultAudioInput get _systemDefaultInput {
    return _systemDefaultAudioInput ??=
        widget.systemDefaultAudioInput ?? SystemDefaultAudioInput();
  }

  SettingsController get _settingsController {
    final injected = widget.controller;
    if (injected != null) return injected;
    return SettingsController(
      api: widget.api,
      apiBaseUrl: widget.apiBaseUrl,
      stickerPackStore: widget.stickerPackStore,
    );
  }

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
    unawaited(_systemDefaultInputSubscription?.cancel());
    unawaited(_systemDefaultAudioInput?.dispose());
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
    _gender = account_display.normalizeGender(user.gender);
    _defaultAvatarKey = user.defaultAvatarKey;
    _emailPublic = user.emailPublic;
    _phonePublic = user.phoneNumberPublic;
    _language = normalizeAccountLanguage(user.language);
    _clearUploadedAvatar = false;
    _pendingAvatarAssetId = null;
    _pendingAvatarUrl = null;
  }

  Future<void> _loadAccount() async {
    setState(() => _applyAccountLoadPatch(accountLoadStarted(user: _user)));
    try {
      final user = await _settingsController.loadAccount();
      if (!mounted) return;
      if (user == null) {
        setState(
          () => _applyAccountLoadPatch(
            accountLoadCancelled(user: _user, accountError: _accountError),
          ),
        );
        return;
      }
      setState(() {
        _applyAccountLoadPatch(accountLoadSucceeded(user: user));
        _syncUserFields(user);
      });
      widget.onUserUpdated?.call(user);
    } catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _applyAccountLoadPatch(accountLoadFailed(user: _user, failure: e)),
      );
    }
  }

  Future<void> _loadSessions() async {
    setState(
      () => _applyAccountSessionsLoadPatch(
        accountSessionsLoadStarted(sessions: _sessions),
      ),
    );
    try {
      final sessions = await _settingsController.loadSessions();
      if (!mounted) return;
      if (sessions == null) {
        setState(
          () => _applyAccountSessionsLoadPatch(
            accountSessionsLoadCancelled(
              sessions: _sessions,
              securityError: _securityError,
            ),
          ),
        );
        return;
      }
      setState(
        () => _applyAccountSessionsLoadPatch(
          accountSessionsLoadSucceeded(sessions: sessions),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyAccountSessionsLoadPatch(
          accountSessionsLoadFailed(sessions: _sessions, failure: e),
        ),
      );
    }
  }

  Future<void> _ensureStickersLoaded({bool forceReload = false}) async {
    if (_loadingStickers) return;
    if (!forceReload && _stickerPacks.isNotEmpty) return;
    await _loadStickers(forceReload: forceReload);
  }

  Future<void> _loadStickers({bool forceReload = false}) async {
    setState(
      () => _applyStickerPackLoadPatch(
        stickerPacksLoadStarted(
          packs: _stickerPacks,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      final result = await _settingsController.loadPersonalStickerPacks(
        userId: _stickerCacheUserId,
        forceReload: forceReload,
      );
      if (!mounted) return;
      final packs = result?.packs;
      setState(() {
        _applyStickerPackLoadPatch(
          stickerPacksLoadSucceeded(
            packs: packs ?? _stickerPacks,
            selectedStickerIds: _selectedStickerIds,
          ),
        );
        if (packs != null) _syncStickerOrderDrafts(packs);
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyStickerPackLoadPatch(
          stickerPacksLoadFailed(
            packs: _stickerPacks,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
    }
  }

  String get _stickerCacheUserId => _user?.id ?? widget.currentUser?.id ?? '';

  void _applyStickerPackLoadPatch(StickerPackLoadPatch patch) {
    _stickerPacks = patch.packs;
    _selectedStickerIds = patch.selectedStickerIds;
    _loadingStickers = patch.loading;
    _stickerError = patch.error;
  }

  void _applyStickerSelectionPatch(StickerSelectionPatch patch) {
    _managingStickers = patch.managing;
    _stickerFilterKeyword = patch.filterKeyword;
    _stickerFilterMimeType = patch.filterMimeType;
    _selectedStickerIds = patch.selectedStickerIds;
  }

  void _applyStickerActionPatch(StickerActionPatch patch) {
    _uploadingStickers = patch.uploading;
    _deletingStickers = patch.deleting;
    _savingStickerOrder = patch.savingOrder;
    _downloadingStickers = patch.downloading;
    _selectedStickerIds = patch.selectedStickerIds;
    _stickerError = patch.error;
    _notice = patch.notice;
  }

  void _applyAccountSessionsLoadPatch(AccountSessionsLoadPatch patch) {
    _sessions = patch.sessions;
    _loadingSessions = patch.loading;
    _securityError = patch.securityError;
  }

  void _applyAccountLoadPatch(AccountLoadPatch patch) {
    _user = patch.user;
    _loadingAccount = patch.loading;
    _accountError = patch.accountError;
  }

  void _applyAudioDeviceListPatch(AudioDeviceListPatch<AudioDeviceInfo> patch) {
    _audioInputs = patch.inputs;
    _audioOutputs = patch.outputs;
    _selectedInput = patch.selectedInput;
    _selectedOutput = patch.selectedOutput;
    _loading = patch.loading;
    _error = patch.error;
  }

  void _applyAudioDeviceSelectionPatch(
    AudioDeviceSelectionPatch<AudioDeviceInfo> patch,
  ) {
    _selectedInput = patch.selectedInput;
    _selectedOutput = patch.selectedOutput;
    _busyDeviceId = patch.busyDeviceId;
    _error = patch.error;
  }

  void _applyAudioVolumePatch(AudioVolumePatch patch) {
    _inputVolume = patch.inputVolume;
    _outputVolume = patch.outputVolume;
  }

  void _applyAudioTestStatePatch(AudioTestStatePatch patch) {
    _testingInput = patch.testingInput;
    _testingOutput = patch.testingOutput;
    _inputLevel = patch.inputLevel;
    _outputLevel = patch.outputLevel;
    _error = patch.error;
  }

  void _applyAccountFormSaveStatePatch(AccountFormSaveStatePatch patch) {
    _savingAccount = patch.savingAccount;
    _savingProfile = patch.savingProfile;
    _accountError = patch.accountError;
    _notice = patch.notice;
  }

  void _applyAccountEditableFieldsPatch(AccountEditableFieldsPatch patch) {
    _gender = patch.gender;
    _emailPublic = patch.emailPublic;
    _phonePublic = patch.phoneNumberPublic;
  }

  void _applyPasswordChangeStatePatch(PasswordChangeStatePatch patch) {
    _changingPassword = patch.changingPassword;
    _securityError = patch.securityError;
    _notice = patch.notice;
  }

  void _applyPasswordVisibilityPatch(PasswordVisibilityPatch patch) {
    _obscureCurrentPassword = patch.obscureCurrentPassword;
    _obscureNewPassword = patch.obscureNewPassword;
    _obscureConfirmPassword = patch.obscureConfirmPassword;
  }

  void _applyAccountDeletionStatePatch(AccountDeletionStatePatch patch) {
    _deletingAccount = patch.deletingAccount;
    _securityError = patch.securityError;
    _notice = patch.notice;
  }

  void _applyAccountAvatarStatePatch(AccountAvatarStatePatch patch) {
    _pendingAvatarAssetId = patch.pendingAvatarAssetId;
    _pendingAvatarUrl = patch.pendingAvatarUrl;
    _clearUploadedAvatar = patch.clearUploadedAvatar;
    _uploadingAvatar = patch.uploadingAvatar;
    _accountError = patch.accountError;
    _stickerError = patch.stickerError;
    _notice = patch.notice;
  }

  void _applyAccountPresetAvatarSelectionPatch(
    AccountPresetAvatarSelectionPatch patch,
  ) {
    _defaultAvatarKey = patch.defaultAvatarKey;
    _pendingAvatarAssetId = patch.pendingAvatarAssetId;
    _pendingAvatarUrl = patch.pendingAvatarUrl;
    _clearUploadedAvatar = patch.clearUploadedAvatar;
    _notice = patch.notice;
  }

  void _applySettingsSectionPatch(SettingsSectionPatch patch) {
    _section = patch.section;
    _notice = patch.notice;
  }

  void _syncStickerOrderDrafts(List<StickerPack> packs) {
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
  }

  Future<void> _refreshActiveSection() async {
    switch (_section) {
      case SettingsSection.profile:
        await _loadAccount();
        break;
      case SettingsSection.preferences:
        break;
      case SettingsSection.stickers:
        await _loadStickers(forceReload: true);
        break;
      case SettingsSection.security:
        await Future.wait([_loadAccount(), _loadSessions()]);
        break;
      case SettingsSection.voice:
        await _ensureVoiceInitialized(forceReload: true);
        break;
    }
  }

  Future<void> _ensureVoiceInitialized({bool forceReload = false}) async {
    if (_voiceInitialized && !forceReload) return;
    if (!_voiceInitialized) {
      _voiceInitialized = true;
      _deviceSubscription ??= widget.audioDeviceService.devicesChanged.listen((
        devices,
      ) {
        unawaited(_applyDevices(devices));
      });
      // Follow the OS-selected microphone when the user has not pinned one.
      // macOS reports it through the native channel; the subscription re-runs
      // selection whenever the system default changes underneath us.
      _systemDefaultInputSubscription ??= _systemDefaultInput.changes.listen((
        deviceId,
      ) {
        _systemDefaultInputId = deviceId;
        unawaited(_onSystemDefaultInputChanged());
      });
      unawaited(_loadStoredAudioSettings());
    }
    _systemDefaultInputId = await _systemDefaultInput.currentDeviceId();
    await _loadDevices();
  }

  Future<void> _saveAccount({
    AccountFormSaveTarget target = AccountFormSaveTarget.account,
  }) async {
    final user = _user;
    if (!_settingsController.hasApi || user == null || _savingAccount) return;

    final draft = target == AccountFormSaveTarget.preferences
        ? preferencesUpdateDraftFromForm(user: user, language: _language)
        : accountUpdateDraftFromForm(
            user: user,
            username: _usernameController.text,
            email: _emailController.text,
            emailPublic: _emailPublic,
            phoneNumber: _phoneController.text,
            phoneNumberPublic: _phonePublic,
            language: _language,
          );
    if (draft.error != null) {
      setState(
        () => _applyAccountFormSaveStatePatch(
          accountFormSaveValidationFailed(
            error: draft.error!,
            savingAccount: _savingAccount,
            savingProfile: _savingProfile,
            notice: _notice,
          ),
        ),
      );
      return;
    }
    if (draft.noChanges) {
      setState(
        () => _applyAccountFormSaveStatePatch(
          accountFormSaveNoChanges(
            target: target,
            savingAccount: _savingAccount,
            savingProfile: _savingProfile,
            accountError: _accountError,
          ),
        ),
      );
      return;
    }

    setState(
      () => _applyAccountFormSaveStatePatch(
        accountFormSaveStarted(
          target: target,
          savingAccount: _savingAccount,
          savingProfile: _savingProfile,
        ),
      ),
    );
    try {
      final updated = await _settingsController.updateAccount(
        username: draft.username,
        email: draft.email,
        emailPublic: draft.emailPublic,
        phoneNumber: draft.phoneNumber,
        phoneNumberPublic: draft.phoneNumberPublic,
        language: draft.language,
      );
      if (!mounted) return;
      if (updated == null) {
        setState(
          () => _applyAccountFormSaveStatePatch(
            accountFormSaveCancelled(
              target: target,
              savingAccount: _savingAccount,
              savingProfile: _savingProfile,
              accountError: _accountError,
              notice: _notice,
            ),
          ),
        );
        return;
      }
      setState(() {
        _user = updated;
        _syncUserFields(updated);
        _applyAccountFormSaveStatePatch(
          accountFormSaveSucceeded(
            target: target,
            savingAccount: _savingAccount,
            savingProfile: _savingProfile,
          ),
        );
      });
      widget.onUserUpdated?.call(updated);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyAccountFormSaveStatePatch(
          accountFormSaveFailed(
            target: target,
            savingAccount: _savingAccount,
            savingProfile: _savingProfile,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<void> _saveProfile() async {
    final user = _user;
    if (!_settingsController.hasApi || user == null || _savingProfile) return;

    final draft = profileUpdateDraftFromForm(
      user: user,
      displayName: _displayNameController.text,
      bio: _bioController.text,
      gender: _gender,
      defaultAvatarKey: _defaultAvatarKey,
      pendingAvatarAssetId: _pendingAvatarAssetId,
      clearUploadedAvatar: _clearUploadedAvatar,
    );
    if (draft.error != null) {
      setState(
        () => _applyAccountFormSaveStatePatch(
          accountFormSaveValidationFailed(
            error: draft.error!,
            savingAccount: _savingAccount,
            savingProfile: _savingProfile,
            notice: _notice,
          ),
        ),
      );
      return;
    }
    if (draft.noChanges) {
      setState(
        () => _applyAccountFormSaveStatePatch(
          accountFormSaveNoChanges(
            target: AccountFormSaveTarget.profile,
            savingAccount: _savingAccount,
            savingProfile: _savingProfile,
            accountError: _accountError,
          ),
        ),
      );
      return;
    }

    setState(
      () => _applyAccountFormSaveStatePatch(
        accountFormSaveStarted(
          target: AccountFormSaveTarget.profile,
          savingAccount: _savingAccount,
          savingProfile: _savingProfile,
        ),
      ),
    );
    try {
      final updated = await _settingsController.updateProfile(
        displayName: draft.displayName,
        bio: draft.bio,
        gender: draft.gender,
        defaultAvatarKey: draft.defaultAvatarKey,
        avatarAssetId: draft.avatarAssetId,
      );
      if (!mounted) return;
      if (updated == null) {
        setState(
          () => _applyAccountFormSaveStatePatch(
            accountFormSaveCancelled(
              target: AccountFormSaveTarget.profile,
              savingAccount: _savingAccount,
              savingProfile: _savingProfile,
              accountError: _accountError,
              notice: _notice,
            ),
          ),
        );
        return;
      }
      setState(() {
        _user = updated;
        _syncUserFields(updated);
        _applyAccountFormSaveStatePatch(
          accountFormSaveSucceeded(
            target: AccountFormSaveTarget.profile,
            savingAccount: _savingAccount,
            savingProfile: _savingProfile,
          ),
        );
      });
      widget.onUserUpdated?.call(updated);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyAccountFormSaveStatePatch(
          accountFormSaveFailed(
            target: AccountFormSaveTarget.profile,
            savingAccount: _savingAccount,
            savingProfile: _savingProfile,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (!_settingsController.hasApi || _uploadingAvatar) return;
    setState(
      () => _applyAccountAvatarStatePatch(
        accountAvatarPreparationStarted(
          target: AccountAvatarErrorTarget.account,
          pendingAvatarAssetId: _pendingAvatarAssetId,
          pendingAvatarUrl: _pendingAvatarUrl,
          clearUploadedAvatar: _clearUploadedAvatar,
          uploadingAvatar: _uploadingAvatar,
          accountError: _accountError,
          stickerError: _stickerError,
        ),
      ),
    );

    SelectedFile? file;
    try {
      file = await widget.fileSelectionService.openFile(
        acceptedTypeGroups: const [
          FileTypeGroup(
            label: '图片',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyAccountAvatarStatePatch(
          accountAvatarActionFailed(
            target: AccountAvatarErrorTarget.account,
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            clearUploadedAvatar: _clearUploadedAvatar,
            accountError: _accountError,
            stickerError: _stickerError,
            failure: account_display.avatarPickerOpenFailureMessage(e),
          ),
        ),
      );
      return;
    }
    if (file == null) return;

    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyAccountAvatarStatePatch(
          accountAvatarActionFailed(
            target: AccountAvatarErrorTarget.account,
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            clearUploadedAvatar: _clearUploadedAvatar,
            accountError: _accountError,
            stickerError: _stickerError,
            failure: account_display.avatarReadFailureMessage(e),
          ),
        ),
      );
      return;
    }
    if (bytes.isEmpty) {
      setState(
        () => _applyAccountAvatarStatePatch(
          accountAvatarActionFailed(
            target: AccountAvatarErrorTarget.account,
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            clearUploadedAvatar: _clearUploadedAvatar,
            accountError: _accountError,
            stickerError: _stickerError,
            failure: account_display.avatarEmptyFileMessage(),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;

    final cropped = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AvatarCropDialog(bytes: bytes),
    );
    if (cropped == null || !mounted) return;

    setState(
      () => _applyAccountAvatarStatePatch(
        accountAvatarUploadStarted(
          target: AccountAvatarErrorTarget.account,
          pendingAvatarAssetId: _pendingAvatarAssetId,
          pendingAvatarUrl: _pendingAvatarUrl,
          clearUploadedAvatar: _clearUploadedAvatar,
          accountError: _accountError,
          stickerError: _stickerError,
        ),
      ),
    );
    try {
      final asset = await _settingsController.uploadImageAsset(
        bytes: cropped,
        filename: account_display.avatarUploadFilename(file.name),
        purpose: 'avatar',
      );
      if (asset == null) {
        if (!mounted) return;
        setState(
          () => _applyAccountAvatarStatePatch(
            accountAvatarActionCancelled(
              target: AccountAvatarErrorTarget.account,
              pendingAvatarAssetId: _pendingAvatarAssetId,
              pendingAvatarUrl: _pendingAvatarUrl,
              clearUploadedAvatar: _clearUploadedAvatar,
              accountError: _accountError,
              stickerError: _stickerError,
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(
        () => _applyAccountAvatarStatePatch(
          accountAvatarPendingUploadSucceeded(
            assetId: asset.id,
            assetUrl: asset.url,
            stickerError: _stickerError,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyAccountAvatarStatePatch(
          accountAvatarActionFailed(
            target: AccountAvatarErrorTarget.account,
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            clearUploadedAvatar: _clearUploadedAvatar,
            accountError: _accountError,
            stickerError: _stickerError,
            failure: e,
          ),
        ),
      );
    }
  }

  List<ManagedSticker> _allStickerItems() {
    return managedStickerItems(
      _stickerPacks,
      orderForPack: (pack) => _stickerOrderDrafts[pack.id],
    );
  }

  List<ManagedSticker> _filteredStickerItems() {
    return filteredManagedStickerItems(
      _allStickerItems(),
      keyword: _stickerFilterKeyword,
      mimeType: _stickerFilterMimeType,
    );
  }

  bool get _stickerFilterActive => stickerFilterActive(
    keyword: _stickerFilterKeyword,
    mimeType: _stickerFilterMimeType,
  );

  bool get _stickerManagementBusy => stickerManagementBusy(
    uploading: _uploadingStickers,
    deleting: _deletingStickers,
    savingOrder: _savingStickerOrder,
    downloading: _downloadingStickers,
  );

  Map<String, int> _stickerSelectionNumbers() {
    return stickerSelectionNumbers(_selectedStickerIds);
  }

  Future<StickerPack> _ensureActiveStickerPack() async {
    if (_stickerPacks.isNotEmpty) return _stickerPacks.first;

    if (!_settingsController.hasApi) {
      throw StateError(stickerPackRequiresServerMessage());
    }
    final created = await _settingsController.createStickerPack(
      name: defaultStickerPackName(StickerManagementScope.personal),
      sortOrder: (_stickerPacks.length + 1) * 10,
    );
    if (created == null) {
      throw StateError(stickerPackRequiresServerMessage());
    }
    if (mounted) {
      setState(() {
        _stickerPacks = [..._stickerPacks, created];
        _stickerOrderDrafts[created.id] = <String>[];
      });
    }
    return created;
  }

  Future<void> _pickAndUploadStickers() async {
    if (!_settingsController.hasApi || _stickerManagementBusy) return;

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
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
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
          uploading: _uploadingStickers,
          deleting: _deletingStickers,
          savingOrder: _savingStickerOrder,
          downloading: _downloadingStickers,
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
      final pack = await _ensureActiveStickerPack();
      final uploadedAssetIds = <String>[];
      var sortIndex = pack.stickers.length;
      for (final entry in uploadItems.asMap().entries) {
        final item = entry.value;
        final asset = await _settingsController.uploadImageAsset(
          bytes: item.bytes,
          filename: stickerUploadFilename(item.filename, entry.key),
          purpose: 'sticker',
        );
        if (asset == null) continue;
        uploadedAssetIds.add(asset.id);
        await _settingsController.addSticker(
          packId: pack.id,
          assetId: asset.id,
          name: stickerNameFromFilename(item.filename),
          sortOrder: (++sortIndex) * 10,
        );
        uploadedCount += 1;
      }
      await _loadStickers(forceReload: true);
      await _pinUploadedStickerAssetsToFront(
        packId: pack.id,
        assetIds: uploadedAssetIds,
      );
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.upload,
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            error: _stickerError,
            notice: stickerUploadNotice(
              scope: StickerManagementScope.personal,
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
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
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

    final pack = sticker_ordering.stickerPackById(_stickerPacks, packId);
    if (pack == null) return;

    final nextOrder = sticker_ordering.stickerOrderWithAssetIdsPinnedToFront(
      pack,
      assetIds,
      order: _stickerOrderDrafts[pack.id],
    );
    if (nextOrder == null) return;

    await _settingsController.reorderStickers(
      packId: pack.id,
      stickerIds: nextOrder,
    );
    await _loadStickers(forceReload: true);
  }

  void _toggleStickerManageMode() {
    setState(
      () => _applyStickerSelectionPatch(
        stickerManagementModeToggled(
          managing: _managingStickers,
          filterKeyword: _stickerFilterKeyword,
          filterMimeType: _stickerFilterMimeType,
        ),
      ),
    );
  }

  void _toggleStickerSelection(String stickerId) {
    setState(
      () => _applyStickerSelectionPatch(
        stickerSelectionToggled(
          managing: _managingStickers,
          filterKeyword: _stickerFilterKeyword,
          filterMimeType: _stickerFilterMimeType,
          selectedStickerIds: _selectedStickerIds,
          stickerId: stickerId,
        ),
      ),
    );
  }

  void _selectAllVisibleStickers(List<ManagedSticker> items) {
    setState(
      () => _applyStickerSelectionPatch(
        stickerVisibleSelectionToggled(
          managing: _managingStickers,
          busy: _stickerManagementBusy,
          filterKeyword: _stickerFilterKeyword,
          filterMimeType: _stickerFilterMimeType,
          selectedStickerIds: _selectedStickerIds,
          visibleItems: items,
        ),
      ),
    );
  }

  Future<void> _deleteSelectedStickers() async {
    final selectedIds = List<String>.from(_selectedStickerIds);
    if (!_settingsController.hasApi ||
        !canStartStickerSelectionAction(
          busy: _stickerManagementBusy,
          selectedStickerIds: selectedIds,
        )) {
      return;
    }
    final byStickerId = {
      for (final item in _allStickerItems()) item.sticker.id: item,
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StickerConfirmDialog(
        title: stickerDeleteDialogTitle(StickerManagementScope.personal),
        body: stickerBulkDeleteConfirmBody(
          scope: StickerManagementScope.personal,
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
          uploading: _uploadingStickers,
          deleting: _deletingStickers,
          savingOrder: _savingStickerOrder,
          downloading: _downloadingStickers,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      for (final stickerId in selectedIds) {
        final item = byStickerId[stickerId];
        if (item == null) continue;
        await _settingsController.deleteSticker(
          packId: item.pack.id,
          stickerId: stickerId,
        );
      }
      await _loadStickers(forceReload: true);
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.delete,
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            error: _stickerError,
            notice: stickerDeletedNotice(
              scope: StickerManagementScope.personal,
              count: selectedIds.length,
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
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<void> _downloadSelectedStickers() async {
    final selectedIds = List<String>.from(_selectedStickerIds);
    await _downloadStickerIds(selectedIds);
  }

  Future<void> _downloadStickerIds(List<String> stickerIds) async {
    if (!_settingsController.hasApi ||
        !canStartStickerSelectionAction(
          busy: _stickerManagementBusy,
          selectedStickerIds: stickerIds,
        )) {
      return;
    }

    setState(
      () => _applyStickerActionPatch(
        stickerActionStarted(
          action: StickerActionKind.download,
          uploading: _uploadingStickers,
          deleting: _deletingStickers,
          savingOrder: _savingStickerOrder,
          downloading: _downloadingStickers,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      final downloaded = await _settingsController.downloadStickers(
        stickerIds: stickerIds,
      );
      if (downloaded == null) {
        if (!mounted) return;
        setState(
          () => _applyStickerActionPatch(
            stickerActionCancelled(
              action: StickerActionKind.download,
              uploading: _uploadingStickers,
              deleting: _deletingStickers,
              savingOrder: _savingStickerOrder,
              downloading: _downloadingStickers,
              selectedStickerIds: _selectedStickerIds,
            ),
          ),
        );
        return;
      }
      final location = await widget.fileSelectionService.getSaveLocation(
        suggestedName: downloaded.filename,
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
              uploading: _uploadingStickers,
              deleting: _deletingStickers,
              savingOrder: _savingStickerOrder,
              downloading: _downloadingStickers,
              selectedStickerIds: _selectedStickerIds,
            ),
          ),
        );
        return;
      }
      await widget.fileSelectionService.saveBytesToPath(
        bytes: downloaded.bytes,
        path: location.path,
        filename: downloaded.filename,
        mimeType: downloaded.mimeType,
      );
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.download,
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            error: _stickerError,
            notice: stickerDownloadNotice(
              scope: StickerManagementScope.personal,
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
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<void> _pinSelectedStickers() async {
    final selectedIds = List<String>.from(_selectedStickerIds);
    if (!_settingsController.hasApi ||
        !canStartStickerSelectionAction(
          busy: _stickerManagementBusy,
          selectedStickerIds: selectedIds,
        )) {
      return;
    }

    final selectedByPack = sticker_ordering.selectedStickerIdsByPack(
      _stickerPacks,
      selectedIds,
    );
    if (selectedByPack.isEmpty) {
      setState(
        () => _applyStickerActionPatch(
          stickerActionNoticeShown(
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            error: _stickerError,
            notice: stickerNoOrderChangeNotice(StickerManagementScope.personal),
          ),
        ),
      );
      return;
    }

    setState(
      () => _applyStickerActionPatch(
        stickerActionStarted(
          action: StickerActionKind.order,
          uploading: _uploadingStickers,
          deleting: _deletingStickers,
          savingOrder: _savingStickerOrder,
          downloading: _downloadingStickers,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      for (final pack in _stickerPacks) {
        final selectedInPack = selectedByPack[pack.id];
        if (selectedInPack == null || selectedInPack.isEmpty) continue;
        final nextOrder = sticker_ordering
            .stickerOrderWithStickerIdsPinnedToFront(
              pack,
              selectedInPack,
              order: _stickerOrderDrafts[pack.id],
            );
        if (nextOrder == null) continue;
        await _settingsController.reorderStickers(
          packId: pack.id,
          stickerIds: nextOrder,
        );
      }
      await _loadStickers(forceReload: true);
      if (!mounted) return;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.order,
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            error: _stickerError,
            notice: stickerPinnedNotice(
              scope: StickerManagementScope.personal,
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
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
    }
  }

  void _previewSticker(ManagedSticker item) {
    final imageUrl = AppConfigScope.of(
      context,
    ).resolveAssetUrl(item.sticker.asset.url);
    if (imageUrl == null) return;
    final placement = _stickerPlacement(item.sticker.id);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => StickerPreviewDialog(
          item: item,
          imageUrl: imageUrl,
          canMoveUp: !_stickerFilterActive && (placement?.canMoveUp ?? false),
          canMoveDown:
              !_stickerFilterActive && (placement?.canMoveDown ?? false),
          canPin: placement?.canPin ?? false,
          canRename: true,
          canDownload: true,
          canDelete: true,
          onRename: (name) => _renameSticker(item, name),
          onSetAvatar: () => _setStickerAsAvatar(item),
          onDownload: () => _downloadStickerIds([item.sticker.id]),
          onDelete: () => _deleteStickerItem(item),
          onMoveUp: () => _moveStickerItem(item, -1),
          onMoveDown: () => _moveStickerItem(item, 1),
          onPin: () => _pinStickerItem(item),
        ),
      ),
    );
  }

  sticker_ordering.StickerPlacementData? _stickerPlacement(String stickerId) {
    return sticker_ordering.stickerPlacement(
      _stickerPacks,
      stickerId,
      orderForPack: (pack) => _stickerOrderDrafts[pack.id],
    );
  }

  Future<String?> _renameSticker(ManagedSticker item, String name) async {
    final trimmed = stickerRenameName(name);
    if (!_settingsController.hasApi || trimmed == null) return null;
    try {
      final updated = await _settingsController.updateSticker(
        packId: item.pack.id,
        stickerId: item.sticker.id,
        name: trimmed,
      );
      if (updated == null) return null;
      await _loadStickers(forceReload: true);
      return updated.name;
    } catch (e) {
      if (!mounted) return null;
      setState(
        () => _applyStickerActionPatch(
          stickerActionErrorShown(
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
            notice: _notice,
          ),
        ),
      );
      return null;
    }
  }

  Future<bool> _deleteStickerItem(ManagedSticker item) async {
    if (!_settingsController.hasApi || _stickerManagementBusy) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StickerConfirmDialog(
        title: stickerDeleteDialogTitle(StickerManagementScope.personal),
        body: stickerSingleDeleteConfirmBody(
          scope: StickerManagementScope.personal,
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
          uploading: _uploadingStickers,
          deleting: _deletingStickers,
          savingOrder: _savingStickerOrder,
          downloading: _downloadingStickers,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      await _settingsController.deleteSticker(
        packId: item.pack.id,
        stickerId: item.sticker.id,
      );
      await _loadStickers(forceReload: true);
      if (!mounted) return false;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.delete,
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            error: _stickerError,
            notice: stickerDeletedNotice(
              scope: StickerManagementScope.personal,
            ),
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
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
      return false;
    }
  }

  Future<sticker_ordering.StickerPlacementData?> _moveStickerItem(
    ManagedSticker item,
    int delta,
  ) async {
    final placement = _stickerPlacement(item.sticker.id);
    if (_stickerFilterActive) return placement;
    if (!_settingsController.hasApi ||
        placement == null ||
        _stickerManagementBusy) {
      return placement;
    }
    final ids = sticker_ordering.movedStickerOrder(
      placement.pack,
      item.sticker.id,
      delta,
      order: _stickerOrderDrafts[placement.pack.id],
    );
    if (ids == null) return placement;

    setState(
      () => _applyStickerActionPatch(
        stickerActionStarted(
          action: StickerActionKind.order,
          uploading: _uploadingStickers,
          deleting: _deletingStickers,
          savingOrder: _savingStickerOrder,
          downloading: _downloadingStickers,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      await _settingsController.reorderStickers(
        packId: placement.pack.id,
        stickerIds: ids,
      );
      await _loadStickers(forceReload: true);
      if (!mounted) return placement;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.order,
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            error: _stickerError,
            notice: stickerMoveNotice(
              scope: StickerManagementScope.personal,
              delta: delta,
            ),
          ),
        ),
      );
      return _stickerPlacement(item.sticker.id);
    } catch (e) {
      if (!mounted) return placement;
      setState(
        () => _applyStickerActionPatch(
          stickerActionFailed(
            action: StickerActionKind.order,
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
      return placement;
    }
  }

  Future<sticker_ordering.StickerPlacementData?> _pinStickerItem(
    ManagedSticker item,
  ) async {
    final placement = _stickerPlacement(item.sticker.id);
    if (!_settingsController.hasApi ||
        placement == null ||
        placement.index == 0 ||
        _stickerManagementBusy) {
      return placement;
    }

    final ids = sticker_ordering.pinnedStickerOrder(
      placement.pack,
      item.sticker.id,
      order: _stickerOrderDrafts[placement.pack.id],
    );
    if (ids == null) return placement;

    setState(
      () => _applyStickerActionPatch(
        stickerActionStarted(
          action: StickerActionKind.order,
          uploading: _uploadingStickers,
          deleting: _deletingStickers,
          savingOrder: _savingStickerOrder,
          downloading: _downloadingStickers,
          selectedStickerIds: _selectedStickerIds,
        ),
      ),
    );
    try {
      await _settingsController.reorderStickers(
        packId: placement.pack.id,
        stickerIds: ids,
      );
      await _loadStickers(forceReload: true);
      if (!mounted) return placement;
      setState(
        () => _applyStickerActionPatch(
          stickerActionSucceeded(
            action: StickerActionKind.order,
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            error: _stickerError,
            notice: stickerPinnedNotice(scope: StickerManagementScope.personal),
          ),
        ),
      );
      return _stickerPlacement(item.sticker.id);
    } catch (e) {
      if (!mounted) return placement;
      setState(
        () => _applyStickerActionPatch(
          stickerActionFailed(
            action: StickerActionKind.order,
            uploading: _uploadingStickers,
            deleting: _deletingStickers,
            savingOrder: _savingStickerOrder,
            downloading: _downloadingStickers,
            selectedStickerIds: _selectedStickerIds,
            failure: e,
          ),
        ),
      );
      return placement;
    }
  }

  Future<void> _setStickerAsAvatar(ManagedSticker item) async {
    if (!_settingsController.hasApi || _uploadingAvatar) return;
    setState(
      () => _applyAccountAvatarStatePatch(
        accountAvatarUploadStarted(
          target: AccountAvatarErrorTarget.sticker,
          pendingAvatarAssetId: _pendingAvatarAssetId,
          pendingAvatarUrl: _pendingAvatarUrl,
          clearUploadedAvatar: _clearUploadedAvatar,
          accountError: _accountError,
          stickerError: _stickerError,
        ),
      ),
    );
    try {
      final downloaded = await _settingsController.downloadStickers(
        stickerIds: [item.sticker.id],
      );
      if (downloaded == null) {
        if (!mounted) return;
        setState(
          () => _applyAccountAvatarStatePatch(
            accountAvatarActionCancelled(
              target: AccountAvatarErrorTarget.sticker,
              pendingAvatarAssetId: _pendingAvatarAssetId,
              pendingAvatarUrl: _pendingAvatarUrl,
              clearUploadedAvatar: _clearUploadedAvatar,
              accountError: _accountError,
              stickerError: _stickerError,
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      final cropped = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AvatarCropDialog(bytes: downloaded.bytes),
      );
      if (cropped == null || !mounted) {
        if (!mounted) return;
        setState(
          () => _applyAccountAvatarStatePatch(
            accountAvatarActionCancelled(
              target: AccountAvatarErrorTarget.sticker,
              pendingAvatarAssetId: _pendingAvatarAssetId,
              pendingAvatarUrl: _pendingAvatarUrl,
              clearUploadedAvatar: _clearUploadedAvatar,
              accountError: _accountError,
              stickerError: _stickerError,
            ),
          ),
        );
        return;
      }
      final asset = await _settingsController.uploadImageAsset(
        bytes: cropped,
        filename: stickerAvatarUploadFilename(stickerId: item.sticker.id),
        purpose: 'avatar',
      );
      if (asset == null) {
        if (!mounted) return;
        setState(
          () => _applyAccountAvatarStatePatch(
            accountAvatarActionCancelled(
              target: AccountAvatarErrorTarget.sticker,
              pendingAvatarAssetId: _pendingAvatarAssetId,
              pendingAvatarUrl: _pendingAvatarUrl,
              clearUploadedAvatar: _clearUploadedAvatar,
              accountError: _accountError,
              stickerError: _stickerError,
            ),
          ),
        );
        return;
      }
      final updated = await _settingsController.updateProfile(
        avatarAssetId: asset.id,
      );
      if (updated == null) {
        if (!mounted) return;
        setState(
          () => _applyAccountAvatarStatePatch(
            accountAvatarActionCancelled(
              target: AccountAvatarErrorTarget.sticker,
              pendingAvatarAssetId: _pendingAvatarAssetId,
              pendingAvatarUrl: _pendingAvatarUrl,
              clearUploadedAvatar: _clearUploadedAvatar,
              accountError: _accountError,
              stickerError: _stickerError,
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _user = updated;
        _syncUserFields(updated);
        _applyAccountAvatarStatePatch(
          accountAvatarProfileUpdatedFromStickerSucceeded(
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            clearUploadedAvatar: _clearUploadedAvatar,
            accountError: _accountError,
          ),
        );
      });
      widget.onUserUpdated?.call(updated);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyAccountAvatarStatePatch(
          accountAvatarActionFailed(
            target: AccountAvatarErrorTarget.sticker,
            pendingAvatarAssetId: _pendingAvatarAssetId,
            pendingAvatarUrl: _pendingAvatarUrl,
            clearUploadedAvatar: _clearUploadedAvatar,
            accountError: _accountError,
            stickerError: _stickerError,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<void> _openStickerFilter() async {
    final result = await showDialog<StickerFilterDraft>(
      context: context,
      builder: (context) => StickerFilterDialog(
        keyword: _stickerFilterKeyword,
        mimeType: _stickerFilterMimeType,
      ),
    );
    if (result == null || !mounted) return;
    setState(
      () => _applyStickerSelectionPatch(
        stickerFilterApplied(
          managing: _managingStickers,
          keyword: result.keyword,
          mimeType: result.mimeType,
        ),
      ),
    );
  }

  void _selectDefaultAvatarKey(String value) {
    setState(
      () => _applyAccountPresetAvatarSelectionPatch(
        accountPresetAvatarSelected(
          defaultAvatarKey: value,
          currentAvatarUrl: _user?.avatarUrl,
        ),
      ),
    );
  }

  Future<void> _changePassword() async {
    if (!account_display.canStartPasswordChange(
      hasApi: _settingsController.hasApi,
      changingPassword: _changingPassword,
    )) {
      return;
    }
    final draft = passwordChangeDraftFromForm(
      currentPassword: _currentPasswordController.text,
      newPassword: _newPasswordController.text,
      confirmPassword: _confirmPasswordController.text,
    );
    if (!draft.isValid) {
      setState(
        () => _applyPasswordChangeStatePatch(
          passwordChangeValidationFailed(
            error: draft.error!,
            changingPassword: _changingPassword,
            notice: _notice,
          ),
        ),
      );
      return;
    }

    setState(() => _applyPasswordChangeStatePatch(passwordChangeStarted()));
    try {
      await _settingsController.changePassword(
        currentPassword: draft.currentPassword!,
        newPassword: draft.newPassword!,
      );
      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      setState(() => _applyPasswordChangeStatePatch(passwordChangeSucceeded()));
      unawaited(_loadSessions());
    } catch (e) {
      if (!mounted) return;
      setState(() => _applyPasswordChangeStatePatch(passwordChangeFailed(e)));
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final user = _user;
    if (!account_display.canStartAccountDeletion(
      hasApi: _settingsController.hasApi,
      user: user,
      deletingAccount: _deletingAccount,
    )) {
      return;
    }
    final targetUser = user!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteAccountDialog(
        spec: account_display.accountDeletionConfirmationSpec(targetUser),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _applyAccountDeletionStatePatch(accountDeletionStarted()));
    try {
      await _settingsController.deleteMyAccount();
      if (!mounted) return;
      await widget.onAccountDeleted?.call();
      if (!mounted) return;
      setState(
        () => _applyAccountDeletionStatePatch(
          accountDeletionFinished(
            securityError: _securityError,
            notice: _notice,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _applyAccountDeletionStatePatch(accountDeletionFailed(e)));
    }
  }

  Future<void> _loadStoredAudioSettings() async {
    try {
      final stored = await widget.audioDeviceStore.read();
      if (!mounted) return;
      final patch = audioStoredVolumesApplied(
        inputVolume: stored.inputVolume,
        outputVolume: stored.outputVolume,
      );
      setState(() => _applyAudioVolumePatch(patch));
      widget.onVolumeChanged?.call('audioinput', patch.inputVolume);
      widget.onVolumeChanged?.call('audiooutput', patch.outputVolume);
    } catch (_) {}
  }

  Future<void> _loadDevices() async {
    setState(
      () => _applyAudioDeviceListPatch(
        audioDeviceListLoadStarted(
          inputs: _audioInputs,
          outputs: _audioOutputs,
          selectedInput: _selectedInput,
          selectedOutput: _selectedOutput,
        ),
      ),
    );
    try {
      // Enumerate while a mic capture track is live. On macOS the device list
      // is empty until the audio module has been initialized by a running
      // capture unit, which is why devices only used to appear after joining a
      // room. Holding the track open across enumeration reproduces that state,
      // and retrying while no input has shown up yet covers the brief window
      // where the module starts before its device list is populated.
      final devices = await _audioTestService.withCaptureSession(
        widget.audioDeviceService.enumerateDevices,
        retryWhile: (devices) =>
            !devices.any((device) => audioDeviceInfoKind(device) == 'audioinput'),
      );
      await _applyDevices(devices);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _applyAudioDeviceListPatch(
          audioDeviceListLoadFailed(
            inputs: _audioInputs,
            outputs: _audioOutputs,
            selectedInput: _selectedInput,
            selectedOutput: _selectedOutput,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<void> _applyDevices(List<AudioDeviceInfo> devices) async {
    if (!mounted) return;
    final systemDefaultInputId = _systemDefaultInputId;
    RestoredAudioDevices<AudioDeviceInfo> restored =
        const RestoredAudioDevices();
    try {
      restored = await restoreStoredAudioDevices(
        widget.audioDeviceStore,
        audioDevices: widget.audioDeviceService,
        devices: devices,
        systemDefaultInputId: systemDefaultInputId,
      );
    } catch (_) {
      // Device choices are a local convenience. If storage or OS routing fails,
      // keep rendering the current device list and let the user re-select.
    }
    if (!mounted) return;
    final systemDefaultInput = systemDefaultInputId == null
        ? null
        : storedAudioDeviceFrom(
            devices,
            kind: 'audioinput',
            deviceId: systemDefaultInputId,
            kindOf: audioDeviceInfoKind,
            deviceIdOf: audioDeviceInfoId,
          );
    setState(
      () => _applyAudioDeviceListPatch(
        audioDeviceListApplied(
          devices: devices,
          restoredInput: restored.input,
          restoredOutput: restored.output,
          hardwareInput: widget.audioDeviceService.selectedAudioInput,
          hardwareOutput: widget.audioDeviceService.selectedAudioOutput,
          currentInput: _selectedInput,
          currentOutput: _selectedOutput,
          kindOf: audioDeviceInfoKind,
          deviceIdOf: audioDeviceInfoId,
          error: _error,
          systemDefaultInput: systemDefaultInput,
        ),
      ),
    );
  }

  // Re-runs device selection when the OS default microphone changes while
  // Settings is open. restoreStoredAudioDevices only falls back to the system
  // default when the user has not pinned a device, so an explicit choice is
  // preserved; otherwise the picker and capture follow the new default.
  Future<void> _onSystemDefaultInputChanged() async {
    if (!mounted || !_voiceInitialized) return;
    await _applyDevices([..._audioInputs, ..._audioOutputs]);
  }

  Future<void> _selectInput(AudioDeviceInfo device) async {
    final wasTestingInput = _testingInput;
    final wasTestingOutput = _testingOutput;
    final didSelect = await _selectDevice(
      device,
      () => widget.audioDeviceService.selectAudioInput(device),
      () => widget.audioDeviceStore.writeInputDeviceId(device.deviceId),
    );
    if (!didSelect) return;
    final effects = audioInputDeviceSelectedEffects(
      wasTestingInput: wasTestingInput,
      wasTestingOutput: wasTestingOutput,
    );
    if (effects.restartInputTest) await _restartInputTest();
    if (effects.restartOutputTest) await _restartOutputTest();
  }

  Future<void> _selectOutput(AudioDeviceInfo device) async {
    final didSelect = await _selectDevice(
      device,
      () => widget.audioDeviceService.selectAudioOutput(device),
      () => widget.audioDeviceStore.writeOutputDeviceId(device.deviceId),
    );
    if (!didSelect) return;
    final effects = audioOutputDeviceSelectedEffects(
      testingOutput: _testingOutput,
    );
    if (effects.routeOutputTest) {
      await _outputTest?.routeOutput(_selectedOutput?.deviceId);
    }
  }

  Future<bool> _selectDevice(
    AudioDeviceInfo device,
    Future<void> Function() select,
    Future<void> Function() rememberSelection,
  ) async {
    if (!canStartAudioDeviceSelection(_busyDeviceId)) return false;
    setState(
      () => _applyAudioDeviceSelectionPatch(
        audioDeviceSelectionStarted(
          device: device,
          selectedInput: _selectedInput,
          selectedOutput: _selectedOutput,
          kindOf: audioDeviceInfoKind,
          deviceIdOf: audioDeviceInfoId,
        ),
      ),
    );
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
      setState(
        () => _applyAudioDeviceSelectionPatch(
          audioDeviceSelectionSucceeded(
            device: device,
            selectedInput: _selectedInput,
            selectedOutput: _selectedOutput,
            kindOf: audioDeviceInfoKind,
            storageFailure: storageError,
          ),
        ),
      );
      widget.onDeviceSelected?.call(device.kind, device.deviceId);
      didSelect = true;
    } catch (e) {
      if (mounted) {
        setState(
          () => _applyAudioDeviceSelectionPatch(
            audioDeviceSelectionFailed(
              selectedInput: _selectedInput,
              selectedOutput: _selectedOutput,
              failure: e,
            ),
          ),
        );
      }
    }
    return didSelect;
  }

  Future<void> _setInputVolume(double volume) async {
    final patch = audioInputVolumeChanged(
      inputVolume: volume,
      outputVolume: _outputVolume,
    );
    setState(() => _applyAudioVolumePatch(patch));
    final inputTest = _inputTest;
    final effects = audioInputVolumeChangedEffects(
      inputVolume: patch.inputVolume,
      hasInputTestTrack: inputTest != null,
    );
    widget.onVolumeChanged?.call(effects.deviceKind, effects.volume);
    unawaited(widget.audioDeviceStore.writeInputVolume(effects.volume));
    if (effects.updateInputTestTrack && inputTest != null) {
      try {
        await inputTest.setCaptureVolume(effects.volume);
      } catch (_) {}
    }
  }

  Future<void> _setOutputVolume(double volume) async {
    final patch = audioOutputVolumeChanged(
      inputVolume: _inputVolume,
      outputVolume: volume,
    );
    setState(() => _applyAudioVolumePatch(patch));
    final outputTest = _outputTest;
    final effects = audioOutputVolumeChangedEffects(
      outputVolume: patch.outputVolume,
      hasOutputRenderer: outputTest != null,
    );
    widget.onVolumeChanged?.call(effects.deviceKind, effects.volume);
    unawaited(widget.audioDeviceStore.writeOutputVolume(effects.volume));
    if (effects.updateOutputRenderer && outputTest != null) {
      try {
        await outputTest.setPlaybackVolume(effects.volume);
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
    setState(
      () => _applyAudioTestStatePatch(
        audioInputTestStarted(
          testingOutput: _testingOutput,
          outputLevel: _outputLevel,
        ),
      ),
    );
    AudioTestHandle? handle;
    try {
      handle = await _audioTestService.startInputTest(
        inputDeviceId: _selectedInput?.deviceId,
        volume: _inputVolume,
        onLevel: (level) {
          if (!mounted) return;
          setState(
            () => _applyAudioTestStatePatch(
              audioInputLevelChanged(
                level: level,
                inputVolume: _inputVolume,
                testingOutput: _testingOutput,
                outputLevel: _outputLevel,
                error: _error,
              ),
            ),
          );
        },
      );
      if (!mounted) {
        await handle.dispose();
        return;
      }
      _inputTest = handle;
    } catch (e) {
      await handle?.dispose();
      if (!mounted) return;
      setState(
        () => _applyAudioTestStatePatch(
          audioInputTestFailed(
            testingOutput: _testingOutput,
            outputLevel: _outputLevel,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<void> _stopInputTest({bool updateState = true}) async {
    final inputTest = _inputTest;
    _inputTest = null;
    await inputTest?.dispose();
    if (updateState && mounted) {
      setState(
        () => _applyAudioTestStatePatch(
          audioInputTestStopped(
            testingOutput: _testingOutput,
            outputLevel: _outputLevel,
            error: _error,
          ),
        ),
      );
    }
  }

  Future<void> _startOutputTest() async {
    if (_testingOutput) return;
    setState(
      () => _applyAudioTestStatePatch(
        audioOutputTestStarted(
          testingInput: _testingInput,
          inputLevel: _inputLevel,
        ),
      ),
    );
    AudioTestHandle? handle;
    try {
      handle = await _audioTestService.startOutputTest(
        inputDeviceId: _selectedInput?.deviceId,
        outputDeviceId: _selectedOutput?.deviceId,
        volume: _outputVolume,
        onLevel: (level) {
          if (!mounted) return;
          setState(
            () => _applyAudioTestStatePatch(
              audioOutputLevelChanged(
                level: level,
                outputVolume: _outputVolume,
                testingInput: _testingInput,
                inputLevel: _inputLevel,
                error: _error,
              ),
            ),
          );
        },
      );
      if (!mounted) {
        await handle.dispose();
        return;
      }
      _outputTest = handle;
    } catch (e) {
      await handle?.dispose();
      if (!mounted) return;
      setState(
        () => _applyAudioTestStatePatch(
          audioOutputTestFailed(
            testingInput: _testingInput,
            inputLevel: _inputLevel,
            failure: e,
          ),
        ),
      );
    }
  }

  Future<void> _stopOutputTest({bool updateState = true}) async {
    final outputTest = _outputTest;
    _outputTest = null;
    await outputTest?.dispose();
    if (updateState && mounted) {
      setState(
        () => _applyAudioTestStatePatch(
          audioOutputTestStopped(
            testingInput: _testingInput,
            inputLevel: _inputLevel,
            error: _error,
          ),
        ),
      );
    }
  }

  bool get _isRefreshing {
    return settingsSectionRefreshing(
      section: _section,
      loadingAccount: _loadingAccount,
      loadingStickers: _loadingStickers,
      loadingSessions: _loadingSessions,
      loadingVoice: _loading,
    );
  }

  void _selectSection(SettingsSection section) {
    final patch = settingsSectionSelected(
      section: section,
      sessionsEmpty: _sessions.isEmpty,
      loadingSessions: _loadingSessions,
    );
    setState(() {
      _applySettingsSectionPatch(patch);
    });
    if (patch.shouldLoadStickers) {
      unawaited(_ensureStickersLoaded());
    }
    if (patch.shouldLoadSessions) {
      unawaited(_loadSessions());
    }
    if (patch.shouldInitializeVoice) {
      unawaited(_ensureVoiceInitialized());
    }
  }

  Widget _buildSectionContent() {
    return switch (_section) {
      SettingsSection.profile => _buildProfileContent(),
      SettingsSection.preferences => _buildPreferencesContent(),
      SettingsSection.stickers => _buildStickersContent(),
      SettingsSection.security => _buildSecurityContent(),
      SettingsSection.voice => _buildVoiceContent(),
    };
  }

  Widget _buildStickersContent() {
    final unavailable = !_settingsController.hasApi;
    final items = _filteredStickerItems();
    final totalCount = _allStickerItems().length;
    final selectionNumbers = _stickerSelectionNumbers();
    final busy = _stickerManagementBusy;
    final allVisibleSelected = stickerAllVisibleSelected(
      selectedStickerIds: _selectedStickerIds,
      visibleItems: items,
    );

    return SettingsList(
      children: [
        if (_notice != null) _SettingsNotice(message: _notice!),
        if (_stickerError != null) _SettingsError(message: _stickerError!),
        if (unavailable)
          const _SettingsEmptyState(text: '表情包需要登录后从服务端读取')
        else
          _SettingsGroup(
            title: '表情包管理',
            trailing: Text(
              stickerManagementCountText(
                filterActive: _stickerFilterActive,
                visibleCount: items.length,
                totalCount: totalCount,
              ),
              style: const TextStyle(
                color: _textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              StickerActionRow(
                children: [
                  Button(
                    onPressed: canStartStickerPrimaryAction(busy: busy)
                        ? _managingStickers
                              ? _deleteSelectedStickers
                              : _pickAndUploadStickers
                        : null,
                    loading: _managingStickers
                        ? _deletingStickers
                        : _uploadingStickers,
                    tone: _managingStickers
                        ? ButtonTone.danger
                        : ButtonTone.primary,
                    icon: Icon(
                      _managingStickers
                          ? Icons.delete_outline
                          : Icons.upload_file,
                    ),
                    width: double.infinity,
                    child: Text(_managingStickers ? '删除' : '本地上传'),
                  ),
                  Button(
                    onPressed: canUseStickerManagementControl(busy: busy)
                        ? _toggleStickerManageMode
                        : null,
                    selected: _managingStickers,
                    tone: _managingStickers
                        ? ButtonTone.primary
                        : ButtonTone.neutral,
                    icon: Icon(
                      _managingStickers ? Icons.close : Icons.checklist_rtl,
                    ),
                    width: double.infinity,
                    child: Text(_managingStickers ? '取消管理' : '批量管理'),
                  ),
                  Button(
                    onPressed: canUseStickerManagementControl(busy: busy)
                        ? _openStickerFilter
                        : null,
                    selected: _stickerFilterActive,
                    tone: _stickerFilterActive
                        ? ButtonTone.primary
                        : ButtonTone.neutral,
                    icon: const Icon(Icons.filter_alt_outlined),
                    width: double.infinity,
                    child: const Text('筛选'),
                  ),
                ],
              ),
              if (_managingStickers) ...[
                const SizedBox(height: 10),
                StickerActionRow(
                  children: [
                    Button(
                      onPressed:
                          canStartStickerSelectionAction(
                            busy: busy,
                            selectedStickerIds: _selectedStickerIds,
                          )
                          ? _downloadSelectedStickers
                          : null,
                      loading: _downloadingStickers,
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
                          ? _pinSelectedStickers
                          : null,
                      loading: _savingStickerOrder,
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
                          ? () => _selectAllVisibleStickers(items)
                          : null,
                      selected: allVisibleSelected,
                      icon: Icon(
                        allVisibleSelected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                      ),
                      width: double.infinity,
                      child: Text(
                        stickerVisibleSelectionButtonText(
                          selectedStickerIds: _selectedStickerIds,
                          visibleItems: items,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              if (_loadingStickers && _stickerPacks.isEmpty)
                const SizedBox(
                  height: 128,
                  child: Center(child: CircularProgressIndicator(color: _cyan)),
                )
              else if (totalCount == 0)
                const _SettingsEmptyState(text: '暂无表情，点击本地上传会自动创建')
              else if (items.isEmpty)
                const _SettingsEmptyState(text: '没有匹配的表情')
              else
                StickerGrid(
                  items: items,
                  managing: _managingStickers,
                  selectionNumbers: selectionNumbers,
                  busy: busy,
                  onTap: (item) {
                    if (_managingStickers) {
                      _toggleStickerSelection(item.sticker.id);
                    } else {
                      _previewSticker(item);
                    }
                  },
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildPreferencesContent() {
    final unavailable = !_settingsController.hasApi || _user == null;
    return SettingsList(
      children: [
        if (_notice != null) _SettingsNotice(message: _notice!),
        if (_accountError != null) _SettingsError(message: _accountError!),
        if (unavailable)
          const _SettingsEmptyState(text: '偏好设置需要登录后从服务端读取')
        else
          _SettingsGroup(
            title: '语言切换',
            children: [
              _SegmentedSetting(
                label: '语言',
                value: _language,
                options: const [
                  _SegmentOption(value: 'zh-Hans', label: '简体中文'),
                  _SegmentOption(value: 'zh-Hant', label: '繁體中文'),
                  _SegmentOption(value: 'en', label: 'English'),
                ],
                onChanged: (value) => setState(() => _language = value),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Button(
                  onPressed: _savingAccount
                      ? null
                      : () => unawaited(
                          _saveAccount(
                            target: AccountFormSaveTarget.preferences,
                          ),
                        ),
                  loading: _savingAccount,
                  icon: const Icon(Icons.save_outlined),
                  tone: ButtonTone.primary,
                  child: const Text('保存偏好设置'),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildProfileContent() {
    final user = _user;
    final unavailable = !_settingsController.hasApi || user == null;
    final appConfig = AppConfigScope.of(context);
    final avatarPreviewUrl = appConfig.resolveAssetUrl(
      account_display.accountAvatarPreviewPath(
        clearUploadedAvatar: _clearUploadedAvatar,
        pendingAvatarUrl: _pendingAvatarUrl,
        currentAvatarUrl: user?.avatarUrl,
      ),
    );
    return SettingsList(
      children: [
        if (_notice != null) _SettingsNotice(message: _notice!),
        if (_accountError != null) _SettingsError(message: _accountError!),
        if (unavailable)
          const _SettingsEmptyState(text: '账号资料需要登录后从服务端读取')
        else ...[
          _SettingsGroup(
            title: '账号标识',
            children: [
              _CopyableField(label: '个人 UID', value: user.uid),
              const SizedBox(height: 14),
              _LabeledTextField(
                label: '登录 Username',
                controller: _usernameController,
                enabled: account_display.canEditUsername(user),
                helperText: account_display.usernameHelperText(user),
              ),
            ],
          ),
          _SettingsGroup(
            title: '默认资料',
            children: [
              _LabeledTextField(
                label: '用户名',
                controller: _displayNameController,
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
                onChanged: (value) => setState(
                  () => _applyAccountEditableFieldsPatch(
                    accountGenderChanged(
                      gender: value,
                      emailPublic: _emailPublic,
                      phoneNumberPublic: _phonePublic,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AvatarPicker(
                label: '头像',
                displayName: _displayNameController.text,
                imageUrl: avatarPreviewUrl,
                defaultAvatarKey: _defaultAvatarKey,
                usingPreset: avatarPreviewUrl == null,
                uploading: _uploadingAvatar,
                enabled: !_uploadingAvatar,
                onUpload: _pickAndUploadAvatar,
                onPresetSelected: _selectDefaultAvatarKey,
                uploadLabel: '上传头像',
              ),
              const SizedBox(height: 14),
              _LabeledTextField(
                label: '签名',
                controller: _bioController,
                maxLines: 4,
                helperText: '用于个人资料面板展示。',
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Button(
              onPressed: _savingProfile ? null : _saveProfile,
              loading: _savingProfile,
              icon: const Icon(Icons.save_outlined),
              tone: ButtonTone.primary,
              child: const Text('保存用户资料'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSecurityContent() {
    final user = _user;
    final unavailable = !_settingsController.hasApi || user == null;
    return SettingsList(
      children: [
        if (_notice != null) _SettingsNotice(message: _notice!),
        if (_securityError != null) _SettingsError(message: _securityError!),
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
                helperText: '用于登录、账号找回和安全通知。',
              ),
              const SizedBox(height: 10),
              _ToggleSetting(
                label: '公开邮箱',
                value: _emailPublic,
                onChanged: (value) => setState(
                  () => _applyAccountEditableFieldsPatch(
                    accountEmailPublicChanged(
                      gender: _gender,
                      emailPublic: value,
                      phoneNumberPublic: _phonePublic,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _LabeledTextField(
                label: '手机号绑定',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                helperText: '用于账号找回和安全通知，留空表示解绑。',
              ),
              const SizedBox(height: 10),
              _ToggleSetting(
                label: '公开手机号',
                value: _phonePublic,
                onChanged: (value) => setState(
                  () => _applyAccountEditableFieldsPatch(
                    accountPhoneNumberPublicChanged(
                      gender: _gender,
                      emailPublic: _emailPublic,
                      phoneNumberPublic: value,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Button(
                  onPressed: _savingAccount ? null : _saveAccount,
                  loading: _savingAccount,
                  icon: const Icon(Icons.save_outlined),
                  tone: ButtonTone.primary,
                  child: const Text('保存绑定信息'),
                ),
              ),
            ],
          ),
          _SettingsGroup(
            title: '重置密码',
            children: [
              _LabeledTextField(
                label: '当前密码',
                controller: _currentPasswordController,
                obscureText: _obscureCurrentPassword,
                onTogglePasswordVisibility: () => setState(
                  () => _applyPasswordVisibilityPatch(
                    passwordVisibilityToggled(
                      field: PasswordVisibilityField.current,
                      obscureCurrentPassword: _obscureCurrentPassword,
                      obscureNewPassword: _obscureNewPassword,
                      obscureConfirmPassword: _obscureConfirmPassword,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                label: '新密码',
                controller: _newPasswordController,
                obscureText: _obscureNewPassword,
                onTogglePasswordVisibility: () => setState(
                  () => _applyPasswordVisibilityPatch(
                    passwordVisibilityToggled(
                      field: PasswordVisibilityField.newPassword,
                      obscureCurrentPassword: _obscureCurrentPassword,
                      obscureNewPassword: _obscureNewPassword,
                      obscureConfirmPassword: _obscureConfirmPassword,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                label: '确认新密码',
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                onTogglePasswordVisibility: () => setState(
                  () => _applyPasswordVisibilityPatch(
                    passwordVisibilityToggled(
                      field: PasswordVisibilityField.confirm,
                      obscureCurrentPassword: _obscureCurrentPassword,
                      obscureNewPassword: _obscureNewPassword,
                      obscureConfirmPassword: _obscureConfirmPassword,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Button(
                      onPressed: null,
                      icon: const Icon(Icons.help_outline),
                      child: const Text('忘记密码'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Button(
                      onPressed: _changingPassword ? null : _changePassword,
                      loading: _changingPassword,
                      icon: const Icon(Icons.lock_reset),
                      tone: ButtonTone.primary,
                      child: const Text('更新密码'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          _SettingsGroup(
            title: '账号活动',
            trailing: ButtonIcon(
              tooltip: '刷新账号活动',
              onPressed: _loadingSessions ? null : _loadSessions,
              icon: const Icon(Icons.refresh),
              size: 30,
            ),
            children: [
              _ReadOnlyLine(
                label: '账号创建时间',
                value: account_display.formatDateTime(user.createdAt),
              ),
              const SizedBox(height: 14),
              _SessionList(sessions: _sessions, loading: _loadingSessions),
            ],
          ),
          _SettingsGroup(
            title: '注销账号',
            danger: true,
            children: [
              Text(
                account_display.accountDeletionDescription(user),
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Button(
                  onPressed:
                      account_display.canStartAccountDeletion(
                        hasApi: _settingsController.hasApi,
                        user: user,
                        deletingAccount: _deletingAccount,
                      )
                      ? _confirmDeleteAccount
                      : null,
                  loading: _deletingAccount,
                  icon: const Icon(Icons.delete_outline),
                  tone: ButtonTone.danger,
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
    return SettingsList(
      children: [
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
                testTooltip: audioInputTestTooltip(_testingInput),
                disabled: _audioInputs.isEmpty,
                onVolumeChanged: (value) => unawaited(_setInputVolume(value)),
                onToggleTest: _toggleInputTest,
              ),
            ),
          ],
        ),
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
                testTooltip: audioOutputTestTooltip(_testingOutput),
                disabled: _audioOutputs.isEmpty,
                onVolumeChanged: (value) => unawaited(_setOutputVolume(value)),
                onToggleTest: _toggleOutputTest,
              ),
            ),
          ],
        ),
        if (_error != null) _SettingsError(message: _error!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _primaryDarkLow,
      body: SettingsScaffold(
        icon: Icons.settings_outlined,
        title: '设置',
        onBack: widget.onClose != null || !widget.isSubWindow
            ? (widget.onClose ?? () => Navigator.of(context).pop())
            : null,
        headerAction: ButtonIcon(
          tooltip: '刷新设置',
          onPressed: _isRefreshing ? null : _refreshActiveSection,
          icon: const Icon(Icons.refresh),
          size: 38,
          loading: _isRefreshing,
        ),
        pinned: _SettingsNavigation(
          selected: _section,
          onChanged: _selectSection,
        ),
        body: _buildSectionContent(),
      ),
    );
  }
}
