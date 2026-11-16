import 'dart:async';

import 'package:bibliolife/features/reader/domain/models/reader_search.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_stable_components.dart';
import 'package:bibliolife/features/reader/performance/reader_performance.dart';
import 'package:flutter/material.dart';

final _readerSearchWhitespace = RegExp(r'\s+');

/// Search content for the canonical reader menu.
///
/// The controller remains the source of truth; this widget owns only focus,
/// debounce and the menu-specific result interactions.
class ReaderSearchSheet extends StatefulWidget {
  const ReaderSearchSheet({
    required this.controller,
    this.debounceDuration = const Duration(milliseconds: 300),
    super.key,
  });

  final ReaderUiController controller;
  final Duration debounceDuration;

  @override
  State<ReaderSearchSheet> createState() => _ReaderSearchSheetState();
}

class _ReaderSearchSheetState extends State<ReaderSearchSheet> {
  late final TextEditingController _query = TextEditingController(
    text: widget.controller.searchState.query,
  );
  late final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  String? _navigationError;
  var _navigationInProgress = false;
  var _suppressQueryListener = false;
  var _focusScheduled = false;
  Animation<double>? _routeAnimation;

  Duration get _boundedDebounce {
    final requested = widget.debounceDuration;
    if (requested.isNegative) return Duration.zero;
    const maximum = Duration(milliseconds: 500);
    return requested > maximum ? maximum : requested;
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQueryChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focusScheduled) return;
    _focusScheduled = true;
    // Keyboard/inset work must not compete with the initial route transition
    // over the Readium PlatformView. Listen to the canonical route animation
    // instead of coupling search to a custom route or a timed delay.
    final animation = ModalRoute.of(context)?.animation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      _routeAnimation = animation..addStatusListener(_handleRouteStatus);
    } else {
      _requestFocusAfterFrame();
    }
  }

  void _handleRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _routeAnimation?.removeStatusListener(_handleRouteStatus);
    _routeAnimation = null;
    _requestFocusAfterFrame();
  }

  void _requestFocusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleRouteStatus);
    _debounce?.cancel();
    _query
      ..removeListener(_onQueryChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (_suppressQueryListener) return;
    _debounce?.cancel();
    final query = _query.text;
    _navigationError = null;
    _debounce = Timer(_boundedDebounce, () => unawaited(_submit(query)));
    if (mounted) setState(() {});
  }

  Future<void> _submit(String rawQuery) async {
    if (!mounted || rawQuery != _query.text) return;
    final query = rawQuery.trim();
    ReaderSearchCommandResult result;
    try {
      result = query.isEmpty
          ? await widget.controller.clearSearch()
          : await widget.controller.search(query);
    } catch (_) {
      if (mounted && rawQuery == _query.text) {
        setState(() => _navigationError = 'Search is temporarily unavailable.');
      }
      return;
    }
    if (!mounted || rawQuery != _query.text) return;
    if (!result.isSuccess && result.status != ReaderSearchCommandStatus.stale) {
      setState(() => _navigationError = 'Search is temporarily unavailable.');
    }
  }

  Future<void> _clearQuery() async {
    _debounce?.cancel();
    _suppressQueryListener = true;
    _query.clear();
    _suppressQueryListener = false;
    try {
      await widget.controller.clearSearch();
    } catch (_) {
      if (mounted) {
        setState(() => _navigationError = 'Search is temporarily unavailable.');
      }
    }
  }

  Future<void> _retry() => _submit(_query.text);

  Future<void> _selectResult(ReaderSearchResult result) async {
    if (_navigationInProgress) return;
    setState(() {
      _navigationInProgress = true;
      _navigationError = null;
    });
    _focusNode.unfocus();
    ReaderSearchCommandResult command;
    try {
      command = await widget.controller.goToSearchResult(result.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _navigationError = 'Could not open this result.';
        _navigationInProgress = false;
      });
      return;
    }
    if (!mounted) return;
    if (!command.isSuccess) {
      setState(() {
        _navigationError = command.status == ReaderSearchCommandStatus.stale
            ? 'This result is no longer available.'
            : 'Could not open this result.';
        _navigationInProgress = false;
      });
      return;
    }
    setState(() => _navigationInProgress = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _header(),
      const SizedBox(height: ReaderStableTokens.menuRowGap),
      Expanded(child: _content()),
    ],
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(
      ReaderStableTokens.sheetHorizontalPadding,
      ReaderStableTokens.menuContentTopPadding,
      ReaderStableTokens.sheetHorizontalPadding,
      0,
    ),
    child: ReaderMenuCard(
      minimumHeight: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: TextField(
          controller: _query,
          focusNode: _focusNode,
          autofocus: false,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) {
            _debounce?.cancel();
            unawaited(_submit(value));
          },
          decoration: InputDecoration(
            hintText: 'Search query',
            border: InputBorder.none,
            isDense: true,
            suffixIcon: _query.text.isEmpty
                ? null
                : ReaderStableIconButton(
                    tooltip: 'Clear search',
                    onPressed: _clearQuery,
                    asset: 'assets/readium/stable/ic_toc_close.svg',
                  ),
          ),
        ),
      ),
    ),
  );

  Widget _content() => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller.searchState;
      return switch (state) {
        ReaderSearchIdle() => const ReaderMenuEmpty(
          title: 'Enter a word or phrase to search.',
        ),
        ReaderSearchLoading(:final query) => ReaderMenuLoading(
          label: 'Searching for $query...',
        ),
        ReaderSearchEmpty(:final query) => ReaderMenuEmpty(
          title: 'No results for "$query".',
        ),
        ReaderSearchFailure(:final error) => ReaderMenuError(
          title: 'Search is unavailable.',
          message: 'Try again in a moment.',
          onRetry: error.retryable ? _retry : null,
        ),
        ReaderSearchReady(:final results) => _results(context, results),
      };
    },
  );

  Widget _results(BuildContext context, List<ReaderSearchResult> results) {
    if (results.isEmpty) {
      return const ReaderMenuEmpty(title: 'No results.');
    }
    return Column(
      children: [
        if (_navigationError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: ReaderMenuCard(
              minimumHeight: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _navigationError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            itemCount: results.length,
            itemBuilder: (context, index) {
              ReaderMenuPerformanceScope.recordRowBuild(context);
              final result = results[index];
              final title = result.title?.trim();
              final semanticsParts = <String>[];
              if (title != null && title.isNotEmpty) semanticsParts.add(title);
              semanticsParts.add(
                result.match ?? result.before ?? 'Search result',
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  button: true,
                  label: semanticsParts.join(', '),
                  child: ReaderMenuCard(
                    minimumHeight: 0,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _navigationInProgress
                          ? null
                          : () => _selectResult(result),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (title != null && title.isNotEmpty)
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            if (result.match != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Match: ${result.match}',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                            if (_snippet(result) case final snippet?)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: snippet,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget? _snippet(ReaderSearchResult result) {
    final spans = <TextSpan>[];
    final before = result.before
        ?.replaceAll(_readerSearchWhitespace, ' ')
        .trim();
    final match = result.match?.replaceAll(_readerSearchWhitespace, ' ').trim();
    final after = result.after?.replaceAll(_readerSearchWhitespace, ' ').trim();
    if (before != null && before.isNotEmpty) {
      spans.add(TextSpan(text: '$before '));
    }
    if (match != null && match.isNotEmpty) {
      spans.add(
        TextSpan(
          text: match,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    }
    if (after != null && after.isNotEmpty) spans.add(TextSpan(text: ' $after'));
    if (spans.isEmpty) return null;
    return Text.rich(TextSpan(children: spans), maxLines: 4);
  }
}
