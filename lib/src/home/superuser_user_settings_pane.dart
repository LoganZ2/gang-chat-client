part of 'home_shell.dart';

enum _SuperuserSettingsSection { profile, account, audio, security }

class _SuperuserUserSettingsPane extends StatefulWidget {
  const _SuperuserUserSettingsPane({
    super.key,
    required this.api,
    required this.apiBaseUrl,
    required this.currentUser,
    required this.initialUser,
    required this.fileSelectionService,
    required this.onClose,
    required this.onSaved,
  });

  final GangApi api;
  final String apiBaseUrl;
  final CurrentUser currentUser;
  final UserSummary initialUser;
  final FileSelectionService fileSelectionService;
  final VoidCallback onClose;
  final ValueChanged<CurrentUser> onSaved;

  @override
  State<_SuperuserUserSettingsPane> createState() =>
      _SuperuserUserSettingsPaneState();
}

class _SuperuserUserSettingsPaneState
    extends State<_SuperuserUserSettingsPane> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  _SuperuserSettingsSection _section = _SuperuserSettingsSection.profile;
  CurrentUser? _user;
  UserAudioSettings? _audio;
  String _gender = 'secret';
  String _language = defaultUserLanguage;
  String _status = 'active';
  bool _emailVerified = false;
  bool _emailPublic = false;
  bool _phonePublic = false;
  String _defaultAvatarKey = 'blue-3';
  String? _pendingAvatarAssetId;
  String? _pendingAvatarUrl;
  bool _usingPreset = true;
  bool _loading = true;
  bool _saving = false;
  bool _savingAudio = false;
  bool _uploadingAvatar = false;
  bool _resettingPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _bio.dispose();
    _email.dispose();
    _phone.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final userFuture = widget.api.getForcedUserSettings(
        widget.initialUser.id,
      );
      final audioFuture = widget.api.getForcedUserAudioSettings(
        widget.initialUser.id,
      );
      final user = await userFuture;
      final audio = await audioFuture;
      if (!mounted) return;
      setState(() {
        _applyUser(user);
        _audio = audio;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFloatingErrorNotice(
        context,
        userFacingErrorMessage(error, fallback: '无法读取用户设置'),
      );
    }
  }

  void _applyUser(CurrentUser user) {
    _user = user;
    _username.text = user.username;
    _displayName.text = user.displayName;
    _bio.text = user.bio;
    _email.text = user.email ?? '';
    _phone.text = user.phoneNumber ?? '';
    _gender = user.gender;
    _language = user.language;
    _status = user.status == 'suspended' ? 'suspended' : 'active';
    _emailVerified = user.emailVerified;
    _emailPublic = user.emailPublic;
    _phonePublic = user.phoneNumberPublic;
    _defaultAvatarKey = user.defaultAvatarKey;
    _pendingAvatarAssetId = null;
    _pendingAvatarUrl = null;
    _usingPreset = user.avatarUrl == null || user.avatarUrl!.trim().isEmpty;
  }

  Future<void> _saveUser() async {
    if (_saving || _user == null) return;
    final usernameError = loginUsernameValidationError(_username.text);
    if (usernameError != null) {
      showFloatingErrorNotice(context, usernameError);
      return;
    }
    final emailError = registerEmailValidationError(_email.text);
    if (emailError != null) {
      showFloatingErrorNotice(context, emailError);
      return;
    }
    if (_displayName.text.trim().isEmpty) {
      showFloatingErrorNotice(context, '用户名不能为空');
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await widget.api.updateForcedUserSettings(
        userId: widget.initialUser.id,
        username: _username.text.trim(),
        email: _email.text.trim(),
        emailVerified: _emailVerified,
        emailPublic: _emailPublic,
        phoneNumber: _phone.text.trim(),
        phoneNumberPublic: _phonePublic,
        displayName: _displayName.text.trim(),
        bio: _bio.text.trim(),
        gender: _gender,
        avatarAssetId: _pendingAvatarAssetId,
        defaultAvatarKey: _defaultAvatarKey,
        language: _language,
        status: _status,
      );
      if (!mounted) return;
      setState(() {
        _applyUser(updated);
        _saving = false;
      });
      widget.onSaved(updated);
      showFloatingSuccessNotice(context, '用户云端设置已保存');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFloatingErrorNotice(
        context,
        userFacingErrorMessage(error, fallback: '保存用户设置失败'),
      );
    }
  }

  Future<void> _saveAudio() async {
    final audio = _audio;
    if (_savingAudio || audio == null) return;
    setState(() => _savingAudio = true);
    try {
      final updated = await widget.api.updateForcedUserAudioSettings(
        userId: widget.initialUser.id,
        settings: audio,
      );
      if (!mounted) return;
      setState(() {
        _audio = updated;
        _savingAudio = false;
      });
      showFloatingSuccessNotice(context, '云端音量设置已保存');
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingAudio = false);
      showFloatingErrorNotice(
        context,
        userFacingErrorMessage(error, fallback: '保存云端音量失败'),
      );
    }
  }

  Future<void> _resetPassword() async {
    if (_resettingPassword || _user?.isSuperuser == true) return;
    final password = _newPassword.text;
    if (password.length < 8 || password.length > 256) {
      showFloatingErrorNotice(context, '新密码长度应为 8 到 256 个字符');
      return;
    }
    if (password != _confirmPassword.text) {
      showFloatingErrorNotice(context, '两次输入的密码不一致');
      return;
    }
    setState(() => _resettingPassword = true);
    try {
      await widget.api.forceResetUserPassword(
        userId: widget.initialUser.id,
        newPassword: password,
      );
      if (!mounted) return;
      _newPassword.clear();
      _confirmPassword.clear();
      setState(() => _resettingPassword = false);
      showFloatingSuccessNotice(context, '密码已重置，该用户的登录会话已失效');
    } catch (error) {
      if (!mounted) return;
      setState(() => _resettingPassword = false);
      showFloatingErrorNotice(
        context,
        userFacingErrorMessage(error, fallback: '重置密码失败'),
      );
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    final file = await widget.fileSelectionService.openFile(
      acceptedTypeGroups: const [
        FileTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp']),
      ],
    );
    if (file == null || !mounted) return;
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        showFloatingErrorNotice(context, '头像图片不能为空');
        return;
      }
      final cropped = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AvatarCropDialog(bytes: bytes),
      );
      if (cropped == null || !mounted) return;
      setState(() => _uploadingAvatar = true);
      final asset = await widget.api.uploadImageAsset(
        bytes: cropped,
        filename: account_display.avatarUploadFilename(file.name),
        purpose: 'avatar',
      );
      if (!mounted) return;
      setState(() {
        _pendingAvatarAssetId = asset.id;
        _pendingAvatarUrl = asset.url;
        _usingPreset = false;
        _uploadingAvatar = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
      showFloatingErrorNotice(
        context,
        userFacingErrorMessage(error, fallback: '上传头像失败'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return SettingsScaffold(
      icon: Icons.manage_accounts_outlined,
      title: user == null ? '用户设置' : '${user.displayName} 的用户设置',
      onBack: widget.onClose,
      pinned: NavigationTabs<_SuperuserSettingsSection>(
        expanded: true,
        value: _section,
        onChanged: (value) => setState(() => _section = value),
        items: const [
          NavigationItem(
            value: _SuperuserSettingsSection.profile,
            label: '用户资料',
            icon: Icons.person_outline,
          ),
          NavigationItem(
            value: _SuperuserSettingsSection.account,
            label: '账号设置',
            icon: Icons.badge_outlined,
          ),
          NavigationItem(
            value: _SuperuserSettingsSection.audio,
            label: '云端音量',
            icon: Icons.volume_up_outlined,
          ),
          NavigationItem(
            value: _SuperuserSettingsSection.security,
            label: '安全',
            icon: Icons.security_outlined,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: UiColors.accent),
            )
          : user == null
          ? const Center(child: Text('无法读取用户设置', style: UiTypography.body))
          : _buildSection(user),
    );
  }

  Widget _buildSection(CurrentUser user) {
    return switch (_section) {
      _SuperuserSettingsSection.profile => _buildProfile(user),
      _SuperuserSettingsSection.account => _buildAccount(user),
      _SuperuserSettingsSection.audio => _buildAudio(),
      _SuperuserSettingsSection.security => _buildSecurity(user),
    };
  }

  Widget _buildProfile(CurrentUser user) {
    final imageUrl = _usingPreset
        ? null
        : AppConfigScope.of(
            context,
          ).resolveAssetUrl(_pendingAvatarUrl ?? user.avatarUrl);
    return SettingsList(
      children: [
        SettingsCard(
          title: '默认资料',
          children: [
            _SuperuserSettingsField(
              label: '用户名',
              controller: _displayName,
              hintText: '显示名称',
            ),
            _SuperuserSegmentedField(
              label: '性别',
              value: _gender,
              segments: const [
                Segment(value: 'male', label: '男'),
                Segment(value: 'female', label: '女'),
                Segment(value: 'secret', label: '保密'),
              ],
              onChanged: (value) => setState(() => _gender = value),
            ),
            AvatarPicker(
              label: '头像',
              displayName: _displayName.text,
              imageUrl: imageUrl,
              defaultAvatarKey: _defaultAvatarKey,
              usingPreset: _usingPreset,
              uploading: _uploadingAvatar,
              enabled: !_saving,
              onUpload: _pickAvatar,
              onPresetSelected: (key) => setState(() {
                _defaultAvatarKey = key;
                _pendingAvatarAssetId = '';
                _pendingAvatarUrl = null;
                _usingPreset = true;
              }),
              uploadLabel: '上传头像',
            ),
            _SuperuserSettingsField(
              label: '签名',
              controller: _bio,
              hintText: '个人签名',
              minLines: 3,
              maxLines: 4,
              height: 92,
            ),
          ],
        ),
        _saveButton(),
      ],
    );
  }

  Widget _buildAccount(CurrentUser user) {
    return SettingsList(
      children: [
        SettingsCard(
          title: '账号标识',
          children: [
            _SuperuserReadOnlyLine(label: 'UID', value: user.uid),
            _SuperuserSettingsField(
              label: '登录用户名',
              controller: _username,
              hintText: 'Username',
            ),
          ],
        ),
        SettingsCard(
          title: '绑定信息',
          children: [
            _SuperuserSettingsField(
              label: '邮箱',
              controller: _email,
              hintText: '邮箱地址',
              keyboardType: TextInputType.emailAddress,
            ),
            _SuperuserToggleLine(
              label: '邮箱已验证',
              value: _emailVerified,
              onChanged: (value) => setState(() => _emailVerified = value),
            ),
            _SuperuserToggleLine(
              label: '公开邮箱',
              value: _emailPublic,
              onChanged: (value) => setState(() => _emailPublic = value),
            ),
            _SuperuserSettingsField(
              label: '手机号',
              controller: _phone,
              hintText: '留空表示未绑定',
              keyboardType: TextInputType.phone,
            ),
            _SuperuserToggleLine(
              label: '公开手机号',
              value: _phonePublic,
              onChanged: (value) => setState(() => _phonePublic = value),
            ),
          ],
        ),
        SettingsCard(
          title: '偏好与状态',
          children: [
            _SuperuserSegmentedField(
              label: '语言',
              value: _language,
              segments: const [
                Segment(value: 'zh-Hans', label: '简体中文'),
                Segment(value: 'zh-Hant', label: '繁體中文'),
                Segment(value: 'en', label: 'English'),
              ],
              onChanged: (value) => setState(() => _language = value),
            ),
            _SuperuserSegmentedField(
              label: '账号状态',
              value: _status,
              segments: const [
                Segment(value: 'active', label: '正常'),
                Segment(value: 'suspended', label: '停用'),
              ],
              onChanged: user.isSuperuser
                  ? null
                  : (value) => setState(() => _status = value),
            ),
          ],
        ),
        _saveButton(),
      ],
    );
  }

  Widget _buildAudio() {
    final audio = _audio;
    if (audio == null) {
      return const Center(child: Text('无法读取云端音量设置'));
    }
    return SettingsList(
      children: [
        SettingsCard(
          title: '默认音量',
          children: [
            _audioSlider(
              '默认输入音量',
              audio.defaultAudioInputVolume,
              (value) => _replaceAudio(defaultInput: value),
            ),
            _audioSlider(
              '默认输出音量',
              audio.defaultAudioOutputVolume,
              (value) => _replaceAudio(defaultOutput: value),
            ),
          ],
        ),
        SettingsCard(
          title: '语音频道音量',
          children: [
            _audioSlider(
              '麦克风输入音量',
              audio.liveMicInputVolume,
              (value) => _replaceAudio(liveMic: value),
            ),
            _audioSlider(
              '用户语音输出音量',
              audio.liveVoiceOutputVolume,
              (value) => _replaceAudio(liveVoice: value),
            ),
            _audioSlider(
              '屏幕共享输出音量',
              audio.liveScreenShareOutputVolume,
              (value) => _replaceAudio(screenShare: value),
            ),
            _audioSlider(
              '音乐盒输出音量',
              audio.liveMusicOutputVolume,
              (value) => _replaceAudio(music: value),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Button(
            key: const ValueKey('save-superuser-audio-settings'),
            onPressed: _savingAudio ? null : _saveAudio,
            loading: _savingAudio,
            tone: ButtonTone.primary,
            icon: const Icon(Icons.save_outlined),
            child: const Text('保存云端音量'),
          ),
        ),
      ],
    );
  }

  Widget _buildSecurity(CurrentUser user) {
    final passwordAllowed = !user.isSuperuser;
    return SettingsList(
      children: [
        SettingsCard(
          title: '重置密码',
          children: [
            const Text(
              '超级用户代为修改时不需要原密码。密码更新后，该用户已登录的设备会自动失效。',
              style: TextStyle(color: UiColors.textMuted, height: 1.45),
            ),
            _SuperuserSettingsField(
              label: '新密码',
              controller: _newPassword,
              hintText: '8 到 256 个字符',
              obscureText: !_showNewPassword,
              enabled: passwordAllowed,
              suffix: ButtonIcon(
                tooltip: _showNewPassword ? '隐藏密码' : '显示密码',
                size: 28,
                onPressed: passwordAllowed
                    ? () => setState(() => _showNewPassword = !_showNewPassword)
                    : null,
                icon: Icon(
                  _showNewPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16,
                ),
              ),
            ),
            _SuperuserSettingsField(
              label: '确认新密码',
              controller: _confirmPassword,
              hintText: '再次输入新密码',
              obscureText: !_showConfirmPassword,
              enabled: passwordAllowed,
              suffix: ButtonIcon(
                tooltip: _showConfirmPassword ? '隐藏密码' : '显示密码',
                size: 28,
                onPressed: passwordAllowed
                    ? () => setState(
                        () => _showConfirmPassword = !_showConfirmPassword,
                      )
                    : null,
                icon: Icon(
                  _showConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Button(
                    tooltip: '超级用户编辑其他账号时不使用忘记密码流程',
                    onPressed: null,
                    icon: const Icon(Icons.help_outline),
                    child: const Text('忘记密码（已禁用）'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Button(
                    key: const ValueKey('force-reset-user-password'),
                    onPressed: passwordAllowed && !_resettingPassword
                        ? _resetPassword
                        : null,
                    loading: _resettingPassword,
                    tone: ButtonTone.primary,
                    icon: const Icon(Icons.lock_reset),
                    child: const Text('更新密码'),
                  ),
                ),
              ],
            ),
            if (!passwordAllowed)
              const Text(
                '不能在其他用户设置中重置超级用户密码',
                style: TextStyle(color: UiColors.textMuted),
              ),
          ],
        ),
      ],
    );
  }

  Widget _saveButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: Button(
        key: const ValueKey('save-superuser-user-settings'),
        onPressed: _saving ? null : _saveUser,
        loading: _saving,
        tone: ButtonTone.primary,
        icon: const Icon(Icons.save_outlined),
        child: const Text('保存用户设置'),
      ),
    );
  }

  Widget _audioSlider(String label, int value, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: UiTypography.body)),
            Text('$value%', style: UiTypography.label),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 24,
          child: UiSlider(
            min: 0,
            max: 100,
            value: value.toDouble(),
            onChanged: (next) => onChanged(next.round()),
          ),
        ),
      ],
    );
  }

  void _replaceAudio({
    int? defaultInput,
    int? defaultOutput,
    int? liveMic,
    int? liveVoice,
    int? screenShare,
    int? music,
  }) {
    final audio = _audio;
    if (audio == null) return;
    setState(() {
      _audio = UserAudioSettings(
        defaultAudioInputVolume: defaultInput ?? audio.defaultAudioInputVolume,
        defaultAudioOutputVolume:
            defaultOutput ?? audio.defaultAudioOutputVolume,
        liveMicInputVolume: liveMic ?? audio.liveMicInputVolume,
        liveVoiceOutputVolume: liveVoice ?? audio.liveVoiceOutputVolume,
        liveScreenShareOutputVolume:
            screenShare ?? audio.liveScreenShareOutputVolume,
        liveMusicOutputVolume: music ?? audio.liveMusicOutputVolume,
        updatedAt: audio.updatedAt,
      );
    });
  }
}

class _SuperuserSettingsField extends StatelessWidget {
  const _SuperuserSettingsField({
    required this.label,
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.suffix,
    this.minLines = 1,
    this.maxLines = 1,
    this.height = Input.defaultHeight,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final Widget? suffix;
  final int minLines;
  final int maxLines;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: UiTypography.label.copyWith(color: UiColors.textMuted),
        ),
        const SizedBox(height: 8),
        Input(
          controller: controller,
          hintText: hintText,
          keyboardType: keyboardType,
          obscureText: obscureText,
          enabled: enabled,
          suffix: suffix,
          minLines: minLines,
          maxLines: maxLines,
          height: height,
        ),
      ],
    );
  }
}

class _SuperuserToggleLine extends StatelessWidget {
  const _SuperuserToggleLine({
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
        Expanded(child: Text(label, style: UiTypography.body)),
        UiSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _SuperuserSegmentedField extends StatelessWidget {
  const _SuperuserSegmentedField({
    required this.label,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<Segment<String>> segments;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: UiTypography.label.copyWith(color: UiColors.textMuted),
        ),
        const SizedBox(height: 8),
        IgnorePointer(
          ignoring: onChanged == null,
          child: Opacity(
            opacity: onChanged == null ? 0.55 : 1,
            child: SegmentedControl<String>(
              expanded: true,
              value: value,
              onChanged: onChanged ?? (_) {},
              segments: segments,
            ),
          ),
        ),
      ],
    );
  }
}

class _SuperuserReadOnlyLine extends StatelessWidget {
  const _SuperuserReadOnlyLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: UiTypography.label.copyWith(color: UiColors.textMuted),
          ),
        ),
        SelectableText(value, style: UiTypography.body),
      ],
    );
  }
}
