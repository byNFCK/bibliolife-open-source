import 'dart:io';

import 'package:bibliolife/core/performance/library_image_performance.dart';
import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:flutter/material.dart';

const double collectionCoverAspectRatio = 16 / 9;
const double collectionCoverRadius = 32;

class CollectionCover extends StatefulWidget {
  const CollectionCover({
    required this.placeholder,
    required this.semanticLabel,
    this.imageFile,
    this.overlay,
    this.imageKey,
    this.cacheWidth,
    this.diagnosticSourceType,
    this.diagnosticId,
    this.diagnosticProfile = 'collection',
    super.key,
  });

  static const BorderRadius borderRadius = BorderRadius.all(
    Radius.circular(collectionCoverRadius),
  );

  final File? imageFile;
  final Widget placeholder;
  final Widget? overlay;
  final String semanticLabel;
  final Key? imageKey;
  final int? cacheWidth;
  final String? diagnosticSourceType;
  final String? diagnosticId;
  final String diagnosticProfile;

  @override
  State<CollectionCover> createState() => _CollectionCoverState();
}

class _CollectionCoverState extends State<CollectionCover> {
  late bool _fileExists;

  @override
  void initState() {
    super.initState();
    _fileExists = _exists(widget.imageFile);
  }

  @override
  void didUpdateWidget(covariant CollectionCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageFile?.path != widget.imageFile?.path) {
      _fileExists = _exists(widget.imageFile);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: widget.semanticLabel,
    child: AspectRatio(
      aspectRatio: collectionCoverAspectRatio,
      child: ClipRRect(
        borderRadius: CollectionCover.borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_fileExists && widget.imageFile != null)
              Image.file(
                widget.imageFile!,
                key: widget.imageKey,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                cacheWidth: widget.cacheWidth,
                excludeFromSemantics: true,
                errorBuilder: (context, error, stackTrace) {
                  LibraryCoverDiagnostics.recordFileFailure(
                    sourceType: widget.diagnosticSourceType ?? 'collection',
                    sourceId: widget.diagnosticId ?? widget.semanticLabel,
                    file: widget.imageFile!,
                    profile: widget.diagnosticProfile,
                    decodeWidth: widget.cacheWidth ?? 480,
                    decodeHeight: null,
                    error: error,
                  );
                  return widget.placeholder;
                },
              )
            else
              widget.placeholder,
            if (widget.overlay != null) widget.overlay!,
          ],
        ),
      ),
    ),
  );

  bool _exists(File? file) {
    if (file == null) return false;
    try {
      return file.existsSync();
    } on FileSystemException {
      return false;
    }
  }
}

enum CollectionCoverPlaceholderStyle {
  card,
  details,
  detailsImageError,
  editorUpload,
  editorImage,
}

class CollectionCoverPlaceholder extends StatelessWidget {
  const CollectionCoverPlaceholder({required this.style, super.key});

  final CollectionCoverPlaceholderStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (style) {
      CollectionCoverPlaceholderStyle.card => Center(
        child: Icon(
          Icons.collections_bookmark_outlined,
          size: 40,
          color: scheme.onSurfaceVariant,
        ),
      ),
      CollectionCoverPlaceholderStyle.details => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.surfaceContainerHighest, scheme.secondaryContainer],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.collections_bookmark_outlined,
            size: 48,
            color: scheme.onSecondaryContainer,
          ),
        ),
      ),
      CollectionCoverPlaceholderStyle.detailsImageError => ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.collections_bookmark_outlined,
            size: 48,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      CollectionCoverPlaceholderStyle.editorUpload => CustomPaint(
        painter: _CollectionCoverDashedBorderPainter(
          color: scheme.outlineVariant,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 40,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(AppStrings.uploadCover),
            ],
          ),
        ),
      ),
      CollectionCoverPlaceholderStyle.editorImage => ColoredBox(
        color: scheme.secondaryContainer,
        child: Center(
          child: Icon(
            Icons.collections_bookmark_outlined,
            color: scheme.onSecondaryContainer,
            size: 48,
          ),
        ),
      ),
    };
  }
}

class _CollectionCoverDashedBorderPainter extends CustomPainter {
  const _CollectionCoverDashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 6.0;
    const dashSpace = 6.0;
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect,
          const Radius.circular(collectionCoverRadius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(
    covariant _CollectionCoverDashedBorderPainter oldDelegate,
  ) => oldDelegate.color != color;
}
