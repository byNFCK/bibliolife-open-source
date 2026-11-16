import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/reader/application/services/readium_epub_annotation_coordinator.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/domain/models/reader_bookmark.dart';
import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_saved_items_sheet.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'saved-items menu keeps title, tabs, divider, and body in canonical order',
    (tester) async {
      final controller = _SavedItemsController(
        bookmarks: List.generate(
          20,
          (index) => _bookmark(id: 'bookmark-$index'),
        ),
        annotationValues: [_annotation()],
      );
      await tester.pumpWidget(_menuHost(controller));
      await tester.tap(find.byKey(const Key('open-saved-items-menu')));
      await tester.pumpAndSettle();

      final title = find.text('Bookmarks and annotations');
      final tabs = find.byKey(
        const Key('reader-saved-items-header-segmented-control'),
      );
      final divider = find.byKey(
        const Key('reader-menu-upper-decorative-strip'),
      );
      final body = find.byKey(const Key('reader-saved-bookmarks-list'));
      final scrollBody = find.byKey(
        const Key('reader-saved-items-scroll-body'),
      );

      expect(title, findsOneWidget);
      expect(tabs, findsOneWidget);
      expect(divider, findsOneWidget);
      expect(body, findsOneWidget);
      expect(scrollBody, findsOneWidget);
      expect(
        find.byKey(const Key('reader-saved-items-switcher')),
        findsNothing,
      );
      final segmentedBefore = tester.widget<BiblioTabs<ReaderSavedItemsTab>>(
        find.byKey(const Key('reader-saved-items-segmented-control')),
      );
      expect(segmentedBefore.selectedId, ReaderSavedItemsTab.bookmarks);

      expect(
        tester.getTopLeft(tabs).dy,
        greaterThan(tester.getBottomLeft(title).dy),
      );
      expect(
        tester.getTopLeft(divider).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(tabs).dy),
      );
      expect(
        tester.getTopLeft(body).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(divider).dy),
      );

      final titleTop = tester.getTopLeft(title).dy;
      final tabsTop = tester.getTopLeft(tabs).dy;
      final dividerTop = tester.getTopLeft(divider).dy;
      await tester.drag(body, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title).dy, titleTop);
      expect(tester.getTopLeft(tabs).dy, tabsTop);
      expect(tester.getTopLeft(divider).dy, dividerTop);

      await tester.tap(find.byKey(const Key('reader-saved-annotations-tab')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('reader-saved-annotations-list')),
        findsOneWidget,
      );
      final segmented = tester.widget<BiblioTabs<ReaderSavedItemsTab>>(
        find.byKey(const Key('reader-saved-items-segmented-control')),
      );
      expect(segmented.selectedId, ReaderSavedItemsTab.annotations);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('stable saved-items tabs retain exact order and switch bodies', (
    tester,
  ) async {
    final controller = _SavedItemsController(
      bookmarks: [_bookmark()],
      annotationValues: [_annotation()],
    );
    await tester.pumpWidget(_host(controller));

    expect(
      find.byKey(const Key('reader-saved-items-switcher')),
      findsOneWidget,
    );
    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.text('Annotations'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.textContaining('Page '), findsNothing);

    await tester.tap(find.byKey(const Key('reader-saved-annotations-tab')));
    await tester.pumpAndSettle();

    expect(find.text('A selected passage'), findsOneWidget);
    expect(
      find.byKey(const Key('reader-saved-annotations-list')),
      findsOneWidget,
    );
    expect(find.textContaining('{"href"'), findsNothing);
  });

  testWidgets('saved-items tabs preserve both list scroll positions', (
    tester,
  ) async {
    final controller = _SavedItemsController(
      bookmarks: List.generate(30, (index) => _bookmark(id: 'bookmark-$index')),
      annotationValues: List.generate(
        30,
        (index) => _annotation(id: 'annotation-$index'),
      ),
    );
    await tester.pumpWidget(_host(controller));

    final bookmarks = find.byKey(const Key('reader-saved-bookmarks-list'));
    await tester.drag(bookmarks, const Offset(0, -500));
    await tester.pumpAndSettle();
    final bookmarkOffset = tester
        .state<ScrollableState>(
          find.descendant(of: bookmarks, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    expect(bookmarkOffset, greaterThan(0));

    await tester.tap(find.byKey(const Key('reader-saved-annotations-tab')));
    await tester.pump();
    final annotations = find.byKey(const Key('reader-saved-annotations-list'));
    await tester.drag(annotations, const Offset(0, -420));
    await tester.pumpAndSettle();
    final annotationOffset = tester
        .state<ScrollableState>(
          find.descendant(of: annotations, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    expect(annotationOffset, greaterThan(0));

    await tester.tap(find.byKey(const Key('reader-saved-bookmarks-tab')));
    await tester.pump();
    final restoredBookmarkOffset = tester
        .state<ScrollableState>(
          find.descendant(of: bookmarks, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    expect(restoredBookmarkOffset, bookmarkOffset);

    await tester.tap(find.byKey(const Key('reader-saved-annotations-tab')));
    await tester.pump();
    final restoredAnnotationOffset = tester
        .state<ScrollableState>(
          find.descendant(of: annotations, matching: find.byType(Scrollable)),
        )
        .position
        .pixels;
    expect(restoredAnnotationOffset, annotationOffset);
  });

  testWidgets('empty annotation state is shown only after its source loads', (
    tester,
  ) async {
    final controller = _SavedItemsController(
      bookmarks: const <LibraryBookmark>[],
      annotationValues: const <ReaderAnnotation>[],
      annotationsLoading: true,
    );
    await tester.pumpWidget(_host(controller));
    await tester.tap(find.byKey(const Key('reader-saved-annotations-tab')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller.annotations.setState(
      const ReaderAnnotationMenuState(
        annotations: <ReaderAnnotation>[],
        isLoading: false,
      ),
    );
    await tester.pump();
    expect(find.text('No annotations yet.'), findsOneWidget);
  });

  testWidgets('tapping an annotation opens its reader location', (
    tester,
  ) async {
    final controller = _SavedItemsController(
      bookmarks: [_bookmark()],
      annotationValues: [_annotation()],
    );
    await tester.pumpWidget(_menuHost(controller));
    await tester.tap(find.byKey(const Key('open-saved-items-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reader-saved-annotations-tab')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('A selected passage'));
    await tester.pumpAndSettle();

    expect(controller.annotations.openedAnnotations, ['annotation']);
    expect(find.text('Bookmarks and annotations'), findsNothing);
    expect(find.text('Edit annotation'), findsNothing);
  });

  testWidgets(
    'long-pressing an annotation opens its editor without navigating',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _SavedItemsController(
        bookmarks: [_bookmark()],
        annotationValues: [_annotation()],
      );
      await tester.pumpWidget(_menuHost(controller));
      await tester.tap(find.byKey(const Key('open-saved-items-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reader-saved-annotations-tab')));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('A selected passage'));
      await tester.pumpAndSettle();

      expect(find.text('Edit annotation'), findsOneWidget);
      expect(controller.annotations.openedAnnotations, isEmpty);
    },
  );

  testWidgets(
    'selected tab survives bookmark and annotation updates below the header',
    (tester) async {
      final controller = _SavedItemsController(
        bookmarks: [_bookmark()],
        annotationValues: const <ReaderAnnotation>[],
        annotationsLoading: true,
      );
      await tester.pumpWidget(_menuHost(controller));
      await tester.tap(find.byKey(const Key('open-saved-items-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reader-saved-annotations-tab')));
      await tester.pump();

      final divider = find.byKey(
        const Key('reader-menu-upper-decorative-strip'),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(CircularProgressIndicator)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(divider).dy),
      );

      controller.annotations.setState(
        const ReaderAnnotationMenuState(
          annotations: <ReaderAnnotation>[],
          isLoading: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No annotations yet.'), findsOneWidget);

      controller.emitBookmarkUpdate();
      await tester.pump();
      final segmented = tester.widget<BiblioTabs<ReaderSavedItemsTab>>(
        find.byKey(const Key('reader-saved-items-segmented-control')),
      );
      expect(segmented.selectedId, ReaderSavedItemsTab.annotations);

      controller.setProgress(ReaderProgressState.page(page: 2, total: 10));
      controller.toggleControls();
      controller.toggleControls();
      await tester.pump();
      final afterReaderUpdates = tester.widget<BiblioTabs<ReaderSavedItemsTab>>(
        find.byKey(const Key('reader-saved-items-segmented-control')),
      );
      expect(afterReaderUpdates.selectedId, ReaderSavedItemsTab.annotations);

      controller.annotations.setState(
        ReaderAnnotationMenuState(
          annotations: const <ReaderAnnotation>[],
          isLoading: false,
          error: StateError('load failed'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Could not load annotations.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Could not load annotations.')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(divider).dy),
      );
    },
  );

  testWidgets(
    'unsupported reader capabilities do not open a saved-items menu',
    (tester) async {
      final controller = _SavedItemsController(
        bookmarks: const <LibraryBookmark>[],
        annotationValues: const <ReaderAnnotation>[],
        capabilities: ReaderCapabilities.forKind(ReaderKind.pdf),
      );
      await tester.pumpWidget(_menuHost(controller));
      await tester.tap(find.byKey(const Key('open-saved-items-menu')));
      await tester.pump();
      expect(find.byKey(const Key('app-modal-sheet')), findsNothing);
    },
  );

  testWidgets('saved items show only bookmarks without highlight capability', (
    tester,
  ) async {
    final controller = _SavedItemsController(
      bookmarks: [_bookmark()],
      annotationValues: [_annotation()],
      capabilities: const ReaderCapabilities(
        supportsTextAppearance: false,
        supportsTableOfContents: false,
        supportsBookmarks: true,
        supportsHighlights: false,
        supportsPageSeeking: true,
        supportsZoom: false,
      ),
    );
    await tester.pumpWidget(_menuHost(controller));
    await tester.tap(find.byKey(const Key('open-saved-items-menu')));
    await tester.pumpAndSettle();
    expect(find.byType(BiblioTabs<ReaderSavedItemsTab>), findsNothing);
    expect(
      find.byKey(const Key('reader-saved-items-header-segmented-control')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reader-saved-bookmarks-list')),
      findsOneWidget,
    );
    expect(find.text('A selected passage'), findsNothing);
  });

  testWidgets('saved-items disposes retained lists across twenty cycles', (
    tester,
  ) async {
    final controller = _SavedItemsController(
      bookmarks: List.generate(20, (index) => _bookmark(id: 'bookmark-$index')),
      annotationValues: List.generate(
        20,
        (index) => _annotation(id: 'annotation-$index'),
      ),
    );
    await tester.pumpWidget(_menuHost(controller));

    for (var cycle = 0; cycle < 20; cycle++) {
      await tester.tap(find.byKey(const Key('open-saved-items-menu')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('reader-saved-bookmarks-list')),
        findsOneWidget,
      );
      Navigator.of(
        tester.element(find.byKey(const Key('app-modal-sheet'))),
      ).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-modal-sheet')), findsNothing);
    }
  });
}

Widget _menuHost(ReaderUiController controller) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          key: const Key('open-saved-items-menu'),
          onPressed: () => showReaderSavedItemsMenu<void>(
            context: context,
            controller: controller,
          ),
          child: const Text('Open saved items'),
        ),
      ),
    ),
  ),
);

Widget _host(ReaderUiController controller) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      height: 600,
      child: ReaderSavedItemsSheet(controller: controller),
    ),
  ),
);

class _SavedItemsController extends ReaderUiController {
  _SavedItemsController({
    required List<LibraryBookmark> bookmarks,
    required List<ReaderAnnotation> annotationValues,
    bool annotationsLoading = false,
    ReaderCapabilities? capabilities,
  }) : _bookmarks = ReaderBookmarkState(bookmarks: bookmarks, isLoading: false),
       annotations = _Annotations(
         ReaderAnnotationMenuState(
           annotations: annotationValues,
           isLoading: annotationsLoading,
         ),
       ),
       super(
         capabilities:
             capabilities ?? ReaderCapabilities.forKind(ReaderKind.epub),
       ) {
    annotations.addListener(notifyListeners);
  }

  final ReaderBookmarkState _bookmarks;
  final _Annotations annotations;

  @override
  ReaderBookmarkState get bookmarkState => _bookmarks;

  @override
  ReaderAnnotationMenuController get annotationMenuController => annotations;

  void emitBookmarkUpdate() => notifyListeners();
}

class _Annotations extends ChangeNotifier
    implements ReaderAnnotationMenuController {
  _Annotations(this._state);
  ReaderAnnotationMenuState _state;
  final List<String> openedAnnotations = [];

  @override
  ReaderAnnotationMenuState get annotationMenuState => _state;

  void setState(ReaderAnnotationMenuState value) {
    _state = value;
    notifyListeners();
  }

  @override
  Future<bool> deleteAnnotation(String id) async => true;

  @override
  Future<bool> openAnnotation(ReaderAnnotation annotation) async {
    openedAnnotations.add(annotation.id);
    return true;
  }

  @override
  Future<void> updateAnnotation({
    required String id,
    required String? note,
    required ReaderAnnotationStyle style,
    required ReaderAnnotationColor color,
  }) async {}
}

LibraryBookmark _bookmark({String id = 'bookmark'}) => LibraryBookmark(
  id: id,
  bookId: 'book',
  locatorJson: '{"href":"chapter.xhtml","locations":{"progression":0.5}}',
  href: 'chapter.xhtml',
  progression: .5,
  position: null,
  chapterTitle: 'Chapter 1',
  title: null,
  note: 'Note',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ReaderAnnotation _annotation({String id = 'annotation'}) => ReaderAnnotation(
  id: id,
  bookId: 'book',
  locatorJson: '{"href":"chapter.xhtml","locations":{"progression":0.5}}',
  locationKey: 'chapter',
  selectedText: id == 'annotation' ? 'A selected passage' : 'Passage $id',
  href: 'chapter.xhtml',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
