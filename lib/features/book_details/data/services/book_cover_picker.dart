import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:path/path.dart' as path;

class PickedBookCover {
  const PickedBookCover({required this.bytes, required this.extension});

  final Uint8List bytes;
  final String extension;
}

abstract interface class BookCoverPicker {
  Future<PickedBookCover?> pickCover();
}

class FilePickerBookCoverPicker implements BookCoverPicker {
  const FilePickerBookCoverPicker({
    this.imageValidator = const FlutterCoverImageValidator(),
  });

  final CoverImageValidator imageValidator;

  static const allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  @override
  Future<PickedBookCover?> pickCover() async {
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
    if (bytes == null || bytes.isEmpty) throw const InvalidPickedBookCover();
    final extension = (file.extension ?? path.extension(file.name))
        .replaceFirst(RegExp(r'^\.'), '')
        .toLowerCase();
    if (!allowedExtensions.contains(extension) ||
        !await imageValidator.isDecodable(bytes)) {
      throw const InvalidPickedBookCover();
    }
    return PickedBookCover(bytes: bytes, extension: extension);
  }
}

class InvalidPickedBookCover implements Exception {
  const InvalidPickedBookCover();
}
