import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/protocol/error_messages.dart';

void main() {
  test('keeps existing Chinese server messages', () {
    expect(
      localizedServerErrorMessage(
        code: 'email_verification_required',
        statusCode: 400,
        message: '请先验证邮箱',
      ),
      '请先验证邮箱',
    );
  });

  test('localizes known English server messages', () {
    expect(
      localizedServerErrorMessage(
        code: 'not_found',
        statusCode: 404,
        message: 'sticker not found',
      ),
      '表情不存在',
    );
    expect(
      localizedServerErrorMessage(
        code: 'unauthorized',
        statusCode: 401,
        message: 'session expired',
      ),
      '登录会话已过期',
    );
  });

  test('uses Chinese code and status fallbacks for unknown messages', () {
    expect(
      localizedServerErrorMessage(
        code: 'validation_failed',
        statusCode: 400,
        message: 'field xyz is malformed',
      ),
      '请求内容不符合要求',
    );
    expect(
      localizedServerErrorMessage(
        code: 'unknown',
        statusCode: 503,
        message: 'upstream exploded',
      ),
      '服务器暂时无法完成请求，请稍后重试',
    );
  });
}
