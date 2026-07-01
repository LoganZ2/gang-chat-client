import 'dart:async';

import 'package:flutter/material.dart';

import '../app/auth_form.dart';
import '../app/auth_session_controller.dart';
import '../app/language_preference.dart';
import '../app/login_account_history.dart';
import '../ui/ui.dart';
import 'desktop_window_controller.dart';
import 'window_controls.dart';

typedef AuthWindowLock =
    Future<void> Function({
      bool registering,
      bool moveWindow,
      bool centerWindow,
      Size? size,
    });
typedef AuthSizeForMode = Size Function(bool registering, {bool showingError});
typedef AuthSubmit =
    Future<void> Function(
      AuthRequest request, {
      required bool rememberPassword,
    });

enum _AuthMode { login, register }

const double _authWindowButtonInset = 36;
const double _authTitleBarTopInset = 6;
const double _authTitleBarHeight = 16;
const double _authTitleBarGap =
    _authWindowButtonInset - _authTitleBarTopInset - _authTitleBarHeight;
const double _authFieldGap = 3;
const double _authModeGap = 10;
const double _authActionGap = 14;
const double _authErrorHeight = 16;
const double _authErrorGap = 4;
const double _authRememberGap = 10;
const double _authRememberHeight = 28;
const double _accountHistoryItemHeight = 38;
const double _authSegmentedControlOuterHeight = 42;
const double _authInputOuterHeight = Input.defaultHeight + 8;
const double _accountHistoryDropdownTop =
    _authTitleBarHeight +
    _authTitleBarGap +
    _authSegmentedControlOuterHeight +
    _authModeGap +
    _authInputOuterHeight +
    _authFieldGap;
const _authTitleBarStyle = TextStyle(
  color: UiColors.textSecondary,
  fontSize: 12,
  fontWeight: FontWeight.w600,
  letterSpacing: 0,
);

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.sizeForMode,
    required this.onSubmit,
    required this.consumeInitialWindowLock,
    required this.lockAuthWindow,
    this.language = defaultLanguagePreference,
    this.accountHistoryStore = const NoopLoginAccountHistoryStore(),
    this.windowController,
  });

  final AuthSizeForMode sizeForMode;
  final AuthSubmit onSubmit;
  final bool Function() consumeInitialWindowLock;
  final AuthWindowLock lockAuthWindow;
  final String language;
  final LoginAccountHistoryStore accountHistoryStore;
  final DesktopWindowController? windowController;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _registering = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  AuthSubmitState _submitState = const AuthSubmitState();
  List<LoginAccountRecord> _accountHistory = const [];
  bool _showAccountHistory = false;
  bool _rememberPassword = false;
  String? _selectedHistoryLogin;
  final Object _accountHistoryTapRegion = Object();

  bool get _showingError =>
      _submitState.error != null && _submitState.error!.isNotEmpty;
  bool get _canShowAccountHistory =>
      !_registering && !_submitState.busy && _accountHistory.isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAccountHistory());
    if (widget.consumeInitialWindowLock()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_lockAuthSize(registering: false, moveWindow: false));
      }
    });
  }

  @override
  void didUpdateWidget(LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountHistoryStore != widget.accountHistoryStore) {
      unawaited(_loadAccountHistory());
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _login.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _loadAccountHistory() async {
    try {
      final records = await widget.accountHistoryStore.read();
      if (!mounted) return;
      final lastLogin = lastLoginAccountRecord(records);
      setState(() {
        _accountHistory = records;
        if (records.isEmpty) _showAccountHistory = false;
        if (!_registering &&
            _login.text.isEmpty &&
            _password.text.isEmpty &&
            lastLogin != null) {
          _setText(_login, lastLogin.login);
          _selectedHistoryLogin = lastLogin.login;
          if (lastLogin.remembersPassword) {
            _setText(_password, lastLogin.password!);
            _rememberPassword = true;
          } else {
            _password.clear();
            _rememberPassword = false;
          }
        }
      });
    } catch (_) {
      // Local history is a convenience feature; the auth form stays usable.
    }
  }

  Future<void> _submit() async {
    if (_submitState.busy) return;

    final result = authRequestFromForm(
      registering: _registering,
      username: _username.text,
      login: _login.text,
      password: _password.text,
      confirmPassword: _confirmPassword.text,
      language: widget.language,
    );
    final request = result.request;
    if (request == null) {
      await _showSubmitState(authSubmitInvalid(result.error));
      return;
    }

    if (_showingError) {
      await _lockAuthSize(showingError: false);
      if (!mounted) return;
    }
    setState(() => _submitState = authSubmitStarted());

    try {
      await widget.onSubmit(
        request,
        rememberPassword: !_registering && _rememberPassword,
      );
      if (!mounted) return;
      if (!request.registering) {
        await _rememberSubmittedAccount(request);
      }
    } catch (e) {
      if (!mounted) return;
      await _showSubmitState(authSubmitFailed(e, language: widget.language));
    }
  }

  Future<void> _rememberSubmittedAccount(AuthRequest request) async {
    final updated = rememberLoginAccount(
      records: _accountHistory,
      login: request.login,
      password: request.password,
      rememberPassword: _rememberPassword,
    );
    setState(() {
      _accountHistory = updated;
      _showAccountHistory = false;
    });
    try {
      await widget.accountHistoryStore.write(updated);
    } catch (_) {
      // The login already succeeded; failing to persist history is non-fatal.
    }
  }

  void _minimizeWindow() {
    final windowController = widget.windowController;
    if (windowController == null) return;
    unawaited(windowController.minimizeWindow());
  }

  void _closeWindow() {
    final windowController = widget.windowController;
    if (windowController == null) return;
    unawaited(windowController.closeWindow());
  }

  void _setMode(bool registering) {
    if (_submitState.busy || _registering == registering) return;
    if (registering) {
      unawaited(_expandAndShowRegister());
      return;
    }
    setState(() {
      _registering = false;
      _submitState = const AuthSubmitState();
      _showAccountHistory = false;
    });
    unawaited(_lockAuthSize(registering: false));
  }

  Future<void> _expandAndShowRegister() async {
    await _lockAuthSize(registering: true);
    if (!mounted || _submitState.busy) return;
    setState(() {
      _registering = true;
      _submitState = const AuthSubmitState();
      _showAccountHistory = false;
    });
  }

  void _toggleAccountHistory() {
    if (!_canShowAccountHistory) return;
    setState(() => _showAccountHistory = !_showAccountHistory);
  }

  void _closeAccountHistory() {
    if (!_showAccountHistory) return;
    setState(() => _showAccountHistory = false);
  }

  void _clearLoginInput() {
    if (_submitState.busy) return;
    _login.clear();
    _password.clear();
    setState(() {
      _selectedHistoryLogin = null;
      _rememberPassword = false;
      _showAccountHistory = false;
      _submitState = const AuthSubmitState();
    });
  }

  void _selectAccountRecord(LoginAccountRecord record) {
    _setText(_login, record.login);
    if (record.remembersPassword) {
      _setText(_password, record.password!);
    } else {
      _password.clear();
    }
    setState(() {
      _selectedHistoryLogin = record.login;
      _rememberPassword = record.remembersPassword;
      _showAccountHistory = false;
      _submitState = const AuthSubmitState();
    });
  }

  void _deleteAccountRecord(LoginAccountRecord record) {
    final updated = deleteLoginAccountRecord(
      records: _accountHistory,
      login: record.login,
    );
    setState(() {
      _accountHistory = updated;
      if (updated.isEmpty) _showAccountHistory = false;
      if (_selectedHistoryLogin != null &&
          loginAccountsMatch(_selectedHistoryLogin!, record.login)) {
        _selectedHistoryLogin = null;
      }
    });
    unawaited(_writeAccountHistory(updated));
  }

  Future<void> _writeAccountHistory(List<LoginAccountRecord> records) async {
    try {
      await widget.accountHistoryStore.write(records);
    } catch (_) {
      // The in-memory UI can still continue if the convenience store fails.
    }
  }

  void _handleLoginChanged(String value) {
    final selected = _selectedHistoryLogin;
    if (selected == null || loginAccountsMatch(selected, value)) return;
    setState(() {
      _selectedHistoryLogin = null;
      if (_rememberPassword) _rememberPassword = false;
    });
  }

  void _setRememberPassword(bool rememberPassword) {
    if (_submitState.busy) return;
    setState(() => _rememberPassword = rememberPassword);
  }

  void _setText(TextEditingController controller, String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _showSubmitState(AuthSubmitState state) async {
    final showingError = state.error != null && state.error!.isNotEmpty;
    if (showingError) {
      await _lockAuthSize(showingError: true);
      if (!mounted) return;
    }
    setState(() => _submitState = state);
  }

  Future<void> _lockAuthSize({
    bool? registering,
    bool showingError = false,
    bool moveWindow = true,
    bool centerWindow = false,
  }) {
    final resolvedRegistering = registering ?? _registering;
    return widget.lockAuthWindow(
      registering: resolvedRegistering,
      moveWindow: moveWindow,
      centerWindow: centerWindow,
      size: widget.sizeForMode(resolvedRegistering, showingError: showingError),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.sizeForMode(_registering, showingError: _showingError);
    final showWindowControls =
        widget.windowController != null &&
        Theme.of(context).platform == TargetPlatform.windows;
    return Scaffold(
      backgroundColor: UiColors.background,
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          key: const ValueKey('auth-surface'),
          width: size.width,
          height: size.height,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: UiColors.surfaceLow),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    24,
                    _authTitleBarTopInset,
                    24,
                    7,
                  ),
                  child: AutofillGroup(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildTitleBar(),
                                    const SizedBox(height: _authTitleBarGap),
                                    SegmentedControl<_AuthMode>(
                                      expanded: true,
                                      value: _registering
                                          ? _AuthMode.register
                                          : _AuthMode.login,
                                      segments: const [
                                        Segment(
                                          value: _AuthMode.login,
                                          label: '登录',
                                          icon: Icons.login_outlined,
                                        ),
                                        Segment(
                                          value: _AuthMode.register,
                                          label: '注册',
                                          icon: Icons.person_add_alt_1_outlined,
                                        ),
                                      ],
                                      onChanged: (mode) {
                                        if (_submitState.busy) return;
                                        _setMode(mode == _AuthMode.register);
                                      },
                                    ),
                                    const SizedBox(height: _authModeGap),
                                    if (_registering) ...[
                                      Input(
                                        controller: _username,
                                        enabled: !_submitState.busy,
                                        hintText: '用户名',
                                        prefixIcon: Icons.person_outline,
                                        autofillHints: const [
                                          AutofillHints.username,
                                        ],
                                        maxLines: 1,
                                        onSubmitted: (_) => _submit(),
                                      ),
                                      const SizedBox(height: _authFieldGap),
                                    ],
                                    TapRegion(
                                      groupId: _accountHistoryTapRegion,
                                      onTapOutside: (_) =>
                                          _closeAccountHistory(),
                                      child: _buildLoginInput(),
                                    ),
                                    const SizedBox(height: _authFieldGap),
                                    Input(
                                      controller: _password,
                                      enabled: !_submitState.busy,
                                      hintText: '密码',
                                      prefixIcon: Icons.lock_outline,
                                      autofillHints: [
                                        _registering
                                            ? AutofillHints.newPassword
                                            : AutofillHints.password,
                                      ],
                                      obscureText: _obscurePassword,
                                      suffix: _PasswordVisibilityToggle(
                                        obscure: _obscurePassword,
                                        enabled: !_submitState.busy,
                                        onPressed: () {
                                          setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          );
                                        },
                                      ),
                                      maxLines: 1,
                                      onSubmitted: _registering
                                          ? null
                                          : (_) => _submit(),
                                    ),
                                    if (!_registering) ...[
                                      const SizedBox(height: _authRememberGap),
                                      _RememberPasswordRow(
                                        value: _rememberPassword,
                                        enabled: !_submitState.busy,
                                        onChanged: _setRememberPassword,
                                      ),
                                    ],
                                    if (_registering) ...[
                                      const SizedBox(height: _authFieldGap),
                                      Input(
                                        controller: _confirmPassword,
                                        enabled: !_submitState.busy,
                                        hintText: '确认密码',
                                        prefixIcon: Icons.lock_outline,
                                        autofillHints: const [
                                          AutofillHints.newPassword,
                                        ],
                                        obscureText: _obscureConfirmPassword,
                                        suffix: _PasswordVisibilityToggle(
                                          obscure: _obscureConfirmPassword,
                                          enabled: !_submitState.busy,
                                          onPressed: () {
                                            setState(
                                              () => _obscureConfirmPassword =
                                                  !_obscureConfirmPassword,
                                            );
                                          },
                                        ),
                                        maxLines: 1,
                                        onSubmitted: (_) => _submit(),
                                      ),
                                    ],
                                    const SizedBox(height: _authActionGap),
                                    if (_showingError) ...[
                                      SizedBox(
                                        height: _authErrorHeight,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            _submitState.error!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: UiColors.danger,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: _authErrorGap),
                                    ],
                                    Button(
                                      width: double.infinity,
                                      tone: ButtonTone.primary,
                                      height: 32,
                                      loading: _submitState.busy,
                                      onPressed: _submit,
                                      child: Text(_registering ? '创建账号' : '登录'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_showAccountHistory && _canShowAccountHistory)
                              Positioned(
                                top: _accountHistoryDropdownTop,
                                left: 0,
                                right: 0,
                                child: TapRegion(
                                  groupId: _accountHistoryTapRegion,
                                  child: _AccountHistoryDropdown(
                                    records: _accountHistory,
                                    onSelected: _selectAccountRecord,
                                    onDeleted: _deleteAccountRecord,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (showWindowControls)
                  Positioned(
                    top: 4,
                    right: 0,
                    child: SelectionContainer.disabled(
                      child: AppWindowControls(
                        onMinimize: _minimizeWindow,
                        onClose: _closeWindow,
                        showMaximize: false,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginInput() {
    return Input(
      controller: _login,
      enabled: !_submitState.busy,
      hintText: _registering ? '邮箱地址' : '用户名或邮箱地址',
      prefixIcon: _registering ? Icons.alternate_email : Icons.person_outline,
      suffix: _canShowAccountHistory
          ? _AccountInputSuffix(
              controller: _login,
              expanded: _showAccountHistory,
              enabled: !_submitState.busy,
              onClear: _clearLoginInput,
              onToggle: _toggleAccountHistory,
            )
          : null,
      autofillHints: _registering
          ? const [AutofillHints.email]
          : const [AutofillHints.username, AutofillHints.email],
      keyboardType: _registering
          ? TextInputType.emailAddress
          : TextInputType.text,
      maxLines: 1,
      onChanged: _registering ? null : _handleLoginChanged,
      onSubmitted: _registering ? null : (_) => _submit(),
    );
  }

  Widget _buildTitleBar() {
    final title = MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: SelectionContainer.disabled(
        child: const SizedBox(
          height: _authTitleBarHeight,
          child: Center(
            child: Text(
              'Gang Chat',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _authTitleBarStyle,
            ),
          ),
        ),
      ),
    );
    final windowController = widget.windowController;
    if (windowController == null) return title;
    return AppWindowDragRegion(
      windowController: windowController,
      child: title,
    );
  }
}

class _RememberPasswordRow extends StatelessWidget {
  const _RememberPasswordRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _authRememberHeight,
      child: Row(
        children: [
          const Text(
            '记住密码',
            style: TextStyle(
              color: UiColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 8),
          UiCheckbox(
            value: value,
            enabled: enabled,
            tooltip: '记住密码',
            onChanged: enabled ? onChanged : null,
          ),
          const Spacer(),
          _AuthTextLink(
            label: '忘记密码？',
            enabled: enabled,
            onPressed: () {
              // Placeholder until the password reset API is wired.
            },
          ),
        ],
      ),
    );
  }
}

class _AuthTextLink extends StatefulWidget {
  const _AuthTextLink({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_AuthTextLink> createState() => _AuthTextLinkState();
}

class _AuthTextLinkState extends State<_AuthTextLink> {
  bool _hovered = false;

  bool get _interactive => widget.enabled;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _handleTap() {
    if (!_interactive) return;
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final color = !_interactive
        ? UiColors.textMuted
        : _hovered
        ? UiColors.controlAccent
        : UiColors.accent;
    return Semantics(
      button: true,
      enabled: _interactive,
      label: widget.label,
      child: MouseRegion(
        cursor: _interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Text(
              widget.label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountInputSuffix extends StatefulWidget {
  const _AccountInputSuffix({
    required this.controller,
    required this.expanded,
    required this.enabled,
    required this.onClear,
    required this.onToggle,
  });

  final TextEditingController controller;
  final bool expanded;
  final bool enabled;
  final VoidCallback onClear;
  final VoidCallback onToggle;

  @override
  State<_AccountInputSuffix> createState() => _AccountInputSuffixState();
}

class _AccountInputSuffixState extends State<_AccountInputSuffix> {
  bool get _canClear =>
      widget.enabled && widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(_AccountInputSuffix oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleTextChanged);
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    super.dispose();
  }

  void _handleTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_canClear)
          _AccountInputClearButton(
            enabled: widget.enabled,
            onPressed: widget.onClear,
          ),
        _AccountHistoryToggle(
          expanded: widget.expanded,
          onPressed: widget.onToggle,
        ),
      ],
    );
  }
}

class _AccountInputClearButton extends StatelessWidget {
  const _AccountInputClearButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '清除账号',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: '清除账号',
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onPressed : null,
            child: SizedBox.square(
              dimension: 24,
              child: Center(
                child: Icon(Icons.close, size: 15, color: UiColors.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountHistoryToggle extends StatelessWidget {
  const _AccountHistoryToggle({
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: expanded ? '收起账号记录' : '展开账号记录',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 24,
            child: Center(
              child: Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 18,
                color: UiColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountHistoryDropdown extends StatefulWidget {
  const _AccountHistoryDropdown({
    required this.records,
    required this.onSelected,
    required this.onDeleted,
  });

  final List<LoginAccountRecord> records;
  final ValueChanged<LoginAccountRecord> onSelected;
  final ValueChanged<LoginAccountRecord> onDeleted;

  @override
  State<_AccountHistoryDropdown> createState() =>
      _AccountHistoryDropdownState();
}

class _AccountHistoryDropdownState extends State<_AccountHistoryDropdown> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rowCount = widget.records.length > 4 ? 4 : widget.records.length;
    final scrollable = widget.records.length > rowCount;
    return Material(
      key: const ValueKey('auth-account-history-dropdown'),
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: UiColors.surface,
          borderRadius: BorderRadius.circular(UiRadii.md),
          border: Border.all(color: UiColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.26),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SizedBox(
          height: rowCount * _accountHistoryItemHeight,
          child: Scrollbar(
            controller: _scrollController,
            interactive: scrollable,
            radius: const Radius.circular(999),
            thickness: scrollable ? 5 : null,
            thumbVisibility: scrollable,
            trackVisibility: false,
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(right: scrollable ? 7 : 0),
              physics: scrollable
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemExtent: _accountHistoryItemHeight,
              itemCount: widget.records.length,
              itemBuilder: (context, index) {
                final record = widget.records[index];
                return _AccountHistoryItem(
                  record: record,
                  onSelected: () => widget.onSelected(record),
                  onDeleted: () => widget.onDeleted(record),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountHistoryItem extends StatefulWidget {
  const _AccountHistoryItem({
    required this.record,
    required this.onSelected,
    required this.onDeleted,
  });

  final LoginAccountRecord record;
  final VoidCallback onSelected;
  final VoidCallback onDeleted;

  @override
  State<_AccountHistoryItem> createState() => _AccountHistoryItemState();
}

class _AccountHistoryItemState extends State<_AccountHistoryItem> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: _accountHistoryItemHeight,
          padding: const EdgeInsets.only(left: 10, right: 6),
          color: _hovered ? UiColors.selected : Colors.transparent,
          child: Row(
            children: [
              Avatar(
                label: widget.record.login,
                imageUrl: AppConfigScope.of(
                  context,
                ).resolveAssetUrl(widget.record.avatarUrl),
                defaultAvatarKey: widget.record.defaultAvatarKey,
                size: 22,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.record.login,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UiColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (widget.record.remembersPassword) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.lock_outline,
                  size: 13,
                  color: UiColors.textMuted,
                ),
              ],
              const SizedBox(width: 6),
              _AccountHistoryDeleteButton(onPressed: widget.onDeleted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountHistoryDeleteButton extends StatefulWidget {
  const _AccountHistoryDeleteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_AccountHistoryDeleteButton> createState() =>
      _AccountHistoryDeleteButtonState();
}

class _AccountHistoryDeleteButtonState
    extends State<_AccountHistoryDeleteButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '删除账号记录',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: SizedBox.square(
            dimension: 26,
            child: Center(
              child: Icon(
                Icons.close,
                size: 15,
                color: _hovered ? UiColors.danger : UiColors.textMuted,
              ),
            ),
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
    final color = enabled ? UiColors.textSecondary : UiColors.textMuted;
    return Tooltip(
      message: obscure ? '显示密码' : '隐藏密码',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: obscure ? '显示密码' : '隐藏密码',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: 24,
            height: 24,
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
