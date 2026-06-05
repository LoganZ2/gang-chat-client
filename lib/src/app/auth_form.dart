import 'auth_session_controller.dart';
import '../auth/auth_client.dart';

class AuthFormResult {
  const AuthFormResult._({this.request, this.error});

  const AuthFormResult.valid(AuthRequest request) : this._(request: request);

  const AuthFormResult.invalid(String error) : this._(error: error);

  final AuthRequest? request;
  final String? error;

  bool get isValid => request != null;
}

class AuthSubmitState {
  const AuthSubmitState({this.busy = false, this.error});

  final bool busy;
  final String? error;
}

AuthFormResult authRequestFromForm({
  required bool registering,
  required String login,
  required String password,
  String username = '',
  String confirmPassword = '',
}) {
  final normalizedLogin = login.trim();
  if (normalizedLogin.isEmpty || password.isEmpty) {
    return const AuthFormResult.invalid('Enter your credentials to continue.');
  }

  if (!registering) {
    return AuthFormResult.valid(
      AuthRequest.login(login: normalizedLogin, password: password),
    );
  }

  final normalizedUsername = username.trim();
  if (normalizedUsername.isEmpty) {
    return const AuthFormResult.invalid('Username is required.');
  }
  if (password != confirmPassword) {
    return const AuthFormResult.invalid('Passwords do not match.');
  }

  return AuthFormResult.valid(
    AuthRequest.register(
      username: normalizedUsername,
      login: normalizedLogin,
      password: password,
    ),
  );
}

AuthSubmitState authSubmitStarted() {
  return const AuthSubmitState(busy: true);
}

AuthSubmitState authSubmitInvalid(String? error) {
  return AuthSubmitState(error: error);
}

AuthSubmitState authSubmitFailed(Object failure) {
  return AuthSubmitState(error: authSubmitFailureMessage(failure));
}

String authSubmitFailureMessage(Object failure) {
  if (failure is AuthException) return failure.message;
  return 'Cannot reach the server: $failure';
}
