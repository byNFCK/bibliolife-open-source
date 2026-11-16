import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';

import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_cover_trim.dart';
import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_image.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';

class BookDetailsCover extends StatelessWidget {
  BookDetailsCover({required LibraryBook this.book, super.key})
    : title = book.title,
      cover = null,
      remoteCache = null,
      isHero = false;

  BookDetailsCover.hero({required LibraryBook this.book, super.key})
    : title = book.title,
      cover = null,
      remoteCache = null,
      isHero = true;

  const BookDetailsCover.remote({
    required this.title,
    required this.cover,
    this.remoteCache,
    super.key,
  }) : book = null,
       isHero = true;

  final LibraryBook? book;
  final String title;
  final BookCoverReference? cover;
  final bool isHero;
  final RemoteCacheService? remoteCache;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tokens = context.appTokens;
        final pageInsets = MediaQuery.paddingOf(context);
        final availableWidth = isHero
            ? math.max(
                0.0,
                constraints.maxWidth -
                    pageInsets.horizontal -
                    2 * tokens.pagePadding,
              )
            : constraints.maxWidth;
        final width = math.min(
          availableWidth,
          (availableWidth * 0.56).clamp(168.0, 280.0),
        );
        final reference =
            cover ??
            _localCover(book?.coverPath) ??
            const BookCoverReference.missing();
        if (isHero) {
          final backColumn =
              math.max(pageInsets.left, pageInsets.right) +
              tokens.pagePadding +
              kMinInteractiveDimension;
          return _BookDetailsCoverHero(
            cover: reference,
            remoteCache: remoteCache,
            title: title,
            availableWidth: availableWidth,
            viewportWidth: constraints.maxWidth,
            topInset: pageInsets.top,
            backColumn: backColumn,
          );
        }
        return Center(
          child: SizedBox(
            width: width,
            child: AspectRatio(
              aspectRatio: context.appTokens.coverAspectRatio,
              child: _BookDetailsCoverSurface(title: title, cover: reference),
            ),
          ),
        );
      },
    );
  }

  BookCoverReference? _localCover(String? path) {
    final value = path?.trim();
    return value == null || value.isEmpty
        ? null
        : BookCoverReference.local(value);
  }
}

class _BookDetailsCoverHero extends StatelessWidget {
  const _BookDetailsCoverHero({
    required this.cover,
    required this.title,
    required this.availableWidth,
    required this.viewportWidth,
    required this.topInset,
    required this.backColumn,
    this.remoteCache,
  });

  final BookCoverReference cover;
  final String title;
  final double availableWidth;
  final double viewportWidth;
  final double topInset;
  final double backColumn;
  final RemoteCacheService? remoteCache;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final viewport = MediaQuery.sizeOf(context);
    final pageInsets = MediaQuery.paddingOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    const profile = BookCoverRenderProfile.details;
    final placeholderRadius = BorderRadius.circular(tokens.cardRadius);
    final theme = Theme.of(context);
    final pageColor = theme.scaffoldBackgroundColor;
    final dark = theme.brightness == Brightness.dark;
    final backBottom = topInset + kMinInteractiveDimension;
    final previousCoverTop = backBottom + 16;
    // Keep the reference position proportional as the status-bar inset changes.
    final coverWidth = math.min(220.0, availableWidth);
    final clearsBackColumn = (viewportWidth - coverWidth) / 2 >= backColumn;
    final coverTop = math.max(
      previousCoverTop * (64 / 88),
      clearsBackColumn ? topInset : backBottom,
    );
    // A single 2:3 poster slot determines hero geometry, never image pixels.
    const bottomPadding = 24.0;
    final availableHeight = math.max(
      0.0,
      viewport.height -
          math.max(
            pageInsets.bottom,
            View.of(context).padding.bottom / pixelRatio,
          ) -
          coverTop -
          bottomPadding,
    );
    final slotHeight = math.min(coverWidth * 1.5, availableHeight);
    final slotWidth = slotHeight / 1.5;
    final heroHeight = coverTop + slotHeight + bottomPadding;
    Widget foregroundSlot(Widget image) => Positioned(
      top: coverTop,
      left: (viewportWidth - slotWidth) / 2,
      width: slotWidth,
      height: slotHeight,
      child: ClipRRect(
        key: const Key('book-details-cover-slot'),
        borderRadius: placeholderRadius,
        child: image,
      ),
    );
    final placeholder = Stack(
      children: [
        foregroundSlot(_coverPlaceholder(context, title, placeholderRadius)),
      ],
    );
    return SizedBox(
      key: const Key('book-details-cover-hero'),
      width: double.infinity,
      height: heroHeight,
      child: BookCoverImage(
        cover: cover,
        remoteCache: remoteCache,
        title: title,
        profile: profile,
        cacheWidth: (slotWidth * pixelRatio).ceil().clamp(
          profile.cacheWidth,
          1080,
        ),
        cacheHeight: (slotHeight * pixelRatio).ceil().clamp(
          profile.cacheHeight,
          1620,
        ),
        resizePolicy: ResizeImagePolicy.fit,
        placeholder: placeholder,
        frameBuilder: (context, frame, index, _) {
          if (index == null) return placeholder;
          return _BookDetailsCoverFrames(
            frame: frame,
            title: title,
            builder: (foreground, background) => Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: _BookDetailsAmbientCover(frame: background),
                ),
                foregroundSlot(
                  FittedBox(fit: BoxFit.contain, child: foreground),
                ),
                Positioned.fill(
                  // Paint one physical pixel beyond the fractional hero edge.
                  bottom: -1 / pixelRatio,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const Key('book-details-cover-fade'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            pageColor.withValues(alpha: 0),
                            pageColor.withValues(alpha: dark ? 0.32 : 0.15),
                            pageColor.withValues(alpha: dark ? 0.76 : 0.52),
                            pageColor.withValues(alpha: dark ? 0.98 : 0.88),
                            pageColor,
                            pageColor,
                          ],
                          // Keep the overlap fully opaque in both themes.
                          stops: const [0.59, 0.70, 0.81, 0.93, 0.97, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BookDetailsCoverFrames extends StatefulWidget {
  const _BookDetailsCoverFrames({
    required this.frame,
    required this.title,
    required this.builder,
  });

  final Widget frame;
  final String title;
  final Widget Function(Widget foreground, Widget background) builder;

  @override
  State<_BookDetailsCoverFrames> createState() =>
      _BookDetailsCoverFramesState();
}

class _BookDetailsCoverFramesState extends State<_BookDetailsCoverFrames> {
  Future<Rect?>? _trim;

  // Image's frameBuilder receives its decoded RawImage with an optional label.
  static RawImage? _rawImage(Widget frame) {
    final child = frame is Semantics ? frame.child : frame;
    return child is RawImage ? child : null;
  }

  @override
  void initState() {
    super.initState();
    _readTrim(_rawImage(widget.frame)?.image);
  }

  @override
  void didUpdateWidget(covariant _BookDetailsCoverFrames oldWidget) {
    super.didUpdateWidget(oldWidget);
    final image = _rawImage(widget.frame)?.image;
    if (!identical(image, _rawImage(oldWidget.frame)?.image)) _readTrim(image);
  }

  void _readTrim(ui.Image? image) {
    _trim = image == null ? null : findBookDetailsCoverTrim(image);
  }

  @override
  Widget build(BuildContext context) {
    final raw = _rawImage(widget.frame);
    final image = raw?.image;
    return FutureBuilder<Rect?>(
      future: _trim,
      builder: (context, snapshot) {
        final source = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done ||
            source == null ||
            raw == null ||
            image == null) {
          return widget.builder(widget.frame, widget.frame);
        }

        final painter = _CroppedCoverPainter(image, source, raw);
        final artwork = SizedBox.fromSize(
          size: source.size / raw.scale,
          child: CustomPaint(painter: painter),
        );
        return widget.builder(widget.frame, artwork);
      },
    );
  }
}

class _CroppedCoverPainter extends CustomPainter {
  _CroppedCoverPainter(this.image, this.source, RawImage raw)
    : filterQuality = raw.filterQuality,
      invertColors = raw.invertColors;

  final ui.Image image;
  final Rect source;
  final FilterQuality filterQuality;
  final bool invertColors;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()
        ..filterQuality = filterQuality
        ..invertColors = invertColors,
    );
  }

  @override
  bool shouldRepaint(_CroppedCoverPainter oldDelegate) =>
      image != oldDelegate.image ||
      source != oldDelegate.source ||
      filterQuality != oldDelegate.filterQuality ||
      invertColors != oldDelegate.invertColors;
}

class _BookDetailsCoverSurface extends StatelessWidget {
  const _BookDetailsCoverSurface({required this.title, required this.cover});

  final String title;
  final BookCoverReference cover;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(context.appTokens.cardRadius);
    return ClipRRect(
      key: const Key('book-details-cover-slot'),
      borderRadius: radius,
      child: SizedBox.expand(
        child: BookCoverImage(
          cover: cover,
          title: title,
          placeholder: _coverPlaceholder(context, title, radius),
          profile: BookCoverRenderProfile.details,
        ),
      ),
    );
  }
}

Widget _coverPlaceholder(
  BuildContext context,
  String title,
  BorderRadius radius,
) {
  final colors = Theme.of(context).colorScheme;
  return Semantics(
    label: 'No cover available for $title',
    image: true,
    child: ExcludeSemantics(
      child: DecoratedBox(
        key: const Key('book-details-cover-placeholder'),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: radius,
        ),
        child: const Center(child: Icon(Icons.menu_book_outlined, size: 64)),
      ),
    ),
  );
}

class _BookDetailsAmbientCover extends StatelessWidget {
  const _BookDetailsAmbientCover({required this.frame});

  // The Image frame is already decoded. The second paint reuses its pixels.
  final Widget frame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.scaffoldBackgroundColor;
    final dark = theme.brightness == Brightness.dark;
    final edgeTint = background.withValues(alpha: dark ? 0.50 : 0.44);
    final sideTint = background.withValues(alpha: dark ? 0.40 : 0.29);
    final centerTint = background.withValues(alpha: dark ? 0.08 : 0.12);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: ClipRect(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    edgeTint,
                    sideTint,
                    centerTint,
                    centerTint,
                    sideTint,
                    edgeTint,
                  ],
                  stops: const [0, 0.17, 0.28, 0.72, 0.83, 1],
                ),
              ),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 10,
                  sigmaY: 10,
                  tileMode: TileMode.clamp,
                ),
                child: ClipRect(
                  child: Transform.scale(
                    // Crop the printed margins before applying the blur.
                    scale: 1.14,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: frame,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
