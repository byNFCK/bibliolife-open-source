import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class CoverStorageService {
  CoverStorageService({
    Future<Directory> Function()? documentsDirectory,
    CoverImageValidator? imageValidator,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _imageValidator = imageValidator ?? const FlutterCoverImageValidator();

  final Future<Directory> Function() _documentsDirectory;
  final CoverImageValidator _imageValidator;
  final Map<String, Future<bool>> _validityChecks = {};

  Future<bool> hasValidStoredCover(String? coverPath) async {
    if (coverPath == null || coverPath.trim().isEmpty) return false;
    return _validityChecks.putIfAbsent(
      coverPath,
      () => _validateStoredCover(coverPath),
    );
  }

  Future<bool> _validateStoredCover(String coverPath) async {
    try {
      final file = File(coverPath);
      if (!await file.exists()) return false;
      return _imageValidator.isDecodable(await file.readAsBytes());
    } on FileSystemException {
      return false;
    }
  }

  Future<String?> storeValidatedCover({
    required String bookId,
    required Uint8List bytes,
    String? extension,
  }) async {
    return _storeValidated(
      relativeDirectory: 'covers',
      key: bookId,
      bytes: bytes,
      extension: extension,
    );
  }

  Future<String?> storeValidatedCollectionCover({
    required String collectionKey,
    required Uint8List bytes,
    String? extension,
  }) => _storeValidated(
    relativeDirectory: path.join('collections', 'covers'),
    key: collectionKey,
    bytes: bytes,
    extension: extension,
  );

  Future<String> storeCover({
    required String bookId,
    required Uint8List bytes,
    required String extension,
  }) async {
    return _storeCover(
      relativeDirectory: 'covers',
      key: bookId,
      bytes: bytes,
      extension: extension,
    );
  }

  Future<String?> _storeValidated({
    required String relativeDirectory,
    required String key,
    required Uint8List bytes,
    String? extension,
  }) async {
    if (bytes.isEmpty || !await _imageValidator.isDecodable(bytes)) {
      return null;
    }
    return _storeCover(
      relativeDirectory: relativeDirectory,
      key: key,
      bytes: bytes,
      extension: extension ?? _extensionFor(bytes),
    );
  }

  Future<String> _storeCover({
    required String relativeDirectory,
    required String key,
    required Uint8List bytes,
    required String extension,
  }) async {
    final normalizedExtension = extension.toLowerCase().replaceFirst(
      RegExp(r'^\.+'),
      '',
    );
    if (!const {
      'jpg',
      'jpeg',
      'png',
      'webp',
      'gif',
    }.contains(normalizedExtension)) {
      throw ArgumentError.value(extension, 'extension');
    }
    final targetDirectory = Directory(
      path.join((await _documentsDirectory()).path, relativeDirectory),
    );
    await targetDirectory.create(recursive: true);
    final destination = File(
      path.join(targetDirectory.path, '$key.$normalizedExtension'),
    );
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      _validityChecks[destination.path] = Future.value(true);
      return destination.path;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> deleteStoredCover(String? coverPath) async {
    if (coverPath == null) return;
    _validityChecks.remove(coverPath);
    final file = File(coverPath);
    if (await file.exists()) await file.delete();
  }

  Future<bool> isManagedManualBookCoverPath({
    required String? coverPath,
    required String bookId,
  }) async {
    if (coverPath == null || coverPath.trim().isEmpty) return false;
    try {
      final directory = Directory(
        path.join((await _documentsDirectory()).path, 'covers'),
      );
      final file = File(coverPath);
      if (!await directory.exists() || !await file.exists()) return false;
      final resolvedDirectory = await directory.resolveSymbolicLinks();
      final resolvedFile = await file.resolveSymbolicLinks();
      if (!path.isWithin(resolvedDirectory, resolvedFile)) return false;
      final basename = path.basename(resolvedFile);
      if (!basename.startsWith('$bookId-manual-')) return false;
      final extension = path
          .extension(basename)
          .replaceFirst('.', '')
          .toLowerCase();
      return const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension);
    } on FileSystemException {
      return false;
    }
  }

  String _extensionFor(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return 'jpg';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    // The extension is only a local filename hint. The decoder validation
    // above remains authoritative for uncommon supported image formats.
    return 'png';
  }
}

abstract interface class CoverImageValidator {
  Future<bool> isDecodable(Uint8List bytes);
}

class FlutterCoverImageValidator implements CoverImageValidator {
  const FlutterCoverImageValidator();

  @override
  Future<bool> isDecodable(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
      return true;
    } on Object {
      return false;
    }
  }
}
