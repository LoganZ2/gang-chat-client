import 'package:client/src/app/error_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves an existing Chinese error', () {
    expect(userFacingErrorMessage('保存失败'), '保存失败');
  });

  test('maps common platform errors without exposing English details', () {
    expect(
      userFacingErrorMessage(Exception('SocketException: connection failed')),
      '网络连接失败，请检查网络后重试',
    );
    expect(
      userFacingErrorMessage(StateError('unsupported platform')),
      '当前平台不支持此操作',
    );
  });

  test('uses the caller fallback for unknown English errors', () {
    expect(
      userFacingErrorMessage(
        StateError('decoder exploded'),
        fallback: '读取图片失败',
      ),
      '读取图片失败',
    );
  });
}
