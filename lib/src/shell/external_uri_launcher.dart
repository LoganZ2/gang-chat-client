import 'dart:io';

class ExternalUriLauncher {
  const ExternalUriLauncher();

  Future<void> open(Uri uri) async {
    final value = uri.toString();
    if (Platform.isWindows) {
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', value]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [value]);
      return;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [value]);
      return;
    }
    throw UnsupportedError('Opening links is not supported on this platform.');
  }
}
