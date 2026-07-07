import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/app_update.dart';
import 'package:client/src/app/settings_about.dart';
import 'package:client/src/shell/app_update_gate.dart';
import 'package:client/src/shell/desktop_window_controller.dart';
import 'package:client/src/shell/release_update_service.dart';
import 'package:client/src/ui/ui.dart' as ui;

void main() {
  testWidgets('update gate reports update and keeps home visible', (
    tester,
  ) async {
    final update = AvailableAppUpdate(
      currentVersion: '0.5.0',
      latestVersion: '0.5.1',
      asset: ReleaseAsset(
        key: 'releases/GangChat_v0.5.1.exe',
        version: '0.5.1',
        platform: AppUpdatePlatform.windows,
        releasedAt: DateTime(2026, 7, 8, 1, 2),
      ),
      downloadUrl: Uri.parse(
        'https://os.example.test/gang-chat/releases/GangChat_v0.5.1.exe',
      ),
    );
    final reportedUpdates = <AvailableAppUpdate>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: AppUpdateGate(
          releaseBucketUrl: 'https://os.example.test/gang-chat',
          currentVersion: '0.5.0',
          autoUpdatePromptStore: const _FakeAutoUpdatePromptStore(true),
          updateService: _FakeReleaseUpdateService(update),
          platformOverride: AppUpdatePlatform.windows,
          windowController: DesktopWindowController(),
          onUpdateAvailable: reportedUpdates.add,
          child: const Scaffold(body: Text('Home is still available')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home is still available'), findsOneWidget);
    expect(find.text('发现新版本'), findsNothing);
    expect(reportedUpdates, [same(update)]);
  });

  testWidgets('update page shows release details and settings actions', (
    tester,
  ) async {
    final update = AvailableAppUpdate(
      currentVersion: '0.5.0',
      latestVersion: '0.5.1',
      asset: ReleaseAsset(
        key: 'releases/GangChat_v0.5.1.exe',
        version: '0.5.1',
        platform: AppUpdatePlatform.windows,
        releasedAt: DateTime(2026, 7, 8, 1, 2),
      ),
      downloadUrl: Uri.parse(
        'https://os.example.test/gang-chat/releases/GangChat_v0.5.1.exe',
      ),
    );
    var backCount = 0;
    var laterCount = 0;
    var downloadCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: AppUpdatePage(
          update: update,
          downloading: false,
          downloadedBytes: 0,
          wrapInScaffold: true,
          onBack: () => backCount += 1,
          onRemindLater: () => laterCount += 1,
          onDownload: () => downloadCount += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('v0.5.1'), findsWidgets);
    expect(find.text('发行时间'), findsOneWidget);
    expect(find.text('2026/07/08 01:02'), findsOneWidget);
    expect(find.text('版本日志'), findsOneWidget);
    expect(find.text('无'), findsOneWidget);
    expect(find.textContaining('安装包来自'), findsNothing);
    expect(find.text('English'), findsNothing);
    expect(find.byTooltip('重新检查'), findsNothing);
    expect(find.widgetWithText(ui.Button, '继续使用'), findsNothing);
    expect(find.widgetWithText(ui.Button, '稍后提醒'), findsOneWidget);
    expect(find.widgetWithText(ui.Button, '下载更新'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ui.Button, '稍后提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ui.Button, '下载更新'));
    await tester.pumpAndSettle();

    expect(backCount, 1);
    expect(laterCount, 1);
    expect(downloadCount, 1);
  });

  testWidgets('update gate keeps child when auto prompt is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: AppUpdateGate(
          releaseBucketUrl: 'https://os.example.test/gang-chat',
          currentVersion: '0.5.0',
          autoUpdatePromptStore: const _FakeAutoUpdatePromptStore(false),
          updateService: _FakeReleaseUpdateService(null),
          platformOverride: AppUpdatePlatform.windows,
          windowController: DesktopWindowController(),
          child: const Scaffold(body: Text('Home is visible')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsNothing);
    expect(find.text('Home is visible'), findsOneWidget);
  });
}

class _FakeReleaseUpdateService extends ReleaseUpdateService {
  _FakeReleaseUpdateService(this.update);

  final AvailableAppUpdate? update;

  @override
  Future<AvailableAppUpdate?> checkForUpdate({
    required String bucketUrl,
    required String currentVersion,
    required AppUpdatePlatform platform,
  }) async {
    return update;
  }
}

class _FakeAutoUpdatePromptStore extends AutoUpdatePromptStore {
  const _FakeAutoUpdatePromptStore(this.enabled);

  final bool enabled;

  @override
  Future<bool> read() async => enabled;

  @override
  Future<void> write(bool enabled) async {}
}
