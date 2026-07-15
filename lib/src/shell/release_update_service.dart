import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../app/app_update.dart';

typedef ReleaseDownloadProgress =
    void Function({required int receivedBytes, int? totalBytes});

typedef ReleaseInstallerProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

typedef ReleaseTemporaryDirectoryProvider = Future<Directory> Function();

class ReleaseDownloadCancelledException implements Exception {
  const ReleaseDownloadCancelledException();

  @override
  String toString() => '版本下载已取消';
}

class ReleaseDownloadCancellationToken {
  bool _cancelled = false;
  bool _active = false;
  http.Client? _client;
  File? _partialFile;
  Completer<void>? _completion;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _client?.close();
  }

  Future<void> cancelAndDeletePartialFile() async {
    cancel();
    final completion = _completion;
    if (_active && completion != null && !completion.isCompleted) {
      try {
        await completion.future.timeout(const Duration(seconds: 2));
      } catch (_) {
        // A still-open file can fail deletion on Windows; try anyway below.
      }
    }
    await _deleteFileQuietly(_partialFile);
  }

  void _bind(http.Client client, File partialFile) {
    _client = client;
    _partialFile = partialFile;
    _active = true;
    _completion = Completer<void>();
    if (_cancelled) client.close();
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const ReleaseDownloadCancelledException();
  }

  void _complete() {
    _client = null;
    _active = false;
    final completion = _completion;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
  }
}

class ReleaseUpdateService {
  const ReleaseUpdateService({
    http.Client? httpClient,
    ReleaseInstallerProcessRunner? processRunner,
    ReleaseTemporaryDirectoryProvider? temporaryDirectoryProvider,
  }) : _httpClient = httpClient,
       _processRunner = processRunner,
       _temporaryDirectoryProvider = temporaryDirectoryProvider;

  final http.Client? _httpClient;
  final ReleaseInstallerProcessRunner? _processRunner;
  final ReleaseTemporaryDirectoryProvider? _temporaryDirectoryProvider;

  Future<AvailableAppUpdate?> checkForUpdate({
    required String bucketUrl,
    required String currentVersion,
    required AppUpdatePlatform platform,
  }) async {
    final response = await _withClient((client) {
      return client.get(_listUri(bucketUrl));
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        '读取版本列表失败（状态码 ${response.statusCode}）',
        uri: _listUri(bucketUrl),
      );
    }

    final assets = parseReleaseAssetsFromS3List(response.body);
    final asset = latestReleaseAssetForPlatform(assets, platform);
    if (asset == null ||
        !isNewerAppVersion(
          currentVersion: currentVersion,
          latestVersion: asset.version,
        )) {
      return null;
    }

    return AvailableAppUpdate(
      currentVersion: currentVersion,
      latestVersion: asset.version,
      asset: asset,
      downloadUrl: Uri.parse(releaseAssetUrl(bucketUrl, asset.key)),
    );
  }

  Future<File> downloadUpdate(
    AvailableAppUpdate update, {
    ReleaseDownloadProgress? onProgress,
    ReleaseDownloadCancellationToken? cancellationToken,
  }) async {
    final request = http.Request('GET', update.downloadUrl);
    final injected = _httpClient;
    final client = injected ?? http.Client();
    File? file;
    try {
      file = await _downloadTarget(update);
      cancellationToken?._bind(client, file);
      cancellationToken?._throwIfCancelled();
      final response = await client.send(request);
      cancellationToken?._throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '版本下载失败（状态码 ${response.statusCode}）',
          uri: update.downloadUrl,
        );
      }

      final sink = file.openWrite();
      var received = 0;
      final contentLength = response.contentLength;
      final total = contentLength != null && contentLength >= 0
          ? contentLength
          : null;
      onProgress?.call(receivedBytes: received, totalBytes: total);
      try {
        await for (final chunk in response.stream) {
          cancellationToken?._throwIfCancelled();
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(receivedBytes: received, totalBytes: total);
        }
        cancellationToken?._throwIfCancelled();
      } finally {
        await sink.close();
      }
      return file;
    } catch (error) {
      await _deleteFileQuietly(file);
      if (error is ReleaseDownloadCancelledException ||
          cancellationToken?.isCancelled == true) {
        throw const ReleaseDownloadCancelledException();
      }
      rethrow;
    } finally {
      cancellationToken?._complete();
      if (injected == null) client.close();
    }
  }

  Future<void> startInstaller(File file) async {
    if (Platform.isWindows) {
      await _startWindowsInstaller(file);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [file.path], mode: ProcessStartMode.detached);
      return;
    }
    throw UnsupportedError(
      'Installing updates is not supported on this platform.',
    );
  }

  Future<void> _startWindowsInstaller(File file) async {
    final arguments = _windowsElevatedInstallerArguments(file.path);
    final runner = _processRunner ?? _runProcess;
    final result = await runner('powershell.exe', arguments);
    if (result.exitCode == 0) return;

    throw ProcessException(
      'powershell.exe',
      arguments,
      _processResultMessage(result),
      result.exitCode,
    );
  }

  Future<T> _withClient<T>(
    Future<T> Function(http.Client client) action,
  ) async {
    final injected = _httpClient;
    if (injected != null) return action(injected);

    final client = http.Client();
    try {
      return await action(client);
    } finally {
      client.close();
    }
  }

  Uri _listUri(String bucketUrl) {
    final base = Uri.parse(bucketUrl);
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        'list-type': '2',
        'prefix': 'releases/',
      },
    );
  }

  Future<File> _downloadTarget(AvailableAppUpdate update) async {
    final directoryProvider =
        _temporaryDirectoryProvider ?? getTemporaryDirectory;
    final directory = await directoryProvider();
    await _cleanupDownloadedInstallers(directory);
    final extension = update.asset.platform == AppUpdatePlatform.windows
        ? 'exe'
        : 'dmg';
    return File(
      '${directory.path}${Platform.pathSeparator}'
      'GangChat_v${update.latestVersion}.$extension',
    );
  }

  Future<void> _cleanupDownloadedInstallers(Directory directory) async {
    if (!await directory.exists()) return;

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!_downloadedInstallerPattern.hasMatch(_pathBasename(entity.path))) {
        continue;
      }
      try {
        await entity.delete();
      } catch (_) {
        // A currently running installer may be locked by Windows; skip it and
        // let the new download surface any conflict with its exact target file.
      }
    }
  }
}

Future<void> _deleteFileQuietly(File? file) async {
  if (file == null) return;
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

final _downloadedInstallerPattern = RegExp(
  r'^GangChat_v\d+\.\d+\.\d+\.(exe|dmg)$',
);

String _pathBasename(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  final index = slash > backslash ? slash : backslash;
  return index < 0 ? path : path.substring(index + 1);
}

Future<ProcessResult> _runProcess(String executable, List<String> arguments) {
  return Process.run(executable, arguments);
}

List<String> _windowsElevatedInstallerArguments(String installerPath) {
  return [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    'Start-Process -FilePath '
        '${_powershellSingleQuoted(installerPath)} -Verb RunAs',
  ];
}

String _powershellSingleQuoted(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String _processResultMessage(ProcessResult result) {
  final stderr = result.stderr?.toString().trim() ?? '';
  if (stderr.isNotEmpty) return stderr;

  final stdout = result.stdout?.toString().trim() ?? '';
  if (stdout.isNotEmpty) return stdout;

  return '安装程序启动失败';
}
