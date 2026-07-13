import 'dart:io';

import '../app/settings_about.dart';

class InstallInfoService {
  const InstallInfoService({this.fileName = gangChatClientInstallInfoFileName});

  final String fileName;

  Future<String?> readInstalledAt() async {
    try {
      final executableDir = File(Platform.resolvedExecutable).parent;
      final infoFile = File(
        '${executableDir.path}${Platform.pathSeparator}$fileName',
      );
      if (!await infoFile.exists()) return null;
      return infoFile.readAsString();
    } catch (_) {
      return null;
    }
  }
}
