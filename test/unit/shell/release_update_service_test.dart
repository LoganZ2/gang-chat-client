import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:client/src/app/app_update.dart';
import 'package:client/src/shell/release_update_service.dart';

void main() {
  test('checkForUpdate returns platform-specific latest release', () async {
    final service = ReleaseUpdateService(
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.queryParameters['list-type'], '2');
        expect(request.url.queryParameters['prefix'], 'releases/');
        return http.Response('''
          <ListBucketResult>
            <Contents><Key>releases/GangChat_v0.5.0.exe</Key></Contents>
            <Contents>
              <Key>releases/GangChat_v0.5.1.exe</Key>
              <LastModified>2026-07-08T02:03:04.000Z</LastModified>
            </Contents>
            <Contents><Key>releases/GangChat_v0.5.1.dmg</Key></Contents>
          </ListBucketResult>
        ''', 200);
      }),
    );

    final update = await service.checkForUpdate(
      bucketUrl: 'https://os.example.test/gang-chat',
      currentVersion: '0.5.0',
      platform: AppUpdatePlatform.windows,
    );

    expect(update?.latestVersion, '0.5.1');
    expect(update?.asset.releasedAt, DateTime.utc(2026, 7, 8, 2, 3, 4));
    expect(
      update?.downloadUrl.toString(),
      'https://os.example.test/gang-chat/releases/GangChat_v0.5.1.exe',
    );
  });

  test('checkForUpdate returns null when current version is latest', () async {
    final service = ReleaseUpdateService(
      httpClient: MockClient((request) async {
        return http.Response('''
          <ListBucketResult>
            <Contents><Key>releases/GangChat_v0.5.1.exe</Key></Contents>
          </ListBucketResult>
        ''', 200);
      }),
    );

    final update = await service.checkForUpdate(
      bucketUrl: 'https://os.example.test/gang-chat',
      currentVersion: '0.5.1',
      platform: AppUpdatePlatform.windows,
    );

    expect(update, isNull);
  });

  test(
    'downloadUpdate removes old GangChat installers from temp first',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'gang_chat_release_update_test_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final oldExe = File(
        '${temp.path}${Platform.pathSeparator}GangChat_v0.5.0.exe',
      );
      final oldDmg = File(
        '${temp.path}${Platform.pathSeparator}GangChat_v0.4.9.dmg',
      );
      final unrelated = File(
        '${temp.path}${Platform.pathSeparator}GangChat_notes.exe',
      );
      await oldExe.writeAsString('old exe');
      await oldDmg.writeAsString('old dmg');
      await unrelated.writeAsString('keep me');

      final service = ReleaseUpdateService(
        httpClient: MockClient((request) async {
          return http.Response('new installer', 200);
        }),
        temporaryDirectoryProvider: () async => temp,
      );

      final file = await service.downloadUpdate(
        AvailableAppUpdate(
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
        ),
      );

      expect(await oldExe.exists(), isFalse);
      expect(await oldDmg.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
      expect(file.path, endsWith('GangChat_v0.5.1.exe'));
      expect(await file.readAsString(), 'new installer');
    },
  );

  test('downloadUpdate cancellation deletes partial installer', () async {
    final temp = await Directory.systemTemp.createTemp(
      'gang_chat_release_update_cancel_test_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final token = ReleaseDownloadCancellationToken();
    final service = ReleaseUpdateService(
      httpClient: _ChunkedDownloadClient([
        'partial '.codeUnits,
        'installer'.codeUnits,
      ]),
      temporaryDirectoryProvider: () async => temp,
    );
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

    await expectLater(
      service.downloadUpdate(
        update,
        cancellationToken: token,
        onProgress: ({required receivedBytes, totalBytes}) {
          if (receivedBytes > 0) token.cancel();
        },
      ),
      throwsA(isA<ReleaseDownloadCancelledException>()),
    );

    final partial = File(
      '${temp.path}${Platform.pathSeparator}GangChat_v0.5.1.exe',
    );
    expect(await partial.exists(), isFalse);
  });

  test(
    'startInstaller launches Windows installer through UAC shell',
    () async {
      String? executable;
      List<String>? arguments;
      final service = ReleaseUpdateService(
        processRunner: (process, args) async {
          executable = process;
          arguments = args;
          return ProcessResult(42, 0, '', '');
        },
      );

      await service.startInstaller(
        File(r"C:\Users\me\AppData\Local\Temp\Gang Chat's_v0.5.1.exe"),
      );

      expect(executable, 'powershell.exe');
      expect(
        arguments,
        containsAllInOrder([
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
        ]),
      );
      expect(arguments?.last, contains('Start-Process -FilePath'));
      expect(arguments?.last, contains('-Verb RunAs'));
      expect(
        arguments?.last,
        contains(r"'C:\Users\me\AppData\Local\Temp\Gang Chat''s_v0.5.1.exe'"),
      );
    },
    skip: !Platform.isWindows ? 'Windows-only installer launcher' : false,
  );

  test(
    'startInstaller surfaces failed Windows launcher',
    () async {
      final service = ReleaseUpdateService(
        processRunner: (process, args) async {
          return ProcessResult(42, 1, '', 'operation canceled');
        },
      );

      expect(
        () => service.startInstaller(File(r'C:\Temp\GangChat_v0.5.1.exe')),
        throwsA(
          isA<ProcessException>()
              .having((error) => error.errorCode, 'errorCode', 1)
              .having(
                (error) => error.message,
                'message',
                contains('operation canceled'),
              ),
        ),
      );
    },
    skip: !Platform.isWindows ? 'Windows-only installer launcher' : false,
  );
}

class _ChunkedDownloadClient extends http.BaseClient {
  _ChunkedDownloadClient(this.chunks);

  final List<List<int>> chunks;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream<List<int>>.fromIterable(chunks), 200);
  }
}
