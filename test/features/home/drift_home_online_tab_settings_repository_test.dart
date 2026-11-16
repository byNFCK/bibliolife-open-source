import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/home/data/drift_home_online_tab_settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftHomeOnlineTabSettingsRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHomeOnlineTabSettingsRepository(database);
  });
  tearDown(() => database.close());

  test(
    'Home visibility persists independently and ignores unknown IDs',
    () async {
      await repository.setVisible(
        sourceId: builtInCatalogSources.first.id,
        visible: false,
      );
      await repository.setVisible(sourceId: 'removed-source', visible: false);

      final values = await repository.watchVisibility().first;

      expect(values, {builtInCatalogSources.first.id: false});
      expect(values['removed-source'], isNull);
    },
  );
}
