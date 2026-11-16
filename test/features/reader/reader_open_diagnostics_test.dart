import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/reader/application/services/reader_open_attempt.dart';
import 'package:bibliolife/features/reader/application/services/reflowable_readium_publication_service.dart';
import 'package:bibliolife/features/reader/application/services/reflowable_book_loader.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/features/reader/domain/repositories/reading_progress_repository.dart';
import 'package:bibliolife/features/reader/presentation/models/readium_epub_reader_controller.dart';
import 'package:bibliolife/features/reader/presentation/screens/reader_route_screen.dart';
import 'package:bibliolife/features/reader/presentation/widgets/unified_reader_screen.dart';
import 'package:bibliolife/shared/application/logging/app_log_provider.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_epub_reader_settings_repository.dart';

void main() {
  testWidgets('missing EPUB record logs lookup failure beside the route UI', (
    tester,
  ) async {
    final container = ProviderContainer.test(
      overrides: [
        bookByIdProvider('missing').overrideWith((_) => Stream.value(null)),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ReaderRouteScreen(
            bookId: 'missing',
            formatHint: BookFormat.epub,
            source: 'book_details',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Book not found.'), findsOneWidget);
    final logs = _logs(container);
    expect(logs.first, containsPair('format', 'EPUB'));
    expect(logs.first, containsPair('source', 'book_details'));
    expect(_terminal(logs), containsPair('failedStage', 'book_lookup'));
    expect(_terminal(logs), containsPair('errorCode', 'book_record_not_found'));
    expect(_terminal(logs), containsPair('bookRecordFound', false));
    expect(
      _terminal(logs),
      containsPair('readiumInitializationReached', false),
    );
  });

  testWidgets('leaving while lookup is pending cancels the EPUB attempt', (
    tester,
  ) async {
    final books = StreamController<LibraryBook?>();
    addTearDown(books.close);
    final container = ProviderContainer.test(
      overrides: [
        bookByIdProvider('pending').overrideWith((_) => books.stream),
      ],
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      ),
    );
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const ReaderRouteScreen(
            bookId: 'pending',
            formatHint: BookFormat.epub,
          ),
        ),
      ),
    );
    await tester.pump();
    navigator.currentState!.pop();
    books.add(null);
    await tester.pumpAndSettle();
    expect(_terminal(_logs(container)), containsPair('result', 'cancelled'));
  });

  test(
    'only the native readiness boundary completes a normal EPUB open',
    () async {
      final container = ProviderContainer.test();
      final reader = _Reader(container);
      await reader.start();
      expect(_logs(container).first, containsPair('kind', 'book_open_start'));
      expect(
        reader.adapter.configuration!.localFilePath,
        reader.adapter.book.filePath,
      );
      expect(reader.adapter.configuration!.initialLocatorJson, _Reader.locator);
      expect(_logs(container).where(_isTerminal), isEmpty);

      reader.event('readerLifecycleChanged', {'phase': 'navigatorReady'});
      await _flush();
      expect(reader.adapter.isLoading, false);
      expect(reader.adapter.error, isNull);
      expect(_logs(container).where(_isTerminal), isEmpty);

      reader.stage('reader_ready', 'success', 'android_readium_navigator');
      await _flush();
      final logs = _logs(container);
      expect(
        logs.where((entry) => entry['stage'] == 'reader_ready'),
        hasLength(1),
      );
      expect(_terminal(logs), containsPair('result', 'ready'));
      expect(logs.map((entry) => entry['openAttemptId']).toSet(), hasLength(1));
      expect(
        container.read(appLogProvider.notifier).formattedText,
        isNot(contains(reader.adapter.book.filePath)),
      );
    },
  );

  for (final failure in [
    (
      name: 'missing file',
      stage: 'file_access',
      component: 'android_file',
      code: 'file_not_found',
      facts: <String, Object?>{
        'fileExists': false,
        'exceptionType': 'ErrnoException',
        'osErrorCode': 2,
        'message': 'ENOENT',
      },
    ),
    (
      name: 'access exception',
      stage: 'file_access',
      component: 'android_file',
      code: 'file_not_found',
      facts: <String, Object?>{
        'readable': false,
        'exceptionType': 'ErrnoException',
        'osErrorCode': 13,
        'message': 'EACCES',
      },
    ),
    (
      name: 'publication opener failure',
      stage: 'publication_open',
      component: 'readium_publication_opener',
      code: 'invalid_publication',
      facts: <String, Object?>{
        'readiumErrorCategory': 'Reading',
        'exceptionType': 'DebugError',
        'message': 'Invalid OPF file',
      },
    ),
    (
      name: 'native initialization failure',
      stage: 'navigator_initialization',
      component: 'android_readium_navigator',
      code: 'navigator_creation_failed',
      facts: <String, Object?>{
        'exceptionType': 'IllegalStateException',
        'message': 'navigator fragment was not attached',
      },
    ),
  ]) {
    test('${failure.name} keeps the native cause and one terminal', () async {
      final container = ProviderContainer.test();
      final reader = _Reader(container);
      await reader.start();
      reader.stage('native_session', 'success', 'android_reader_session', {
        'nativeSessionCreated': true,
      });
      reader.stage(
        'readium_initialization',
        'started',
        'readium_initial_locator',
        {'readiumInitializationReached': true},
      );
      reader.stage(failure.stage, 'failed', failure.component, {
        'errorCode': failure.code,
        ...failure.facts,
      });
      reader.error(failure.code);
      reader.error(failure.code);
      await _flush();
      final terminal = _terminal(_logs(container));
      expect(terminal['result'], 'failed');
      expect(terminal['failedStage'], failure.stage);
      expect(terminal['component'], failure.component);
      expect(terminal['errorCode'], failure.code);
      expect(terminal['nativeSessionCreated'], true);
      expect(terminal['readiumInitializationReached'], true);
      for (final entry in failure.facts.entries) {
        expect(terminal, containsPair(entry.key, entry.value));
      }
      expect(reader.adapter.error, isA<ReadiumBridgeError>());
    });
  }

  testWidgets('generic reader error UI has one matching terminal log', (
    tester,
  ) async {
    final container = ProviderContainer.test();
    final attempt = ReaderOpenAttempt(
      container.read(appLogProvider.notifier),
      bookId: 'epub-book',
      source: 'book_details',
    )..stage('reader_bootstrap', 'started', 'reader_repositories');
    final reader = _Reader(container, openAttempt: attempt);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedReaderScreen(
          book: reader.adapter.book,
          controller: reader.adapter,
          viewport: const SizedBox.expand(),
        ),
      ),
    );
    const error = ReadiumBridgeError(
      code: 'transport_unavailable',
      fatal: true,
    );
    reader.adapter.handleViewportError(error);
    await tester.pump();
    expect(find.text('This book could not be opened.'), findsOneWidget);
    final terminal = _terminal(_logs(container));
    expect(terminal, containsPair('errorCode', error.code));
    expect(terminal, containsPair('nativeSessionCreated', false));
    expect(reader.adapter.error, same(error));
    await tester.pumpWidget(const SizedBox());
    reader.adapter.dispose();
    await tester.pump();
  });

  test(
    'restoration success is logged before normal reader readiness',
    () async {
      final container = ProviderContainer.test();
      final reader = _Reader(container);
      await reader.start();
      final configuration = reader.adapter.configuration!;
      final id = configuration.openAttemptId!;
      final payload = configuration.toMap(resolvedInstanceId: 'test-view');
      expect(payload['openAttemptId'], id);
      expect(payload['initialLocatorSource'], 'launch_request');

      reader.event('readerDiagnostic', {
        ..._restoration(id, 'viewport_verification', 'success'),
        'viewportVerification': 'verified',
      });
      reader.event(
        'readerDiagnostic',
        _restoration(id, 'restoration_terminal', 'success'),
      );
      await _flush();
      expect(_logs(container).where(_isTerminal), isEmpty);
      reader.event('readerLifecycleChanged', {'phase': 'navigatorReady'});
      reader.stage('reader_ready', 'success', 'android_readium_navigator');
      await _flush();
      final logs = _logs(container);
      expect(logs.where(_isRestoration).map((e) => e['result']), [
        'success',
        'success',
      ]);
      expect(_terminal(logs)['result'], 'ready');
      expect(reader.adapter.error, isNull);
    },
  );

  for (final (stage, reason) in const [
    ('target_resource_resolution', 'target_not_in_reading_order'),
    ('post_restore_layout', 'cancelled'),
    ('viewport_verification', 'viewport_locator_did_not_converge'),
  ]) {
    test('failed $stage keeps evidence before the one open terminal', () async {
      final container = ProviderContainer.test();
      final reader = _Reader(container);
      await reader.start();
      final id = reader.adapter.configuration!.openAttemptId!;
      final terminal = {
        ..._restoration(id, 'restoration_terminal', 'failed'),
        'restorationStage': stage,
        'failureReason': reason,
        if (stage == 'viewport_verification') ...{
          'viewportVerification': 'not_verified',
          'actualReadingOrderIndex': 2,
          'actualResourceProgression': 0.3,
        },
      };
      final failure = _initializationFailure(id, terminal);
      reader.event('readerDiagnostic', _restoration(id, stage, 'started'));
      reader.event('readerDiagnostic', terminal);
      reader.event('readerDiagnostic', failure);
      reader.error('initial_locator_restoration_failed', details: failure);
      await _flush();
      final logs = _logs(container);
      expect(logs.where(_isRestoration), hasLength(2));
      final restore = logs.where(_isRestoration).last;
      expect(restore['failureReason'], reason);
      final open = _terminal(logs);
      expect(logs.indexOf(restore), lessThan(logs.indexOf(open)));
      expect(open['failedStage'], 'navigator_initialization');
      expect(
        open['initialLocatorRestoration'],
        containsPair('failureReason', reason),
      );
      if (stage == 'viewport_verification') {
        expect(restore['viewportVerification'], 'not_verified');
        expect(restore['actualReadingOrderIndex'], 2);
        expect(restore['actualResourceProgression'], 0.3);
      }
    });
  }

  test(
    'fatal error alone preserves restoration details after cleanup',
    () async {
      final container = ProviderContainer.test();
      final reader = _Reader(container);
      await reader.start();
      final id = reader.adapter.configuration!.openAttemptId!;
      final restore = {
        ..._restoration(id, 'restoration_terminal', 'failed'),
        'restorationStage': 'locator_offset',
        'failureReason': 'unexpected_exception',
        'exceptionType': 'IllegalStateException',
        'requestedResourceProgression': 0.7,
        'requestedHrefMatchesPublication': true,
        'resolvedReadingOrderIndex': 3,
        'message': 'permission denied',
        'href': '/data/private.epub',
        'actualResourceProgression': double.infinity,
        'initialLocatorGeometry': {
          'targetDocumentOffsetLayoutPx': 3.75,
          'requestedItemOffsetPx': 180,
          'verificationCheck': 'requested_range_not_at_start_boundary',
          'requestedLocatorFields': {
            'hasFragment': true,
            'hasQuote': false,
            'selector': 'private-selector',
          },
          'beforePositioning': {'layoutPass': 4, 'resourceTopPx': -20},
          'afterPositioningLayout': {
            'layoutPass': 5,
            'resourceTopPx': 0,
            'viewportAnchorYPx': 184.5,
            'canScrollTowardStart': false,
            'href': '/data/private.epub',
          },
          'afterVerification': {
            'layoutPass': 6,
            'reportedMeasurementGeneration': 2,
            'anchorLocalYPx': double.infinity,
          },
        },
      };
      final details = _initializationFailure(id, restore);
      reader.error('initial_locator_restoration_failed', details: details);
      reader.error('initial_locator_restoration_failed', details: details);
      await _flush();
      await reader.adapter.disposeAndWait();
      final logs = _logs(container);
      final restored = logs.where(_isRestoration).single;
      expect(restored['openAttemptId'], id);
      expect(restored['failureReason'], 'unexpected_exception');
      expect(restored['exceptionType'], 'IllegalStateException');
      expect(restored['message'], 'permission denied');
      expect(restored['requestedResourceProgression'], 0.7);
      expect(restored['requestedHrefMatchesPublication'], true);
      expect(restored['resolvedReadingOrderIndex'], 3);
      expect(restored, isNot(contains('actualResourceProgression')));
      final geometry = restored['initialLocatorGeometry'];
      expect(geometry, {
        'targetDocumentOffsetLayoutPx': 3.75,
        'requestedItemOffsetPx': 180,
        'verificationCheck': 'requested_range_not_at_start_boundary',
        'requestedLocatorFields': {'hasFragment': true, 'hasQuote': false},
        'beforePositioning': {'layoutPass': 4, 'resourceTopPx': -20},
        'afterPositioningLayout': {
          'layoutPass': 5,
          'resourceTopPx': 0,
          'viewportAnchorYPx': 184.5,
          'canScrollTowardStart': false,
        },
        'afterVerification': {
          'layoutPass': 6,
          'reportedMeasurementGeneration': 2,
        },
      });
      expect(jsonEncode(logs), isNot(contains('/data/private.epub')));
      expect(jsonEncode(logs), isNot(contains('private-selector')));
      final terminal = _terminal(logs);
      expect(terminal['failedStage'], 'navigator_initialization');
      expect(
        terminal['initialLocatorRestoration'],
        containsPair('initialLocatorGeometry', geometry),
      );
    },
  );

  test('restoration fields cannot cross opening attempts', () async {
    final container = ProviderContainer.test();
    final first = _Reader(container);
    final second = _Reader(container);
    await first.start();
    await second.start();
    final firstId = first.adapter.configuration!.openAttemptId!;
    final secondId = second.adapter.configuration!.openAttemptId!;
    final foreign = _restoration(secondId, 'restoration_terminal', 'failed');
    first.event('readerDiagnostic', foreign);
    first.error(
      'initial_locator_restoration_failed',
      details: _initializationFailure(secondId, foreign),
    );
    second.event('readerDiagnostic', foreign);
    second.stage('reader_ready', 'success', 'android_readium_navigator');
    await _flush();
    final logs = _logs(container);
    expect(logs.where(_isRestoration).single['openAttemptId'], secondId);
    expect(
      _terminal(logs.where((e) => e['openAttemptId'] == firstId).toList()),
      isNot(contains('initialLocatorRestoration')),
    );
  });

  test('platform creation exception preserves the safe native code', () async {
    final container = ProviderContainer.test();
    final reader = _Reader(container);
    await reader.start();
    reader.adapter.handlePlatformViewCreationError(
      PlatformException(
        code: 'error',
        message:
            'ReadiumPlatformViewCreationException: activity_unavailable\n'
            '/data/user/0/private.epub token=secret',
      ),
    );
    await _flush();
    final terminal = _terminal(_logs(container));
    expect(terminal, containsPair('failedStage', 'platform_view'));
    expect(terminal, containsPair('errorCode', 'activity_unavailable'));
    expect(
      terminal,
      containsPair('exceptionType', 'ReadiumPlatformViewCreationException'),
    );
    expect(terminal, containsPair('nativeSessionCreated', false));
    expect(jsonEncode(terminal), isNot(contains('private.epub')));
    expect(jsonEncode(terminal), isNot(contains('secret')));
  });

  test(
    'overlapping attempts keep IDs and ignore late events from disposed readers',
    () async {
      final container = ProviderContainer.test();
      final first = _Reader(container);
      final second = _Reader(container);
      await first.start();
      await second.start();
      final starts = _logs(
        container,
      ).where((e) => e['kind'] == 'book_open_start').toList();
      final firstId = starts.first['openAttemptId'] as int;
      final secondId = starts.last['openAttemptId'] as int;
      expect(firstId, lessThan(secondId));

      first.client.emit(
        second.adapter.nativeController!.instanceId,
        'readerDiagnostic',
        _stage('reader_ready', 'success', 'android_readium_navigator'),
      );
      await first.adapter.disposeAndWait();
      second.stage('reader_ready', 'success', 'android_readium_navigator');
      await _flush();
      final terminals = _logs(container).where(_isTerminal).toList();
      expect(terminals, hasLength(2));
      expect(terminals[0], containsPair('openAttemptId', firstId));
      expect(terminals[0], containsPair('result', 'cancelled'));
      expect(terminals[1], containsPair('openAttemptId', secondId));
      expect(terminals[1], containsPair('result', 'ready'));
    },
  );
  test(
    'physical log fragments fit the Android sink and retain one terminal',
    () async {
      final originalPrint = debugPrint;
      final printed = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
      addTearDown(() => debugPrint = originalPrint);
      final container = ProviderContainer.test();
      final attempt = ReaderOpenAttempt(
        container.read(appLogProvider.notifier),
        bookId: 'synthetic-id',
        source: 'other',
        format: 'TXT',
      );
      attempt.stage('viewport_verification', 'started', 'diagnostic_test', {
        'boundedSample': List.filled(200, 123.456),
      });
      attempt.fail(code: 'initial_locator_restoration_failed');
      await _flush();
      expect(
        printed.where((line) => line.startsWith('Reader.Open.chunk ')),
        isNotEmpty,
      );
      expect(printed.every((line) => utf8.encode(line).length < 1023), true);
      expect(_logs(container).where(_isTerminal), hasLength(1));
      expect(
        _terminal(_logs(container)),
        containsPair('openAttemptId', attempt.id),
      );
    },
  );

  test(
    'new recovery and top-boundary evidence survives the private-field whitelist',
    () async {
      final container = ProviderContainer.test();
      final reader = _Reader(container, format: BookFormat.txt);
      await reader.start();
      final id = reader.adapter.configuration!.openAttemptId!;
      reader.event('readerDiagnostic', {
        ..._restoration(id, 'viewport_verification', 'success'),
        'viewportVerification': 'verified',
        'initialLocatorGeometry': {
          'verificationCheck': 'top_boundary_clamp_verified',
          'recoveryOffsetCheck': 'current_point_aligned',
          'offsetBeforeRecoveryPx': 54500.3,
          'offsetAfterRecoveryPx': 54500.3,
          'beforeRecovery': {
            'resourceHeightPx': 98992,
            'reportedMeasurementGeneration': 1,
          },
          'afterRecovery': {
            'resourceHeightPx': 104000,
            'reportedMeasurementGeneration': 3,
            'measurementEpoch': 2,
          },
          'privateSelector': 'PRIVATE BOOK TEXT',
        },
      });
      await _flush();
      final evidence =
          _logs(
                container,
              ).where(_isRestoration).single['initialLocatorGeometry']
              as Map;
      expect(evidence['verificationCheck'], 'top_boundary_clamp_verified');
      expect(evidence['recoveryOffsetCheck'], 'current_point_aligned');
      expect((evidence['afterRecovery'] as Map)['resourceHeightPx'], 104000);
      expect(jsonEncode(evidence), isNot(contains('PRIVATE BOOK TEXT')));
      expect(_logs(container).where(_isTerminal), isEmpty);
    },
  );

  for (final format in [BookFormat.txt, BookFormat.fb2]) {
    test(
      '${format.name} retains one attempt through native restore failure',
      () async {
        final container = ProviderContainer.test();
        final attempt = ReaderOpenAttempt(
          container.read(appLogProvider.notifier),
          bookId: '${format.name}-book',
          source: 'book_details',
          format: format.name.toUpperCase(),
        );
        attempt.stage('epub_conversion', 'success', 'generated_publication', {
          'conversionCacheStatus': 'hit',
          'generatedPublicationId': 'safe-publication-id',
        });
        final reader = _Reader(container, format: format, openAttempt: attempt);
        await reader.start();
        expect(reader.adapter.configuration!.openAttemptId, attempt.id);
        final restore = {
          ..._restoration(attempt.id, 'restoration_terminal', 'failed'),
          'failureReason': 'viewport_locator_did_not_converge',
          'initialLocatorGeometry': {
            'domEquivalence': false,
            'rangeEvidence': {
              'matches': false,
              'rangeResolved': true,
              'rangeTopCssPx': 12.5,
              'anchorCssPx': 15.0,
              'distanceCssPx': 2.5,
              'text': 'SECRET BOOK TEXT',
            },
          },
        };
        final failure = _initializationFailure(attempt.id, restore);
        reader.event('readerDiagnostic', failure);
        reader.error('initial_locator_restoration_failed', details: failure);
        await _flush();
        final logs = _logs(container);
        expect(logs.where((e) => e['kind'] == 'book_open_start'), hasLength(1));
        expect(logs.map((e) => e['openAttemptId']).toSet(), {attempt.id});
        expect(
          _terminal(logs),
          containsPair('errorCode', 'initial_locator_restoration_failed'),
        );
        expect(
          _terminal(logs),
          containsPair('generatedPublicationId', 'safe-publication-id'),
        );
        expect(jsonEncode(logs), isNot(contains('SECRET BOOK TEXT')));
        expect(jsonEncode(logs), contains('rangeTopCssPx'));
      },
    );
    test(
      '${format.name} decoding failure reaches one correlated terminal',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'reader-open-diagnostic-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final source = File('${directory.path}/private-source.${format.name}');
        await source.writeAsBytes([0xff, 0xfe, 0x01]);
        final container = ProviderContainer.test();
        final attempt = ReaderOpenAttempt(
          container.read(appLogProvider.notifier),
          bookId: 'source-book',
          source: 'book_details',
          format: format.name.toUpperCase(),
        );
        final fixture = _Reader(
          container,
          format: format,
          sourcePath: source.path,
        );
        final service = ReflowableReadiumPublicationService(
          cacheDirectory: () async => Directory('${directory.path}/cache'),
        );
        await expectLater(
          service.prepare(
            fixture.adapter.book,
            onDiagnostic: (stage, result, facts) {
              if (result == 'failed') {
                attempt.fail(
                  stageName: stage,
                  component: 'generated_publication',
                  code: facts['errorCode'] as String?,
                  facts: facts,
                );
              } else {
                attempt.stage(stage, result, 'generated_publication', facts);
              }
            },
          ),
          throwsA(
            format == BookFormat.txt
                ? isA<FormatException>()
                : isA<ReflowableBookException>(),
          ),
        );
        await _flush();
        expect(
          _terminal(_logs(container)),
          containsPair('failedStage', 'text_decode'),
        );
        expect(
          _terminal(_logs(container)),
          containsPair('openAttemptId', attempt.id),
        );
        expect(jsonEncode(_logs(container)), isNot(contains(source.path)));
      },
    );
    test(
      '${format.name} standalone attempt waits for native ready and ignores late events',
      () async {
        final container = ProviderContainer.test();
        final reader = _Reader(container, format: format);
        await reader.start();
        expect(reader.adapter.configuration!.openAttemptId, isNotNull);
        reader.event('readerLifecycleChanged', {'phase': 'navigatorReady'});
        await _flush();
        expect(_logs(container).where(_isTerminal), isEmpty);
        reader.stage('reader_ready', 'success', 'android_readium_navigator');
        await _flush();
        expect(_terminal(_logs(container)), containsPair('result', 'ready'));
        expect(
          _terminal(_logs(container)),
          containsPair('originalFormat', format.name.toUpperCase()),
        );
        await reader.adapter.disposeAndWait();
        reader.stage(
          'navigator_initialization',
          'failed',
          'android_readium_navigator',
        );
        await _flush();
        expect(_logs(container).where(_isTerminal), hasLength(1));
      },
    );
    testWidgets(
      '${format.name} route logs preparation failure before native initialization',
      (tester) async {
        final fixtureContainer = ProviderContainer.test();
        final fixture = _Reader(fixtureContainer, format: format);
        final book = fixture.adapter.book;
        final container = ProviderContainer.test(
          overrides: [
            bookByIdProvider(book.id).overrideWith((_) => Stream.value(book)),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: ReaderRouteScreen(bookId: book.id, formatHint: format),
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump();
        await tester.pump();
        expect(find.text('This book could not be opened.'), findsOneWidget);
        final terminal = _terminal(_logs(container));
        expect(terminal, containsPair('failedStage', 'file_access'));
        expect(terminal, containsPair('errorCode', 'file_not_found'));
        expect(terminal, containsPair('nativeSessionCreated', false));
        expect(
          terminal,
          containsPair('originalFormat', format.name.toUpperCase()),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

List<Map<String, Object?>> _logs(ProviderContainer container) => container
    .read(appLogProvider)
    .where((entry) => entry.category == 'Reader.Open')
    .map((entry) => jsonDecode(entry.message) as Map<String, Object?>)
    .toList();

bool _isTerminal(Map<String, Object?> entry) =>
    entry['kind'] == 'book_open_terminal';

bool _isRestoration(Map<String, Object?> entry) =>
    entry['kind'] == 'initial_locator_restoration';

Map<String, Object?> _restoration(int id, String stage, String result) =>
    _stage(stage, result, 'readium_initial_locator', {
      'kind': 'initial_locator_restoration',
      'openAttemptId': id,
      'locatorSource': 'saved_progress',
      'elapsedMs': 5,
    });

Map<String, Object?> _initializationFailure(
  int id,
  Map<String, Object?> restoration,
) => _stage('navigator_initialization', 'failed', 'android_readium_navigator', {
  'openAttemptId': id,
  'errorCode': 'initial_locator_restoration_failed',
  'exceptionType': 'InitialLocatorRestorationFailed',
  'initialLocatorRestoration': restoration,
});

Map<String, Object?> _terminal(List<Map<String, Object?>> logs) =>
    logs.where(_isTerminal).single;

Map<String, Object?> _stage(
  String stage,
  String result,
  String component, [
  Map<String, Object?> fields = const {},
]) => {
  'category': 'Reader.Open',
  'stage': stage,
  'result': result,
  'component': component,
  ...fields,
};

class _Reader {
  _Reader(
    ProviderContainer container, {
    ReaderOpenAttempt? openAttempt,
    BookFormat format = BookFormat.epub,
    String? sourcePath,
  }) {
    adapter = ReadiumEpubReaderController(
      book: LibraryBook(
        id: '${format.name}-book',
        title: 'Book',
        sortTitle: null,
        author: null,
        description: null,
        filePath: sourcePath ?? '/data/user/0/example/files/private title.epub',
        fileName: 'private title.epub',
        fileExtension: format.name,
        format: format,
        mediaType: null,
        coverPath: null,
        language: null,
        publisher: null,
        publishedDate: null,
        isbn: null,
        pageCount: null,
        fileSizeBytes: 10,
        dateAdded: DateTime.utc(2026),
        lastOpenedAt: null,
        isFavorite: false,
      ),
      localFilePath: format == BookFormat.epub
          ? null
          : '/data/cache/generated/publication.epub',
      progressRepository: _Progress(),
      settingsRepository: FakeEpubReaderSettingsRepository(),
      initialLocatorJson: locator,
      appLogService: container.read(appLogProvider.notifier),
      openAttempt: openAttempt,
      controllerBuilder: (configuration) =>
          ReadiumEpubController(configuration: configuration, client: client),
    );
    addTearDown(adapter.dispose);
  }

  static const locator =
      '{"href":"chapter.xhtml","type":"application/xhtml+xml"}';
  final client = _Client();
  late final ReadiumEpubReaderController adapter;

  Future<void> start() async {
    await adapter.initialize();
    await adapter.nativeController!.start();
  }

  void event(String type, Map<String, Object?> payload) =>
      client.emit(adapter.nativeController!.instanceId, type, payload);

  void stage(
    String stage,
    String result,
    String component, [
    Map<String, Object?> fields = const {},
  ]) => event('readerDiagnostic', _stage(stage, result, component, fields));

  void error(String code, {Map<String, Object?>? details}) =>
      event('readerError', {'code': code, 'fatal': true, 'details': details});
}

class _Progress extends Fake implements ReadingProgressRepository {
  @override
  Future<ReadingProgress?> getForBook(String bookId) async => null;
}

class _Client extends Fake implements ReadiumBridgeClient {
  final _events = StreamController<ReadiumReaderEvent>.broadcast();
  var _sequence = 0;

  @override
  Stream<ReadiumReaderEvent> get events => _events.stream;

  @override
  Future<void> attachToPlatform() async {}

  void emit(String instanceId, String type, Map<String, Object?> payload) {
    if (_events.isClosed) return;
    _events.add(
      ReadiumReaderEvent.parse({
        'protocolVersion': ReadiumBridgeConstants.protocolVersion,
        'instanceId': instanceId,
        'sequence': ++_sequence,
        'type': type,
        'payload': payload,
      }),
    );
  }

  @override
  Future<void> dispose() => _events.close();
}
