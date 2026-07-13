import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/settings_about.dart';

void main() {
  test('debug builds use fixed app version', () {
    expect(gangChatClientVersion, '1.0.0');
  });

  test('appVersionLabel normalizes display text', () {
    expect(appVersionLabel('1.2.3'), 'v1.2.3');
    expect(appVersionLabel('v2.0.0'), 'v2.0.0');
  });

  test('appVersionNumberLabel strips display prefix', () {
    expect(appVersionNumberLabel('1.2.3'), '1.2.3');
    expect(appVersionNumberLabel('v2.0.0'), '2.0.0');
  });

  test('compareAppVersions compares semantic version parts', () {
    expect(compareAppVersions('1.2.3', '1.2.3'), 0);
    expect(compareAppVersions('1.2.4', '1.2.3'), greaterThan(0));
    expect(compareAppVersions('1.2.3', '1.3.0'), lessThan(0));
    expect(compareAppVersions('v1.2.3+4', '1.2.3'), 0);
  });

  test('updateCheckSucceededText describes current and newer versions', () {
    expect(
      updateCheckSucceededText(currentVersion: '1.0.0', latestVersion: '1.0.0'),
      '当前已是最新版本',
    );
    expect(
      updateCheckSucceededText(currentVersion: '1.0.0', latestVersion: '1.1.0'),
      '发现新版本 v1.1.0',
    );
  });

  test('feedback helpers use bound email and version', () {
    expect(boundEmailForFeedback(' user@example.test '), 'user@example.test');
    expect(boundEmailForFeedback(''), isNull);
    expect(feedbackMailSubject('1.0.0'), contains('v1.0.0'));
    expect(
      feedbackMailBody(
        senderEmail: 'user@example.test',
        currentVersion: '1.0.0',
      ),
      contains('发件人（绑定邮箱）：user@example.test'),
    );
  });

  test(
    'official release time converts UTC across the Beijing date boundary',
    () {
      expect(
        officialDateTimeLabel(DateTime.utc(2026, 7, 12, 20, 34)),
        '2026/07/13 04:34 UTC+08:00',
      );
      expect(
        officialVersionTimeLabel('2026-07-12T20:34:27.126Z'),
        '2026/07/13 04:34 UTC+08:00',
      );
    },
  );

  test('install time stays local and supports legacy date files', () {
    expect(installTimeLabel('2026/07/01'), '2026/07/01');
    expect(installTimeLabel('2026-07-01T12:34:56'), '2026/07/01 12:34');
  });
}
