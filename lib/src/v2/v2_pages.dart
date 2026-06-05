import 'dart:async';

import 'package:flutter/material.dart';

import '../app/auth_form.dart';
import '../app/auth_session_controller.dart';
import '../app/authenticated_app_context.dart';
import '../ui/ui.dart';

typedef AuthWindowLock =
    Future<void> Function({
      bool registering,
      bool moveWindow,
      bool centerWindow,
    });

class V2LoginPage extends StatefulWidget {
  const V2LoginPage({
    super.key,
    required this.size,
    required this.onSubmit,
    required this.consumeInitialWindowLock,
    required this.lockAuthWindow,
  });

  final Size size;
  final Future<void> Function(AuthRequest request) onSubmit;
  final bool Function() consumeInitialWindowLock;
  final AuthWindowLock lockAuthWindow;

  @override
  State<V2LoginPage> createState() => _V2LoginPageState();
}

class _V2LoginPageState extends State<V2LoginPage> {
  final _login = TextEditingController();
  final _password = TextEditingController();

  AuthSubmitState _submitState = const AuthSubmitState();

  @override
  void initState() {
    super.initState();
    if (widget.consumeInitialWindowLock()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.lockAuthWindow(moveWindow: false));
    });
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitState.busy) return;

    final result = authRequestFromForm(
      registering: false,
      login: _login.text,
      password: _password.text,
    );
    final request = result.request;
    if (request == null) {
      setState(() => _submitState = authSubmitInvalid(result.error));
      return;
    }

    setState(() => _submitState = authSubmitStarted());

    try {
      await widget.onSubmit(request);
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitState = authSubmitFailed(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.background,
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: widget.size.width,
          height: widget.size.height,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: UiColors.surfaceLow),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Gang Chat V2', style: UiTypography.title),
                    const SizedBox(height: 16),
                    TextInput(
                      controller: _login,
                      hint: 'Username or email address',
                      prefixIcon: Icons.person_outline,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    TextInput(
                      controller: _password,
                      hint: 'Password',
                      prefixIcon: Icons.lock_outline,
                      obscureText: true,
                      onSubmitted: (_) => _submit(),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _submitState.error ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: UiColors.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Button(
                          tone: ButtonTone.primary,
                          loading: _submitState.busy,
                          onPressed: _submit,
                          child: const Text('Login'),
                        ),
                      ],
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

class V2HomePage extends StatelessWidget {
  const V2HomePage({super.key, required this.app});

  final AuthenticatedAppContext app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.background,
      body: SizedBox.expand(key: ValueKey(app.currentUser.id)),
    );
  }
}
