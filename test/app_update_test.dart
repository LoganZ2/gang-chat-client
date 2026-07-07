import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/app_update.dart';

void main() {
  test('parseReleaseAssetsFromS3List accepts GangChat release names only', () {
    final assets = parseReleaseAssetsFromS3List('''
      <ListBucketResult>
        <Contents>
          <Key>releases/GangChat_v0.5.0.exe</Key>
          <LastModified>2026-07-08T01:02:03.000Z</LastModified>
        </Contents>
        <Contents>
          <Key>releases/GangChat_v0.5.1.dmg</Key>
          <LastModified>2026-07-09T04:05:06.000Z</LastModified>
        </Contents>
        <Contents><Key>releases/GangChat-0.5.2-windows.zip</Key></Contents>
        <Contents><Key>avatars/not-a-release.png</Key></Contents>
      </ListBucketResult>
    ''');

    expect(assets, hasLength(2));
    expect(assets.first.version, '0.5.0');
    expect(assets.first.platform, AppUpdatePlatform.windows);
    expect(assets.first.releasedAt, DateTime.utc(2026, 7, 8, 1, 2, 3));
    expect(assets.last.version, '0.5.1');
    expect(assets.last.platform, AppUpdatePlatform.macos);
    expect(assets.last.releasedAt, DateTime.utc(2026, 7, 9, 4, 5, 6));
  });

  test('latestReleaseAssetForPlatform chooses highest semantic version', () {
    final assets = [
      const ReleaseAsset(
        key: 'releases/GangChat_v0.5.0.exe',
        version: '0.5.0',
        platform: AppUpdatePlatform.windows,
      ),
      const ReleaseAsset(
        key: 'releases/GangChat_v0.10.0.exe',
        version: '0.10.0',
        platform: AppUpdatePlatform.windows,
      ),
      const ReleaseAsset(
        key: 'releases/GangChat_v0.9.0.dmg',
        version: '0.9.0',
        platform: AppUpdatePlatform.macos,
      ),
    ];

    final latest = latestReleaseAssetForPlatform(
      assets,
      AppUpdatePlatform.windows,
    );

    expect(latest?.version, '0.10.0');
  });

  test('releaseAssetUrl encodes each key segment', () {
    expect(
      releaseAssetUrl(
        'https://os.example.test/gang-chat/',
        'releases/GangChat_v1.2.3.exe',
      ),
      'https://os.example.test/gang-chat/releases/GangChat_v1.2.3.exe',
    );
  });

  test('releaseTimeLabel formats release time when available', () {
    expect(releaseTimeLabel(null), '暂无');
    expect(releaseTimeLabel(DateTime(2026, 7, 8, 9, 5)), '2026/07/08 09:05');
  });
}
