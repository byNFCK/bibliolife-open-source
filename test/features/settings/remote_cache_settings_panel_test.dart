import 'dart:async';

import 'package:bibliolife/features/catalog_sources/application/remote_cache_settings_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_settings_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_cache_budget.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_body.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows and persists all three online-cache choices', (
    tester,
  ) async {
    final repository = _FakeRepository();
    addTearDown(repository.dispose);
    final service = _FakeRemoteCacheService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteCacheSettingsRepositoryProvider.overrideWithValue(repository),
          remoteCacheServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsSection(
              title: 'Storage',
              cardKey: Key('settings-section-storage'),
              children: [
                OnlineCacheSettingTile(),
                ClearOnlineCacheSettingTile(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('1.25 GB'), findsOneWidget);
    expect(find.text('10.0 MB used'), findsOneWidget);
    expect(find.byKey(const Key('online-cache-limit-512')), findsOneWidget);
    expect(find.byKey(const Key('online-cache-limit-1280')), findsOneWidget);
    expect(find.byKey(const Key('online-cache-limit-2048')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.byKey(const Key('online-cache-limit-512')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(repository.value.maximumBytes, remoteCacheMinimumMaximumBytes);
    expect(
      (await service.snapshot()).maximumBytes,
      remoteCacheMinimumMaximumBytes,
    );
    expect(find.text('512 MB'), findsOneWidget);

    await tester.tap(find.byKey(const Key('online-cache-limit-2048')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(repository.value.maximumBytes, remoteCacheMaximumMaximumBytes);
    expect(
      (await service.snapshot()).maximumBytes,
      remoteCacheMaximumMaximumBytes,
    );
    expect(find.text('2 GB'), findsOneWidget);

    await tester.tap(find.byKey(const Key('online-cache-clear')));
    await tester.pump();
    expect(
      find.byKey(const Key('online-cache-clear-confirmation')),
      findsOneWidget,
    );
    await tester.tap(find.text('Clear'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect((await service.snapshot()).bytes, 0);
    expect(find.text('2 GB'), findsOneWidget);
  });
}

class _FakeRepository implements RemoteCacheSettingsRepository {
  final _changes = StreamController<RemoteCacheBudget>.broadcast();
  RemoteCacheBudget value = const RemoteCacheBudget.defaultValue();

  @override
  Future<RemoteCacheBudget> load() async => value;

  @override
  Future<void> save(RemoteCacheBudget budget) async {
    value = budget;
    _changes.add(budget);
  }

  @override
  Stream<RemoteCacheBudget> watch() async* {
    yield value;
    yield* _changes.stream;
  }

  Future<void> dispose() => _changes.close();
}

class _FakeRemoteCacheService extends RemoteCacheService {
  _FakeRemoteCacheService()
    : _budget = const RemoteCacheBudget.defaultValue(),
      super(
        cacheDirectory: () => throw UnimplementedError(),
        availableBytes: () => throw UnimplementedError(),
      );

  RemoteCacheBudget _budget;
  int _bytes = 10 * remoteCacheMegabyteBytes;

  @override
  Future<RemoteCacheSnapshot> snapshot() async => RemoteCacheSnapshot(
    bytes: _bytes,
    entryCount: _bytes == 0 ? 0 : 1,
    maximumBytes: _budget.maximumBytes,
  );

  @override
  Future<void> updateBudget(RemoteCacheBudget budget) async {
    _budget = budget;
  }

  @override
  Future<void> clear() async {
    _bytes = 0;
  }
}
