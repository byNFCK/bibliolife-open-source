import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/catalog_source_url_normalizer.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CatalogSourceMutationKind { idle, adding, updating, deleting, toggling }

class CatalogSourceMutationState {
  const CatalogSourceMutationState({
    this.kind = CatalogSourceMutationKind.idle,
    this.failure,
  });
  final CatalogSourceMutationKind kind;
  final CatalogSourceFailure? failure;
}

final catalogSourcesControllerProvider =
    NotifierProvider<CatalogSourcesController, CatalogSourceMutationState>(
      CatalogSourcesController.new,
    );

class CatalogSourcesController extends Notifier<CatalogSourceMutationState> {
  @override
  CatalogSourceMutationState build() => const CatalogSourceMutationState();

  Future<bool> add(String name, String url) => _save(
    kind: CatalogSourceMutationKind.adding,
    name: name,
    url: url,
    save: (repository, normalizedName, baseUri) =>
        repository.addCustomSource(name: normalizedName, baseUri: baseUri),
  );

  Future<bool> update(String id, String name, String url) => _save(
    kind: CatalogSourceMutationKind.updating,
    name: name,
    url: url,
    excludingSourceId: id,
    save: (repository, normalizedName, baseUri) => repository
        .updateCustomSource(id: id, name: normalizedName, baseUri: baseUri),
  );

  Future<bool> setEnabled(String id, bool enabled) => _mutate(
    CatalogSourceMutationKind.toggling,
    () => ref
        .read(catalogSourceRepositoryProvider)
        .setEnabled(id: id, enabled: enabled),
  );

  Future<bool> delete(String id) => _mutate(
    CatalogSourceMutationKind.deleting,
    () => ref.read(catalogSourceRepositoryProvider).deleteCustomSource(id),
  );

  Future<bool> _save({
    required CatalogSourceMutationKind kind,
    required String name,
    required String url,
    required Future<void> Function(
      CatalogSourceRepository repository,
      String name,
      Uri baseUri,
    )
    save,
    String? excludingSourceId,
  }) async {
    if (!_begin(kind)) return false;
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      state = const CatalogSourceMutationState(
        failure: CatalogSourceFailure.emptyName,
      );
      return false;
    }
    final parsed = CatalogSourceUrlNormalizer.normalize(url);
    if (!parsed.isValid) {
      state = CatalogSourceMutationState(failure: _urlFailure(parsed.failure));
      return false;
    }
    final repository = ref.read(catalogSourceRepositoryProvider);
    if (await repository.normalizedUrlExists(
      parsed.uri!,
      excludingSourceId: excludingSourceId,
    )) {
      state = const CatalogSourceMutationState(
        failure: CatalogSourceFailure.duplicateUrl,
      );
      return false;
    }
    state = CatalogSourceMutationState(kind: kind);
    try {
      await save(repository, normalizedName, parsed.uri!);
      state = const CatalogSourceMutationState();
      return true;
    } catch (error) {
      state = CatalogSourceMutationState(failure: _repositoryFailure(error));
      return false;
    }
  }

  Future<bool> _mutate(
    CatalogSourceMutationKind kind,
    Future<void> Function() mutation,
  ) async {
    if (!_begin(kind)) return false;
    state = CatalogSourceMutationState(kind: kind);
    try {
      await mutation();
      state = const CatalogSourceMutationState();
      return true;
    } catch (error) {
      state = CatalogSourceMutationState(failure: _repositoryFailure(error));
      return false;
    }
  }

  bool _begin(CatalogSourceMutationKind kind) {
    if (state.kind == CatalogSourceMutationKind.idle) return true;
    state = const CatalogSourceMutationState(
      failure: CatalogSourceFailure.operationAlreadyInProgress,
    );
    return false;
  }

  void clearError() => state = const CatalogSourceMutationState();

  CatalogSourceFailure _repositoryFailure(Object error) {
    final message = error is StateError ? error.message.toString() : '';
    return switch (message) {
      'duplicateUrl' => CatalogSourceFailure.duplicateUrl,
      'sourceNotFound' => CatalogSourceFailure.sourceNotFound,
      'builtInImmutable' => CatalogSourceFailure.builtInImmutable,
      'builtInCannotBeDeleted' => CatalogSourceFailure.builtInCannotBeDeleted,
      _ => CatalogSourceFailure.persistenceFailure,
    };
  }

  CatalogSourceFailure _urlFailure(CatalogSourceUrlFailure? failure) =>
      switch (failure) {
        CatalogSourceUrlFailure.emptyUrl => CatalogSourceFailure.emptyUrl,
        CatalogSourceUrlFailure.insecureHttp =>
          CatalogSourceFailure.insecureHttp,
        CatalogSourceUrlFailure.missingHost => CatalogSourceFailure.missingHost,
        CatalogSourceUrlFailure.unsupportedScheme =>
          CatalogSourceFailure.unsupportedScheme,
        _ => CatalogSourceFailure.malformedUrl,
      };
}
