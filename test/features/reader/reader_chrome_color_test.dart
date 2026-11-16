import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_stable_components.dart';
import 'package:bibliolife/features/reader/presentation/widgets/unified_reader_screen.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Page and title controls use the light reference surface', (
    tester,
  ) async {
    final controller = _ChromeController();
    await _pumpReader(tester, controller, lightTheme);

    _expectReferenceColors(tester, fallbackLightColorScheme);
    expect(tester.getSize(find.byKey(_pageKey)), const Size(112, 40));
    expect(tester.getSize(find.byKey(_titleKey)).height, 48);
    expect(find.text('Reader title'), findsOneWidget);
  });

  testWidgets('Page and title controls use the dark reference surface', (
    tester,
  ) async {
    final controller = _ChromeController();
    await _pumpReader(tester, controller, darkTheme);

    _expectReferenceColors(tester, fallbackDarkColorScheme);
  });

  testWidgets('long title keeps the existing two-line geometry and clipping', (
    tester,
  ) async {
    final controller = _ChromeController();
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: UnifiedReaderScreen(
          book: _book(
            'A very long reader title that remains constrained to two lines',
          ),
          controller: controller,
          viewport: const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(
      find.text(
        'A very long reader title that remains constrained to two lines',
      ),
    );
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.byKey(_titleKey)).height, 48);
  });

  testWidgets('Page and title controls retain their callbacks', (tester) async {
    final controller = _ChromeController();
    await _pumpReader(tester, controller, lightTheme);

    await tester.tap(find.byKey(_pageKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-modal-sheet')), findsOneWidget);
    expect(find.text('Reading progress'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_titleKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-modal-sheet')), findsOneWidget);
    expect(find.text('Table of contents'), findsOneWidget);
  });

  testWidgets('reference surfaces keep their base color while pressed', (
    tester,
  ) async {
    final controller = _ChromeController();
    await _pumpReader(tester, controller, lightTheme);

    final pageGesture = await tester.startGesture(
      tester.getCenter(find.byKey(_pageKey)),
    );
    await tester.pump();
    _expectReferenceColors(tester, fallbackLightColorScheme);
    await pageGesture.cancel();
    await tester.pumpAndSettle();

    final titleGesture = await tester.startGesture(
      tester.getCenter(find.byKey(_titleKey)),
    );
    await tester.pump();
    _expectReferenceColors(tester, fallbackLightColorScheme);
    await titleGesture.cancel();
  });

  testWidgets('opening Page and TOC preserves one native viewport state', (
    tester,
  ) async {
    final controller = _ChromeController();
    final viewportKey = GlobalKey<_StableViewportState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: UnifiedReaderScreen(
          book: _book('Reader title'),
          controller: controller,
          viewport: _StableViewport(key: viewportKey),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = viewportKey.currentState!;

    await tester.tap(find.byKey(_pageKey));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_titleKey));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(viewportKey.currentState, same(state));
    expect(state.initCount, 1);
  });

  testWidgets('theme switching updates the reference surfaces in place', (
    tester,
  ) async {
    final controller = _ChromeController();
    final viewportKey = GlobalKey<_StableViewportState>();

    Future<void> pumpWithTheme(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: UnifiedReaderScreen(
            book: _book('Reader title'),
            controller: controller,
            viewport: _StableViewport(key: viewportKey),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpWithTheme(lightTheme);
    final state = viewportKey.currentState!;
    _expectReferenceColors(tester, fallbackLightColorScheme);

    await pumpWithTheme(darkTheme);
    _expectReferenceColors(tester, fallbackDarkColorScheme);
    expect(viewportKey.currentState, same(state));
    expect(state.initCount, 1);
  });

  testWidgets('native selection removes chrome without removing the viewport', (
    tester,
  ) async {
    final controller = _ChromeController();
    await _pumpReader(tester, controller, lightTheme);

    controller.setReaderChromeSuppressed(true);
    await tester.pump();

    expect(find.byKey(_pageKey), findsNothing);
    expect(find.byKey(_titleKey), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.black,
      ),
      findsOneWidget,
    );

    controller.setReaderChromeSuppressed(false);
    await tester.pump();
    expect(find.byKey(_pageKey), findsOneWidget);
    expect(find.byKey(_titleKey), findsOneWidget);
  });
}

const _pageKey = Key('reader-page-control');
const _titleKey = Key('reader-title-toc-control');

void _expectReferenceColors(WidgetTester tester, ColorScheme scheme) {
  final page = tester.widget<Material>(find.byKey(_pageKey));
  final title = tester.widget<Material>(find.byKey(_titleKey));
  expect(
    page.color,
    ReaderChromeReferenceTokens.controlBackground(
      tester.element(find.byKey(_pageKey)),
    ),
  );
  // The Android reference uses the legacy Material3 `colorSurfaceVariant`
  // semantic role; keep this assertion explicit despite Flutter's deprecation.
  // ignore: deprecated_member_use
  expect(page.color, scheme.surfaceVariant);
  // ignore: deprecated_member_use
  expect(title.color, scheme.surfaceVariant);

  final topSurface = tester.widget<Material>(
    find
        .descendant(
          of: find.byKey(const Key('reader-top-chrome-surface')),
          matching: find.byType(Material),
        )
        .first,
  );
  final bottomSurface = tester.widget<Material>(
    find
        .descendant(
          of: find.byKey(const Key('reader-bottom-chrome-surface')),
          matching: find.byType(Material),
        )
        .first,
  );
  expect(topSurface.color, scheme.surface);
  expect(bottomSurface.color, scheme.surface);

  final pageText = tester.widget<Text>(find.text('Progress 11%'));
  final titleText = tester.widget<Text>(find.text('Reader title'));
  expect(pageText.style?.color, scheme.onSurfaceVariant);
  expect(titleText.style?.color, scheme.onSurfaceVariant);
}

Future<void> _pumpReader(
  WidgetTester tester,
  _ChromeController controller,
  ThemeData theme,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: UnifiedReaderScreen(
        book: _book('Reader title'),
        controller: controller,
        viewport: const ColoredBox(color: Colors.black),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

LibraryBook _book(String title) => LibraryBook(
  id: 'reader-chrome-test',
  title: title,
  sortTitle: null,
  author: null,
  description: null,
  filePath: '/reader-chrome-test.epub',
  fileName: 'reader-chrome-test.epub',
  fileExtension: BookFormat.epub.normalizedExtension,
  format: BookFormat.epub,
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

class _ChromeController extends ReaderUiController {
  _ChromeController()
    : super(capabilities: ReaderCapabilities.forKind(ReaderKind.epub)) {
    setProgress(ReaderProgressState.page(page: 2, total: 10));
  }

  @override
  ReaderTocController get tocController => _toc;

  static final _toc = _ChromeTocController();

  bool _readerChromeSuppressed = false;

  @override
  bool get readerChromeSuppressed => _readerChromeSuppressed;

  void setReaderChromeSuppressed(bool value) {
    _readerChromeSuppressed = value;
    notifyListeners();
  }
}

class _ChromeTocController implements ReaderTocController {
  @override
  final entries = const [ReaderTocEntry(id: 'chapter-1', title: 'Chapter 1')];

  @override
  bool get isReady => true;

  @override
  Future<void> goTo(String entryId) async {}
}

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
