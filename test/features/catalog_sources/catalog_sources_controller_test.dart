import 'dart:async';

import 'package:bibliolife/features/catalog_sources/application/catalog_sources_controller.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = _FakeRepository();
    container = ProviderContainer(
      overrides: [catalogSourceRepositoryProvider.overrideWithValue(repository)],
    );
  });
  tearDown(() => container.dispose());

  test('initial state is idle and does not own a source list', () {
    final state = container.read(catalogSourcesControllerProvider);
    expect(state.kind, CatalogSourceMutationKind.idle);
    expect(state.failure, isNull);
  });

  test('add enters pending state, succeeds once, and returns idle', () async {
    final gate = Completer<void>();
    repository.addGate = gate;
    final controller = container.read(catalogSourcesControllerProvider.notifier);
    final pending = controller.add('Local', 'https://local.example');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(catalogSourcesControllerProvider).kind, CatalogSourceMutationKind.adding);
    expect(await controller.add('Second', 'https://second.example'), isFalse);
    expect(repository.addCalls, 1);
    gate.complete();
    expect(await pending, isTrue);
    expect(container.read(catalogSourcesControllerProvider).kind, CatalogSourceMutationKind.idle);
  });

  test('validation and repository failures are typed and clearable', () async {
    final controller = container.read(catalogSourcesControllerProvider.notifier);
    expect(await controller.add('', 'https://local.example'), isFalse);
    expect(container.read(catalogSourcesControllerProvider).failure, CatalogSourceFailure.emptyName);
    controller.clearError();
    expect(container.read(catalogSourcesControllerProvider).failure, isNull);

    repository.addError = StateError('duplicateUrl');
    expect(await controller.add('Local', 'https://local.example'), isFalse);
    expect(container.read(catalogSourcesControllerProvider).failure, CatalogSourceFailure.duplicateUrl);
  });

  test('edit, toggle and delete call one local repository mutation each', () async {
    final controller = container.read(catalogSourcesControllerProvider.notifier);
    expect(await controller.update('id', 'Renamed', 'https://local.example'), isTrue);
    expect(await controller.setEnabled('id', false), isTrue);
    expect(await controller.delete('id'), isTrue);
    expect(repository.updateCalls, 1);
    expect(repository.toggleCalls, 1);
    expect(repository.deleteCalls, 1);
  });

  test('typed built-in delete and persistence failures are surfaced', () async {
    final controller = container.read(catalogSourcesControllerProvider.notifier);
    repository.deleteError = StateError('builtInCannotBeDeleted');
    expect(await controller.delete('builtin'), isFalse);
    expect(container.read(catalogSourcesControllerProvider).failure, CatalogSourceFailure.builtInCannotBeDeleted);
    repository.deleteError = Exception('disk');
    expect(await controller.delete('custom'), isFalse);
    expect(container.read(catalogSourcesControllerProvider).failure, CatalogSourceFailure.persistenceFailure);
  });
}

class _FakeRepository implements CatalogSourceRepository {
  final _controller = StreamController<List<CatalogSource>>.broadcast();
  Completer<void>? addGate;
  Object? addError;
  Object? deleteError;
  int addCalls = 0;
  int updateCalls = 0;
  int toggleCalls = 0;
  int deleteCalls = 0;

  @override
  Stream<List<CatalogSource>> watchAll() => _controller.stream;
  @override
  Future<List<CatalogSource>> getAll() async => const [];
  @override
  Future<CatalogSource?> getById(String id) async => null;
  @override
  Future<void> ensureBuiltInSources() async {}
  @override
  Future<CatalogSource> addCustomSource({required String name, required Uri baseUri}) async {
    addCalls++;
    await addGate?.future;
    if (addError != null) throw addError!;
    return _source(id: 'id', name: name, baseUri: baseUri);
  }
  @override
  Future<void> updateCustomSource({required String id, required String name, required Uri baseUri}) async {
    updateCalls++;
  }
  @override
  Future<void> setEnabled({required String id, required bool enabled}) async { toggleCalls++; }
  @override
  Future<void> deleteCustomSource(String id) async {
    deleteCalls++;
    if (deleteError != null) throw deleteError!;
  }
  @override
  Future<bool> normalizedUrlExists(Uri uri, {String? excludingSourceId}) async => false;

  CatalogSource _source({required String id, required String name, required Uri baseUri}) => CatalogSource(
    id: id, name: name, baseUri: baseUri, type: CatalogSourceType.unknownOpds,
    isBuiltIn: false, isEnabled: true, supportsSearch: false, supportsNavigation: false,
    supportsAcquisition: false, createdAt: DateTime(2026), updatedAt: DateTime(2026),
  );
}
