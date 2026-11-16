import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_search.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_search_sheet.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_stable_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search focus waits for the modal entrance to complete', (
    tester,
  ) async {
    final controller = _FakeSearchController();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showReaderMenu<void>(
                context: context,
                title: 'Search',
                child: ReaderSearchSheet(controller: controller),
              ),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    var editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isFalse);

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('search disposes focus state across twenty modal cycles', (
    tester,
  ) async {
    final controller = _FakeSearchController();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showReaderMenu<void>(
                context: context,
                title: 'Search',
                child: ReaderSearchSheet(controller: controller),
              ),
              child: const Text('Open repeated search'),
            ),
          ),
        ),
      ),
    );

    for (var cycle = 0; cycle < 20; cycle++) {
      await tester.tap(find.text('Open repeated search'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      Navigator.of(tester.element(find.byType(EditableText))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
    }
  });

  test('ready results are immutable and preserve snippet segments', () {
    final source = <ReaderSearchResult>[
      const ReaderSearchResult(
        id: 'r1',
        title: 'Chapter 1',
        before: 'Перед ',
        match: 'Привіт',
        after: ' після',
      ),
    ];
    final state = ReaderSearchReady(
      query: 'Привіт',
      results: source,
      isComplete: true,
    );
    source.clear();

    expect(state.results, hasLength(1));
    expect(state.results.single.match, 'Привіт');
    expect(
      () => state.results.add(const ReaderSearchResult(id: 'r2')),
      throwsUnsupportedError,
    );
  });

  testWidgets(
    'shared search submits trimmed queries and navigates by stable ID',
    (tester) async {
      final controller = _FakeSearchController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderSearchSheet(
              controller: controller,
              debounceDuration: Duration.zero,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '  Привіт  світе  ');
      await tester.pump();
      expect(controller.queries, ['Привіт  світе']);
      expect(find.text('Chapter 1'), findsOneWidget);
      expect(find.textContaining('Match:'), findsOneWidget);

      await tester.tap(find.text('Chapter 1'));
      await tester.pump();
      expect(controller.navigatedIds, ['result-1']);
    },
  );

  testWidgets(
    'shared search keeps loading, empty, and failure states nonfatal',
    (tester) async {
      final controller = _FakeSearchController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderSearchSheet(
              controller: controller,
              debounceDuration: Duration.zero,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'term');
      await tester.pump();
      controller.setSearchState(const ReaderSearchLoading(query: 'term'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      controller.setSearchState(const ReaderSearchEmpty(query: 'term'));
      await tester.pump();
      expect(find.textContaining('No results'), findsOneWidget);

      controller.setSearchState(
        const ReaderSearchFailure(
          query: 'term',
          error: ReaderSearchError(code: 'temporary'),
        ),
      );
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(controller.queries, contains('term'));
    },
  );
}

class _FakeSearchController extends ReaderUiController {
  _FakeSearchController()
    : super(
        capabilities: const ReaderCapabilities(
          supportsTextAppearance: false,
          supportsTableOfContents: false,
          supportsBookmarks: false,
          supportsHighlights: false,
          supportsPageSeeking: false,
          supportsZoom: false,
          supportsSearch: true,
          supportsSearchResultNavigation: true,
          supportsSearchResultHighlighting: true,
        ),
      );

  final queries = <String>[];
  final navigatedIds = <String>[];

  @override
  Future<ReaderSearchCommandResult> search(String query) async {
    queries.add(query);
    setSearchState(ReaderSearchLoading(query: query));
    setSearchState(
      ReaderSearchReady(
        query: query,
        results: const [
          ReaderSearchResult(
            id: 'result-1',
            title: 'Chapter 1',
            before: 'Перед ',
            match: 'Привіт',
            after: ' після',
          ),
        ],
        isComplete: true,
      ),
    );
    return const ReaderSearchCommandResult.completed();
  }

  @override
  Future<ReaderSearchCommandResult> goToSearchResult(String resultId) async {
    navigatedIds.add(resultId);
    return const ReaderSearchCommandResult.completed();
  }
}
