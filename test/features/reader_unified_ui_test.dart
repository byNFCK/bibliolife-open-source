import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/presentation/models/local_reader_settings_adapters.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_settings_repository.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_stable_components.dart';
import 'package:bibliolife/features/reader/presentation/widgets/unified_reader_screen.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reader capabilities', () {
    test('are derived from ReaderKind instead of a filename', () {
      expect(
        ReaderCapabilities.forKind(ReaderKind.epub).supportsHighlights,
        isTrue,
      );
      expect(
        ReaderCapabilities.forKind(
          ReaderKind.reflowable,
        ).supportsTextAppearance,
        isTrue,
      );
      expect(ReaderCapabilities.forKind(ReaderKind.pdf).supportsZoom, isTrue);
      expect(
        ReaderCapabilities.forKind(ReaderKind.comic).supportsTableOfContents,
        isFalse,
      );
    });

    test('normalizes page progress and seek targets', () {
      final pdf = ReaderProgressState.page(page: 3, total: 10);
      expect(pdf.progression, closeTo(2 / 9, 0.0001));
      expect(pdf.pageFor(0.0), 1);
      expect(pdf.pageFor(1.0), 10);
      expect(pdf.pageFor(0.5), 6);
      expect(ReaderProgressState.page(page: 1, total: 1).pageFor(0.5), 1);
      expect(const ReaderProgressState.unknown().pageFor(0.5), 0);
    });
  });

  testWidgets('one chrome type wraps every Flutter reader kind', (
    tester,
  ) async {
    for (final format in [
      BookFormat.pdf,
      BookFormat.fb2,
      BookFormat.txt,
      BookFormat.cbz,
      BookFormat.cbr,
    ]) {
      final controller = ReaderUiController(
        capabilities: ReaderCapabilities.forKind(readerKindFor(format)),
      )..setProgress(ReaderProgressState.page(page: 1, total: 10));
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedReaderScreen(
            book: _book(format),
            controller: controller,
            viewport: const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Close reader'),
        findsOneWidget,
        reason: format.name,
      );
      expect(
        find.byTooltip('Reader settings'),
        findsOneWidget,
        reason: format.name,
      );
      expect(find.byTooltip('Search'), findsOneWidget, reason: format.name);
      expect(find.byTooltip('Add bookmark'), findsNothing, reason: format.name);
      expect(
        find.byTooltip('Bookmarks and annotations'),
        findsNothing,
        reason: format.name,
      );
      expect(find.text('Progress 0%'), findsOneWidget, reason: format.name);
      expect(find.textContaining('Page '), findsNothing, reason: format.name);
      expect(find.byType(Slider), findsNothing, reason: format.name);
    }
  });

  testWidgets('fixed-layout reader settings open without text settings', (
    tester,
  ) async {
    for (final format in [BookFormat.pdf, BookFormat.cbz, BookFormat.cbr]) {
      final settings = format == BookFormat.pdf
          ? PdfReaderSettingsAdapter(const EmptyReaderSettingsRepository())
          : ComicReaderSettingsAdapter(const EmptyReaderSettingsRepository());
      final controller = ReaderUiController(
        capabilities: ReaderCapabilities.forKind(readerKindFor(format)),
        settings: settings,
      )..setProgress(ReaderProgressState.page(page: 1, total: 10));
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedReaderScreen(
            book: _book(format),
            controller: controller,
            viewport: const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Reader settings'));
      await tester.pumpAndSettle();
      expect(find.text('Typography'), findsNothing);
      expect(
        find.text(format == BookFormat.pdf ? 'Page' : 'Layout'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: format.name);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      controller.dispose();
      settings.dispose();
    }
  });

  testWidgets('EPUB uses the same chrome without a Flutter pointer overlay', (
    tester,
  ) async {
    final controller = ReaderUiController(
      capabilities: ReaderCapabilities.forKind(ReaderKind.epub),
    )..setProgress(ReaderProgressState.reflowable(progression: .4));
    expect(controller.capabilities.supportsNativeContentTap, isTrue);
    final viewportKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedReaderScreen(
          book: _book(BookFormat.epub),
          controller: controller,
          viewport: ColoredBox(key: viewportKey, color: Colors.black),
        ),
      ),
    );
    expect(find.byTooltip('Close reader'), findsOneWidget);
    expect(find.byTooltip('Reader settings'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.text('Progress 40%'), findsOneWidget);
    expect(find.textContaining('Page '), findsNothing);
    expect(find.byType(Slider), findsNothing);
    controller.setProgress(ReaderProgressState.reflowable(progression: .44));
    await tester.pump();
    expect(find.text('Progress 44%'), findsOneWidget);
    expect(find.textContaining('Page '), findsNothing);
    expect(
      find.ancestor(
        of: find.byKey(viewportKey),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Listener &&
              widget.behavior == HitTestBehavior.translucent,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'EPUB paginated progress shows only global Progress and updates',
    (tester) async {
      final controller =
          ReaderUiController(
            capabilities: ReaderCapabilities.forKind(ReaderKind.epub),
          )..setProgress(
            ReaderProgressState.renderedPage(
              pageIndex: 0,
              pageCount: 50,
              progression: .17,
              publicationScoped: false,
            ),
          );
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedReaderScreen(
            book: _book(BookFormat.epub),
            controller: controller,
            viewport: const ColoredBox(color: Colors.black),
          ),
        ),
      );
      expect(find.text('Progress 17%'), findsOneWidget);
      expect(find.textContaining('Page '), findsNothing);

      controller.setProgress(
        ReaderProgressState.renderedPage(
          pageIndex: 1,
          pageCount: 50,
          progression: .44,
          publicationScoped: false,
        ),
      );
      await tester.pump();
      expect(find.text('Progress 44%'), findsOneWidget);
      expect(find.textContaining('Page '), findsNothing);
    },
  );

  testWidgets('native EPUB loading does not cover or block its viewport', (
    tester,
  ) async {
    final controller = ReaderUiController(
      capabilities: ReaderCapabilities.forKind(ReaderKind.epub),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedReaderScreen(
          book: _book(BookFormat.epub),
          controller: controller,
          viewport: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    expect(controller.isLoading, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shared chrome is bounded to the top and bottom safe areas', (
    tester,
  ) async {
    final controller = ReaderUiController(
      capabilities: ReaderCapabilities.forKind(ReaderKind.epub),
    )..setProgress(ReaderProgressState.reflowable(progression: .4));
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedReaderScreen(
          book: _book(BookFormat.epub),
          controller: controller,
          viewport: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewportSize = tester.getSize(find.byType(Scaffold));
    final topToolbar = tester.getRect(find.byTooltip('Close reader'));
    final bottomPill = tester.getRect(find.text('Progress 40%'));
    expect(topToolbar.top, lessThan(viewportSize.height * .25));
    expect(bottomPill.center.dy, greaterThan(viewportSize.height * .6));
    expect(bottomPill.bottom, greaterThan(viewportSize.height - 100));
  });

  testWidgets('a central tap hides and restores both shared chrome surfaces', (
    tester,
  ) async {
    final controller = ReaderUiController(
      capabilities: ReaderCapabilities.forKind(ReaderKind.pdf),
    )..setProgress(ReaderProgressState.page(page: 1, total: 10));
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedReaderScreen(
          book: _book(BookFormat.pdf),
          controller: controller,
          viewport: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 250));
    expect(controller.controlsVisible, isFalse);
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 250));
    expect(controller.controlsVisible, isTrue);
  });

  testWidgets('viewport state survives chrome visibility changes', (
    tester,
  ) async {
    final controller = ReaderUiController(
      capabilities: ReaderCapabilities.forKind(ReaderKind.pdf),
    )..setProgress(ReaderProgressState.page(page: 1, total: 2));
    final key = GlobalKey<_StableViewportState>();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedReaderScreen(
          book: _book(BookFormat.pdf),
          controller: controller,
          viewport: _StableViewport(key: key),
        ),
      ),
    );
    final state = key.currentState!;
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 250));
    expect(key.currentState, same(state));
    expect(state.initCount, 1);
  });

  testWidgets('native chrome toggles keep viewport geometry stable', (
    tester,
  ) async {
    final controller = ReaderUiController(
      capabilities: ReaderCapabilities.forKind(ReaderKind.epub),
    )..setProgress(ReaderProgressState.progression(progression: .5));
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedReaderScreen(
          book: _book(BookFormat.epub),
          controller: controller,
          viewport: ColoredBox(key: key, color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byKey(key));

    controller.toggleControls();
    await tester.pump(const Duration(milliseconds: 250));
    final hidden = tester.getRect(find.byKey(key));
    controller.toggleControls();
    await tester.pump(const Duration(milliseconds: 250));
    final restored = tester.getRect(find.byKey(key));

    expect(hidden, before);
    expect(restored, before);
  });

  testWidgets('stable shared chrome uses the floating rounded-card contract', (
    tester,
  ) async {
    final controller = ReaderUiController(
      capabilities: ReaderCapabilities.forKind(ReaderKind.epub),
    )..setProgress(ReaderProgressState.progression(progression: .5));
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedReaderScreen(
          book: _book(BookFormat.epub),
          controller: controller,
          viewport: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    expect(find.byTooltip('Close reader'), findsOneWidget);
    expect(find.byType(ReaderStableChromeSurface), findsNWidgets(2));
  });
}

LibraryBook _book(BookFormat format) => LibraryBook(
  id: format.name,
  title: 'Reader title',
  sortTitle: null,
  author: null,
  description: null,
  filePath: '/book.${format.normalizedExtension}',
  fileName: 'book.${format.normalizedExtension}',
  fileExtension: format.normalizedExtension,
  format: format,
  mediaType: null,
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 0,
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
);

class _StableViewport extends StatefulWidget {
  const _StableViewport({required super.key});
  @override
  State<_StableViewport> createState() => _StableViewportState();
}

class _StableViewportState extends State<_StableViewport> {
  var initCount = 0;
  @override
  void initState() {
    super.initState();
    initCount++;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}
