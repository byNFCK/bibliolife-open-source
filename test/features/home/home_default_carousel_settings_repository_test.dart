import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/home/data/drift_home_default_carousel_settings_repository.dart';
import 'package:bibliolife/features/home/domain/home_default_carousel.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftHomeDefaultCarouselSettingsRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHomeDefaultCarouselSettingsRepository(
      database.homeDefaultCarouselSettingsDao,
    );
  });

  tearDown(() => database.close());

  test('missing preference defaults to Recently opened', () async {
    expect(await repository.load(), HomeDefaultCarousel.recentlyOpened);
  });

  for (final entry in {
    'recently_opened': HomeDefaultCarousel.recentlyOpened,
    'favorites': HomeDefaultCarousel.favorites,
  }.entries) {
    test('loads stable stored value ${entry.key}', () async {
      await database.homeDefaultCarouselSettingsDao.upsert(
        HomeDefaultCarouselSettingsEntriesCompanion.insert(
          id: const Value(1),
          defaultCarousel: entry.key,
        ),
      );

      expect(await repository.load(), entry.value);
    });
  }

  test(
    'unknown stored value falls back to and repairs Recently opened',
    () async {
      await database.homeDefaultCarouselSettingsDao.upsert(
        HomeDefaultCarouselSettingsEntriesCompanion.insert(
          id: const Value(1),
          defaultCarousel: 'legacy_value',
        ),
      );

      expect(await repository.load(), HomeDefaultCarousel.recentlyOpened);
      expect(
        (await database.homeDefaultCarouselSettingsDao.load())?.defaultCarousel,
        'recently_opened',
      );
    },
  );

  for (final carousel in HomeDefaultCarousel.values) {
    test('persists ${carousel.name} across database recreation', () async {
      await database.close();
      final directory = await Directory.systemTemp.createTemp(
        'home-default-carousel-settings-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}settings.db',
      );
      final first = AppDatabase(NativeDatabase(file));
      final firstRepository = DriftHomeDefaultCarouselSettingsRepository(
        first.homeDefaultCarouselSettingsDao,
      );
      await firstRepository.save(carousel);
      await first.close();

      final reopened = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await reopened.close();
        await directory.delete(recursive: true);
      });

      expect(
        await DriftHomeDefaultCarouselSettingsRepository(
          reopened.homeDefaultCarouselSettingsDao,
        ).load(),
        carousel,
      );
    });
  }
}
