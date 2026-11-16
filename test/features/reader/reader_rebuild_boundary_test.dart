import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/presentation/widgets/unified_reader_screen.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'chrome progress and menu animation keep viewport subtree stable',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ReaderUiController(
        capabilities: ReaderCapabilities.forKind(ReaderKind.pdf),
      )..setProgress(ReaderProgressState.page(page: 2, total: 10));
      var viewportBuilds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedReaderScreen(
            book: _book,
            controller: controller,
            viewport: _BuildProbe(onBuild: () => viewportBuilds++),
          ),
        ),
      );
      expect(viewportBuilds, 1);

      controller.toggleControls();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(viewportBuilds, 1);

      controller
        ..showControls()
        ..setProgress(ReaderProgressState.page(page: 3, total: 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Progress 22%'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(viewportBuilds, 1);

      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel'))
          .onPressed!();
      await tester.pumpAndSettle();
      expect(viewportBuilds, 1);
      controller.dispose();
    },
  );

  test('identical progress snapshots do not notify twice', () {
    final controller = ReaderUiController(
      capabilities: ReaderCapabilities.forKind(ReaderKind.pdf),
    );
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.setProgress(ReaderProgressState.page(page: 2, total: 10));
    controller.setProgress(ReaderProgressState.page(page: 2, total: 10));
    expect(notifications, 1);
    controller.dispose();
  });

  testWidgets('keyboard insets do not resize the reader viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ReaderUiController(
      capabilities: ReaderCapabilities.forKind(ReaderKind.pdf),
    );

    Widget readerWithInsets(double bottom) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: bottom)),
        child: UnifiedReaderScreen(
          book: _book,
          controller: controller,
          viewport: const ColoredBox(color: Colors.black),
        ),
      ),
    );

    await tester.pumpWidget(readerWithInsets(0));
    final viewport = find.byKey(const Key('reader-stable-viewport-boundary'));
    final before = tester.getRect(viewport);
    await tester.pumpWidget(readerWithInsets(320));
    await tester.pump();
    final after = tester.getRect(viewport);

    expect(after, before);
    controller.dispose();
  });
}

class _BuildProbe extends StatelessWidget {
  const _BuildProbe({required this.onBuild});
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const ColoredBox(color: Colors.black);
  }
}

final _book = LibraryBook(
  id: 'book',
  title: 'Book',
  sortTitle: null,
  author: null,
  description: null,
  filePath: '/book.pdf',
  fileName: 'book.pdf',
  fileExtension: 'pdf',
  format: BookFormat.pdf,
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
