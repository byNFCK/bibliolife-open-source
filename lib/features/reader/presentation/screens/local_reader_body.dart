import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_repository_provider.dart';
import 'package:bibliolife/features/bookmarks/application/providers/bookmark_repository_provider.dart';
import 'package:bibliolife/features/reader/application/providers/epub_reader_settings_repository_provider.dart';
import 'package:bibliolife/features/reader/application/providers/reader_settings_repository_provider.dart';
import 'package:bibliolife/features/reader/application/services/comic_archive_service.dart';
import 'package:bibliolife/features/reader/application/services/reader_open_attempt.dart';
import 'package:bibliolife/features/reader/application/services/reflowable_readium_publication_service.dart';
import 'package:bibliolife/features/reader/application/services/readium_epub_annotation_coordinator.dart';
import 'package:bibliolife/features/reader/application/providers/reader_annotation_repository_provider.dart';
import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/presentation/models/local_reader_settings_adapters.dart';
import 'package:bibliolife/shared/application/logging/app_log_provider.dart';
import 'package:bibliolife/features/reader/presentation/models/readium_epub_reader_controller.dart';
import 'package:bibliolife/features/reader/presentation/widgets/unified_reader_screen.dart';
import 'package:bibliolife/features/reader/performance/reader_performance.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';

class LocalReaderBody extends ConsumerStatefulWidget {
  const LocalReaderBody({
    required this.book,
    this.initialLocatorJson,
    this.chromeBrightness,
    this.openAttempt,
    super.key,
  });
  final LibraryBook book;
  final String? initialLocatorJson;
  final Brightness? chromeBrightness;
  final ReaderOpenAttempt? openAttempt;

  @override
  ConsumerState<LocalReaderBody> createState() => _LocalReaderBodyState();
}

class _LocalReaderBodyState extends ConsumerState<LocalReaderBody> {
  late final LocalReaderSettingsAdapter? _settings;
  late final ReaderUiController _ui;
  ReaderOpenAttempt? _generatedOpening;

  @override
  void initState() {
    super.initState();
    final kind = readerKindFor(widget.book.format);
    if (kind == ReaderKind.reflowable) {
      _generatedOpening =
          widget.openAttempt ??
          ReaderOpenAttempt(
            ref.read(appLogProvider.notifier),
            bookId: widget.book.id,
            source: 'other',
            format: widget.book.format.name.toUpperCase(),
          );
    }
    final repository = ref.read(readerSettingsRepositoryProvider);
    _settings = switch (kind) {
      ReaderKind.pdf => PdfReaderSettingsAdapter(repository),
      ReaderKind.comic => ComicReaderSettingsAdapter(repository),
      _ => null,
    };
    _ui = ReaderUiController(
      capabilities: ReaderCapabilities.forKind(kind),
      settings: _settings,
    );
    if (_settings != null) unawaited(_settings.initialize());
  }

  @override
  void dispose() {
    _generatedOpening?.cancel();
    _ui.dispose();
    _settings?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = readerPresentationFor(widget.book.format);
    if (presentation == ReaderPresentation.readiumFlutter) {
      return _EpubReaderBody(
        book: widget.book,
        openAttempt: widget.openAttempt,
        initialLocatorJson: widget.initialLocatorJson,
        chromeBrightness: widget.chromeBrightness,
      );
    }
    if (presentation == ReaderPresentation.readiumReflowable) {
      return _ReadiumReflowableReaderBody(
        book: widget.book,
        openAttempt: _generatedOpening,
        initialLocatorJson: widget.initialLocatorJson,
        chromeBrightness: widget.chromeBrightness,
      );
    }
    return UnifiedReaderScreen(
      book: widget.book,
      controller: _ui,
      viewport: switch (readerKindFor(widget.book.format)) {
        ReaderKind.pdf => _PdfViewport(book: widget.book, ui: _ui),
        ReaderKind.comic => _ComicViewport(book: widget.book, ui: _ui),
        _ => const SizedBox.expand(),
      },
    );
  }
}

class _ReadiumReflowableReaderBody extends StatefulWidget {
  const _ReadiumReflowableReaderBody({
    required this.book,
    this.openAttempt,
    this.initialLocatorJson,
    this.chromeBrightness,
  });

  final LibraryBook book;
  final ReaderOpenAttempt? openAttempt;
  final String? initialLocatorJson;
  final Brightness? chromeBrightness;

  @override
  State<_ReadiumReflowableReaderBody> createState() =>
      _ReadiumReflowableReaderBodyState();
}

class _ReadiumReflowableReaderBodyState
    extends State<_ReadiumReflowableReaderBody> {
  late final Future<String> _publication = _preparePublication();

  Future<String> _preparePublication() {
    final opening = widget.openAttempt;
    opening?.resolveFile(widget.book.filePath);
    return ReflowableReadiumPublicationService().prepare(
      widget.book,
      onDiagnostic: (stage, result, facts) {
        if (result == 'failed') {
          opening?.fail(
            stageName: stage,
            component: 'generated_publication',
            code: facts['errorCode'] as String?,
            facts: facts,
          );
        } else {
          opening?.stage(stage, result, 'generated_publication', facts);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _publication,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        widget.openAttempt?.fail(error: snapshot.error);
        return const Center(child: Text('This book could not be opened.'));
      }
      final localFilePath = snapshot.data;
      if (localFilePath == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return _EpubReaderBody(
        book: widget.book,
        openAttempt: widget.openAttempt,
        localFilePath: localFilePath,
        initialLocatorJson: widget.initialLocatorJson,
        chromeBrightness: widget.chromeBrightness,
      );
    },
  );
}

class _EpubReaderBody extends ConsumerStatefulWidget {
  const _EpubReaderBody({
    required this.book,
    this.localFilePath,
    this.openAttempt,
    this.initialLocatorJson,
    this.chromeBrightness,
  });

  final LibraryBook book;
  final String? localFilePath;
  final ReaderOpenAttempt? openAttempt;
  final String? initialLocatorJson;
  final Brightness? chromeBrightness;

  @override
  ConsumerState<_EpubReaderBody> createState() => _EpubReaderBodyState();
}

class _EpubReaderBodyState extends ConsumerState<_EpubReaderBody> {
  late ReadiumEpubReaderController _adapter = _createAdapter(
    initialLocatorJson: widget.initialLocatorJson,
    openAttempt: widget.openAttempt,
  );
  ReadiumEpubAnnotationCoordinator? _annotationCoordinator;
  var _replacingSession = false;

  ReadiumEpubReaderController _createAdapter({
    String? initialLocatorJson,
    ReaderOpenAttempt? openAttempt,
  }) => ReadiumEpubReaderController(
    book: widget.book,
    initialLocatorJson: initialLocatorJson,
    chromeBrightness: widget.chromeBrightness,
    localFilePath: widget.localFilePath,
    progressRepository: ref.read(readingProgressRepositoryProvider),
    bookmarkRepository: ref.read(bookmarkRepositoryProvider),
    settingsRepository: ref.read(epubReaderSettingsRepositoryProvider),
    readerSettingsRepository: ref.read(readerSettingsRepositoryProvider),
    libraryRepository: ref.read(libraryRepositoryProvider),
    onReadingModeCommitted: _replaceReaderSession,
    appLogService: ref.read(appLogProvider.notifier),
    openAttempt: openAttempt,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_initializeAnnotations(_adapter));
  }

  Future<ReadiumEpubAnnotationCoordinator?> _initializeAnnotations(
    ReadiumEpubReaderController adapter,
  ) async {
    await adapter.initialize();
    final controller = adapter.nativeController;
    if (!mounted || controller == null) return null;
    final coordinator = ReadiumEpubAnnotationCoordinator(
      bookId: widget.book.id,
      controller: controller,
      repository: ref.read(readerAnnotationRepositoryProvider),
    );
    adapter.attachAnnotationMenuController(coordinator);
    await coordinator.start();
    if (mounted && identical(adapter, _adapter)) {
      _annotationCoordinator = coordinator;
    }
    return coordinator;
  }

  Future<void> _replaceReaderSession(String? locatorJson) async {
    if (!mounted || _replacingSession) {
      throw StateError('reader_session_replacement_unavailable');
    }
    final oldAdapter = _adapter;
    final oldCoordinator = _annotationCoordinator;
    setState(() => _replacingSession = true);
    await WidgetsBinding.instance.endOfFrame;
    await oldCoordinator?.dispose();
    await oldAdapter.disposeAndWait();
    final replacement = _createAdapter(initialLocatorJson: locatorJson);
    final coordinator = await _initializeAnnotations(replacement);
    if (!mounted) {
      await coordinator?.dispose();
      await replacement.disposeAndWait();
      return;
    }
    setState(() {
      _adapter = replacement;
      _annotationCoordinator = coordinator;
      _replacingSession = false;
    });
  }

  @override
  void dispose() {
    unawaited(_annotationCoordinator?.dispose());
    _adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _replacingSession
      ? const SizedBox.expand()
      : UnifiedReaderScreen(
          book: widget.book,
          controller: _adapter,
          viewport: ReadiumEpubViewportHost(adapter: _adapter),
        );
}

/// Rebuilds the viewport when the adapter finishes its asynchronous bootstrap
/// without replacing the stable native controller or PlatformView state.
class ReadiumEpubViewportHost extends StatefulWidget {
  const ReadiumEpubViewportHost({
    required this.adapter,
    this.platformViewBuilder,
    super.key,
  });

  final ReadiumEpubReaderController adapter;
  final ReadiumEpubPlatformViewBuilder? platformViewBuilder;

  @override
  State<ReadiumEpubViewportHost> createState() =>
      _ReadiumEpubViewportHostState();
}

class _ReadiumEpubViewportHostState extends State<ReadiumEpubViewportHost> {
  var _ready = false;
  ReadiumEpubController? _renderedController;
  ReadiumEpubOpenConfiguration? _renderedConfiguration;

  @override
  void initState() {
    super.initState();
    _ready = _hasViewport;
    widget.adapter.addListener(_adapterChanged);
    _rememberViewport();
  }

  @override
  void didUpdateWidget(covariant ReadiumEpubViewportHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adapter == widget.adapter) return;
    oldWidget.adapter.removeListener(_adapterChanged);
    widget.adapter.addListener(_adapterChanged);
    _adapterChanged();
  }

  bool get _hasViewport =>
      widget.adapter.nativeController != null &&
      widget.adapter.configuration != null;

  void _adapterChanged() {
    if (!mounted) return;
    final controller = widget.adapter.nativeController;
    final configuration = widget.adapter.configuration;
    final ready = controller != null && configuration != null;
    if (ready == _ready &&
        identical(controller, _renderedController) &&
        configuration == _renderedConfiguration) {
      return;
    }
    if (ready && !_ready) {
      ReaderPerformance.mark(
        'READER_PERF_VIEWPORT_CREATE_START',
        type: 'readium',
      );
    }
    setState(() {
      _ready = ready;
      _renderedController = controller;
      _renderedConfiguration = configuration;
    });
  }

  void _rememberViewport() {
    _renderedController = widget.adapter.nativeController;
    _renderedConfiguration = widget.adapter.configuration;
  }

  @override
  void dispose() {
    widget.adapter.removeListener(_adapterChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.adapter.nativeController;
    final configuration = widget.adapter.configuration;
    if (!_ready || controller == null || configuration == null) {
      return const SizedBox.expand();
    }
    return ReaderPerformanceFirstFrame(
      marker: 'READER_PERF_VIEWPORT_READY',
      type: 'readium',
      child: ReadiumEpubViewport(
        key: ValueKey(controller.instanceId),
        configuration: configuration,
        controller: controller,
        onContentTap: (event) => widget.adapter.handleContentTap(
          event,
          controllerId: controller.instanceId,
        ),
        onError: (error) => widget.adapter.handleViewportError(
          error,
          controllerId: controller.instanceId,
        ),
        onPlatformViewCreationError:
            widget.adapter.handlePlatformViewCreationError,
        platformViewBuilder: widget.platformViewBuilder,
      ),
    );
  }
}

class _ComicViewport extends ConsumerStatefulWidget {
  const _ComicViewport({required this.book, required this.ui});
  final LibraryBook book;
  final ReaderUiController ui;
  @override
  ConsumerState<_ComicViewport> createState() => _ComicViewportState();
}

class _ComicViewportState extends ConsumerState<_ComicViewport> {
  late final Future<void> _initial = _load();
  PageController? _controller;
  final ScrollController _scrollController = ScrollController();
  ComicArchive? _archive;
  var _lastPageIndex = 0;

  @override
  void initState() {
    super.initState();
    final settings = widget.ui.readerSettings;
    if (settings case final Listenable listenable) {
      listenable.addListener(_settingsChanged);
    }
    unawaited(_initial);
  }

  void _settingsChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleLogicalPageRestore();
  }

  void _scheduleLogicalPageRestore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mode = widget.ui.readerSettings?.state.page?.readingMode;
      final archive = _archive;
      if (archive == null || archive.pages.length <= 1) return;
      if (mode == ReaderReadingMode.continuous &&
          _scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent *
              (_lastPageIndex / (archive.pages.length - 1)),
        );
      } else if (_controller?.hasClients == true) {
        _controller!.jumpToPage(_lastPageIndex);
      }
    });
  }

  Future<void> _load() async {
    try {
      ReaderPerformance.mark(
        'READER_PERF_VIEWPORT_CREATE_START',
        type: 'comic',
      );
      final values = await Future.wait<Object?>([
        ComicArchiveService().prepare(widget.book),
        ref.read(readingProgressRepositoryProvider).getForBook(widget.book.id),
      ]);
      final archive = values[0]! as ComicArchive;
      final saved = values[1] as ReadingProgress?;
      final index = ((saved?.currentPage ?? 1) - 1).clamp(
        0,
        archive.pages.length - 1,
      );
      _archive = archive;
      _controller = PageController(initialPage: index);
      await ref
          .read(libraryRepositoryProvider)
          .markBookOpened(widget.book.id, DateTime.now());
      _update(index);
      widget.ui.setReady(seek: _seek);
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ReaderPerformance.mark('READER_PERF_FIRST_CONTENT', type: 'comic');
          }
        });
        _scheduleLogicalPageRestore();
      }
    } catch (error) {
      widget.ui.setError(error);
    }
  }

  void _update(int index) {
    final archive = _archive;
    if (archive == null) return;
    _lastPageIndex = index;
    final progress = ReaderProgressState.page(
      page: index + 1,
      total: archive.pages.length,
    );
    widget.ui.setProgress(progress, seek: _seek);
    unawaited(
      ref
          .read(readingProgressRepositoryProvider)
          .save(
            ReadingProgress(
              bookId: widget.book.id,
              locatorJson: jsonEncode({'type': 'comic', 'page': index}),
              progression: progress.progression,
              currentChapterTitle: null,
              currentPage: index + 1,
              totalPages: archive.pages.length,
              updatedAt: DateTime.now(),
            ),
          ),
    );
  }

  Future<void> _seek(double progression) async {
    final archive = _archive;
    final controller = _controller;
    if (archive == null || controller == null) return;
    final page = ReaderProgressState.page(
      page: 1,
      total: archive.pages.length,
    ).pageFor(progression);
    final mode = widget.ui.readerSettings?.state.page?.readingMode;
    if (mode == ReaderReadingMode.continuous && _scrollController.hasClients) {
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent * progression,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    } else {
      await controller.animateToPage(
        page - 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    final settings = widget.ui.readerSettings;
    if (settings case final Listenable listenable) {
      listenable.removeListener(_settingsChanged);
    }
    _controller?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final archive = _archive;
    final controller = _controller;
    if (archive == null || controller == null) return const SizedBox.expand();
    final state = widget.ui.readerSettings?.state;
    final page = state?.page ?? const ReaderPageSettings();
    final gap = state?.spacing?.pageGap ?? 10;
    if (page.readingMode == ReaderReadingMode.continuous) {
      return LayoutBuilder(
        builder: (context, constraints) =>
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.maxScrollExtent > 0) {
                  final progression =
                      notification.metrics.pixels /
                      notification.metrics.maxScrollExtent;
                  final index = (progression * (archive.pages.length - 1))
                      .round()
                      .clamp(0, archive.pages.length - 1);
                  if (index != _lastPageIndex) {
                    _update(index);
                  }
                }
                return false;
              },
              child: ListView.builder(
                controller: _scrollController,
                itemCount: archive.pages.length,
                itemBuilder: (context, index) => SizedBox(
                  height: constraints.maxHeight,
                  child: _comicPage(archive.pages[index], page.imageFit, gap),
                ),
              ),
            ),
      );
    }
    return PageView.builder(
      controller: controller,
      reverse: page.readingDirection == ReaderReadingDirection.rightToLeft,
      itemCount: archive.pages.length,
      onPageChanged: _update,
      itemBuilder: (context, index) =>
          _comicPage(archive.pages[index], page.imageFit, gap),
    );
  }

  Widget _comicPage(String filePath, ReaderImageFit fit, double gap) =>
      ColoredBox(
        color: Colors.black,
        child: Padding(
          padding: EdgeInsets.all(gap / 2),
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: SizedBox.expand(
              child: Image.file(
                File(filePath),
                fit: fit == ReaderImageFit.width
                    ? BoxFit.fitWidth
                    : BoxFit.contain,
              ),
            ),
          ),
        ),
      );
}

class _PdfViewport extends ConsumerStatefulWidget {
  const _PdfViewport({required this.book, required this.ui});
  final LibraryBook book;
  final ReaderUiController ui;
  @override
  ConsumerState<_PdfViewport> createState() => _PdfViewportState();
}

class _PdfViewportState extends ConsumerState<_PdfViewport> {
  PdfControllerPinch? _controller;
  var _currentPage = 1;
  var _totalPages = 0;

  @override
  void initState() {
    super.initState();
    final settings = widget.ui.readerSettings;
    if (settings case final Listenable listenable) {
      listenable.addListener(_settingsChanged);
    }
    unawaited(_initialize());
  }

  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    try {
      final saved = await ref
          .read(readingProgressRepositoryProvider)
          .getForBook(widget.book.id);
      _currentPage = saved?.currentPage ?? 1;
      ReaderPerformance.mark('READER_PERF_VIEWPORT_CREATE_START', type: 'pdf');
      _controller = PdfControllerPinch(
        document: PdfDocument.openFile(widget.book.filePath),
        initialPage: _currentPage,
      );
      await ref
          .read(libraryRepositoryProvider)
          .markBookOpened(widget.book.id, DateTime.now());
      if (mounted) setState(() {});
    } catch (error) {
      widget.ui.setError(error);
    }
  }

  void _update(int page) {
    _currentPage = page;
    final progress = ReaderProgressState.page(page: page, total: _totalPages);
    widget.ui.setProgress(progress, seek: _seek);
    unawaited(
      ref
          .read(readingProgressRepositoryProvider)
          .save(
            ReadingProgress(
              bookId: widget.book.id,
              locatorJson: jsonEncode({'type': 'pdf', 'page': page}),
              progression: progress.progression,
              currentChapterTitle: null,
              currentPage: page,
              totalPages: _totalPages == 0 ? null : _totalPages,
              updatedAt: DateTime.now(),
            ),
          ),
    );
  }

  Future<void> _seek(double progression) async {
    final controller = _controller;
    if (controller == null || _totalPages <= 1) return;
    await controller.animateToPage(
      pageNumber: ReaderProgressState.page(
        page: 1,
        total: _totalPages,
      ).pageFor(progression),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    final settings = widget.ui.readerSettings;
    if (settings case final Listenable listenable) {
      listenable.removeListener(_settingsChanged);
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.expand();
    return PdfViewPinch(
      controller: controller,
      padding: widget.ui.readerSettings?.state.spacing?.pageGap ?? 10,
      onDocumentLoaded: (document) {
        ReaderPerformance.mark('READER_PERF_FIRST_CONTENT', type: 'pdf');
        _totalPages = document.pagesCount;
        _update(_currentPage.clamp(1, _totalPages));
        widget.ui.setReady(seek: _seek);
      },
      onDocumentError: widget.ui.setError,
      onPageChanged: _update,
    );
  }
}
