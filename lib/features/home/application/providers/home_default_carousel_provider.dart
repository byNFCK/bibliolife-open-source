import 'dart:async';

import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/home/data/drift_home_default_carousel_settings_repository.dart';
import 'package:bibliolife/features/home/domain/home_default_carousel.dart';
import 'package:bibliolife/features/home/domain/home_default_carousel_settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:bibliolife/features/home/domain/home_default_carousel.dart';

final homeDefaultCarouselSettingsRepositoryProvider =
    Provider<HomeDefaultCarouselSettingsRepository>(
      (ref) => DriftHomeDefaultCarouselSettingsRepository(
        ref.watch(appDatabaseProvider).homeDefaultCarouselSettingsDao,
      ),
    );

final defaultHomeCarouselProvider =
    AsyncNotifierProvider<DefaultHomeCarouselNotifier, HomeDefaultCarousel>(
      DefaultHomeCarouselNotifier.new,
    );

class DefaultHomeCarouselNotifier extends AsyncNotifier<HomeDefaultCarousel> {
  @override
  FutureOr<HomeDefaultCarousel> build() =>
      ref.read(homeDefaultCarouselSettingsRepositoryProvider).load();

  Future<void> setDefault(HomeDefaultCarousel carousel) async {
    final previous = state;
    state = AsyncData(carousel);
    try {
      await ref
          .read(homeDefaultCarouselSettingsRepositoryProvider)
          .save(carousel);
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
