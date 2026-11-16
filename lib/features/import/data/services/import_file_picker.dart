import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:bibliolife/shared/models/book_format.dart';

class PickedImportFile {
  const PickedImportFile({required this.path, required this.name});

  final String path;
  final String name;
}

abstract interface class ImportFilePicker {
  Future<PickedImportFile?> pickBookFile();
}

class FilePickerImportFilePicker implements ImportFilePicker {
  const FilePickerImportFilePicker({this.useAnyFileType});

  final bool? useAnyFileType;

  static const allowedExtensions = BookFormat.supportedExtensions;

  static FileType fileTypeFor({required bool isAndroid}) =>
      isAndroid ? FileType.any : FileType.custom;

  @override
  Future<PickedImportFile?> pickBookFile() async {
    final useAnyType = useAnyFileType ?? Platform.isAndroid;
    final result = await FilePicker.pickFiles(
      type: fileTypeFor(isAndroid: useAnyType),
      allowedExtensions: useAnyType ? null : allowedExtensions,
      allowMultiple: false,
    );
    final file = result?.files.singleOrNull;
    final path = file?.path;
    if (file == null || path == null) return null;

    return PickedImportFile(path: path, name: file.name);
  }
}
