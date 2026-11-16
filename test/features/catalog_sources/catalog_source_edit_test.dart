import 'dart:async';

import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_source_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Edit form prefills a resolved custom source and Cancel does not mutate',
    (tester) async {
      final repository = _ControlledRepository(_source());
      await tester.pumpWidget(_editApp(repository));
      await _openEditForm(tester);

      expect(find.text('Edit library'), findsOneWidget);
      expect(find.text('Edit Test Library'), findsOneWidget);
      expect(find.text('https://edit.example/opds'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Open edit form'), findsOneWidget);
      expect(repository.updateCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Edit Save blocks duplicate submit and pops exactly once', (
    tester,
  ) async {
    final repository = _PendingUpdateRepository(_source());
    final navigatorObserver = _CountingNavigatorObserver();
    await tester.pumpWidget(_editApp(repository, observer: navigatorObserver));
    await _openEditForm(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Renamed Library',
    );

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(repository.updateCalls, 1);
    expect(repository.lastUpdatedId, 'edit-source');
    expect(repository.lastUpdatedName, 'Renamed Library');
    expect(repository.lastUpdatedUri.toString(), 'https://edit.example/opds');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Save'), warnIfMissed: false);
    await tester.pump();
    expect(repository.updateCalls, 1);
    expect(navigatorObserver.popCalls, 0);

    repository.completeUpdate();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Open edit form'), findsOneWidget);
    expect(repository.updateCalls, 1);
    expect(navigatorObserver.popCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

Widget _editApp(
  CatalogSourceRepository repository, {
  NavigatorObserver? observer,
}) => ProviderScope(
  overrides: [catalogSourceRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    navigatorObservers: [?observer],
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const CatalogSourceFormScreen(sourceId: 'edit-source'),
              ),
            ),
            child: const Text('Open edit form'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _openEditForm(WidgetTester tester) async {
  await tester.tap(find.text('Open edit form'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

CatalogSource _source() => CatalogSource(
  id: 'edit-source',
  name: 'Edit Test Library',
  baseUri: Uri.parse('https://edit.example/opds'),
  type: CatalogSourceType.unknownOpds,
  isBuiltIn: false,
  isEnabled: true,
  supportsSearch: false,
  supportsNavigation: false,
  supportsAcquisition: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _ControlledRepository implements CatalogSourceRepository {
  _ControlledRepository(this.source);

  final CatalogSource source;
  int updateCalls = 0;

  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value([source]);

  @override
  Future<List<CatalogSource>> getAll() async => [source];

  @override
  Future<CatalogSource?> getById(String id) async =>
      id == source.id ? source : null;

  @override
  Future<void> updateCustomSource({
    required String id,
    required String name,
    required Uri baseUri,
  }) async {
    updateCalls++;
  }

  @override
  Future<bool> normalizedUrlExists(
    Uri uri, {
    String? excludingSourceId,
  }) async => false;

  @override
  Future<void> ensureBuiltInSources() async {}

  @override
  Future<CatalogSource> addCustomSource({
    required String name,
    required Uri baseUri,
  }) => throw StateError('unexpected mutation');

  @override
  Future<void> setEnabled({required String id, required bool enabled}) =>
      throw StateError('unexpected mutation');

  @override
  Future<void> deleteCustomSource(String id) =>
      throw StateError('unexpected mutation');
}

class _PendingUpdateRepository extends _ControlledRepository {
  _PendingUpdateRepository(super.source);

  final _updateCompleter = Completer<void>();
  String? lastUpdatedId;
  String? lastUpdatedName;
  Uri? lastUpdatedUri;

  @override
  Future<void> updateCustomSource({
    required String id,
    required String name,
    required Uri baseUri,
  }) {
    updateCalls++;
    lastUpdatedId = id;
    lastUpdatedName = name;
    lastUpdatedUri = baseUri;
    return _updateCompleter.future;
  }

  void completeUpdate() => _updateCompleter.complete();
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int popCalls = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCalls++;
    super.didPop(route, previousRoute);
  }
}
