import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as file_selector;

class FileTypeGroup {
  const FileTypeGroup({required this.label, required this.extensions});

  final String label;
  final List<String> extensions;
}

class SelectedFile {
  const SelectedFile._({
    required this.name,
    required this.mimeType,
    required Future<Uint8List> Function() readAsBytes,
    required Future<int> Function() length,
  }) : _readAsBytes = readAsBytes,
       _length = length;

  factory SelectedFile._fromSelectorFile(file_selector.XFile file) {
    return SelectedFile._(
      name: file.name,
      mimeType: file.mimeType,
      readAsBytes: file.readAsBytes,
      length: file.length,
    );
  }

  factory SelectedFile.fromPath(String path) {
    return SelectedFile._fromSelectorFile(file_selector.XFile(path));
  }

  final String name;
  final String? mimeType;
  final Future<Uint8List> Function() _readAsBytes;
  final Future<int> Function() _length;

  Future<Uint8List> readAsBytes() => _readAsBytes();

  Future<int> length() => _length();
}

class SaveFileLocation {
  const SaveFileLocation({required this.path});

  final String path;
}

class FileSelectionService {
  const FileSelectionService();

  Future<SelectedFile?> openFile({
    List<FileTypeGroup> acceptedTypeGroups = const [],
  }) async {
    final file = acceptedTypeGroups.isEmpty
        ? await file_selector.openFile()
        : await file_selector.openFile(
            acceptedTypeGroups: _selectorTypeGroups(acceptedTypeGroups),
          );
    return file == null ? null : SelectedFile._fromSelectorFile(file);
  }

  Future<List<SelectedFile>> openFiles({
    List<FileTypeGroup> acceptedTypeGroups = const [],
  }) async {
    final files = acceptedTypeGroups.isEmpty
        ? await file_selector.openFiles()
        : await file_selector.openFiles(
            acceptedTypeGroups: _selectorTypeGroups(acceptedTypeGroups),
          );
    return files.map(SelectedFile._fromSelectorFile).toList(growable: false);
  }

  Future<SaveFileLocation?> getSaveLocation({
    required String suggestedName,
    List<FileTypeGroup> acceptedTypeGroups = const [],
    String? confirmButtonText,
  }) async {
    final location = acceptedTypeGroups.isEmpty
        ? await file_selector.getSaveLocation(
            suggestedName: suggestedName,
            confirmButtonText: confirmButtonText,
          )
        : await file_selector.getSaveLocation(
            suggestedName: suggestedName,
            acceptedTypeGroups: _selectorTypeGroups(acceptedTypeGroups),
            confirmButtonText: confirmButtonText,
          );
    return location == null ? null : SaveFileLocation(path: location.path);
  }

  List<SelectedFile> filesFromPaths(Iterable<String> paths) {
    return paths.map(SelectedFile.fromPath).toList(growable: false);
  }

  Future<void> saveBytesToPath({
    required Uint8List bytes,
    required String path,
    required String filename,
    String? mimeType,
  }) {
    return file_selector.XFile.fromData(
      bytes,
      mimeType: mimeType,
      name: filename,
    ).saveTo(path);
  }
}

List<file_selector.XTypeGroup> _selectorTypeGroups(List<FileTypeGroup> groups) {
  return groups
      .map(
        (group) => file_selector.XTypeGroup(
          label: group.label,
          extensions: group.extensions,
        ),
      )
      .toList(growable: false);
}
