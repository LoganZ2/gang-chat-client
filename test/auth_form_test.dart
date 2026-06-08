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
    expect(result.error, '请输入账号和密码后继续。');
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
        login: 'a@example.test',
        password: 'secret',
      ).error,
      '用户名不能为空。',
    );
    expect(
      authRequestFromForm(
        registering: true,
        username: 'logan',
        login: 'a@example.test',
        password: 'secret',
        confirmPassword: 'different',
      ).error,
      '两次输入的密码不一致。',
    );
  });

  test('authRequestFromForm builds register request', () {
    final result = authRequestFromForm(
      registering: true,
      username: ' logan ',
      login: ' a@example.test ',
      password: 'secret',
      confirmPassword: 'secret',
    );

    expect(result.error, isNull);
    expect(result.request?.registering, isTrue);
    expect(result.request?.username, 'logan');
    expect(result.request?.login, 'a@example.test');
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
    expect(failed.error, '无法连接服务器：Bad state: offline');
  });

  test('auth submit failure uses auth exception messages directly', () {
    final failed = authSubmitFailed(
      AuthException(
        'Invalid credentials',
        statusCode: 401,
        code: 'invalid_credentials',
      ),
    );

    expect(failed.busy, isFalse);
    expect(failed.error, 'Invalid credentials');
  });
}
