import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/app_update.dart';
import 'package:client/src/app/settings_about.dart';
import 'package:client/src/shell/app_update_gate.dart';
import 'package:client/src/shell/desktop_window_controller.dart';
import 'package:client/src/shell/release_update_service.dart';
import 'package:client/src/ui/ui.dart' as ui;

void main() {
  testWidgets('update gate shows update page and allows continuing', (
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
          child: const Scaffold(body: Text('Home is still available')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('v0.5.1'), findsWidgets);
    expect(find.text('发行时间'), findsOneWidget);
    expect(find.text('2026/07/08 01:02'), findsOneWidget);
    expect(find.textContaining('安装包来自'), findsNothing);
    expect(find.text('English'), findsNothing);

    await tester.tap(find.widgetWithText(ui.Button, '继续使用'));
    await tester.pumpAndSettle();

    expect(find.text('Home is still available'), findsOneWidget);
  });

  testWidgets('update gate keeps app running when installer launch fails', (
    tester,
  ) async {
    final update = AvailableAppUpdate(
      currentVersion: '0.5.0',
      latestVersion: '0.5.1',
      asset: const ReleaseAsset(
        key: 'releases/GangChat_v0.5.1.exe',
        version: '0.5.1',
        platform: AppUpdatePlatform.windows,
      ),
      downloadUrl: Uri.parse(
        'https://os.example.test/gang-chat/releases/GangChat_v0.5.1.exe',
      ),
    );
    final updateService = _FakeReleaseUpdateService(
      update,
      installError: const ProcessException(
        'powershell.exe',
        [],
        'operation canceled',
        1,
      ),
    );
    final windowEvents = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: ui.uiTheme(),
        home: AppUpdateGate(
          releaseBucketUrl: 'https://os.example.test/gang-chat',
          currentVersion: '0.5.0',
          autoUpdatePromptStore: const _FakeAutoUpdatePromptStore(true),
          updateService: updateService,
          platformOverride: AppUpdatePlatform.windows,
          windowController: _RecordingWindowController(windowEvents),
          child: const Scaffold(body: Text('Home should remain hidden')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ui.Button, '下载更新'));
    await tester.pumpAndSettle();

    expect(updateService.startedInstallers, hasLength(1));
    expect(windowEvents, isEmpty);
    expect(find.textContaining('下载或启动安装器失败'), findsOneWidget);
    expect(find.text('Home should remain hidden'), findsNothing);
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
  _FakeReleaseUpdateService(this.update, {this.installError});

  final AvailableAppUpdate? update;
  final Object? installError;
  final List<String> startedInstallers = [];

  @override
  Future<AvailableAppUpdate?> checkForUpdate({
    required String bucketUrl,
    required String currentVersion,
    required AppUpdatePlatform platform,
  }) async {
    return update;
  }

  @override
  Future<File> downloadUpdate(
    AvailableAppUpdate update, {
    ReleaseDownloadProgress? onProgress,
  }) async {
    onProgress?.call(receivedBytes: 0, totalBytes: 10);
    onProgress?.call(receivedBytes: 10, totalBytes: 10);
    return File(
      '${Directory.systemTemp.path}/GangChat_v${update.latestVersion}.exe',
    );
  }

  @override
  Future<void> startInstaller(File file) async {
    startedInstallers.add(file.path);
    final error = installError;
    if (error != null) throw error;
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

class _RecordingWindowController extends DesktopWindowController {
  _RecordingWindowController(this.events);

  final List<String> events;

  @override
  Future<void> terminateApplication() async {
    events.add('terminate');
  }
}
