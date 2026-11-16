import 'package:bibliolife/features/home/application/providers/home_default_carousel_provider.dart';
import 'package:bibliolife/features/home/domain/home_default_carousel_settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider updates reactively and persists the selected value', () async {
    final repository = _MemoryHomeDefaultCarouselSettingsRepository();
    final container = ProviderContainer(
      overrides: [
        homeDefaultCarouselSettingsRepositoryProvider.overrideWithValue(
          repository,
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(defaultHomeCarouselProvider.future),
      HomeDefaultCarousel.recentlyOpened,
    );

    await container
        .read(defaultHomeCarouselProvider.notifier)
        .setDefault(HomeDefaultCarousel.favorites);

    expect(
      container.read(defaultHomeCarouselProvider),
      const AsyncData(HomeDefaultCarousel.favorites),
    );
    expect(repository.value, HomeDefaultCarousel.favorites);
  });
}

class _MemoryHomeDefaultCarouselSettingsRepository
    implements HomeDefaultCarouselSettingsRepository {
  HomeDefaultCarousel value = HomeDefaultCarousel.recentlyOpened;

  @override
  Future<HomeDefaultCarousel> load() async => value;

  @override
  Future<void> save(HomeDefaultCarousel carousel) async => value = carousel;
}
