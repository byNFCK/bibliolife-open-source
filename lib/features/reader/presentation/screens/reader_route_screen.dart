import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/reader/application/services/reader_open_attempt.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/presentation/screens/local_reader_body.dart';
import 'package:bibliolife/features/reader/performance/reader_performance.dart';
import 'package:bibliolife/shared/application/logging/app_log_provider.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReaderRouteScreen extends ConsumerStatefulWidget {
  const ReaderRouteScreen({
    required this.bookId,
    this.initialLocatorJson,
    this.formatHint,
    this.source = 'other',
    super.key,
  });
  final String bookId;
  final String? initialLocatorJson;
  final BookFormat? formatHint;
  final String source;

  @override
  ConsumerState<ReaderRouteScreen> createState() => _ReaderRouteScreenState();
}

class _ReaderRouteScreenState extends ConsumerState<ReaderRouteScreen> {
  final ReaderFrameTimingObserver _frameTimings = ReaderFrameTimingObserver();
  final Stopwatch _lifetime = Stopwatch();
  late final AppLogService _log;
  late DateTime _lookupStartedAt;
  late Stopwatch _lookupElapsed;
  ReaderOpenAttempt? _opening;
  bool _lookupResolved = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _log = ref.read(appLogProvider.notifier);
    _startLookup();
    _lifetime.start();
    _frameTimings.start();
    ReaderPerformance.mark('READER_PERF_ROUTE_PUSH_START');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ReaderPerformance.mark(
          'READER_PERF_FIRST_ROUTE_FRAME',
          elapsed: _lifetime.elapsed,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant ReaderRouteScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId) {
      _opening?.cancel();
      _startLookup();
    }
  }

  void _startLookup() {
    _lookupStartedAt = DateTime.now();
    _lookupElapsed = Stopwatch()..start();
    _lookupResolved = false;
    _opening = _hasOpenDiagnostics(widget.formatHint)
        ? _newLookupAttempt(widget.formatHint!.name.toUpperCase())
        : null;
  }

  ReaderOpenAttempt _newLookupAttempt(String format) => ReaderOpenAttempt(
    _log,
    bookId: widget.bookId,
    source: widget.source,
    format: format,
    startedAt: _lookupStartedAt,
    elapsed: _lookupElapsed,
  )..stage('book_lookup', 'started', 'library_repository');

  void _lookupSucceeded(LibraryBook book) {
    if (_lookupResolved || _leaving) return;
    _lookupResolved = true;
    if (!_hasOpenDiagnostics(book.format)) {
      _opening?.cancel();
      return;
    }
    if (_opening?.isFinished == true) _startLookup();
    _lookupResolved = true;
    final attempt = _opening ??= _newLookupAttempt(
      book.format.name.toUpperCase(),
    );
    attempt.stage('book_lookup', 'success', 'library_repository', {
      'bookRecordFound': true,
    });
    attempt.stage('format_dispatch', 'success', 'reader_dispatch', {
      'originalFormat': book.format.name.toUpperCase(),
      'readerFormat': 'EPUB',
    });
  }

  void _lookupFailed([Object? error]) {
    if (_lookupResolved ||
        _leaving ||
        (widget.formatHint != null &&
            !_hasOpenDiagnostics(widget.formatHint))) {
      return;
    }
    final attempt = _opening ??= _newLookupAttempt('unknown');
    attempt.fail(
      code: error == null ? 'book_record_not_found' : 'book_lookup_failed',
      error: error,
      facts: {if (error == null) 'bookRecordFound': false},
    );
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    if (_opening == null && !_lookupResolved && widget.formatHint == null) {
      _opening = _newLookupAttempt('unknown');
    }
    _opening?.cancel();
  }

  @override
  void dispose() {
    _leave();
    ReaderPerformance.mark(
      'READER_PERF_ROUTE_DISPOSE_START',
      elapsed: _lifetime.elapsed,
    );
    _frameTimings.stop();
    super.dispose();
    ReaderPerformance.mark(
      'READER_PERF_ROUTE_DISPOSE_END',
      elapsed: _lifetime.elapsed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(bookByIdProvider(widget.bookId));
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: book.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) {
              _lookupFailed(error);
              return const Center(child: Text('Could not open this book.'));
            },
            data: (book) {
              if (book == null) {
                _lookupFailed();
                return const Center(child: Text('Book not found.'));
              }
              _lookupSucceeded(book);
              return switch (readerKindFor(book.format)) {
                ReaderKind.epub ||
                ReaderKind.pdf ||
                ReaderKind.reflowable ||
                ReaderKind.comic => LocalReaderBody(
                  book: book,
                  openAttempt: _opening,
                  initialLocatorJson: widget.initialLocatorJson,
                  chromeBrightness: Theme.of(context).brightness,
                ),
                ReaderKind.unsupported => const Center(
                  child: Text('This file format is not supported.'),
                ),
              };
            },
          ),
        ),
      ),
    );
  }
}

bool _hasOpenDiagnostics(BookFormat? format) =>
    format == BookFormat.epub ||
    format == BookFormat.txt ||
    format == BookFormat.fb2;
