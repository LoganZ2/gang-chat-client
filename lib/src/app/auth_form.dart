import 'auth_session_controller.dart';
import '../auth/auth_client.dart';
import 'language_preference.dart';

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
  String language = defaultLanguagePreference,
}) {
  final copy = authFormCopy(language);
  final normalizedLogin = login.trim();
  if (normalizedLogin.isEmpty || password.isEmpty) {
    return AuthFormResult.invalid(copy.missingCredentials);
  }

  if (!registering) {
    return AuthFormResult.valid(
      AuthRequest.login(login: normalizedLogin, password: password),
    );
  }

  final normalizedUsername = username.trim();
  if (normalizedUsername.isEmpty) {
    return AuthFormResult.invalid(copy.missingUsername);
  }
  if (password != confirmPassword) {
    return AuthFormResult.invalid(copy.passwordMismatch);
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

AuthSubmitState authSubmitFailed(
  Object failure, {
  String language = defaultLanguagePreference,
}) {
  return AuthSubmitState(
    error: authSubmitFailureMessage(failure, language: language),
  );
}

String authSubmitFailureMessage(
  Object failure, {
  String language = defaultLanguagePreference,
}) {
  final copy = authFormCopy(language);
  if (failure is AuthException) return copy.authException(failure);
  return copy.connectionFailed(failure);
}

AuthFormCopy authFormCopy(String language) {
  return switch (normalizeLanguagePreference(language)) {
    'zh-Hant' => const AuthFormCopy.zhHant(),
    'en' => const AuthFormCopy.en(),
    _ => const AuthFormCopy.zhHans(),
  };
}

class AuthFormCopy {
  const AuthFormCopy.zhHans()
    : missingCredentials = '请输入账号和密码后继续',
      missingUsername = '用户名不能为空',
      passwordMismatch = '两次输入的密码不一致',
      connectionFailedPrefix = '无法连接服务器：',
      invalidCredentials = '账号或密码不正确',
      rateLimited = '登录尝试次数过多，请稍后再试',
      conflict = '用户名或邮箱已被占用',
      badRequest = '请检查账号信息后再试',
      serverError = '服务器暂时无法完成请求，请稍后再试',
      requestFailedPrefix = '请求失败',
      fallback = '认证请求失败，请稍后再试';

  const AuthFormCopy.zhHant()
    : missingCredentials = '請輸入帳號和密碼後繼續',
      missingUsername = '使用者名稱不能為空',
      passwordMismatch = '兩次輸入的密碼不一致',
      connectionFailedPrefix = '無法連線伺服器：',
      invalidCredentials = '帳號或密碼不正確',
      rateLimited = '登入嘗試次數過多，請稍後再試',
      conflict = '使用者名稱或電子郵件已被使用',
      badRequest = '請檢查帳號資訊後再試',
      serverError = '伺服器暫時無法完成請求，請稍後再試',
      requestFailedPrefix = '請求失敗',
      fallback = '認證請求失敗，請稍後再試';

  const AuthFormCopy.en()
    : missingCredentials = 'Enter your account and password to continue',
      missingUsername = 'Username is required',
      passwordMismatch = 'The two passwords do not match',
      connectionFailedPrefix = 'Unable to connect to the server: ',
      invalidCredentials = 'Incorrect account or password',
      rateLimited = 'Too many login attempts, try again later',
      conflict = 'That username or email is already taken',
      badRequest = 'Check your account details and try again',
      serverError =
          'The server could not complete the request, try again later',
      requestFailedPrefix = 'Request failed',
      fallback = 'Authentication failed, try again later';

  final String missingCredentials;
  final String missingUsername;
  final String passwordMismatch;
  final String connectionFailedPrefix;
  final String invalidCredentials;
  final String rateLimited;
  final String conflict;
  final String badRequest;
  final String serverError;
  final String requestFailedPrefix;
  final String fallback;

  String connectionFailed(Object failure) {
    return '$connectionFailedPrefix$failure';
  }

  String authException(AuthException failure) {
    return switch (failure.code.trim()) {
      'unauthorized' || 'invalid_credentials' => invalidCredentials,
      'rate_limited' => rateLimited,
      'conflict' => conflict,
      'bad_request' || 'validation_failed' => badRequest,
      'internal_error' => serverError,
      'request_failed' => requestFailed(failure.statusCode),
      _ => fallback,
    };
  }

  String requestFailed(int statusCode) {
    return '$requestFailedPrefix ($statusCode)';
  }
}
