import 'package:bibliolife/features/home/domain/home_default_carousel.dart';

abstract interface class HomeDefaultCarouselSettingsRepository {
  Future<HomeDefaultCarousel> load();

  Future<void> save(HomeDefaultCarousel carousel);
}
