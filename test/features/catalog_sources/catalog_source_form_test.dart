import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_source_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('add form validates local input and preserves it after failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
        ],
        child: const MaterialApp(home: CatalogSourceFormScreen()),
      ),
    );
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Catalog URL'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('Enter a library name'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Local');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Catalog URL'),
      'http://example.org',
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('Use an HTTPS URL.'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('http://example.org'), findsOneWidget);
  });
}

class _Repository implements CatalogSourceRepository {
  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value(const []);
  @override
  Future<List<CatalogSource>> getAll() async => const [];
  @override
  Future<CatalogSource?> getById(String id) async => null;
  @override
  Future<void> ensureBuiltInSources() async {}
  @override
  Future<CatalogSource> addCustomSource({
    required String name,
    required Uri baseUri,
  }) => throw UnimplementedError();
  @override
  Future<void> updateCustomSource({
    required String id,
    required String name,
    required Uri baseUri,
  }) => throw UnimplementedError();
  @override
  Future<void> setEnabled({required String id, required bool enabled}) async {}
  @override
  Future<void> deleteCustomSource(String id) async {}
  @override
  Future<bool> normalizedUrlExists(
    Uri uri, {
    String? excludingSourceId,
  }) async => false;
}
