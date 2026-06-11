import 'dart:async';

import 'package:flutter/material.dart';

import '../app/auth_form.dart';
import '../app/auth_session_controller.dart';
import '../ui/ui.dart';

typedef AuthWindowLock =
    Future<void> Function({
      bool registering,
      bool moveWindow,
      bool centerWindow,
      Size? size,
    });
typedef AuthSizeForMode = Size Function(bool registering, {bool showingError});

enum _AuthMode { login, register }

const double _authWindowButtonInset = 36;
const double _authTitleBarTopInset = 6;
const double _authTitleBarHeight = 16;
const double _authTitleBarGap =
    _authWindowButtonInset - _authTitleBarTopInset - _authTitleBarHeight;
const double _authFieldGap = 3;
const double _authModeGap = 10;
const double _authActionGap = 8;
const double _authErrorHeight = 16;
const double _authErrorGap = 4;
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
  });

  final AuthSizeForMode sizeForMode;
  final Future<void> Function(AuthRequest request) onSubmit;
  final bool Function() consumeInitialWindowLock;
  final AuthWindowLock lockAuthWindow;

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

  bool get _showingError =>
      _submitState.error != null && _submitState.error!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.consumeInitialWindowLock()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_lockAuthSize(registering: false, moveWindow: false));
      }
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _login.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitState.busy) return;

    final result = authRequestFromForm(
      registering: _registering,
      username: _username.text,
      login: _login.text,
      password: _password.text,
      confirmPassword: _confirmPassword.text,
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
      await widget.onSubmit(request);
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      await _showSubmitState(authSubmitFailed(e));
    }
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
    });
    unawaited(_lockAuthSize(registering: false));
  }

  Future<void> _expandAndShowRegister() async {
    await _lockAuthSize(registering: true);
    if (!mounted || _submitState.busy) return;
    setState(() {
      _registering = true;
      _submitState = const AuthSubmitState();
    });
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                24,
                _authTitleBarTopInset,
                24,
                7,
              ),
              child: AutofillGroup(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            MouseRegion(
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
                            ),
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
                                autofillHints: const [AutofillHints.username],
                                maxLines: 1,
                                onSubmitted: (_) => _submit(),
                              ),
                              const SizedBox(height: _authFieldGap),
                            ],
                            Input(
                              controller: _login,
                              enabled: !_submitState.busy,
                              hintText: _registering ? '邮箱地址' : '用户名或邮箱地址',
                              prefixIcon: _registering
                                  ? Icons.alternate_email
                                  : Icons.person_outline,
                              autofillHints: _registering
                                  ? const [AutofillHints.email]
                                  : const [
                                      AutofillHints.username,
                                      AutofillHints.email,
                                    ],
                              keyboardType: _registering
                                  ? TextInputType.emailAddress
                                  : TextInputType.text,
                              maxLines: 1,
                              onSubmitted: _registering
                                  ? null
                                  : (_) => _submit(),
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
                                    () => _obscurePassword = !_obscurePassword,
                                  );
                                },
                              ),
                              maxLines: 1,
                              onSubmitted: _registering
                                  ? null
                                  : (_) => _submit(),
                            ),
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
                    );
                  },
                ),
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
