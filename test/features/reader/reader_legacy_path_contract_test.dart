import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = _repositoryRoot();

  String source(String relativePath) => File(
    '${root.path}${Platform.pathSeparator}$relativePath',
  ).readAsStringSync();

  test('legacy full-screen EPUB Activity path is absent', () {
    expect(
      File(
        '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}bibliolife_readium${Platform.pathSeparator}android${Platform.pathSeparator}src${Platform.pathSeparator}main${Platform.pathSeparator}kotlin${Platform.pathSeparator}app${Platform.pathSeparator}bibliolife${Platform.pathSeparator}reader${Platform.pathSeparator}readium${Platform.pathSeparator}ReaderActivity.kt',
      ).existsSync(),
      isFalse,
    );

    final manifest = source(
      'packages/bibliolife_readium/android/src/main/AndroidManifest.xml',
    );
    expect(manifest, isNot(contains('ReaderActivity')));

    final plugin = source(
      'packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/BiblioLifeReadiumPlugin.kt',
    );
    expect(plugin, isNot(contains('openBook')));
    expect(plugin, isNot(contains('startActivity')));
    expect(plugin, isNot(contains('ActivityResult')));

    final exports = source(
      'packages/bibliolife_readium/lib/bibliolife_readium.dart',
    );
    expect(exports, isNot(contains('readium_reader.dart')));
    expect(exports, isNot(contains('readium_annotation_bridge.dart')));

    expect(
      File(
        '${root.path}/lib/features/reader/application/services/book_reader_service.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      source('lib/features/reader/presentation/screens/local_reader_body.dart'),
      allOf(contains('ReadiumEpubViewport'), contains('UnifiedReaderScreen')),
    );
  });

  test(
    'EPUB progress remains controller-owned rather than Activity-result-owned',
    () {
      final controller = source(
        'lib/features/reader/presentation/models/readium_epub_reader_controller.dart',
      );
      expect(controller, contains('progressRepository'));
      expect(controller, contains('save'));
      expect(controller, isNot(contains('ActivityResult')));
      expect(controller, isNot(contains('startActivity')));
    },
  );
}

Directory _repositoryRoot() {
  var directory = Directory.current;
  while (directory.parent.path != directory.path) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/packages').existsSync()) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate the BiblioLife repository root');
}
