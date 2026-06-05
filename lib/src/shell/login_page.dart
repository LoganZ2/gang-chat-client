import 'dart:async';

import 'package:flutter/material.dart';

import '../app/auth_form.dart';
import '../app/auth_session_controller.dart';
import '../auth/auth_client.dart';
import '../ui/ui.dart';

typedef AuthWindowLock =
    Future<void> Function({
      bool registering,
      bool moveWindow,
      bool centerWindow,
    });

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onSubmit,
    required this.sizeForMode,
    required this.consumeInitialWindowLock,
    required this.lockAuthWindow,
  });

  final Future<void> Function(AuthRequest request) onSubmit;
  final Size Function(bool registering) sizeForMode;
  final bool Function() consumeInitialWindowLock;
  final AuthWindowLock lockAuthWindow;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.consumeInitialWindowLock()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.lockAuthWindow(moveWindow: false));
    });
  }

  Future<void> _submit() async {
    if (_busy) return;

    final result = authRequestFromForm(
      registering: _registering,
      username: _username.text,
      login: _email.text,
      password: _password.text,
      confirmPassword: _confirmPassword.text,
    );
    final request = result.request;
    if (request == null) {
      setState(() => _error = result.error);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.onSubmit(request);
      if (!mounted) return;
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Cannot reach the server: $e';
      });
      return;
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _setMode(bool registering) {
    if (_busy || _registering == registering) return;
    if (registering) {
      unawaited(_expandAndShowRegister());
      return;
    }
    setState(() {
      _registering = false;
      _error = null;
    });
    unawaited(widget.lockAuthWindow());
  }

  Future<void> _expandAndShowRegister() async {
    await widget.lockAuthWindow(registering: true);
    if (!mounted || _busy) return;
    setState(() {
      _registering = true;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.sizeForMode(_registering);
    return Scaffold(
      backgroundColor: const Color(0xFF14171D),
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF181C24)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, bottom: 4),
                      child: Text(
                        'Gang Chat',
                        style: TextStyle(
                          color: Color(0xFFECEFF1),
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 17),
                    _AuthModeSwitch(
                      registering: _registering,
                      enabled: !_busy,
                      onLogin: () => _setMode(false),
                      onRegister: () => _setMode(true),
                    ),
                    const SizedBox(height: 12),
                    if (_registering) ...[
                      _LoginLineField(
                        icon: Icons.person_outline,
                        controller: _username,
                        enabled: !_busy,
                        hintText: 'Username',
                        autofillHints: const [AutofillHints.username],
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _LoginLineField(
                      icon: _registering
                          ? Icons.alternate_email
                          : Icons.person_outline,
                      controller: _email,
                      enabled: !_busy,
                      hintText: _registering
                          ? 'Email address'
                          : 'Username or email address',
                      autofillHints: _registering
                          ? const [AutofillHints.email]
                          : const [AutofillHints.username, AutofillHints.email],
                      keyboardType: _registering
                          ? TextInputType.emailAddress
                          : TextInputType.text,
                    ),
                    const SizedBox(height: 8),
                    _LoginLineField(
                      icon: Icons.lock_outline,
                      controller: _password,
                      enabled: !_busy,
                      hintText: 'Password',
                      autofillHints: [
                        _registering
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      obscureText: _obscurePassword,
                      trailing: _PasswordVisibilityToggle(
                        obscure: _obscurePassword,
                        enabled: !_busy,
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                      onSubmitted: _registering ? null : (_) => _submit(),
                    ),
                    if (_registering) ...[
                      const SizedBox(height: 8),
                      _LoginLineField(
                        icon: Icons.lock_outline,
                        controller: _confirmPassword,
                        enabled: !_busy,
                        hintText: 'Confirm password',
                        autofillHints: const [AutofillHints.newPassword],
                        obscureText: _obscureConfirmPassword,
                        trailing: _PasswordVisibilityToggle(
                          obscure: _obscureConfirmPassword,
                          enabled: !_busy,
                          onPressed: () {
                            setState(
                              () => _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                            );
                          },
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 38,
                      child: Stack(
                        children: [
                          if (_error != null)
                            Positioned.fill(
                              right: 130,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _error!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFE58383),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              height: 38,
                              child: OverflowBox(
                                alignment: Alignment.topRight,
                                minHeight: 46,
                                maxHeight: 46,
                                child: Button(
                                  onPressed: _submit,
                                  loading: _busy,
                                  height: 38,
                                  tone: ButtonTone.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: _busy
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Color(0xFF6FCFA6),
                                          ),
                                        )
                                      : Text(
                                          _registering
                                              ? 'Create account'
                                              : 'Login',
                                        ),
                                ),
                              ),
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
    );
  }
}

class _AuthModeSwitch extends StatelessWidget {
  const _AuthModeSwitch({
    required this.registering,
    required this.enabled,
    required this.onLogin,
    required this.onRegister,
  });

  final bool registering;
  final bool enabled;
  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          _AuthModeTab(
            label: 'Login',
            active: !registering,
            enabled: enabled,
            onTap: onLogin,
          ),
          const SizedBox(width: 18),
          _AuthModeTab(
            label: 'Register',
            active: registering,
            enabled: enabled,
            onTap: onRegister,
          ),
        ],
      ),
    );
  }
}

class _AuthModeTab extends StatelessWidget {
  const _AuthModeTab({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFECEFF1) : const Color(0xFF6F7785);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        height: 22,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? const Color(0xFF6FCFA6) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                height: 1,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginLineField extends StatelessWidget {
  const _LoginLineField({
    required this.icon,
    required this.controller,
    required this.enabled,
    required this.hintText,
    this.autofillHints,
    this.keyboardType,
    this.obscureText = false,
    this.trailing,
    this.onSubmitted,
  });

  final IconData icon;
  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final Iterable<String>? autofillHints;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 36,
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, 1.5),
                child: Icon(icon, color: Color(0xFF6F7785), size: 16),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              autofillHints: autofillHints,
              keyboardType: keyboardType,
              obscureText: obscureText,
              onSubmitted: onSubmitted,
              cursorColor: const Color(0xFFB0B8C0),
              style: const TextStyle(
                color: Color(0xFFECEFF1),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF6F7785),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          ?trailing,
        ],
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
    final color = enabled ? const Color(0xFFB0B8C0) : const Color(0xFF6F7785);
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
            width: 30,
            height: 36,
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
