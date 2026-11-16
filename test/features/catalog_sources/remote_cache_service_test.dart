import 'dart:io';
import 'dart:typed_data';

import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_cache_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteCacheService', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'bibliolife-remote-cache-',
      );
    });
    tearDown(() => directory.delete(recursive: true));

    test('persists normalized metadata with a hashed key', () async {
      final cache = RemoteCacheService(
        cacheDirectory: () async => directory,
        availableBytes: () async => 1024 * 1024 * 1024,
      );
      final expires = DateTime.utc(2030);

      await cache.writeMetadata(
        'safe-hash',
        RemoteMetadataCacheEntry(
          bodyBytes: Uint8List.fromList([1, 2, 3]),
          expiresAt: expires,
          etag: 'etag',
        ),
      );
      final result = await cache.readMetadata('safe-hash');

      expect(result?.bodyBytes, Uint8List.fromList([1, 2, 3]));
      expect(result?.expiresAt, expires);
      expect(result?.etag, 'etag');
    });

    test(
      'coalesces identical cover requests and respects its disk budget',
      () async {
        var requests = 0;
        final cache = RemoteCacheService(
          cacheDirectory: () async => directory,
          validateFetchedCovers: false,
          availableBytes: () async => 1024 * 1024 * 1024,
          coverFetcher: (_) async {
            requests++;
            return Uint8List.fromList(List.filled(4, requests));
          },
          coverMaximumBytes: 5,
          metadataMaximumBytes: 5,
          maximumBytes: 5,
        );
        final uri = Uri.parse('https://covers.example/one.jpg');

        await Future.wait([cache.cover(uri), cache.cover(uri)]);
        expect(requests, 1);
        // Simulates a card leaving and re-entering the lazy grid: the stable
        // hashed key resolves from disk without a second physical request.
        await cache.cover(uri);
        expect(requests, 1);
        await cache.cover(Uri.parse('https://covers.example/two.jpg'));

        expect(requests, 2);
        expect((await cache.snapshot()).bytes, lessThanOrEqualTo(5));
      },
    );

    test('cached cover lookup never starts a physical request', () async {
      var requests = 0;
      final cache = RemoteCacheService(
        cacheDirectory: () async => directory,
        validateFetchedCovers: false,
        availableBytes: () async => 1024 * 1024 * 1024,
        coverFetcher: (_) async {
          requests++;
          return Uint8List.fromList([1, 2, 3]);
        },
      );
      final uri = Uri.parse('https://covers.example/ready.jpg');

      expect(await cache.cachedCover(uri), isNull);
      expect(requests, 0);

      await cache.cover(uri);
      expect(await cache.cachedCover(uri), isNotNull);
      expect(requests, 1);
    });

    test('validated cover requests reject non-image responses', () async {
      final cache = RemoteCacheService(
        cacheDirectory: () async => directory,
        validateFetchedCovers: true,
        availableBytes: () async => 1024 * 1024 * 1024,
        coverFetcher: (_) async =>
            Uint8List.fromList('<html>error</html>'.codeUnits),
      );

      expect(
        await cache.cover(Uri.parse('https://covers.example/broken.jpg')),
        isNull,
      );
      expect((await cache.snapshot()).entryCount, 0);
    });

    test(
      'clearing remote cache does not delete local imported files',
      () async {
        final local = File(
          '${directory.path}${Platform.pathSeparator}local.epub',
        );
        await local.writeAsBytes([1]);
        final cache = RemoteCacheService(
          cacheDirectory: () async => directory,
          validateFetchedCovers: false,
          coverFetcher: (_) async => Uint8List.fromList([1]),
          availableBytes: () async => 1024 * 1024,
        );
        await cache.cover(Uri.parse('https://covers.example/cover.jpg'));

        await cache.clear();

        expect(await local.exists(), isTrue);
        expect((await cache.snapshot()).entryCount, 0);
      },
    );

    test('uses the persisted startup budget and deterministic split', () async {
      final cache = RemoteCacheService(
        cacheDirectory: () async => directory,
        availableBytes: () async => 4 * 1024 * 1024 * 1024,
        initialBudget: Future.value(
          RemoteCacheBudget.fromStored(remoteCacheMinimumMaximumBytes),
        ),
      );

      final snapshot = await cache.snapshot();
      expect(snapshot.maximumBytes, remoteCacheMinimumMaximumBytes);
      expect(
        cache.coverMaximumBytes + cache.metadataMaximumBytes,
        remoteCacheMinimumMaximumBytes,
      );
      expect(
        cache.coverMaximumBytes,
        remoteCacheMinimumMaximumBytes * 1100 ~/ 1280,
      );
    });

    test('rapid budget updates finish with the newest budget', () async {
      final cache = RemoteCacheService(
        cacheDirectory: () async => directory,
        availableBytes: () async => 4 * 1024 * 1024 * 1024,
      );

      await Future.wait([
        cache.updateBudget(
          RemoteCacheBudget.fromStored(remoteCacheMinimumMaximumBytes),
        ),
        cache.updateBudget(
          RemoteCacheBudget.fromStored(remoteCacheMaximumMaximumBytes),
        ),
      ]);

      expect(
        (await cache.snapshot()).maximumBytes,
        remoteCacheMaximumMaximumBytes,
      );
    });
  });
}
