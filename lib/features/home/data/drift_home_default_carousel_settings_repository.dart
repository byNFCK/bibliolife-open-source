import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/home/domain/home_default_carousel.dart';
import 'package:bibliolife/features/home/domain/home_default_carousel_settings_repository.dart';
import 'package:drift/drift.dart';

class DriftHomeDefaultCarouselSettingsRepository
    implements HomeDefaultCarouselSettingsRepository {
  const DriftHomeDefaultCarouselSettingsRepository(this._dao);

  final HomeDefaultCarouselSettingsDao _dao;

  @override
  Future<HomeDefaultCarousel> load() async {
    final stored = await _dao.load();
    final carousel = HomeDefaultCarouselPreferenceCodec.decode(
      stored?.defaultCarousel,
    );
    if (stored != null &&
        stored.defaultCarousel !=
            HomeDefaultCarouselPreferenceCodec.encode(carousel)) {
      await save(carousel);
    }
    return carousel;
  }

  @override
  Future<void> save(HomeDefaultCarousel carousel) => _dao.upsert(
    HomeDefaultCarouselSettingsEntriesCompanion.insert(
      id: const Value(1),
      defaultCarousel: HomeDefaultCarouselPreferenceCodec.encode(carousel),
    ),
  );
}
