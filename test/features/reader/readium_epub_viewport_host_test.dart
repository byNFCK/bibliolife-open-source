import 'dart:async';

import 'package:bibliolife/features/reader/domain/models/epub_reader_settings.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/features/reader/domain/repositories/epub_reader_settings_repository.dart';
import 'package:bibliolife/features/reader/domain/repositories/reading_progress_repository.dart';
import 'package:bibliolife/features/reader/presentation/models/readium_epub_reader_controller.dart';
import 'package:bibliolife/features/reader/presentation/screens/local_reader_body.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows the PlatformView after asynchronous adapter initialization',
    (tester) async {
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (configuration) => ReadiumEpubController(
          configuration: configuration,
          client: _FakeClient(),
        ),
      );
      var nativeViewCreations = 0;
      var nativeViewBuilds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ReadiumEpubViewportHost(
            adapter: adapter,
            platformViewBuilder: (context, configuration, onCreated) =>
                _CreationProbe(
                  onCreated: () => nativeViewCreations++,
                  onBuild: () => nativeViewBuilds++,
                ),
          ),
        ),
      );
      expect(find.byType(_CreationProbe), findsNothing);

      await adapter.initialize();
      await tester.pump();

      expect(find.byType(_CreationProbe), findsOneWidget);
      expect(nativeViewCreations, 1);
      expect(nativeViewBuilds, 1);

      adapter.notifyListeners();
      await tester.pump();
      expect(find.byType(_CreationProbe), findsOneWidget);
      expect(nativeViewCreations, 1);
      expect(nativeViewBuilds, 1);

      adapter.dispose();
    },
  );

  testWidgets('replaces the PlatformView when the adapter session changes', (
    tester,
  ) async {
    final firstClient = _FakeClient();
    final secondClient = _FakeClient();
    ReadiumEpubReaderController adapter(_FakeClient client) =>
        ReadiumEpubReaderController(
          book: _book(),
          progressRepository: _ProgressRepository(),
          settingsRepository: _SettingsRepository(),
          controllerBuilder: (configuration) => ReadiumEpubController(
            configuration: configuration,
            client: client,
          ),
        );
    final sessions = await tester.runAsync(() async {
      final first = adapter(firstClient);
      final second = adapter(secondClient);
      await first.initialize();
      await second.initialize();
      return (first, second);
    });
    final (first, second) = sessions!;
    var nativeViewCreations = 0;

    Widget host(ReadiumEpubReaderController value) => MaterialApp(
      home: ReadiumEpubViewportHost(
        adapter: value,
        platformViewBuilder: (context, configuration, onCreated) =>
            _CreationProbe(
              onCreated: () => nativeViewCreations++,
              onBuild: () {},
            ),
      ),
    );

    await tester.pumpWidget(host(first));
    expect(nativeViewCreations, 1);
    await tester.pumpWidget(host(second));
    expect(nativeViewCreations, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await first.disposeAndWait();
      await second.disposeAndWait();
    });
  });
}

class _CreationProbe extends StatefulWidget {
  const _CreationProbe({required this.onCreated, required this.onBuild});

  final VoidCallback onCreated;
  final VoidCallback onBuild;

  @override
  State<_CreationProbe> createState() => _CreationProbeState();
}

class _CreationProbeState extends State<_CreationProbe> {
  @override
  void initState() {
    super.initState();
    widget.onCreated();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return const SizedBox.expand();
  }
}

class _ProgressRepository implements ReadingProgressRepository {
  @override
  Future<ReadingProgress?> getForBook(String bookId) async => null;

  @override
  Future<void> save(ReadingProgress progress) async {}

  @override
  Future<void> deleteForBook(String bookId) async {}

  @override
  Stream<List<ReadingProgress>> watchAll() => Stream.value(const []);

  @override
  Stream<ReadingProgress?> watchForBook(String bookId) => Stream.value(null);
}

class _SettingsRepository implements EpubReaderSettingsRepository {
  @override
  Future<EpubReaderSettings> load() async => EpubReaderSettings.defaults;

  @override
  Future<void> save(EpubReaderSettings settings) async {}

  @override
  Future<void> reset() async {}
}

class _FakeClient implements ReadiumBridgeClient {
  @override
  Stream<ReadiumReaderEvent> get events => const Stream.empty();

  @override
  Future<void> attachToPlatform() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future.value(const ReadiumNavigationResult('completed'));
}

LibraryBook _book() => LibraryBook(
  id: 'host-book',
  title: 'Host book',
  sortTitle: null,
  author: null,
  description: null,
  filePath: r'C:\books\host-book.epub',
  fileName: 'host-book.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: null,
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 1,
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
);
