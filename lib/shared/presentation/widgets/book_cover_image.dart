import 'dart:io';

import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/core/performance/library_image_performance.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter/material.dart';

/// Renders local and remote covers through their distinct image providers.
class BookCoverImage extends StatefulWidget {
  const BookCoverImage({
    required this.cover,
    required this.title,
    required this.placeholder,
    this.cacheWidth,
    this.cacheHeight,
    this.resizePolicy = ResizeImagePolicy.exact,
    this.frameBuilder,
    this.remoteCache,
    this.profile = BookCoverRenderProfile.searchGrid,
    this.performanceSession,
    this.diagnosticSourceType,
    this.diagnosticId,
    super.key,
  });

  final BookCoverReference cover;
  final String title;
  final Widget placeholder;
  final int? cacheWidth;
  final int? cacheHeight;
  final ResizeImagePolicy resizePolicy;
  final ImageFrameBuilder? frameBuilder;
  final RemoteCacheService? remoteCache;
  final BookCoverRenderProfile profile;
  final OnlineSearchPerformanceSession? performanceSession;
  final String? diagnosticSourceType;
  final String? diagnosticId;

  @override
  State<BookCoverImage> createState() => _BookCoverImageState();
}

class _BookCoverImageState extends State<BookCoverImage> {
  var _loadStarted = false;
  var _loadCompleted = false;
  var _loadFailed = false;
  Future<File?>? _cachedRemoteFile;

  @override
  void initState() {
    super.initState();
    _reportCandidate();
  }

  @override
  void didUpdateWidget(covariant BookCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cover != widget.cover ||
        oldWidget.profile != widget.profile ||
        oldWidget.cacheWidth != widget.cacheWidth ||
        oldWidget.cacheHeight != widget.cacheHeight ||
        oldWidget.resizePolicy != widget.resizePolicy) {
      _loadStarted = false;
      _loadCompleted = false;
      _loadFailed = false;
      _cachedRemoteFile = null;
      _reportCandidate();
    }
  }

  @override
  Widget build(BuildContext context) => switch (widget.cover) {
    LocalBookCover(:final file) => _local(file),
    RemoteBookCover(:final uri) => _remote(uri),
    AssetBookCover(:final assetName) => Image.asset(
      assetName,
      fit: BoxFit.cover,
      semanticLabel: 'Cover of ${widget.title}',
      frameBuilder: widget.frameBuilder,
      errorBuilder: (_, error, _) =>
          _fallback('assetLoad:${error.runtimeType}'),
    ),
    MissingBookCover() => widget.placeholder,
  };

  Widget _local(File file) {
    if (_loadFailed) return widget.placeholder;
    return Image(
      image: _resize(FileImage(file)),
      fit: BoxFit.cover,
      semanticLabel: 'Cover of ${widget.title}',
      frameBuilder: widget.frameBuilder,
      errorBuilder: (_, error, _) {
        LibraryCoverDiagnostics.recordFileFailure(
          sourceType: widget.diagnosticSourceType ?? 'local',
          sourceId: widget.diagnosticId ?? widget.title,
          file: file,
          profile: widget.profile.name,
          decodeWidth: widget.cacheWidth ?? widget.profile.cacheWidth,
          decodeHeight: widget.cacheHeight ?? widget.profile.cacheHeight,
          error: error,
        );
        return _fallback('localLoad:${error.runtimeType}');
      },
    );
  }

  Widget _remote(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      return _fallback('unsupportedRemoteUri');
    }
    if (!_loadStarted) {
      _loadStarted = true;
      _log('REMOTE_COVER_LOAD_STARTED ${_remoteContext(uri)}');
      final remote = widget.cover as RemoteBookCover;
      widget.performanceSession?.recordCoverRequest(
        sourceId: remote.sourceId ?? 'none',
        remoteId: remote.remoteId ?? 'none',
        uri: uri,
        cacheWidth: widget.cacheWidth ?? widget.profile.cacheWidth,
        cacheHeight: widget.cacheHeight ?? widget.profile.cacheHeight,
      );
    }
    final cache = widget.remoteCache;
    if (cache != null) {
      _cachedRemoteFile ??= cache.cover(
        uri,
        performanceSession: widget.performanceSession,
      );
      return FutureBuilder<File?>(
        future: _cachedRemoteFile,
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (file == null) return widget.placeholder;
          return Image(
            image: _resize(FileImage(file)),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            semanticLabel: 'Cover of ${widget.title}',
            frameBuilder: (context, child, frame, synchronous) {
              if (frame != null && !_loadCompleted) {
                _loadCompleted = true;
                widget.performanceSession?.recordImageDecode();
                final remote = widget.cover as RemoteBookCover;
                widget.performanceSession?.recordCoverCompleted(
                  sourceId: remote.sourceId ?? 'none',
                  remoteId: remote.remoteId ?? 'none',
                  uri: remote.uri,
                );
              }
              return widget.frameBuilder?.call(
                    context,
                    child,
                    frame,
                    synchronous,
                  ) ??
                  child;
            },
            errorBuilder: (_, error, _) {
              LibraryCoverDiagnostics.recordFileFailure(
                sourceType: 'remote-cache',
                sourceId: widget.diagnosticId ?? _remoteContext(uri),
                file: file,
                uri: uri,
                profile: widget.profile.name,
                decodeWidth: widget.cacheWidth ?? widget.profile.cacheWidth,
                decodeHeight: widget.cacheHeight ?? widget.profile.cacheHeight,
                error: error,
              );
              return _fallback('cachedLoad:${error.runtimeType}');
            },
          );
        },
      );
    }
    return Image(
      image: _resize(NetworkImage(uri.toString())),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      semanticLabel: 'Cover of ${widget.title}',
      loadingBuilder: (_, child, loading) =>
          loading == null ? child : widget.placeholder,
      frameBuilder: (context, child, frame, synchronous) {
        if (frame != null && !_loadCompleted) {
          _loadCompleted = true;
          widget.performanceSession?.recordImageDecode();
          _log('REMOTE_COVER_LOAD_COMPLETED ${_remoteContext(uri)}');
          final remote = widget.cover as RemoteBookCover;
          widget.performanceSession?.recordCoverCompleted(
            sourceId: remote.sourceId ?? 'none',
            remoteId: remote.remoteId ?? 'none',
            uri: uri,
          );
        }
        return widget.frameBuilder?.call(context, child, frame, synchronous) ??
            child;
      },
      errorBuilder: (_, error, _) {
        LibraryCoverDiagnostics.recordRemoteFailure(
          sourceId: widget.diagnosticId ?? _remoteContext(uri),
          uri: uri,
          profile: widget.profile.name,
          decodeWidth: widget.cacheWidth ?? widget.profile.cacheWidth,
          decodeHeight: widget.cacheHeight ?? widget.profile.cacheHeight,
          error: error,
        );
        return _fallback('networkLoad:${error.runtimeType}');
      },
    );
  }

  ImageProvider<Object> _resize(ImageProvider<Object> provider) => ResizeImage(
    provider,
    width: widget.cacheWidth ?? widget.profile.cacheWidth,
    height: widget.cacheHeight ?? widget.profile.cacheHeight,
    policy: widget.resizePolicy,
  );

  Widget _fallback(String reason) {
    if (!_loadFailed) {
      _loadFailed = true;
      final remote = widget.cover;
      if (remote is RemoteBookCover) {
        _log(
          'REMOTE_COVER_LOAD_FAILED ${_remoteContext(remote.uri)} error=$reason',
        );
        widget.performanceSession?.recordCoverFailed(
          sourceId: remote.sourceId ?? 'none',
          remoteId: remote.remoteId ?? 'none',
          uri: remote.uri,
          reason: reason,
        );
      }
      _log('REMOTE_COVER_FALLBACK_USED reason=$reason');
    }
    return widget.placeholder;
  }

  void _reportCandidate() {
    final remote = widget.cover;
    if (remote is! RemoteBookCover) return;
    _log('REMOTE_COVER_CANDIDATE ${_remoteContext(remote.uri)}');
    _log('REMOTE_COVER_SELECTED ${_remoteContext(remote.uri)} type=remote');
  }

  String _remoteContext(Uri uri) {
    final remote = widget.cover as RemoteBookCover;
    return 'canonicalId=${remote.canonicalId ?? 'none'} sourceId=${remote.sourceId ?? 'none'} remoteId=${remote.remoteId ?? 'none'} uri=${uri.scheme}://${uri.host}${uri.path}';
  }

  // Cover URLs and canonical identities must not reach diagnostic output.
  void _log(String _) {}
}
