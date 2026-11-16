enum HomeDefaultCarousel { recentlyOpened, favorites }

abstract final class HomeDefaultCarouselPreferenceCodec {
  static String encode(HomeDefaultCarousel carousel) => switch (carousel) {
    HomeDefaultCarousel.recentlyOpened => 'recently_opened',
    HomeDefaultCarousel.favorites => 'favorites',
  };

  static HomeDefaultCarousel decode(String? value) => switch (value) {
    'recently_opened' => HomeDefaultCarousel.recentlyOpened,
    'favorites' => HomeDefaultCarousel.favorites,
    _ => HomeDefaultCarousel.recentlyOpened,
  };
}
