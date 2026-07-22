import 'package:client/src/shell/client_system_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('client system names cover supported Flutter platforms', () {
    expect(clientSystemName(TargetPlatform.android), 'Android');
    expect(clientSystemName(TargetPlatform.iOS), 'iOS');
    expect(clientSystemName(TargetPlatform.linux), 'Linux');
    expect(clientSystemName(TargetPlatform.macOS), 'macOS');
    expect(clientSystemName(TargetPlatform.windows), 'Windows');
    expect(clientSystemName(TargetPlatform.fuchsia), 'Fuchsia');
  });

  test('client user agent includes the normalized system name', () {
    expect(
      gangChatClientUserAgent(TargetPlatform.android),
      'GangChat Client (Android)',
    );
    expect(
      gangChatClientUserAgent(TargetPlatform.windows),
      'GangChat Client (Windows)',
    );
  });
}
