import 'dart:io';
import 'dart:typed_data';

import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stored-cover validity is coalesced instead of decoding repeatedly',
    () async {
      final root = await Directory.systemTemp.createTemp('cover-validity-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}${Platform.pathSeparator}cover.png');
      await file.writeAsBytes([1, 2, 3]);
      final validator = _CountingValidator();
      final storage = CoverStorageService(
        documentsDirectory: () async => root,
        imageValidator: validator,
      );

      expect(await storage.hasValidStoredCover(file.path), isTrue);
      expect(await storage.hasValidStoredCover(file.path), isTrue);

      expect(validator.calls, 1);
    },
  );

  test(
    'malformed and zero-byte covers are rejected before persistence',
    () async {
      final root = await Directory.systemTemp.createTemp('cover-invalid-');
      addTearDown(() => root.delete(recursive: true));
      final storage = CoverStorageService(documentsDirectory: () async => root);

      expect(
        await storage.storeValidatedCover(
          bookId: 'malformed',
          bytes: Uint8List.fromList(const [0x3c, 0x68, 0x74, 0x6d, 0x6c, 0x3e]),
          extension: 'jpg',
        ),
        isNull,
      );
      expect(
        await storage.storeValidatedCover(
          bookId: 'empty',
          bytes: Uint8List(0),
          extension: 'png',
        ),
        isNull,
      );
      expect(await root.list(recursive: true).toList(), isEmpty);
    },
  );
}

class _CountingValidator implements CoverImageValidator {
  var calls = 0;

  @override
  Future<bool> isDecodable(Uint8List bytes) async {
    calls++;
    return true;
  }
}
