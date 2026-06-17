import 'dart:convert';
import 'dart:io';

const _skippedDirectories = {
  '.dart_tool',
  '.codegraph',
  '.git',
  '.idea',
  '.vscode',
  '.plugin_symlinks',
  'build',
  'ephemeral',
  'Pods',
};

const _binaryExtensions = {
  '.a',
  '.app',
  '.bin',
  '.dll',
  '.dylib',
  '.exe',
  '.gif',
  '.ico',
  '.jar',
  '.jpeg',
  '.jpg',
  '.keystore',
  '.lib',
  '.lockfile',
  '.png',
  '.so',
  '.ttf',
  '.webp',
  '.zip',
};

const _mojibakeMarkers = [
  '�',
  'Ã',
  'Â',
  'â€',
  'ä¸',
  'ä½',
  'å¥',
  'æœ',
  '鈥',
  '锛',
  '浣犵',
  '娴佺',
  '鍥藉',
  '涓嶇',
  '鐗堟',
];

void main() {
  final root = Directory.current.absolute;
  final failures = <String>[];

  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relativePath = _relativePath(root, entity);
    if (_shouldSkip(relativePath)) continue;

    final bytes = entity.readAsBytesSync();
    if (_hasUtf8Bom(bytes)) {
      failures.add('$relativePath: has UTF-8 BOM; save as UTF-8 without BOM');
      continue;
    }

    late final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (error) {
      failures.add('$relativePath: is not valid UTF-8 (${error.message})');
      continue;
    }

    if (relativePath != 'tool/check_utf8.dart') {
      for (final marker in _mojibakeMarkers) {
        if (text.contains(marker)) {
          failures.add(
            '$relativePath: contains suspicious mojibake marker "$marker"',
          );
          break;
        }
      }
    }
  }

  if (failures.isEmpty) {
    stdout.writeln('UTF-8 check passed.');
    return;
  }

  stderr.writeln('UTF-8 check failed:');
  for (final failure in failures) {
    stderr.writeln('- $failure');
  }
  exitCode = 1;
}

String _relativePath(Directory root, File file) {
  final rootPath = root.path;
  final filePath = file.absolute.path;
  final relative = filePath.startsWith(rootPath)
      ? filePath.substring(rootPath.length + 1)
      : filePath;
  return relative.replaceAll(r'\', '/');
}

bool _shouldSkip(String relativePath) {
  final parts = relativePath.split('/');
  if (parts.any(_skippedDirectories.contains)) return true;
  return _binaryExtensions.contains(_extension(relativePath));
}

String _extension(String path) {
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  if (dot <= slash) return '';
  return path.substring(dot).toLowerCase();
}

bool _hasUtf8Bom(List<int> bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
}
