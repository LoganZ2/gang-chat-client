import 'dart:async';

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

enum _SettingsSection { profile, security, voice }

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
  bool _changingPassword = false;
  bool _deletingAccount = false;
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
  bool _requestedDeviceAccess = false;
  String? _error;
  bool _loading = true;
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
    _deviceSubscription = lk.Hardware.instance.onDeviceChange.stream.listen((
      devices,
    ) {
      unawaited(_applyDevices(devices));
    });
    unawaited(_loadStoredAudioSettings());
    unawaited(_loadDevices());
    unawaited(_loadAccount());
    unawaited(_loadSessions());
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

  Future<void> _refreshActiveSection() async {
    switch (_section) {
      case _SettingsSection.profile:
        await _loadAccount();
        break;
      case _SettingsSection.security:
        await Future.wait([_loadAccount(), _loadSessions()]);
        break;
      case _SettingsSection.voice:
        await _loadDevices();
        break;
    }
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
      setState(() => _accountError = '默认用户名不能为空');
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
    if (nextDisplayName == null &&
        nextBio == null &&
        nextGender == null &&
        nextAvatarKey == null) {
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
        avatarAssetId: nextAvatarKey == null ? null : '',
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
      _SettingsSection.security => _loadingAccount || _loadingSessions,
      _SettingsSection.voice => _loading,
    };
  }

  String get _activeTitle {
    return switch (_section) {
      _SettingsSection.profile => '用户资料',
      _SettingsSection.security => '隐私和安全',
      _SettingsSection.voice => '默认语音源',
    };
  }

  Widget _buildSectionContent() {
    return switch (_section) {
      _SettingsSection.profile => _buildProfileContent(),
      _SettingsSection.security => _buildSecurityContent(),
      _SettingsSection.voice => _buildVoiceContent(),
    };
  }

  Widget _buildProfileContent() {
    final user = _user;
    final unavailable = widget.api == null || user == null;
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
                label: '个人永久 UID',
                value: user.uid,
                tooltip: '复制 UID',
                onCopy: () => _copyText(user.uid, 'UID 已复制'),
              ),
              const SizedBox(height: 14),
              _LabeledTextField(
                label: '登录 Username',
                controller: _usernameController,
                enabled: _canEditUsername(user),
                trailing: KeyIconButton(
                  tooltip: '复制 Username',
                  onPressed: () => _copyText(
                    _usernameController.text.trim(),
                    'Username 已复制',
                  ),
                  icon: const Icon(Icons.copy),
                  size: 30,
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
                label: '默认用户名',
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
                onChanged: (value) => setState(() => _gender = value),
              ),
              const SizedBox(height: 14),
              _AvatarKeyPicker(
                value: _defaultAvatarKey,
                displayName: _displayNameController.text,
                avatarUrl: AppConfigScope.of(
                  context,
                ).resolveAssetUrl(user.avatarUrl),
                onChanged: (value) => setState(() => _defaultAvatarKey = value),
              ),
              const SizedBox(height: 14),
              _LabeledTextField(
                label: '默认签名',
                controller: _bioController,
                maxLines: 4,
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
        _DeviceSection(
          title: 'Input source',
          icon: Icons.mic,
          devices: _audioInputs,
          selectedDevice: _selectedInput,
          busyDeviceId: _busyDeviceId,
          emptyText: _loading
              ? 'Loading input sources'
              : 'No input sources found',
          fallbackLabel: 'Microphone',
          onSelect: _selectInput,
        ),
        const SizedBox(height: 16),
        _AudioControlPanel(
          title: 'Input volume',
          icon: Icons.graphic_eq,
          volume: _inputVolume,
          level: _inputLevel,
          testing: _testingInput,
          testTooltip: _testingInput ? 'Stop input test' : 'Test input volume',
          disabled: _audioInputs.isEmpty,
          onVolumeChanged: (value) => unawaited(_setInputVolume(value)),
          onToggleTest: _toggleInputTest,
        ),
        const SizedBox(height: 30),
        _DeviceSection(
          title: 'Output source',
          icon: Icons.headphones,
          devices: _audioOutputs,
          selectedDevice: _selectedOutput,
          busyDeviceId: _busyDeviceId,
          emptyText: _loading
              ? 'Loading output sources'
              : 'No output sources found',
          fallbackLabel: 'Output',
          onSelect: _selectOutput,
        ),
        const SizedBox(height: 16),
        _AudioControlPanel(
          title: 'Output volume',
          icon: Icons.volume_up,
          volume: _outputVolume,
          level: _outputLevel,
          testing: _testingOutput,
          testTooltip: _testingOutput
              ? 'Stop output test'
              : 'Test output volume',
          disabled: _audioOutputs.isEmpty,
          onVolumeChanged: (value) => unawaited(_setOutputVolume(value)),
          onToggleTest: _toggleOutputTest,
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
                    if (section == _SettingsSection.security &&
                        _sessions.isEmpty &&
                        !_loadingSessions) {
                      unawaited(_loadSessions());
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

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.label,
    required this.controller,
    this.enabled = true,
    this.maxLines = 1,
    this.obscureText = false,
    this.keyboardType,
    this.trailing,
    this.helperText,
    this.onTogglePasswordVisibility,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final int maxLines;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? trailing;
  final String? helperText;
  final VoidCallback? onTogglePasswordVisibility;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _FieldLabel(label)),
            ?trailing,
          ],
        ),
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
            suffixIcon: onTogglePasswordVisibility == null
                ? null
                : _PasswordVisibilityToggle(
                    obscure: obscureText,
                    enabled: enabled,
                    onPressed: onTogglePasswordVisibility!,
                  ),
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
    required this.onChanged,
  });

  static const _keys = [
    'blue-3',
    'green-2',
    'amber-2',
    'violet-2',
    'rose-2',
    'teal-2',
    'olive-2',
    'slate-2',
  ];

  final String value;
  final String displayName;
  final String? avatarUrl;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel('默认头像'),
        const SizedBox(height: 10),
        Row(
          children: [
            _AvatarPreview(
              label: displayName,
              imageUrl: avatarUrl,
              defaultAvatarKey: value,
              size: 46,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
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
                              color: value == key ? _cyan : _borderColor,
                              width: value == key ? 2 : 1,
                            ),
                          ),
                          child: const SizedBox.square(dimension: 28),
                        ),
                      ),
                    ),
                ],
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
            fontSize: (size * 0.36).clamp(12, 20).toDouble(),
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
  var peak = 0.0;
  for (final value in event.event) {
    if (value is! num) continue;
    final sample = value.toDouble();
    if (sample > peak) peak = sample;
  }
  return peak.clamp(0.0, 1.0).toDouble();
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
  const palette = <Color>[
    Color(0xFF46695B),
    Color(0xFF566A7F),
    Color(0xFF71614E),
    Color(0xFF665B7D),
    Color(0xFF7A5961),
    Color(0xFF536E73),
    Color(0xFF6A704B),
    Color(0xFF5E6472),
  ];
  final index = key.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
  return palette[index % palette.length];
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
              child: KeySurface(
                onPressed: disabled ? null : onToggleTest,
                tooltip: testTooltip,
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                backgroundColor: const Color(0xFF5B6397),
                selectedBackgroundColor: const Color(0xFF5B6397),
                pressedBackgroundColor: const Color(0xFF454C7A),
                disabledBackgroundColor: const Color(0xFF303542),
                borderColor: const Color(0xFF5B6397),
                selectedBorderColor: const Color(0xFF5B6397),
                disabledBorderColor: _borderColor,
                borderRadius: 2,
                hoverLift: 0,
                pressDepth: 0,
                baseDepth: 0,
                child: Center(
                  child: Text(
                    testing ? '停止测试' : '测试',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: disabled ? _textMuted : _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
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
                            : const Color(0xFFE8EBEE),
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
