import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('performance flags keep verbose telemetry behind the primary flag', () {
    const primary = bool.fromEnvironment('BIBLIOLIFE_NET_PERF_LOGS');
    const requestedVerbose = bool.fromEnvironment(
      'BIBLIOLIFE_NET_PERF_VERBOSE_LOGS',
    );
    const requestedFrames = bool.fromEnvironment(
      'BIBLIOLIFE_SEARCH_FRAME_METRICS',
    );

    expect(biblioLifeNetPerfLogsEnabled, primary);
    expect(biblioLifeNetPerfVerboseLogsEnabled, primary && requestedVerbose);
    expect(biblioLifeSearchFrameMetricsEnabled, primary && requestedFrames);
  });

  test('lifecycle markers are emitted only in verbose mode', () {
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);

    onlinePerformanceMarker('test_marker', fields: {'records': 1});

    if (biblioLifeNetPerfVerboseLogsEnabled) {
      expect(logs, ['SEARCH_PERF_MARKER test_marker records=1']);
    } else {
      expect(logs, isEmpty);
    }
  });

  test('request fingerprint excludes API keys and token-like parameters', () {
    final fingerprint = sanitizedRequestFingerprint(
      sourceId: 'builtin-google-books',
      method: 'get',
      uri: Uri.parse(
        'https://www.googleapis.com/books/v1/volumes?key=secret&q=romeo&access_token=hidden&startIndex=0&sig=private',
      ),
    );

    expect(
      fingerprint,
      'builtin-google-books|GET|www.googleapis.com/books/v1/volumes?q=romeo&startIndex=0',
    );
    expect(fingerprint, isNot(contains('secret')));
    expect(fingerprint, isNot(contains('hidden')));
    expect(fingerprint, isNot(contains('private')));
  });

  test(
    'scope propagates source attribution and summary aggregates counters',
    () async {
      final logs = <String>[];
      final session = OnlineSearchPerformanceSession(
        id: 'search-test',
        log: logs.add,
      )..configureSources(1);

      await OnlinePerformanceScope.run(
        session,
        'builtin-google-books',
        () async {
          expect(OnlinePerformanceScope.session, same(session));
          expect(OnlinePerformanceScope.sourceId, 'builtin-google-books');
          session.sourceStarted('builtin-google-books');
          final first = session.networkStarted(
            sourceId: OnlinePerformanceScope.sourceId,
            method: 'GET',
            uri: Uri.parse('https://example.test/books?q=romeo&key=secret'),
          );
          first.completed(statusCode: 200, responseBytes: 128);
          final duplicate = session.networkStarted(
            sourceId: OnlinePerformanceScope.sourceId,
            method: 'GET',
            uri: Uri.parse('https://example.test/books?key=secret&q=romeo'),
          );
          duplicate.completed(statusCode: 200, responseBytes: 128);
          session.recordParser(
            sourceId: 'builtin-google-books',
            parser: 'googleBooksJson',
            responseBytes: 128,
            itemCount: 2,
            decode: Duration.zero,
            mapping: Duration.zero,
          );
          session.recordCanonical(
            inputRecordCount: 2,
            resultCount: 1,
            mergedCount: 1,
            rejectedCount: 0,
            comparisonCount: 1,
            normalizationCalls: 0,
            isbnConversions: 0,
            mergeDuration: Duration.zero,
          );
          session.recordStateEmission(wholeListReplacement: true);
          session.recordFirstVisibleResultCandidate();
          session.recordCoverRequest(
            sourceId: 'builtin-google-books',
            remoteId: 'volume-id',
            uri: Uri.parse('https://books.google.com/cover.jpg?token=private'),
            cacheWidth: 360,
            cacheHeight: 540,
          );
          session.recordCoverCompleted(
            sourceId: 'builtin-google-books',
            remoteId: 'volume-id',
            uri: Uri.parse('https://books.google.com/cover.jpg?token=private'),
          );
          session.sourceFinished('builtin-google-books', recordCount: 2);
        },
      );

      session.finish(reason: 'queryReplaced');
      session.finish(reason: 'routeDisposed');

      final summaries = logs
          .where((line) => line.startsWith('SEARCH_PERF_SUMMARY '))
          .toList();
      expect(summaries, hasLength(1));
      final summary = summaries.single;
      expect(summary, contains('SEARCH_PERF_SUMMARY v=3 s=search-test'));
      expect(summary, contains('net=2,1,0,0'));
      expect(summary, contains('res=2,1,'));
      expect(summary, contains('cover=1,0,0,0,0,0,0,0,1,0'));
      expect(logs.join('\n'), isNot(contains('secret')));
      expect(logs.join('\n'), isNot(contains('private')));
      expect(logs.join('\n'), isNot(contains('romeo')));
    },
  );
}
