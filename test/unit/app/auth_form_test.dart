import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/auth_form.dart';
import 'package:client/src/auth/auth_client.dart';

void main() {
  test('authRequestFromForm validates required login credentials', () {
    final result = authRequestFromForm(
      registering: false,
      login: ' ',
      password: '',
    );

    expect(result.request, isNull);
    expect(result.error, '请输入账号和密码后继续');
  });

  test('authRequestFromForm localizes validation errors', () {
    final english = authRequestFromForm(
      registering: false,
      login: ' ',
      password: '',
      language: 'en',
    );
    final traditional = authRequestFromForm(
      registering: true,
      login: 'a@example.test',
      password: 'secret',
      language: 'zh-Hant',
    );

    expect(english.error, 'Enter your account and password to continue');
    expect(traditional.error, '使用者名稱不能為空');
  });

  test('authRequestFromForm builds trimmed login request', () {
    final result = authRequestFromForm(
      registering: false,
      login: ' logan ',
      password: 'secret',
    );

    expect(result.error, isNull);
    expect(result.request?.registering, isFalse);
    expect(result.request?.login, 'logan');
    expect(result.request?.password, 'secret');
  });

  test('authRequestFromForm validates register fields', () {
    expect(
      authRequestFromForm(
        registering: true,
        username: 'logan.test',
        login: 'a@example.test',
        password: 'secret',
        confirmPassword: 'secret',
      ).error,
      '登录用户名需为 3-32 位，只能包含英文字母、数字、下划线或连字符',
    );
    expect(
      authRequestFromForm(
        registering: true,
        username: 'logan',
        login: 'invalid-email',
        password: 'secret',
        confirmPassword: 'secret',
      ).error,
      '请输入有效的邮箱地址',
    );
    expect(
      authRequestFromForm(
        registering: true,
        login: 'a@example.test',
        password: 'secret',
      ).error,
      '登录用户名不能为空',
    );
    expect(
      authRequestFromForm(
        registering: true,
        username: 'logan',
        login: 'a@example.test',
        password: 'secret',
        confirmPassword: 'different',
      ).error,
      '两次输入的密码不一致',
    );
  });

  test('registerEmailValidationError validates normalized email format', () {
    expect(registerEmailValidationError(' '), '邮箱不能为空');
    expect(registerEmailValidationError('logan.example.test'), '请输入有效的邮箱地址');
    expect(registerEmailValidationError(' logan@example.test '), isNull);
  });

  test('authRequestFromForm builds register request', () {
    final result = authRequestFromForm(
      registering: true,
      username: ' logan ',
      login: ' a@example.test ',
      password: 'secret',
      confirmPassword: 'secret',
      emailVerificationToken: 'verification-token',
    );

    expect(result.error, isNull);
    expect(result.request?.registering, isTrue);
    expect(result.request?.username, 'logan');
    expect(result.request?.login, 'a@example.test');
    expect(result.request?.emailVerificationToken, 'verification-token');
  });

  test('authRequestFromForm requires email verification before register', () {
    final result = authRequestFromForm(
      registering: true,
      username: 'logan',
      login: 'a@example.test',
      password: 'secret',
      confirmPassword: 'secret',
    );

    expect(result.request, isNull);
    expect(result.error, '请先验证邮箱');
  });

  test('auth submit state covers started invalid and generic failure', () {
    final started = authSubmitStarted();

    expect(started.busy, isTrue);
    expect(started.error, isNull);

    final invalid = authSubmitInvalid('Missing password');

    expect(invalid.busy, isFalse);
    expect(invalid.error, 'Missing password');

    final failed = authSubmitFailed(StateError('offline'));

    expect(failed.busy, isFalse);
    expect(failed.error, '无法连接服务器');
  });

  test('auth submit failure gives a concise TLS recovery message', () {
    final failed = authSubmitFailed(
      HandshakeException('Handshake error in client'),
    );

    expect(failed.error, '无法建立安全连接，请检查网络、代理或系统时间后重试');
  });

  test('auth submit failure localizes auth exception codes', () {
    final failed = authSubmitFailed(
      AuthException(
        'Invalid credentials',
        statusCode: 401,
        code: 'invalid_credentials',
      ),
    );
    final english = authSubmitFailed(
      AuthException(
        'invalid credentials',
        statusCode: 401,
        code: 'unauthorized',
      ),
      language: 'en',
    );
    final traditional = authSubmitFailed(
      AuthException(
        'too many failed login attempts',
        statusCode: 429,
        code: 'rate_limited',
      ),
      language: 'zh-Hant',
    );

    expect(failed.busy, isFalse);
    expect(failed.error, '账号或密码不正确');
    expect(english.error, 'Incorrect account or password');
    expect(traditional.error, '登入嘗試次數過多，請稍後再試');
  });
}
