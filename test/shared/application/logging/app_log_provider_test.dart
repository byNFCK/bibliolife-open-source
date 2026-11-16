import 'package:bibliolife/shared/application/logging/app_log_entry.dart';
import 'package:bibliolife/shared/application/logging/app_log_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initializes once with a timestamped runtime event', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final entries = container.read(appLogProvider);
    expect(entries, hasLength(1));
    expect(entries.single.category, 'App');
    expect(entries.single.message, 'Application log service initialized');
    expect(entries.single.level, AppLogLevel.info);
    expect(entries.single.timestamp.isUtc, isTrue);
  });

  test('appends timestamped entries and notifies listeners', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(appLogProvider.notifier)..clear();
    final notifications = <List<AppLogEntry>>[];
    final subscription = container.listen(appLogProvider, (_, next) {
      notifications.add(next);
    });
    addTearDown(subscription.close);

    final before = DateTime.now().toUtc();
    service.debug(category: 'Reader', message: 'drag started');
    final entry = container.read(appLogProvider).single;

    expect(entry.timestamp.isUtc, isTrue);
    expect(entry.timestamp.isBefore(before), isFalse);
    expect(entry.timestamp.isAfter(DateTime.now().toUtc()), isFalse);
    expect(entry.category, 'Reader');
    expect(entry.level, AppLogLevel.debug);
    expect(notifications, hasLength(1));
  });

  test('preserves levels, categories, and chronological copy formatting', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(appLogProvider.notifier)..clear();

    service.debug(category: 'Reader', message: 'first');
    service.info(category: 'Database', message: 'second');
    service.warning(category: 'Import', message: 'third');
    service.error(category: 'UI', message: 'fourth');

    final entries = container.read(appLogProvider);
    expect(entries.map((entry) => entry.level), [
      AppLogLevel.debug,
      AppLogLevel.info,
      AppLogLevel.warning,
      AppLogLevel.error,
    ]);
    expect(entries.map((entry) => entry.category), [
      'Reader',
      'Database',
      'Import',
      'UI',
    ]);
    expect(service.formattedText, contains('[DEBUG] [Reader] first\n'));
    expect(
      service.formattedText.indexOf('first'),
      lessThan(service.formattedText.indexOf('second')),
    );
    expect(
      service.formattedText.indexOf('second'),
      lessThan(service.formattedText.indexOf('third')),
    );
    expect(
      service.formattedText.indexOf('third'),
      lessThan(service.formattedText.indexOf('fourth')),
    );
  });

  test('bounds the buffer to 1000 and discards oldest entries', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(appLogProvider.notifier)..clear();

    for (var index = 0; index <= AppLogService.maxEntries; index++) {
      service.info(category: 'Test', message: 'entry $index');
    }

    final entries = container.read(appLogProvider);
    expect(entries, hasLength(AppLogService.maxEntries));
    expect(entries.first.message, 'entry 1');
    expect(entries.last.message, 'entry 1000');
  });
}
