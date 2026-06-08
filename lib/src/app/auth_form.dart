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
    return const AuthFormResult.invalid('请输入账号和密码后继续。');
  }

  if (!registering) {
    return AuthFormResult.valid(
      AuthRequest.login(login: normalizedLogin, password: password),
    );
  }

  final normalizedUsername = username.trim();
  if (normalizedUsername.isEmpty) {
    return const AuthFormResult.invalid('用户名不能为空。');
  }
  if (password != confirmPassword) {
    return const AuthFormResult.invalid('两次输入的密码不一致。');
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
  return '无法连接服务器：$failure';
}
