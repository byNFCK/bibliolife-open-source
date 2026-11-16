import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

class PickedCollectionCover {
  const PickedCollectionCover({required this.bytes, required this.extension});

  final Uint8List bytes;
  final String extension;
}

abstract interface class CollectionCoverPicker {
  Future<PickedCollectionCover?> pickCover();
}

class FilePickerCollectionCoverPicker implements CollectionCoverPicker {
  const FilePickerCollectionCoverPicker();

  static const allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  @override
  Future<PickedCollectionCover?> pickCover() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return null;

    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) return null;
    final extension = (file.extension ?? path.extension(file.name))
        .replaceFirst(RegExp(r'^\.+'), '')
        .toLowerCase();
    if (!allowedExtensions.contains(extension)) return null;
    return PickedCollectionCover(bytes: bytes, extension: extension);
  }
}
