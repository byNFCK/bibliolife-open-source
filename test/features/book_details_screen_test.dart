import 'package:bibliolife/features/book_details/presentation/local_book_actions.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_selector_sheet.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_tile.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/core/database/app_database.dart' show AppDatabase;
import 'package:bibliolife/core/database/mappers/book_mapper.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_details_formatters.dart';
import 'package:bibliolife/features/book_details/presentation/screens/book_details_screen.dart';
import 'package:bibliolife/features/book_details/application/providers/book_file_export_service_provider.dart';
import 'package:bibliolife/features/book_details/application/providers/book_details_edit_service_provider.dart';
import 'package:bibliolife/features/book_details/application/providers/original_book_metadata_resolver_provider.dart';
import 'package:bibliolife/features/book_details/application/providers/book_cover_picker_provider.dart';
import 'package:bibliolife/features/book_details/application/services/book_details_edit_service.dart';
import 'package:bibliolife/features/book_details/application/services/original_book_metadata_resolver.dart';
import 'package:bibliolife/features/book_details/data/services/book_cover_picker.dart';
import 'package:bibliolife/features/book_details/application/services/book_file_export_service.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_description_panel.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_cover.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_cover_trim.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_float_menu.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_edit_sheet.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_toc_sheet.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/expandable_book_details_section.dart';
import 'package:bibliolife/features/bookmarks/application/providers/bookmark_repository_provider.dart';
import 'package:bibliolife/features/bookmarks/domain/models/bookmark_location_key.dart';
import 'package:bibliolife/features/bookmarks/domain/models/bookmark_metadata_update.dart';
import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/bookmarks/domain/repositories/bookmark_repository.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/library/data/repositories/drift_library_repository.dart';
import 'package:bibliolife/features/collections/application/providers/collection_repository_provider.dart';
import 'package:bibliolife/features/collections/domain/repositories/collection_repository.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/import/application/providers/import_repository_provider.dart';
import 'package:bibliolife/features/import/data/services/book_importer.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:bibliolife/features/metadata/domain/repositories/book_metadata_repository.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_repository_provider.dart';
import 'package:bibliolife/features/reader/application/providers/reader_annotation_repository_provider.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/domain/models/reader_launch_request.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_annotation_repository.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/features/reader/domain/repositories/reading_progress_repository.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/book_cover_provenance.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('book details formatters', () {
    test('progress clamps to 0 and 100 percent', () {
      expect(readingProgressPercent(-0.25), 0);
      expect(readingProgressPercent(1.25), 100);
      expect(readingProgressPercent(double.nan), 0);
      expect(readingProgressPercent(0.586), 59);
    });

    test('page labels never fabricate a missing total', () {
      expect(readingPageLabel(_progress(current: 17, total: 100)), '17/100');
      expect(readingPageLabel(_progress(current: 17)), '17');
      expect(readingPageLabel(_progress(current: 17, total: 0)), '17');
      expect(readingPageLabel(_progress()), isNull);
    });

    test('page falls back to the typed Readium locator position', () {
      expect(readingPageLabel(_progress(locatorPosition: 23)), '23');
      expect(readingPageLabel(_progress(locatorPosition: 0)), isNull);
      expect(readingPageLabel(_progress(locatorJson: '{malformed')), isNull);
    });

    test('file metadata uses uppercase format, middle dot and human size', () {
      expect(formatFileSize(2048), '2.0 KB');
      expect(formatFileSize(2 * 1024 * 1024), '2.0 MB');
      expect(formatFileSize(0), isNull);
      expect(
        formatBookFileSummary(_book(fileSizeBytes: 2 * 1024 * 1024)),
        'EPUB · 2.0 MB',
      );
    });
  });

  group('Book Details cover edge trim', () {
    const width = 200;
    const height = 160;

    for (final (name, left, right) in [
      ('normal', 0, 0),
      ('left white gutter', 8, 0),
      ('right pale gutter', 0, 10),
      ('both gutters', 7, 11),
    ]) {
      test(name, () {
        final pixels = ByteData(width * height * 4);
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final color = x < left
                ? 0xffffffff
                : x >= width - right
                ? 0xeee9e1ff
                : 0x297d78ff;
            pixels.setUint32((y * width + x) * 4, color);
          }
        }
        final trim = detectBookDetailsCoverTrim(pixels, width, height);
        expect(
          trim,
          left + right == 0
              ? isNull
              : ui.Rect.fromLTRB(
                  left.toDouble(),
                  0,
                  (width - right).toDouble(),
                  height.toDouble(),
                ),
        );
      });
    }

    test('keeps wide and illustrated bright areas', () {
      final pixels = ByteData(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          // The left field is too wide; the right one contains artwork.
          final light = x < 20 || (x >= width - 8 && y % 4 != 0);
          pixels.setUint32(
            (y * width + x) * 4,
            light ? 0xffffffff : 0x297d78ff,
          );
        }
      }
      expect(detectBookDetailsCoverTrim(pixels, width, height), isNull);
    });

    test('keeps a near-white artwork area without an abrupt boundary', () {
      final pixels = ByteData(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final color = x < 8 ? 0xf0f0f0ff : 0xddddddff;
          pixels.setUint32((y * width + x) * 4, color);
        }
      }
      expect(detectBookDetailsCoverTrim(pixels, width, height), isNull);
    });
  });

  testWidgets('renders the exact core structure and collapsed metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(),
        progress: _progress(current: 17, total: 100, progression: 0.58),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(find.text('A local EPUB'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Page: 17/100'), findsOneWidget);
    expect(find.text('Progress: 58%'), findsOneWidget);
    expect(find.byKey(const Key('bookmark-action')), findsOneWidget);
    expect(find.byKey(const Key('annotations-action')), findsNothing);
    expect(find.byKey(const Key('favorite-action')), findsOneWidget);
    expect(find.textContaining('Author: '), findsNothing);
    expect(find.byIcon(Icons.history_edu_outlined), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Author, .+')), findsOneWidget);
    expect(find.textContaining('File:'), findsOneWidget);
    expect(find.textContaining('Language: '), findsOneWidget);
    expect(find.text('More information'), findsOneWidget);
    expect(find.textContaining('ISBN: '), findsNothing);
  });

  testWidgets('non-empty cover path uses the file-backed cover widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(book: _book(coverPath: '/definitely-missing/biblio-cover.png')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BookDetailsCover), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('missing local cover keeps the framed production slot', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(book: _book()));
    await tester.pumpAndSettle();

    final slot = find.byKey(const Key('book-details-cover-slot'));
    final placeholder = find.byKey(const Key('book-details-cover-placeholder'));
    expect(slot, findsOneWidget);
    expect(placeholder, findsOneWidget);
    expect(tester.getSize(slot).aspectRatio, closeTo(2 / 3, 0.02));
    final decoration =
        tester.widget<DecoratedBox>(placeholder).decoration as BoxDecoration;
    expect(
      decoration.border!.top.color,
      Theme.of(tester.element(placeholder)).colorScheme.outlineVariant,
    );
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  for (final coverCase in [
    (name: 'portrait', size: const Size(320, 480), dark: true, gutter: 0.0),
    (name: 'wide', size: const Size(360, 180), dark: false, gutter: 0.0),
    (name: 'tall', size: const Size(160, 640), dark: true, gutter: 0.0),
    (
      name: 'square on a compact screen',
      size: const Size(240, 240),
      dark: false,
      gutter: 0.0,
    ),
    (
      name: 'trimmed square on a compact screen',
      size: const Size(240, 240),
      dark: true,
      gutter: 10.0,
    ),
  ]) {
    testWidgets(
      '${coverCase.name} cover stays compact inside the ambient hero',
      (tester) async {
        final viewport = switch (coverCase.name) {
          'square on a compact screen' => const Size(280, 568),
          'trimmed square on a compact screen' => const Size(320, 568),
          _ => const Size(393, 878),
        };
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);

        final directory = Directory.systemTemp.createTempSync(
          'book-details-hero-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final file = File('${directory.path}/cover.png');
        final cover = find.byType(BookDetailsCover);
        const profile = BookCoverRenderProfile.details;
        final provider = ResizeImage(
          FileImage(file),
          width: profile.cacheWidth,
          height: profile.cacheHeight,
          policy: ResizeImagePolicy.fit,
        );
        await tester.pumpWidget(const SizedBox());
        final imageContext = tester.element(find.byType(SizedBox));

        await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawColor(Colors.white, BlendMode.src);
          canvas.drawRect(
            Rect.fromLTRB(
              coverCase.gutter,
              0,
              coverCase.size.width - coverCase.gutter,
              coverCase.size.height,
            ),
            Paint()..color = Colors.deepOrange,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            coverCase.size.width.toInt(),
            coverCase.size.height.toInt(),
          );
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          image.dispose();
          picture.dispose();
          await file.writeAsBytes(png.buffer.asUint8List());
          await precacheImage(provider, imageContext);
        });
        final scheme = coverCase.dark
            ? fallbackDarkColorScheme
            : fallbackLightColorScheme;
        await tester.pumpWidget(
          _subject(
            book: _book(coverPath: file.path),
            scheme: scheme,
          ),
        );
        await tester.pumpAndSettle();

        final blur = find.descendant(
          of: cover,
          matching: find.byType(ImageFiltered),
        );
        final foreground = find.byKey(const Key('book-details-cover-slot'));
        expect(
          tester.widget<ImageFiltered>(blur).imageFilter,
          ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10, tileMode: TileMode.clamp),
        );
        expect(
          find.descendant(of: foreground, matching: find.byType(ShaderMask)),
          findsNothing,
        );
        expect(find.ancestor(of: foreground, matching: blur), findsNothing);
        final rawImage = find.byType(RawImage);
        final foregroundFrame = tester.widget<RawImage>(
          find.descendant(of: foreground, matching: rawImage),
        );
        expect(foregroundFrame.image, isNotNull);
        if (coverCase.gutter > 0) {
          final paintedBackground = find.descendant(
            of: blur,
            matching: find.byWidgetPredicate(
              (widget) => widget is CustomPaint && widget.painter != null,
            ),
          );
          for (var i = 0; i < 50 && paintedBackground.evaluate().isEmpty; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(paintedBackground, findsOneWidget);
          expect(tester.getSize(paintedBackground), const Size(220, 240));
        } else {
          final backgroundFrame = tester.widget<RawImage>(
            find.descendant(of: blur, matching: rawImage),
          );
          expect(backgroundFrame.image, same(foregroundFrame.image));
        }
        final coverRect = tester.getRect(foreground);
        final blurRect = tester.getRect(blur);
        final expectedCoverTop = viewport.width <= 320 ? 72.0 : 64.0;
        expect(coverRect.size, const Size(220, 330));
        expect(coverRect.center.dx, closeTo(tester.getCenter(cover).dx, 0.01));
        expect(coverRect.top, closeTo(expectedCoverTop, 0.01));
        final fit = tester.widget<FittedBox>(
          find.descendant(of: foreground, matching: find.byType(FittedBox)),
        );
        expect(fit.fit, BoxFit.contain);
        final rawSize = tester.getSize(
          find.descendant(of: foreground, matching: rawImage),
        );
        expect(rawSize.aspectRatio, closeTo(coverCase.size.aspectRatio, 0.01));
        expect(
          tester.widget<ClipRRect>(foreground).borderRadius,
          BorderRadius.circular(24),
        );
        expect(blurRect.topLeft, Offset.zero);
        expect(blurRect.width, viewport.width);
        expect(blurRect.height, closeTo(expectedCoverTop + 330 + 24, 0.01));
        final fade = find.byKey(const Key('book-details-cover-fade'));
        final gradient =
            (tester.widget<DecoratedBox>(fade).decoration as BoxDecoration)
                    .gradient!
                as LinearGradient;
        final fadeRect = tester.getRect(fade);
        expect(fadeRect.topLeft, blurRect.topLeft);
        expect(fadeRect.width, blurRect.width);
        expect(
          fadeRect.bottom - blurRect.bottom,
          closeTo(1 / tester.view.devicePixelRatio, 0.01),
        );
        expect(gradient.colors.first.a, 0);
        expect(gradient.colors.reversed.take(2), [
          scheme.surface,
          scheme.surface,
        ]);
        expect(gradient.stops!.reversed.skip(1).first, lessThan(1));
        final layerStack = find
            .ancestor(of: fade, matching: find.byType(Stack))
            .first;
        final layers = tester.widget<Stack>(layerStack).children;
        final foregroundLayer = find
            .ancestor(of: foreground, matching: find.byType(Positioned))
            .first;
        expect(layers[1], same(tester.widget(foregroundLayer)));
        expect(layers.last, isA<Positioned>());
        final back = find.byTooltip('Back');
        expect(tester.getTopLeft(back).dy, greaterThanOrEqualTo(24));
        expect(coverRect.overlaps(tester.getRect(back)), isFalse);
        expect(back.hitTestable(), findsOneWidget);
        final systemBars = tester
            .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
              find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .value;
        expect(systemBars.statusBarColor, Colors.transparent);
        expect(
          systemBars.statusBarIconBrightness,
          coverCase.dark ? Brightness.light : Brightness.dark,
        );
        final title = find.byKey(const Key('book-details-title'));
        expect(tester.getTopLeft(title).dy - blurRect.bottom, closeTo(6, 0.01));
        expect(find.bySemanticsLabel('Cover of A local EPUB'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('More information keeps the required metadata order', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(isbn: '9780306406157', publishedDate: '2024-03-05'),
      ),
    );
    await tester.pumpAndSettle();

    final language = find.textContaining('Language:');
    final published = find.textContaining('Publication date:');
    final file = find.textContaining('File:');
    expect(language, findsOneWidget);
    expect(published, findsOneWidget);
    expect(file, findsOneWidget);
    expect(find.textContaining('ISBN:'), findsNothing);
    expect(find.textContaining('Publication date:'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('more-information-toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('more-information-toggle')));
    await tester.pumpAndSettle();
    expect(language, findsOneWidget);
    expect(published, findsOneWidget);
    expect(file, findsOneWidget);
    expect(
      tester.getTopLeft(language).dy,
      lessThan(tester.getTopLeft(published).dy),
    );
    expect(
      tester.getTopLeft(published).dy,
      lessThan(tester.getTopLeft(file).dy),
    );
    expect(find.textContaining('Publication date:'), findsOneWidget);
    expect(
      tester.getTopLeft(file).dy,
      lessThan(tester.getTopLeft(find.textContaining('ISBN:')).dy),
    );
  });

  testWidgets('renders rich metadata and hides absent optional labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(
          authors: const ['Alice Author', 'Bob Author'],
          contributors: const ['Casey Editor'],
          subjects: const ['Fiction', 'History'],
          identifiers: const ['urn:uuid:package-id'],
          publishedDate: '2024-03-05',
          rights: 'CC BY',
          seriesName: 'Chronicles',
          seriesIndex: 2,
          catalogSourceId: 'builtin-project-gutenberg',
          metadataOrigins: const {
            'title': 'epub',
            'description': 'remote',
            'subjects': 'epub+remote',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alice Author, Bob Author'), findsOneWidget);
    expect(find.textContaining('Publication date: 2024-03-05'), findsOneWidget);
    expect(find.textContaining('Genre: History'), findsNothing);
    expect(find.textContaining('Rights: CC BY'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const Key('more-information-toggle')),
    );
    await tester.tap(find.byKey(const Key('more-information-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Genre: History'), findsOneWidget);
    expect(find.textContaining('Rights: CC BY'), findsOneWidget);
    expect(
      find.textContaining('Identifiers: urn:uuid:package-id'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Metadata: EPUB and Project Gutenberg'),
      findsOneWidget,
    );
    expect(find.textContaining('Contributors:'), findsNothing);
    expect(find.textContaining('Series:'), findsNothing);
  });

  testWidgets(
    'ISBN remains hidden until More information expands and preserves X',
    (tester) async {
      await tester.pumpWidget(
        _subject(book: _book(publisher: null, isbn: '080442957X')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Publisher:'), findsNothing);
      expect(find.textContaining('ISBN: 080442957X'), findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('more-information-toggle')),
      );
      await tester.tap(find.byKey(const Key('more-information-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ISBN: 080442957X'), findsOneWidget);
    },
  );

  testWidgets(
    'expanded information has exact order and omits ISBN identifier',
    (tester) async {
      await tester.pumpWidget(
        _subject(
          book: _book(
            isbn: '9780306406157',
            publishedDate: '2024-03-05',
            subjects: const ['One', 'Two'],
            source: 'Archive source',
            identifiers: const ['978-0-306-40615-7', 'urn:uuid:package-id'],
            modifiedDate: '2025-01-02T03:04:05Z',
            rights: 'Public domain',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('more-information-toggle')),
      );
      await tester.tap(find.byKey(const Key('more-information-toggle')));
      await tester.pumpAndSettle();

      final fields = [
        find.textContaining('Language:'),
        find.textContaining('Publication date:'),
        find.textContaining('File:'),
        find.textContaining('ISBN:'),
        find.textContaining('Subgenres or tags:'),
        find.textContaining('Source:'),
        find.textContaining('Identifiers:'),
        find.textContaining('Modified:'),
        find.textContaining('Rights:'),
      ];
      for (var index = 0; index < fields.length - 1; index++) {
        expect(
          tester.getTopLeft(fields[index]).dy,
          lessThan(tester.getTopLeft(fields[index + 1]).dy),
        );
      }
      expect(find.textContaining('urn:uuid:package-id'), findsOneWidget);
      expect(find.textContaining('978-0-306-40615-7'), findsNothing);
      expect(find.textContaining('Publication date:'), findsOneWidget);
    },
  );

  testWidgets('More information exposes one semantic toggle and state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_subject(book: _book()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();

    final toggle = find.bySemanticsLabel('Book metadata');
    expect(toggle, findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Language: uk-UA')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('File: EPUB · 2.0 MB')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('ISBN: 9780306406157')), findsNothing);
    expect(
      tester.getSemantics(toggle).getSemanticsData().flagsCollection.isExpanded,
      ui.Tristate.isFalse,
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(toggle).getSemanticsData().flagsCollection.isExpanded,
      ui.Tristate.isTrue,
    );
    expect(find.byKey(const Key('more-information-content')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Language: uk-UA')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('File: EPUB · 2.0 MB')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('ISBN: 9780306406157')),
      findsOneWidget,
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('more-information-content')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Language: uk-UA')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('File: EPUB · 2.0 MB')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets(
    'expanded metadata rows are non-selectable and collapse through the shared contour',
    (tester) async {
      await tester.pumpWidget(
        _subject(
          book: _book(
            source: 'Archive source',
            identifiers: const ['urn:uuid:package-id'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();

      final toggle = find.byKey(const Key('more-information-toggle'));
      for (final label in ['Source:', 'Identifiers:']) {
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        final row = find.textContaining(label);
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('more-information-content')), findsNothing);
      }

      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final identifiers = find.textContaining('Identifiers:');
      expect(find.byType(SelectableText), findsNothing);
      await tester.longPress(identifiers);
      await tester.pump();
      expect(find.byType(SelectableText), findsNothing);
      if (find
          .byKey(const Key('more-information-content'))
          .evaluate()
          .isEmpty) {
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }

      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('more-information-content')), findsOneWidget);
    },
  );

  testWidgets(
    'Description and More information share structure and expand independently',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final description = List.filled(30, 'Long description preview').join(' ');
      await tester.pumpWidget(
        _subject(
          book: _book(
            authors: const ['Alice Author', 'Bob Author'],
            description: description,
            publishedDate: '2024-03-05',
            subjects: const ['Fiction'],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ExpandableBookDetailsSection), findsNWidgets(2));
      final sharedMaterials = tester.widgetList<Material>(
        find.descendant(
          of: find.byType(ExpandableBookDetailsSection),
          matching: find.byType(Material),
        ),
      );
      final sharedShapes = sharedMaterials
          .map((material) => material.shape)
          .whereType<RoundedRectangleBorder>()
          .toList();
      expect(sharedShapes, hasLength(2));
      expect(sharedShapes[0].side, sharedShapes[1].side);
      expect(sharedShapes[0].side.width, 1);
      expect(
        sharedShapes[0].side.color,
        Theme.of(
          tester.element(find.byType(ExpandableBookDetailsSection).first),
        ).colorScheme.outlineVariant,
      );
      expect(sharedShapes[0].borderRadius, sharedShapes[1].borderRadius);
      final sharedAnimations = tester.widgetList<AnimatedSize>(
        find.descendant(
          of: find.byType(ExpandableBookDetailsSection),
          matching: find.byType(AnimatedSize),
        ),
      );
      expect(sharedAnimations, hasLength(2));
      expect(
        sharedAnimations.every(
          (animation) =>
              animation.duration == const Duration(milliseconds: 200) &&
              animation.curve == Curves.easeInOutCubic,
        ),
        true,
      );
      final sharedInks = tester.widgetList<Ink>(
        find.descendant(
          of: find.byType(ExpandableBookDetailsSection),
          matching: find.byType(Ink),
        ),
      );
      expect(
        sharedInks.every(
          (ink) => (ink.decoration! as BoxDecoration).border == null,
        ),
        true,
      );
      final ordered = [
        find.byKey(const Key('book-author')),
        find.byKey(const Key('book-description-text')),
        find.text('More information'),
      ];
      for (var index = 0; index < ordered.length - 1; index++) {
        expect(
          tester.getTopLeft(ordered[index]).dy,
          lessThan(tester.getTopLeft(ordered[index + 1]).dy),
        );
      }
      expect(find.textContaining('Publication date:'), findsOneWidget);
      expect(find.textContaining('Genre: Fiction & Literature'), findsNothing);
      expect(
        find.bySemanticsLabel('Genre: Fiction & Literature'),
        findsNothing,
      );
      expect(find.bySemanticsLabel(description), findsOneWidget);
      expect(find.bySemanticsLabel('Book metadata'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('description-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(description));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('book-description-text')))
            .maxLines,
        isNull,
      );
      expect(find.byKey(const Key('more-information-content')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('more-information-toggle')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Book metadata'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('more-information-content')), findsOneWidget);
      await tester.pumpAndSettle();
      final metadataOrder = [
        find.textContaining('Language:'),
        find.textContaining('Publication date:'),
        find.textContaining('File:'),
        find.textContaining('Genre:'),
      ];
      for (var index = 0; index < metadataOrder.length - 1; index++) {
        expect(
          tester.getTopLeft(metadataOrder[index]).dy,
          lessThan(tester.getTopLeft(metadataOrder[index + 1]).dy),
        );
      }
      expect(
        find.textContaining('Genre: Fiction & Literature'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('book-description-text')))
            .maxLines,
        isNull,
      );

      await tester.ensureVisible(find.byKey(const Key('description-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(description));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('book-description-text')))
            .maxLines,
        3,
      );
      expect(
        find.textContaining('Genre: Fiction & Literature'),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('preview-only metadata is a static outlined block', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _subject(
        book: _book(
          author: null,
          authors: const [],
          description: null,
          isbn: null,
          subjects: const [],
          identifiers: const [],
          source: null,
          modifiedDate: null,
          rights: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book-author')), findsNothing);
    expect(find.byType(BookDescriptionPanel), findsNothing);
    expect(find.text('More information'), findsOneWidget);
    expect(find.textContaining('Language:'), findsOneWidget);
    expect(find.textContaining('File:'), findsOneWidget);
    expect(find.text('More'), findsNothing);
    expect(find.text('Less'), findsNothing);
    expect(find.byKey(const Key('more-information-content')), findsNothing);
    expect(find.byType(ExpandableBookDetailsSection), findsOneWidget);
    final information = tester.getSemantics(
      find.bySemanticsLabel('Book metadata'),
    );
    expect(
      information.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      false,
    );
    semantics.dispose();
  });

  testWidgets('long Unicode title wraps without truncation on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longTitle =
        'Дуже довга назва книги, яка точно не повинна займати більше двох рядків';
    await tester.pumpWidget(_subject(book: _book(title: longTitle)));
    await tester.pumpAndSettle();

    final title = find.text(longTitle);
    expect(tester.widget<Text>(title).maxLines, isNull);
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('Read main segment opens the exact book route', (tester) async {
    await tester.pumpWidget(_subject(book: _book(id: 'exact-reader')));
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('continue-reading'));
    expect(find.text('Read'), findsOneWidget);
    expect(find.byKey(const Key('book-details-more-actions')), findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('reader:exact-reader'), findsOneWidget);
  });

  testWidgets('Read and menu segments dispatch only their own actions', (
    tester,
  ) async {
    var readCalls = 0;
    var menuActionCalls = 0;
    final router = GoRouter(
      initialLocation: '/details',
      routes: [
        GoRoute(
          path: '/details',
          builder: (context, state) => Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: BookDetailsFloatMenu(
                  onRead: () => readCalls++,
                  actions: [
                    BookDetailsMenuAction(
                      label: 'Only menu action',
                      icon: Icons.save_alt,
                      onSelected: () => menuActionCalls++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: buildAppTheme(fallbackLightColorScheme),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    final read = find.byKey(const Key('continue-reading'));
    final menu = find.byKey(const Key('book-details-more-actions'));
    final row = find.byKey(const Key('book-details-action-row'));
    final gap = find.byKey(const Key('book-details-action-gap'));
    final menuButton = find.byKey(const Key('book-details-menu-button'));
    final readRect = tester.getRect(read);
    final menuRect = tester.getRect(menuButton);
    final gapRect = tester.getRect(gap);
    expect(gapRect.width, 6);
    expect(gapRect.left, closeTo(readRect.right, 0.5));
    expect(gapRect.right, closeTo(menuRect.left, 0.5));
    expect(readRect.height, 56);
    expect(menuRect.height, 56);
    expect(readRect.width, closeTo(tester.getRect(row).width - 62, 0.5));
    expect(menuRect.width, 56);
    expect(
      tester.widget<FilledButton>(read).style!.backgroundColor!.resolve({}),
      fallbackLightColorScheme.primaryContainer,
    );
    final menuMaterial = tester.widget<Material>(menuButton);
    expect(menuMaterial.color, fallbackLightColorScheme.primaryContainer);
    expect(
      (menuMaterial.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(28),
    );
    expect(
      (menuMaterial.shape! as RoundedRectangleBorder).side,
      BorderSide.none,
    );
    expect(tester.widget<SizedBox>(gap).child, isNull);
    expect(
      find
          .ancestor(of: gap, matching: find.byType(Material))
          .evaluate()
          .where(
            (element) =>
                (element.widget as Material).color ==
                fallbackLightColorScheme.primaryContainer,
          ),
      isEmpty,
    );
    await tester.tapAt(Offset(gapRect.center.dx, readRect.center.dy));
    await tester.pumpAndSettle();
    expect(readCalls, 0);
    expect(menuActionCalls, 0);

    await tester.tap(read);
    await tester.pumpAndSettle();
    expect(readCalls, 1);
    expect(menuActionCalls, 0);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(readCalls, 1);
    expect(menuActionCalls, 0);
    final item = find.byKey(
      const ValueKey('book-details-menu-Only menu action'),
    );
    expect(item, findsOneWidget);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(readCalls, 1);
    expect(menuActionCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating menu opens below with a small gap at 390 and 412 px', (
    tester,
  ) async {
    for (final width in [390.0, 412.0]) {
      for (final scheme in [
        fallbackLightColorScheme,
        fallbackDarkColorScheme,
      ]) {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          _subject(
            book: _book(
              tocJson:
                  '{"version":1,"entries":[{"title":"Chapter",'
                  '"locatorJson":"{\\"href\\":\\"chapter.xhtml\\"}",'
                  '"children":[]}]}',
            ),
            scheme: scheme,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('book-details-more-actions')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('book-details-more-actions')));
        await tester.pumpAndSettle();

        final menuItem = find.byKey(
          const ValueKey('book-details-menu-Add to collection'),
        );
        expect(menuItem, findsOneWidget);
        final menuRect = tester.getRect(_menuSurface(scheme));
        final buttonRect = tester.getRect(
          find.byKey(const Key('continue-reading')),
        );
        final triggerRect = tester.getRect(
          find.byKey(const Key('book-details-more-actions')),
        );
        final readRect = tester.getRect(
          find.byKey(const Key('continue-reading')),
        );
        final actionRowRect = tester.getRect(
          find.byKey(const Key('book-details-action-row')),
        );
        final gapRect = tester.getRect(
          find.byKey(const Key('book-details-action-gap')),
        );
        final menuButtonRect = tester.getRect(
          find.byKey(const Key('book-details-menu-button')),
        );
        final menuButton = tester.widget<Material>(
          find.byKey(const Key('book-details-menu-button')),
        );
        final menuShape = menuButton.shape! as RoundedRectangleBorder;
        expect(menuRect.left, greaterThanOrEqualTo(0));
        expect(menuRect.right, lessThanOrEqualTo(width));
        expect(menuRect.top, greaterThanOrEqualTo(0));
        expect(menuRect.bottom, lessThanOrEqualTo(844));
        expect(menuRect.top - triggerRect.bottom, closeTo(8, 1));
        expect(menuRect.right, closeTo(triggerRect.right, 1));
        expect(triggerRect.bottom, lessThan(buttonRect.bottom + 1));
        expect(triggerRect.width, 56);
        expect(triggerRect.height, 56);
        expect(menuButton.color, scheme.primaryContainer);
        expect(menuShape.side, BorderSide.none);
        expect(menuShape.borderRadius, BorderRadius.circular(28));
        expect(menuButtonRect.left, closeTo(gapRect.right, 0.5));
        expect(gapRect.left, closeTo(readRect.right, 0.5));
        expect(gapRect.width, 6);
        expect(menuButtonRect.width, 56);
        expect(menuButtonRect.height, 56);
        expect(readRect.height, 56);
        expect(readRect.width, closeTo(actionRowRect.width - 62, 0.5));
        final readButton = tester.widget<FilledButton>(
          find.byKey(const Key('continue-reading')),
        );
        expect(
          readButton.style!.backgroundColor!.resolve({}),
          scheme.primaryContainer,
        );
        expect(
          find
              .ancestor(
                of: find.byKey(const Key('book-details-action-gap')),
                matching: find.byType(Material),
              )
              .evaluate()
              .where(
                (element) =>
                    (element.widget as Material).color ==
                    scheme.primaryContainer,
              ),
          isEmpty,
        );
        for (final label in [
          'Add to collection',
          'Edit book',
          'Save book file',
          'Delete',
        ]) {
          expect(
            find.byKey(ValueKey('book-details-menu-$label')),
            findsOneWidget,
          );
        }
        expect(
          find.byKey(const ValueKey('book-details-menu-Table of contents')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('floating menu flips above when below would hit the safe area', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 300);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    final router = GoRouter(
      initialLocation: '/details',
      routes: [
        GoRoute(
          path: '/details',
          builder: (context, state) => Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: SizedBox(
                  width: 320,
                  child: BookDetailsFloatMenu(
                    onRead: () {},
                    actions: [
                      BookDetailsMenuAction(
                        label: 'Add to collection',
                        icon: Icons.playlist_add,
                        onSelected: () {},
                      ),
                      BookDetailsMenuAction(
                        label: 'Edit book',
                        icon: Icons.edit_outlined,
                        onSelected: () {},
                      ),
                      BookDetailsMenuAction(
                        label: 'Delete',
                        icon: Icons.delete_outline,
                        onSelected: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: buildAppTheme(fallbackLightColorScheme),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    final trigger = find.byKey(const Key('book-details-more-actions'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    final menuRect = tester.getRect(_menuSurface(fallbackLightColorScheme));
    final triggerRect = tester.getRect(trigger);
    final safeInsets = MediaQuery.viewPaddingOf(tester.element(trigger));
    expect(triggerRect.top - menuRect.bottom, closeTo(8, 1));
    expect(safeInsets.top, 0);
    expect(safeInsets.bottom, 24);
    expect(menuRect.top, greaterThanOrEqualTo(safeInsets.top));
    expect(menuRect.bottom, lessThanOrEqualTo(300 - safeInsets.bottom));
    expect(menuRect.left, greaterThanOrEqualTo(0));
    expect(menuRect.right, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating menu dismisses outside, on Back, and reopens once', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(
          tocJson:
              '{"version":1,"entries":[{"title":"Chapter",'
              '"locatorJson":"{\\"href\\":\\"chapter.xhtml\\"}",'
              '"children":[]}]}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trigger = find.byKey(const Key('book-details-more-actions'));
    final item = find.byKey(
      const ValueKey('book-details-menu-Add to collection'),
    );
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(item, findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(item, findsNothing);

    for (var i = 0; i < 3; i++) {
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(item, findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(item, findsNothing);
      expect(find.text('A local EPUB'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('TOC stays outside the menu and route changes close the menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(
          tocJson:
              '{"version":1,"entries":[{"title":"Chapter",'
              '"locatorJson":"{\\"href\\":\\"chapter.xhtml\\"}",'
              '"children":[]}]}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trigger = find.byKey(const Key('book-details-more-actions'));
    final tocButton = find.byKey(const Key('toc-action'));
    await tester.ensureVisible(tocButton);
    await tester.pumpAndSettle();
    await tester.tap(tocButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-toc-modal')), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(trigger));
    router.pushNamed(AppRoutes.readerName, pathParameters: {'bookId': 'book'});
    await tester.pumpAndSettle();
    expect(find.text('reader:book'), findsOneWidget);
    expect(find.text('Table of contents'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing details removes an open menu overlay', (tester) async {
    await tester.pumpWidget(
      _subject(
        book: _book(
          tocJson:
              '{"version":1,"entries":[{"title":"Chapter",'
              '"locatorJson":"{\\"href\\":\\"chapter.xhtml\\"}",'
              '"children":[]}]}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trigger = find.byKey(const Key('book-details-more-actions'));
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('book-details-menu-Add to collection')),
      findsOneWidget,
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('book-details-menu-Add to collection')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reusable menu selects one action once and closes on book change',
    (tester) async {
      var selections = 0;
      var reads = 0;
      final router = GoRouter(
        initialLocation: '/details/first',
        routes: [
          GoRoute(
            path: '/details/:bookId',
            builder: (context, state) => Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: BookDetailsFloatMenu(
                    key: ValueKey(state.pathParameters['bookId']),
                    onRead: () => reads++,
                    actions: [
                      BookDetailsMenuAction(
                        label: 'First action',
                        icon: Icons.bookmark_outline,
                        onSelected: () => selections++,
                      ),
                      BookDetailsMenuAction(
                        label: 'Second action',
                        icon: Icons.share_outlined,
                        onSelected: () => selections++,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      final trigger = find.byKey(const Key('book-details-more-actions'));
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      final second = find.byKey(
        const ValueKey('book-details-menu-Second action'),
      );
      final colors = Theme.of(tester.element(trigger)).colorScheme;
      final menuRect = tester.getRect(_menuSurface(colors));
      expect(menuRect.top - tester.getRect(trigger).bottom, closeTo(8, 1));
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(selections, 1);
      expect(find.text('First action'), findsNothing);
      expect(find.text('Second action'), findsNothing);

      await tester.tap(trigger);
      await tester.pumpAndSettle();
      router.go('/details/second');
      await tester.pumpAndSettle();
      expect(find.text('First action'), findsNothing);
      expect(find.text('Second action'), findsNothing);
      expect(selections, 1);
      expect(reads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('menu exposes five actions in order without old controls', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(book: _book()));
    await tester.pumpAndSettle();
    expect(find.text('Read'), findsOneWidget);
    expect(find.byKey(const Key('bookmark-action')), findsOneWidget);
    expect(find.byKey(const Key('favorite-action')), findsOneWidget);
    expect(find.byKey(const Key('add-book-to-collection')), findsNothing);
    expect(find.byKey(const Key('refresh-book-metadata')), findsNothing);
    expect(find.byKey(const Key('delete-book')), findsNothing);

    final trigger = find.byKey(const Key('book-details-more-actions'));
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    const labels = [
      'Add to favorites',
      'Add to collection',
      'Edit book',
      'Save book file',
      'Delete',
    ];
    final rects = <Rect>[];
    for (final label in labels) {
      final item = find.byKey(ValueKey('book-details-menu-$label'));
      expect(item, findsOneWidget);
      rects.add(tester.getRect(item));
    }
    expect(
      find.byKey(const ValueKey('book-details-menu-Table of contents')),
      findsNothing,
    );
    expect(find.text('Refresh'), findsNothing);
    expect(find.byType(MenuItemButton), findsNWidgets(5));
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].top, rects[i - 1].bottom);
    }
    final surface = find
        .ancestor(
          of: find.byKey(const ValueKey('book-details-menu-Delete')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Material &&
                widget.color ==
                    Theme.of(
                      tester.element(trigger),
                    ).colorScheme.surfaceContainerHigh,
          ),
        )
        .first;
    expect(tester.getSize(surface).height, 5 * 48 + 16);
    final delete = tester.widget<MenuItemButton>(
      find.descendant(
        of: find.byKey(const ValueKey('book-details-menu-Delete')),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(
      delete.style?.foregroundColor?.resolve({}),
      Theme.of(tester.element(trigger)).colorScheme.error,
    );
  });

  testWidgets('Delete confirmation cancels and confirms exactly once', (
    tester,
  ) async {
    final repository = _LibraryRepository(_book());
    await tester.pumpWidget(
      _subject(book: repository.book, libraryRepository: repository),
    );
    await tester.pumpAndSettle();
    final trigger = find.byKey(const Key('book-details-more-actions'));
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Delete')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('book-details-menu-Delete')),
      findsNothing,
    );
    expect(find.text('Delete book?'), findsOneWidget);
    expect(
      find.text(
        'Remove "A local EPUB" and its saved reading progress from BiblioLife?',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 0);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Delete')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Delete'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.deleteCalls, 1);
  });

  testWidgets('menu Add to collection opens the existing selector once', (
    tester,
  ) async {
    final collectionRepository = _DetailsCollectionRepository();
    await tester.pumpWidget(
      _subject(book: _book(), collectionRepository: collectionRepository),
    );
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(
      find.byKey(const ValueKey('book-details-menu-Add to collection')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('book-details-menu-Add to collection')),
      findsNothing,
    );
    expect(find.text('No collections yet.'), findsOneWidget);
    expect(collectionRepository.watchAllCalls, 1);
  });

  testWidgets(
    'internal refresh still invalidates the book stream without writing',
    (tester) async {
      final book = _book();
      final library = _LibraryRepository(book);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryRepositoryProvider.overrideWithValue(library)],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  ref.watch(bookByIdProvider(book.id));
                  return TextButton(
                    onPressed: () => LocalBookActions(
                      context,
                      ref,
                      book,
                    ).run(LocalBookAction.refresh),
                    child: const Text('Internal test trigger'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = library.watchAllCalls;
      expect(before, greaterThan(0));
      await tester.tap(find.text('Internal test trigger'));
      await tester.pumpAndSettle();
      expect(library.watchAllCalls, greaterThan(before));
      expect(library.updateCalls, 0);
    },
  );

  testWidgets('library menu has five actions without Refresh', (tester) async {
    final book = _book();
    await tester.pumpWidget(
      _subject(book: book, startAtHost: true, hostBookTile: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More options for ${book.title}'));
    await tester.pumpAndSettle();
    const labels = [
      'Add to favorites',
      'Add to collection',
      'Edit book',
      'Save book file',
      'Delete',
    ];
    expect(find.text('Refresh'), findsNothing);
    expect(find.byType(MenuItemButton), findsNWidgets(5));
    final rects = [
      for (final label in labels)
        tester.getRect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(MenuItemButton),
          ),
        ),
    ];
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].top, rects[i - 1].bottom);
    }
    final colors = Theme.of(tester.element(find.text('Delete'))).colorScheme;
    final surface = find
        .ancestor(
          of: find.text('Delete'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Material &&
                widget.color == colors.surfaceContainerHigh,
          ),
        )
        .first;
    expect(tester.getSize(surface).height, 5 * 48 + 16);
  });

  testWidgets('Edit book closes the menu and opens one prefilled editor', (
    tester,
  ) async {
    final book = _book(
      author: 'Current author',
      coverPath: '/missing/current-cover.jpg',
    );
    await tester.pumpWidget(_subject(book: book));
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('book-details-menu-Edit book')),
      findsNothing,
    );
    expect(find.byType(BookEditSheet), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('book-edit-title')))
          .controller!
          .text,
      book.title,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('book-edit-author')))
          .controller!
          .text,
      'Current author',
    );
    expect(
      find.descendant(
        of: find.byType(BookEditSheet),
        matching: find.byType(BookDetailsCover),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('book-edit-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(BookEditSheet), findsNothing);
  });

  testWidgets('Restore original is a draft until Cancel', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('book-restore-cancel-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() async {
        await database.close();
        await root.delete(recursive: true);
      }),
    );
    final coverDirectory = Directory('${root.path}/covers')
      ..createSync(recursive: true);
    final customCover = File('${coverDirectory.path}/book-manual-existing.jpg')
      ..writeAsBytesSync([4, 5, 6]);
    final book =
        _book(
          title: 'Edited title',
          author: 'Edited author',
          filePath: '${root.path}/source.epub',
          coverPath: customCover.path,
          authors: const ['Edited author'],
        ).withCover(
          coverPath: customCover.path,
          provenance: BookCoverProvenance.manual,
        );
    await tester.runAsync(
      () => database.booksDao.insertBook(book.toBooksCompanion()),
    );
    final resolver = _ControlledOriginalBookMetadataResolver(
      result: OriginalBookMetadata(
        title: 'Source title',
        author: 'First Author, Second Author',
        authors: const ['First Author', 'Second Author'],
        coverBytes: Uint8List.fromList([7, 8, 9]),
        coverExtension: 'png',
      ),
    );
    await tester.pumpWidget(
      _subject(
        book: book,
        libraryRepository: DriftLibraryRepository(database.booksDao),
        bookDetailsEditService: BookDetailsEditService(
          booksDao: database.booksDao,
          coverStorage: CoverStorageService(
            documentsDirectory: () async => root,
            imageValidator: const _AcceptImageValidator(),
          ),
        ),
        originalBookMetadataResolver: resolver,
      ),
    );
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('book-edit-restore-original')),
    );
    await tester.tap(find.byKey(const Key('book-edit-restore-original')));
    await tester.pumpAndSettle();

    expect(resolver.calls, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('book-edit-title')))
          .controller!
          .text,
      'Source title',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('book-edit-author')))
          .controller!
          .text,
      'First Author, Second Author',
    );
    expect(find.byKey(const Key('book-edit-selected-cover')), findsOneWidget);
    final beforeCancel = (await tester.runAsync(
      () => database.booksDao.getBookById(book.id),
    ))!;
    expect(beforeCancel.title, 'Edited title');
    expect(beforeCancel.author, 'Edited author');
    expect(beforeCancel.coverPath, customCover.path);
    expect(await tester.runAsync(customCover.exists), isTrue);

    await tester.ensureVisible(find.byKey(const Key('book-edit-cancel')));
    await tester.tap(find.byKey(const Key('book-edit-cancel')));
    await tester.pumpAndSettle();
    final afterCancel = (await tester.runAsync(
      () => database.booksDao.getBookById(book.id),
    ))!;
    expect(afterCancel.title, 'Edited title');
    expect(afterCancel.author, 'Edited author');
    expect(afterCancel.coverPath, customCover.path);
    expect(await tester.runAsync(customCover.exists), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Restore original Save persists source fields and cover', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('book-restore-save-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() async {
        await database.close();
        await root.delete(recursive: true);
      }),
    );
    final coverDirectory = Directory('${root.path}/covers')
      ..createSync(recursive: true);
    final customCover = File('${coverDirectory.path}/book-manual-existing.jpg')
      ..writeAsBytesSync([4, 5, 6]);
    final book =
        _book(
          title: 'Edited title',
          author: 'Edited author',
          filePath: '${root.path}/source.epub',
          coverPath: customCover.path,
          authors: const ['Edited author'],
        ).withCover(
          coverPath: customCover.path,
          provenance: BookCoverProvenance.manual,
        );
    await tester.runAsync(
      () => database.booksDao.insertBook(book.toBooksCompanion()),
    );
    final originalBytes = Uint8List.fromList([7, 8, 9]);
    final resolver = _ControlledOriginalBookMetadataResolver(
      result: OriginalBookMetadata(
        title: 'Source title',
        author: 'First Author, Second Author',
        authors: const ['First Author', 'Second Author'],
        coverBytes: originalBytes,
        coverExtension: 'png',
      ),
    );
    final editService = _CapturingBookDetailsEditService(
      booksDao: database.booksDao,
      coverStorage: CoverStorageService(
        documentsDirectory: () async => root,
        imageValidator: const _AcceptImageValidator(),
      ),
    );
    await tester.pumpWidget(
      _subject(
        book: book,
        libraryRepository: DriftLibraryRepository(database.booksDao),
        bookDetailsEditService: editService,
        originalBookMetadataResolver: resolver,
      ),
    );
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('book-edit-restore-original')),
    );
    await tester.tap(find.byKey(const Key('book-edit-restore-original')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(customCover.exists), isTrue);
    await tester.ensureVisible(find.byKey(const Key('book-edit-save')));
    await tester.tap(find.byKey(const Key('book-edit-save')));
    await tester.pumpAndSettle();

    final saveCall = editService.lastCall!;
    expect(saveCall.title, 'Source title');
    expect(saveCall.author, 'First Author, Second Author');
    expect(saveCall.updateTitle, isTrue);
    expect(saveCall.updateAuthor, isTrue);
    expect(saveCall.replacementCoverBytes, originalBytes);
    expect(saveCall.replacementCoverProvenance, BookCoverProvenance.embedded);
    expect(saveCall.replacementAuthors, ['First Author', 'Second Author']);
    expect(saveCall.clearCover, isFalse);
    expect(saveCall.cleanupReplacedManualCover, isTrue);
    final unchanged = (await tester.runAsync(
      () => database.booksDao.getBookById(book.id),
    ))!;
    expect(unchanged.title, 'Edited title');
    expect(unchanged.coverPath, customCover.path);
    expect(await tester.runAsync(customCover.exists), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('manual edits after Restore original are saved', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('book-restore-edit-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() async {
        await database.close();
        await root.delete(recursive: true);
      }),
    );
    final book = _book(
      title: 'Edited title',
      author: 'Edited author',
      filePath: '${root.path}/source.epub',
      authors: const ['Edited author'],
    );
    await tester.runAsync(
      () => database.booksDao.insertBook(book.toBooksCompanion()),
    );
    final resolver = _ControlledOriginalBookMetadataResolver(
      result: const OriginalBookMetadata(
        title: 'Source title',
        author: 'Source author',
        authors: ['Source author'],
        coverBytes: null,
        coverExtension: null,
      ),
    );
    final editService = _CapturingBookDetailsEditService(
      booksDao: database.booksDao,
      coverStorage: CoverStorageService(
        documentsDirectory: () async => root,
        imageValidator: const _AcceptImageValidator(),
      ),
    );
    await tester.pumpWidget(
      _subject(
        book: book,
        libraryRepository: DriftLibraryRepository(database.booksDao),
        bookDetailsEditService: editService,
        originalBookMetadataResolver: resolver,
      ),
    );
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('book-edit-restore-original')),
    );
    await tester.tap(find.byKey(const Key('book-edit-restore-original')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('book-edit-title')),
      'Chosen title',
    );
    await tester.enterText(
      find.byKey(const Key('book-edit-author')),
      'Chosen author',
    );
    await tester.ensureVisible(find.byKey(const Key('book-edit-save')));
    await tester.tap(find.byKey(const Key('book-edit-save')));
    await tester.pumpAndSettle();

    final saveCall = editService.lastCall!;
    expect(saveCall.title, 'Chosen title');
    expect(saveCall.author, 'Chosen author');
    expect(saveCall.replacementAuthors, isNull);
    expect(saveCall.clearCover, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Restore with no source cover clears only on Save', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('book-restore-empty-'),
    ))!;
    addTearDown(
      () => tester.runAsync(() async {
        await database.close();
        await root.delete(recursive: true);
      }),
    );
    final coverDirectory = Directory('${root.path}/covers')
      ..createSync(recursive: true);
    final customCover = File('${coverDirectory.path}/book-manual-existing.jpg')
      ..writeAsBytesSync([4, 5, 6]);
    final book =
        _book(
          title: 'Edited title',
          author: 'Edited author',
          filePath: '${root.path}/source.epub',
          coverPath: customCover.path,
        ).withCover(
          coverPath: customCover.path,
          provenance: BookCoverProvenance.manual,
        );
    await tester.runAsync(
      () => database.booksDao.insertBook(book.toBooksCompanion()),
    );
    final resolver = _ControlledOriginalBookMetadataResolver(
      result: const OriginalBookMetadata(
        title: 'Source title',
        author: null,
        authors: [],
        coverBytes: null,
        coverExtension: null,
      ),
    );
    final editService = _CapturingBookDetailsEditService(
      booksDao: database.booksDao,
      coverStorage: CoverStorageService(
        documentsDirectory: () async => root,
        imageValidator: const _AcceptImageValidator(),
      ),
    );
    await tester.pumpWidget(
      _subject(
        book: book,
        libraryRepository: DriftLibraryRepository(database.booksDao),
        bookDetailsEditService: editService,
        originalBookMetadataResolver: resolver,
      ),
    );
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('book-edit-restore-original')),
    );
    await tester.tap(find.byKey(const Key('book-edit-restore-original')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-edit-selected-cover')), findsNothing);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(await tester.runAsync(customCover.exists), isTrue);
    final beforeSave = (await tester.runAsync(
      () => database.booksDao.getBookById(book.id),
    ))!;
    expect(beforeSave.title, 'Edited title');
    expect(beforeSave.coverPath, customCover.path);

    await tester.ensureVisible(find.byKey(const Key('book-edit-save')));
    await tester.tap(find.byKey(const Key('book-edit-save')));
    await tester.pumpAndSettle();
    final saveCall = editService.lastCall!;
    expect(saveCall.title, 'Source title');
    expect(saveCall.author, '');
    expect(saveCall.replacementCoverBytes, isNull);
    expect(saveCall.clearCover, isTrue);
    expect(saveCall.removeManualCover, isFalse);
    expect(saveCall.cleanupReplacedManualCover, isTrue);
    final unchanged = (await tester.runAsync(
      () => database.booksDao.getBookById(book.id),
    ))!;
    expect(unchanged.title, 'Edited title');
    expect(unchanged.coverPath, customCover.path);
    expect(await tester.runAsync(customCover.exists), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('failed Restore original leaves the entire draft unchanged', (
    tester,
  ) async {
    final book =
        _book(
          title: 'Edited title',
          author: 'Edited author',
          coverPath: '/missing/manual-cover.jpg',
        ).withCover(
          coverPath: '/missing/manual-cover.jpg',
          provenance: BookCoverProvenance.manual,
        );
    final resolver = _ControlledOriginalBookMetadataResolver(
      error: const OriginalBookMetadataUnavailable(),
    );
    await tester.pumpWidget(
      _subject(book: book, originalBookMetadataResolver: resolver),
    );
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('book-edit-title')),
      'Unchanged draft',
    );
    await tester.enterText(
      find.byKey(const Key('book-edit-author')),
      'Draft author',
    );
    await tester.ensureVisible(
      find.byKey(const Key('book-edit-restore-original')),
    );
    await tester.tap(find.byKey(const Key('book-edit-restore-original')));
    await tester.pumpAndSettle();

    expect(resolver.calls, 1);
    expect(find.text(AppStrings.restoreOriginalError), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('book-edit-title')))
          .controller!
          .text,
      'Unchanged draft',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('book-edit-author')))
          .controller!
          .text,
      'Draft author',
    );
    expect(
      find.descendant(
        of: find.byType(BookEditSheet),
        matching: find.byType(BookDetailsCover),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cover picker cancellation keeps the current edit draft', (
    tester,
  ) async {
    final picker = _FakeBookCoverPicker(null);
    await tester.pumpWidget(_subject(book: _book(), bookCoverPicker: picker));
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-edit-change-cover')));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(find.byKey(const Key('book-edit-selected-cover')), findsNothing);
    expect(find.byKey(const Key('book-edit-error')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('book-edit-title')))
          .controller!
          .text,
      'A local EPUB',
    );
  });

  testWidgets('cover picker failure is shown without discarding text', (
    tester,
  ) async {
    final picker = _FakeBookCoverPicker(null, error: StateError('picker'));
    await tester.pumpWidget(_subject(book: _book(), bookCoverPicker: picker));
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('book-edit-title')),
      'Draft title',
    );
    await tester.tap(find.byKey(const Key('book-edit-change-cover')));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(find.text('Could not select a book cover.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('book-edit-title')))
          .controller!
          .text,
      'Draft title',
    );
  });

  testWidgets('selected cover remains a draft until Save', (tester) async {
    final source = Uint8List.fromList([1, 2, 3]);
    final picker = _FakeBookCoverPicker(
      PickedBookCover(bytes: source, extension: 'jpg'),
    );
    await tester.pumpWidget(_subject(book: _book(), bookCoverPicker: picker));
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-edit-change-cover')));
    await tester.pumpAndSettle();

    expect(picker.calls, 1);
    expect(find.byKey(const Key('book-edit-selected-cover')), findsOneWidget);
    expect(find.byKey(const Key('book-edit-error')), findsNothing);
    await tester.tap(find.byKey(const Key('book-edit-cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(BookEditSheet), findsNothing);
    expect(source, [1, 2, 3]);
  });

  testWidgets('save failure leaves editor open with entered values', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final failingService = _FailingBookDetailsEditService(
      booksDao: database.booksDao,
      coverStorage: CoverStorageService(),
    );
    await tester.pumpWidget(
      _subject(book: _book(), bookDetailsEditService: failingService),
    );
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('book-edit-title')),
      'Keep this draft',
    );
    await tester.ensureVisible(find.byKey(const Key('book-edit-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-edit-save')));
    await tester.pumpAndSettle();

    expect(find.byType(BookEditSheet), findsOneWidget);
    expect(find.text('Could not save book details.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('book-edit-title')))
          .controller!
          .text,
      'Keep this draft',
    );
  });

  testWidgets('empty title blocks save and keeps editor open', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final failingService = _FailingBookDetailsEditService(
      booksDao: database.booksDao,
      coverStorage: CoverStorageService(),
    );
    await tester.pumpWidget(
      _subject(book: _book(), bookDetailsEditService: failingService),
    );
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('book-edit-title')), '   ');
    await tester.ensureVisible(find.byKey(const Key('book-edit-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-edit-save')));
    await tester.pumpAndSettle();

    expect(find.byType(BookEditSheet), findsOneWidget);
    expect(find.text('Enter a book title.'), findsOneWidget);
    expect(failingService.calls, 0);
  });

  for (final size in [const Size(390, 844), const Size(412, 915)]) {
    for (final scheme in [fallbackLightColorScheme, fallbackDarkColorScheme]) {
      testWidgets(
        'edit sheet fits ${size.width} px ${scheme.brightness.name} with keyboard inset',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpWidget(_subject(book: _book(), scheme: scheme));
          await tester.pumpAndSettle();
          await _openDetailsMenu(tester);
          await tester.tap(
            find.byKey(const ValueKey('book-details-menu-Edit book')),
          );
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('book-edit-save')));
          await tester.pumpAndSettle();

          final saveRect = tester.getRect(
            find.byKey(const Key('book-edit-save')),
          );
          expect(saveRect.left, greaterThanOrEqualTo(0));
          expect(saveRect.right, lessThanOrEqualTo(size.width));
          expect(saveRect.bottom, lessThanOrEqualTo(size.height));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Edit book save updates the watched Book Details immediately', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final book = _book();
    await database.booksDao.insertBook(book.toBooksCompanion());
    final service = BookDetailsEditService(
      booksDao: database.booksDao,
      coverStorage: CoverStorageService(),
    );
    await tester.pumpWidget(
      _subject(
        book: book,
        libraryRepository: DriftLibraryRepository(database.booksDao),
        bookDetailsEditService: service,
      ),
    );
    await tester.pumpAndSettle();
    await _openDetailsMenu(tester);
    await tester.tap(find.byKey(const ValueKey('book-details-menu-Edit book')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('book-edit-title')),
      'Updated from editor',
    );
    await tester.enterText(
      find.byKey(const Key('book-edit-author')),
      'Updated author',
    );
    await tester.ensureVisible(find.byKey(const Key('book-edit-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-edit-save')));
    await tester.pumpAndSettle();

    expect(find.byType(BookEditSheet), findsNothing);
    expect(find.text('Updated from editor'), findsOneWidget);
    expect(find.text('Updated author'), findsOneWidget);
    final saved = await database.booksDao.getBookById(book.id);
    expect(saved!.coverPath, book.coverPath);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Save book file closes the menu and invokes export once', (
    tester,
  ) async {
    late Finder menuItem;
    await tester.pumpWidget(
      _subject(
        book: _book(),
        bookFileExportService: _ControlledBookFileExportService(
          BookFileSaveOutcome.saved,
          onExport: () => expect(menuItem.evaluate(), isEmpty),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trigger = find.byKey(const Key('book-details-more-actions'));
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    menuItem = find.byKey(const ValueKey('book-details-menu-Save book file'));
    expect(menuItem, findsOneWidget);
    await tester.tap(menuItem);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('book-details-menu-Save book file')),
      findsNothing,
    );
    expect(find.text('Book file saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Save cancellation is silent and unavailable source reports error',
    (tester) async {
      await tester.pumpWidget(
        _subject(
          book: _book(),
          bookFileExportService: _ControlledBookFileExportService(
            BookFileSaveOutcome.cancelled,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('book-details-more-actions')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book-details-more-actions')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('book-details-menu-Save book file')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Book file saved.'), findsNothing);
      expect(find.text('Could not save the book file.'), findsNothing);

      await tester.pumpWidget(
        _subject(
          book: _book(),
          bookFileExportService: _ControlledBookFileExportService(
            BookFileSaveOutcome.unavailable,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('book-details-more-actions')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book-details-more-actions')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('book-details-menu-Save book file')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('The original book file is unavailable.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Back pops to the previous route', (tester) async {
    await tester.pumpWidget(_subject(book: _book(), startAtHost: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open details'), findsOneWidget);
  });

  testWidgets('missing total renders Page current without slash zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(book: _book(), progress: _progress(current: 9, total: 0)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Page: 9'), findsOneWidget);
    expect(find.textContaining('/0'), findsNothing);
  });

  testWidgets('missing current page omits Page but keeps Progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(book: _book(), progress: _progress(progression: 0.25)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Page:'), findsNothing);
    expect(find.text('Progress: 25%'), findsOneWidget);
  });

  testWidgets('Bookmark opens the combined saved-items modal', (tester) async {
    await tester.pumpWidget(_subject(book: _book(), bookmarks: [_bookmark()]));
    await tester.pumpAndSettle();

    final semantics = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Bookmarks and annotations' &&
          widget.properties.selected == true,
    );
    expect(semantics, findsOneWidget);
    await _scrollDetails(tester, const Key('bookmark-action'));
    await tester.tap(find.byKey(const Key('bookmark-action')));
    await tester.pumpAndSettle();
    expect(find.text('Bookmarks and annotations'), findsOneWidget);
    expect(find.byKey(const Key('book-saved-items-switcher')), findsOneWidget);
    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.text('Annotations'), findsOneWidget);
    expect(find.byKey(const Key('bookmarks-list')), findsOneWidget);
    expect(find.text('Saved place'), findsOneWidget);
    final selector = find.byKey(const Key('book-saved-items-switcher'));
    BiblioTabs<Object> tabs() => tester.widget(selector);
    expect(tabs().selectedId, tabs().items.first.id);
    final bookmarks = find.byKey(
      const Key('bookmarks-list'),
      skipOffstage: false,
    );
    final bookmarksElement = tester.element(bookmarks);
    await tester.tap(find.text('Annotations'));
    await tester.pumpAndSettle();
    expect(tabs().selectedId, tabs().items.last.id);
    expect(tester.element(bookmarks), same(bookmarksElement));
    await tester.tap(find.text('Bookmarks'));
    await tester.pumpAndSettle();
    expect(tabs().selectedId, tabs().items.first.id);
    expect(find.text('Saved place'), findsOneWidget);
  });

  testWidgets('TOC uses the canonical reader-style modal and nested rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(
          tocJson:
              '{"version":1,"entries":[{"title":"Chapter",'
              '"locatorJson":"{\\"href\\":\\"chapter.xhtml\\"}",'
              '"children":[{"title":"A long nested section title that wraps safely on narrow screens",'
              '"locatorJson":"{\\"href\\":\\"section.xhtml\\"}","children":[]}]}]}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollDetails(tester, const Key('toc-action'));
    await tester.tap(find.byKey(const Key('toc-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book-toc-modal')), findsOneWidget);
    expect(find.byKey(const Key('book-toc-drag-handle')), findsOneWidget);
    expect(find.text('Table of contents'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    final list = tester.widget<ListView>(
      find.byKey(const Key('book-toc-list')),
    );
    expect(
      list.padding,
      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
    final nested = tester
        .getTopLeft(find.textContaining('long nested section'))
        .dx;
    final root = tester.getTopLeft(find.text('Chapter')).dx;
    expect(nested - root, BookTocPresentation.nestedIndent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TOC remains safe at narrow width and 1.5 text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: _subject(
          book: _book(
            tocJson:
                '{"version":1,"entries":[{"title":"A deliberately long chapter title that must wrap without clipping",'
                '"locatorJson":"{\\"href\\":\\"chapter.xhtml\\"}","children":[]}]}',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollDetails(tester, const Key('toc-action'));
    await tester.tap(find.byKey(const Key('toc-action')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('TOC selection preserves the stored reader locator', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(
          tocJson:
              '{"version":1,"entries":[{"title":"Open chapter","locatorJson":"{\\"href\\":\\"chapter.xhtml\\"}","children":[]}]}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollDetails(tester, const Key('toc-action'));
    await tester.tap(find.byKey(const Key('toc-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-toc-entry-0')));
    await tester.pumpAndSettle();
    expect(find.text('locator:{"href":"chapter.xhtml"}'), findsOneWidget);
  });

  testWidgets('combined modal switches to the existing annotations content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(id: 'exact-annotations'),
        annotations: [_annotation(bookId: 'exact-annotations')],
      ),
    );
    await tester.pumpAndSettle();

    await _scrollDetails(tester, const Key('bookmark-action'));
    await tester.tap(find.byKey(const Key('bookmark-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annotations'));
    await tester.pumpAndSettle();

    expect(find.text('selected annotation'), findsOneWidget);
    expect(find.text('No bookmarks yet.'), findsNothing);
  });

  testWidgets('combined modal closes in place and reopens on Bookmarks', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(book: _book(), bookmarks: [_bookmark()]));
    await tester.pumpAndSettle();
    final detailsTitle = tester.element(
      find.byKey(const Key('book-details-title')),
    );

    await _scrollDetails(tester, const Key('bookmark-action'));
    await tester.tap(find.byKey(const Key('bookmark-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annotations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      tester.element(find.byKey(const Key('book-details-title'))),
      same(detailsTitle),
    );
    await tester.tap(find.byKey(const Key('bookmark-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bookmarks-list')), findsOneWidget);
    expect(find.text('Saved place'), findsOneWidget);
  });

  for (final scenario in [
    (
      size: const Size(320, 700),
      scale: 1.0,
      scheme: fallbackLightColorScheme,
      name: 'narrow',
    ),
    (
      size: const Size(400, 800),
      scale: 1.5,
      scheme: fallbackDarkColorScheme,
      name: 'large text in dark theme',
    ),
  ]) {
    testWidgets('combined modal keeps tabs in the header on ${scenario.name}', (
      tester,
    ) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: scenario.size,
            textScaler: TextScaler.linear(scenario.scale),
          ),
          child: _subject(
            book: _book(),
            bookmarks: [_bookmark()],
            scheme: scenario.scheme,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollDetails(tester, const Key('bookmark-action'));
      await tester.tap(find.byKey(const Key('bookmark-action')));
      await tester.pumpAndSettle();

      final divider = find.byKey(
        const Key('reader-menu-upper-decorative-strip'),
      );
      final selector = find.byKey(const Key('book-saved-items-switcher'));
      final context = tester.element(selector);
      expect(Theme.of(context).brightness, scenario.scheme.brightness);
      expect(MediaQuery.textScalerOf(context).scale(10), 10 * scenario.scale);
      final titleBounds = tester.getRect(
        find.text('Bookmarks and annotations'),
      );
      final tabsBounds = tester.getRect(selector);
      final dividerBounds = tester.getRect(divider);
      final contentBounds = tester.getRect(
        find.byKey(const Key('bookmarks-list')),
      );
      expect(titleBounds.bottom, lessThan(tabsBounds.top));
      expect(tabsBounds.bottom, lessThan(dividerBounds.top));
      expect(dividerBounds.bottom, lessThanOrEqualTo(contentBounds.top));
      expect(
        dividerBounds.top - tabsBounds.bottom,
        closeTo(tabsBounds.top - titleBounds.bottom, 0.01),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final favorite in [false, true]) {
    testWidgets(
      'Favorite ${favorite ? 'active' : 'inactive'} state is semantic and visible',
      (tester) async {
        await tester.pumpWidget(_subject(book: _book(isFavorite: favorite)));
        await tester.pumpAndSettle();

        expect(
          find.byIcon(favorite ? Icons.favorite : Icons.favorite_border),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label ==
                    (favorite ? 'Remove from favorites' : 'Add to favorites') &&
                widget.properties.selected == favorite,
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'library menu dispatches the existing collection, editor, export and delete flows',
    (tester) async {
      final book = _book();
      var exports = 0;
      final collections = _DetailsCollectionRepository();
      await tester.pumpWidget(
        _subject(
          book: book,
          startAtHost: true,
          hostBookTile: true,
          collectionRepository: collections,
          bookFileExportService: _ControlledBookFileExportService(
            BookFileSaveOutcome.saved,
            onExport: () => exports++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> openMenu() async {
        await tester.tap(find.byTooltip('More options for ${book.title}'));
        await tester.pumpAndSettle();
      }

      await openMenu();
      await tester.tap(find.text('Add to collection'));
      await tester.pumpAndSettle();
      expect(find.byType(CollectionSelectorSheet), findsOneWidget);
      expect(collections.watchAllCalls, greaterThan(0));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await openMenu();
      await tester.tap(find.text('Edit book'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<BookEditSheet>(find.byType(BookEditSheet)).book.id,
        book.id,
      );
      await tester.tap(find.byKey(const Key('book-edit-cancel')));
      await tester.pumpAndSettle();
      await openMenu();
      await tester.tap(find.text('Save book file'));
      await tester.pumpAndSettle();
      expect(exports, 1);
      await openMenu();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete book?'), findsOneWidget);
      expect(find.textContaining(book.title), findsWidgets);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'favorite menu and button share pending state and updated value',
    (tester) async {
      final library = _LiveFavoriteRepository();
      addTearDown(library.close);
      await tester.pumpWidget(
        _subject(book: _book(), libraryRepository: library),
      );
      await tester.pumpAndSettle();
      await _openDetailsMenu(tester);
      await tester.tap(find.text('Add to favorites'));
      await tester.pump();
      await tester.pump();
      expect(library.favoriteCalls, 1);
      final favoriteButton = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const Key('favorite-action')),
          matching: find.byType(IconButton),
        ),
      );
      expect(favoriteButton.onPressed, isNull);
      library.pending.complete();
      await tester.pumpAndSettle();
      await _openDetailsMenu(tester);
      expect(find.text('Remove from favorites'), findsOneWidget);
      await tester.tap(find.text('Remove from favorites'));
      await tester.pumpAndSettle();
      expect(library.favoriteCalls, 2);
      await _openDetailsMenu(tester);
      expect(find.text('Add to favorites'), findsOneWidget);
    },
  );

  testWidgets('duplicate favorite tap is guarded while mutation is pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    final library = _LibraryRepository(_book(), favoritePending: pending);
    await tester.pumpWidget(
      _subject(book: _book(), libraryRepository: library),
    );
    await tester.pumpAndSettle();
    final action = find.byKey(const Key('favorite-action'));
    await _scrollDetails(tester, const Key('favorite-action'));
    await tester.tap(action);
    await tester.pump();
    await tester.tap(action, warnIfMissed: false);
    await tester.pump();

    expect(library.favoriteCalls, 1);
    pending.complete();
    await tester.pump();
  });

  testWidgets('description collapses to three lines, expands and collapses', (
    tester,
  ) async {
    final description = List.filled(
      30,
      'Long Unicode description текст',
    ).join(' ');
    await tester.pumpWidget(_subject(book: _book(description: description)));
    await tester.pumpAndSettle();

    var text = tester.widget<Text>(
      find.byKey(const Key('book-description-text')),
    );
    expect(text.maxLines, 3);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(
      find.descendant(
        of: find.byType(BookDescriptionPanel),
        matching: find.byType(Stack),
      ),
      findsOneWidget,
    );
    final animation = tester.widget<AnimatedSize>(
      find.descendant(
        of: find.byType(BookDescriptionPanel),
        matching: find.byType(AnimatedSize),
      ),
    );
    expect(animation.duration, const Duration(milliseconds: 200));
    expect(animation.curve, Curves.easeInOutCubic);
    final paddings = tester
        .widgetList<Padding>(
          find.descendant(
            of: find.byType(BookDescriptionPanel),
            matching: find.byType(Padding),
          ),
        )
        .map((padding) => padding.padding);
    expect(paddings, contains(const EdgeInsets.fromLTRB(16, 16, 16, 32)));
    final materials = tester.widgetList<Material>(
      find.descendant(
        of: find.byType(BookDescriptionPanel),
        matching: find.byType(Material),
      ),
    );
    expect(
      materials.any((material) => material.color == Colors.transparent),
      true,
    );
    final outlineShapes = materials
        .map((material) => material.shape)
        .whereType<RoundedRectangleBorder>()
        .toList();
    expect(outlineShapes, hasLength(1));
    expect(outlineShapes.single.side.width, 1);
    expect(
      outlineShapes.single.side.color,
      Theme.of(
        tester.element(find.byType(BookDescriptionPanel)),
      ).colorScheme.outlineVariant,
    );
    expect(
      find.descendant(
        of: find.byType(BookDescriptionPanel),
        matching: find.byIcon(Icons.expand_more),
      ),
      findsNothing,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('description-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('description-toggle')));
    await tester.pumpAndSettle();
    text = tester.widget<Text>(find.byKey(const Key('book-description-text')));
    expect(text.maxLines, isNull);
    expect(find.text('Less'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('description-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('description-toggle')));
    await tester.pumpAndSettle();
    text = tester.widget<Text>(find.byKey(const Key('book-description-text')));
    expect(text.maxLines, 3);
  });

  testWidgets('empty description omits the panel and More action', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(book: _book(description: ' \n\t ')));
    await tester.pumpAndSettle();

    expect(find.byType(BookDescriptionPanel), findsNothing);
    expect(find.byKey(const Key('description-toggle')), findsNothing);
  });

  testWidgets('unavailable optional metadata rows are omitted', (tester) async {
    await tester.pumpWidget(
      _subject(
        book: _book(
          language: null,
          publisher: null,
          isbn: null,
          subjects: const [],
          identifiers: const [],
          rights: null,
          source: null,
          modifiedDate: null,
          fileSizeBytes: 0,
          format: BookFormat.unknown,
          fileExtension: '',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Language:'), findsNothing);
    expect(find.textContaining('Publisher:'), findsNothing);
    expect(find.textContaining('ISBN:'), findsNothing);
    expect(find.textContaining('0 B'), findsNothing);
    expect(find.text('More information'), findsNothing);
  });

  for (final scenario in [
    (size: const Size(320, 700), scale: 1.0, name: 'narrow screen'),
    (size: const Size(400, 800), scale: 1.5, name: 'text scale 1.5'),
  ]) {
    testWidgets('${scenario.name} has no overflow', (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: scenario.size,
            textScaler: TextScaler.linear(scenario.scale),
          ),
          child: _subject(
            book: _book(
              title: 'A very long title that needs two safe lines',
              author: 'A very long Unicode author name Автор Автор Автор',
              publisher: 'A publisher with an exceptionally long legal name',
            ),
            progress: _progress(current: 123456, total: 999999),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('continue-reading')), findsOneWidget);
      expect(
        find.byKey(const Key('book-details-management-actions')),
        findsNothing,
      );
    });
  }

  for (final scheme in [
    fallbackLightColorScheme,
    fallbackDarkColorScheme,
    ColorScheme.fromSeed(seedColor: Colors.teal),
  ]) {
    testWidgets(
      '${scheme.brightness.name} ${scheme.primary} uses semantic Material roles',
      (tester) async {
        await tester.pumpWidget(_subject(book: _book(), scheme: scheme));
        await tester.pumpAndSettle();
        final continueButton = tester.widget<FilledButton>(
          find.byKey(const Key('continue-reading')),
        );
        expect(
          continueButton.style!.backgroundColor!.resolve({}),
          scheme.primaryContainer,
        );
        final card = tester.widget<Ink>(
          find
              .ancestor(
                of: find.byKey(const Key('more-information-toggle')),
                matching: find.byType(Ink),
              )
              .first,
        );
        final decoration = card.decoration! as BoxDecoration;
        expect(decoration.color, scheme.surfaceContainerLow);
      },
    );
  }

  testWidgets('missing book keeps a working Back action', (tester) async {
    await tester.pumpWidget(_subject(book: null, startAtHost: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();

    expect(find.text('Book not found.'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });
}

Finder _menuSurface(ColorScheme colors) => find.byWidgetPredicate((widget) {
  if (widget is! Material ||
      widget.color != colors.surfaceContainerHigh ||
      widget.shape is! RoundedRectangleBorder) {
    return false;
  }
  return (widget.shape! as RoundedRectangleBorder).borderRadius ==
      BorderRadius.circular(20);
});

Future<void> _scrollDetails(WidgetTester tester, Key key) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
  await tester.pumpAndSettle();
  expect(find.byKey(key), findsOneWidget);
}

Widget _subject({
  required LibraryBook? book,
  ReadingProgress? progress,
  List<LibraryBookmark> bookmarks = const [],
  List<ReaderAnnotation> annotations = const [],
  LibraryRepository? libraryRepository,
  BookImporter? bookImporter,
  CollectionRepository? collectionRepository,
  ColorScheme? scheme,
  bool startAtHost = false,
  bool hostBookTile = false,
  BookFileExportService? bookFileExportService,
  BookDetailsEditService? bookDetailsEditService,
  BookCoverPicker? bookCoverPicker,
  OriginalBookMetadataResolver? originalBookMetadataResolver,
}) {
  final library =
      libraryRepository ?? _LibraryRepository(book ?? _book(id: 'other'));
  final router = GoRouter(
    initialLocation: startAtHost ? '/host' : '/books/${book?.id ?? 'missing'}',
    routes: [
      GoRoute(
        path: '/host',
        builder: (context, state) => Scaffold(
          body: hostBookTile && book != null
              ? Consumer(
                  builder: (context, ref, child) {
                    ref.watch(bookByIdProvider(book.id));
                    return LibraryBookTile(book: book);
                  },
                )
              : Center(
                  child: FilledButton(
                    onPressed: () =>
                        context.push('/books/${book?.id ?? 'missing'}'),
                    child: const Text('Open details'),
                  ),
                ),
        ),
      ),
      GoRoute(
        path: AppRoutes.libraryPath,
        builder: (context, state) =>
            const Scaffold(body: Text('Library route')),
      ),
      GoRoute(
        path: AppRoutes.bookDetailsPath,
        name: AppRoutes.bookDetailsName,
        builder: (context, state) =>
            BookDetailsScreen(bookId: state.pathParameters['bookId']!),
      ),
      GoRoute(
        path: AppRoutes.readerPath,
        name: AppRoutes.readerName,
        builder: (context, state) {
          final request = state.extra as ReaderLaunchRequest?;
          return Scaffold(
            body: Column(
              children: [
                Text('reader:${state.pathParameters['bookId']}'),
                if (request?.initialLocatorJson != null)
                  Text('locator:${request!.initialLocatorJson}'),
              ],
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.bookAnnotationsPath,
        name: AppRoutes.bookAnnotationsName,
        builder: (context, state) => Scaffold(
          body: Text('annotations:${state.pathParameters['bookId']}'),
        ),
      ),
    ],
  );
  final colorScheme = scheme ?? fallbackLightColorScheme;
  return ProviderScope(
    overrides: [
      libraryRepositoryProvider.overrideWithValue(library),
      if (bookImporter != null)
        bookImporterProvider.overrideWithValue(bookImporter),
      if (bookFileExportService != null)
        bookFileExportServiceProvider.overrideWithValue(bookFileExportService),
      if (bookDetailsEditService != null)
        bookDetailsEditServiceProvider.overrideWithValue(
          bookDetailsEditService,
        ),
      if (bookCoverPicker != null)
        bookCoverPickerProvider.overrideWithValue(bookCoverPicker),
      if (originalBookMetadataResolver != null)
        originalBookMetadataResolverProvider.overrideWithValue(
          originalBookMetadataResolver,
        ),
      if (collectionRepository != null)
        collectionRepositoryProvider.overrideWithValue(collectionRepository),
      readingProgressRepositoryProvider.overrideWithValue(
        _ProgressRepository(progress),
      ),
      bookmarkRepositoryProvider.overrideWithValue(
        _BookmarkRepository(bookmarks),
      ),
      readerAnnotationRepositoryProvider.overrideWithValue(
        _AnnotationRepository(annotations),
      ),
    ],
    child: MaterialApp.router(
      theme: buildAppTheme(colorScheme),
      darkTheme: buildAppTheme(colorScheme),
      themeMode: colorScheme.brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      routerConfig: router,
    ),
  );
}

Future<void> _openDetailsMenu(WidgetTester tester) async {
  final trigger = find.byKey(const Key('book-details-more-actions'));
  await tester.ensureVisible(trigger);
  await tester.pumpAndSettle();
  await tester.tap(trigger);
  await tester.pumpAndSettle();
}

LibraryBook _book({
  String id = 'book',
  String title = 'A local EPUB',
  String? author = 'Автор Name',
  String? description =
      'A sufficiently long description that can be displayed in the panel.',
  String? coverPath,
  String? language = 'uk-UA',
  String? publisher = 'Видавництво',
  String? isbn = '9780306406157',
  List<String> authors = const [],
  List<String> contributors = const [],
  List<String> identifiers = const [],
  List<String> subjects = const [],
  String? publishedDate,
  String? rights,
  String? source,
  String? modifiedDate,
  String? seriesName,
  double? seriesIndex,
  String? catalogSourceId,
  Map<String, String> metadataOrigins = const {},
  int fileSizeBytes = 2 * 1024 * 1024,
  BookFormat format = BookFormat.epub,
  String fileExtension = 'epub',
  bool isFavorite = false,
  String? tocJson,
  String filePath = '/books/book.epub',
}) {
  return LibraryBook(
    id: id,
    title: title,
    sortTitle: null,
    author: author,
    description: description,
    filePath: filePath,
    fileName: '$id.epub',
    fileExtension: fileExtension,
    format: format,
    mediaType: null,
    coverPath: coverPath,
    language: language,
    publisher: publisher,
    publishedDate: publishedDate,
    isbn: isbn,
    pageCount: null,
    fileSizeBytes: fileSizeBytes,
    dateAdded: DateTime(2026),
    lastOpenedAt: null,
    isFavorite: isFavorite,
    authors: authors,
    contributors: contributors,
    identifiers: identifiers,
    subjects: subjects,
    rights: rights,
    source: source,
    modifiedDate: modifiedDate,
    seriesName: seriesName,
    seriesIndex: seriesIndex,
    catalogSourceId: catalogSourceId,
    metadataOrigins: metadataOrigins,
    tocJson: tocJson,
  );
}

class _ControlledBookFileExportService extends BookFileExportService {
  _ControlledBookFileExportService(this.outcome, {this.onExport})
    : super(_UnexpectedBookFileSaver());

  final BookFileSaveOutcome outcome;
  final VoidCallback? onExport;

  @override
  Future<BookFileExportSource?> resolveSource(LibraryBook book) async =>
      const BookFileExportSource(
        path: '/controlled.epub',
        fileName: 'controlled.epub',
        mimeType: 'application/epub+zip',
        sizeBytes: 1,
      );

  @override
  Future<BookFileSaveOutcome> export(LibraryBook book) async {
    onExport?.call();
    return outcome;
  }
}

class _UnexpectedBookFileSaver implements BookFileSaver {
  @override
  Future<BookFileSaveOutcome> save({
    required String sourcePath,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  }) async => throw StateError('The controlled export service owns this test.');
}

class _FakeBookCoverPicker implements BookCoverPicker {
  _FakeBookCoverPicker(this.result, {this.error});

  final PickedBookCover? result;
  final Object? error;
  var calls = 0;

  @override
  Future<PickedBookCover?> pickCover() async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

class _FailingBookDetailsEditService extends BookDetailsEditService {
  _FailingBookDetailsEditService({
    required super.booksDao,
    required super.coverStorage,
  });

  var calls = 0;

  @override
  Future<void> save({
    required String bookId,
    required String title,
    required String? author,
    bool updateTitle = true,
    bool updateAuthor = true,
    Uint8List? replacementCoverBytes,
    String? replacementCoverExtension,
    BookCoverProvenance? replacementCoverProvenance,
    List<String>? replacementAuthors,
    bool removeManualCover = false,
    bool clearCover = false,
    bool cleanupReplacedManualCover = false,
  }) async {
    calls++;
    throw StateError('Controlled save failure');
  }
}

typedef _BookDetailsEditCall = ({
  String bookId,
  String title,
  String? author,
  bool updateTitle,
  bool updateAuthor,
  Uint8List? replacementCoverBytes,
  String? replacementCoverExtension,
  BookCoverProvenance? replacementCoverProvenance,
  List<String>? replacementAuthors,
  bool removeManualCover,
  bool clearCover,
  bool cleanupReplacedManualCover,
});

class _CapturingBookDetailsEditService extends BookDetailsEditService {
  _CapturingBookDetailsEditService({
    required super.booksDao,
    required super.coverStorage,
  });

  _BookDetailsEditCall? lastCall;

  @override
  Future<void> save({
    required String bookId,
    required String title,
    required String? author,
    bool updateTitle = true,
    bool updateAuthor = true,
    Uint8List? replacementCoverBytes,
    String? replacementCoverExtension,
    BookCoverProvenance? replacementCoverProvenance,
    List<String>? replacementAuthors,
    bool removeManualCover = false,
    bool clearCover = false,
    bool cleanupReplacedManualCover = false,
  }) async {
    lastCall = (
      bookId: bookId,
      title: title,
      author: author,
      updateTitle: updateTitle,
      updateAuthor: updateAuthor,
      replacementCoverBytes: replacementCoverBytes,
      replacementCoverExtension: replacementCoverExtension,
      replacementCoverProvenance: replacementCoverProvenance,
      replacementAuthors: replacementAuthors,
      removeManualCover: removeManualCover,
      clearCover: clearCover,
      cleanupReplacedManualCover: cleanupReplacedManualCover,
    );
  }
}

ReadingProgress _progress({
  int? current,
  int? total,
  double progression = 0,
  int? locatorPosition,
  String? locatorJson,
}) {
  return ReadingProgress(
    bookId: 'book',
    locatorJson:
        locatorJson ??
        '{"href":"chapter.xhtml","locations":'
            '{"position":${locatorPosition ?? 'null'}}}',
    progression: progression,
    currentChapterTitle: null,
    currentPage: current,
    totalPages: total,
    updatedAt: DateTime(2026),
  );
}

LibraryBookmark _bookmark() {
  return LibraryBookmark(
    id: 'bookmark',
    bookId: 'book',
    locatorJson: '{"href":"chapter.xhtml"}',
    href: 'chapter.xhtml',
    progression: 0.2,
    position: 17,
    chapterTitle: 'Chapter',
    title: 'Saved place',
    note: null,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

ReaderAnnotation _annotation({String bookId = 'book'}) => ReaderAnnotation(
  id: 'annotation',
  bookId: bookId,
  locatorJson: '{"href":"chapter.xhtml"}',
  locationKey: 'chapter.xhtml#annotation',
  selectedText: 'selected annotation',
  href: 'chapter.xhtml',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _LibraryRepository implements LibraryRepository {
  _LibraryRepository(this.book, {this.favoritePending});

  final LibraryBook book;
  final Completer<void>? favoritePending;
  var favoriteCalls = 0;
  var deleteCalls = 0;
  var updateCalls = 0;
  var watchAllCalls = 0;

  @override
  Stream<List<LibraryBook>> watchAllBooks() {
    watchAllCalls++;
    return Stream.value([book]);
  }

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => watchAllBooks();

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();

  @override
  Future<List<LibraryBook>> getAllBooks() async => [book];

  @override
  Future<LibraryBook?> getBookById(String id) async =>
      id == book.id ? book : null;

  @override
  Future<LibraryBook?> findBookByFilePath(String filePath) async => null;

  @override
  Future<LibraryBook?> findBookByOriginalFilePath(
    String originalFilePath,
  ) async => null;

  @override
  Future<void> addBook(LibraryBook book) async {}

  @override
  Future<void> updateBook(LibraryBook book) async {
    updateCalls++;
  }

  @override
  Future<void> deleteBook(String id) async {
    deleteCalls++;
  }

  @override
  Future<void> setFavorite(String id, bool isFavorite) async {
    favoriteCalls++;
    await favoritePending?.future;
  }

  @override
  Future<void> markBookOpened(String id, DateTime openedAt) async {}
}

class _LiveFavoriteRepository extends _LibraryRepository {
  _LiveFavoriteRepository() : super(_book());
  final pending = Completer<void>();
  final changes = StreamController<List<LibraryBook>>.broadcast();
  LibraryBook current = _book();
  @override
  Stream<List<LibraryBook>> watchAllBooks() async* {
    yield [current];
    yield* changes.stream;
  }

  @override
  Future<void> setFavorite(String id, bool isFavorite) async {
    favoriteCalls++;
    if (favoriteCalls == 1) await pending.future;
    current = _book(isFavorite: isFavorite);
    changes.add([current]);
  }

  Future<void> close() => changes.close();
}

class _DetailsCollectionRepository implements CollectionRepository {
  var watchAllCalls = 0;

  @override
  Stream<List<LibraryCollection>> watchAll() {
    watchAllCalls++;
    return Stream.value(const <LibraryCollection>[]);
  }

  @override
  Stream<List<LibraryCollection>> watchForBook(String bookId) =>
      Stream.value(const <LibraryCollection>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingMetadataRepository implements BookMetadataRepository {
  var calls = 0;

  @override
  Future<MetadataExtractionResult> extractMetadata({
    required String filePath,
    required BookFormat format,
  }) async {
    calls++;
    return const MetadataFileReadFailed();
  }
}

class _ControlledOriginalBookMetadataResolver
    extends OriginalBookMetadataResolver {
  _ControlledOriginalBookMetadataResolver({this.result, this.error})
    : super(metadataRepository: _CountingMetadataRepository());

  final OriginalBookMetadata? result;
  final Object? error;
  var calls = 0;

  @override
  Future<OriginalBookMetadata> resolve(LibraryBook book) async {
    calls++;
    if (error != null) throw error!;
    return result!;
  }
}

class _AcceptImageValidator implements CoverImageValidator {
  const _AcceptImageValidator();

  @override
  Future<bool> isDecodable(Uint8List bytes) async => bytes.isNotEmpty;
}

class _ProgressRepository implements ReadingProgressRepository {
  const _ProgressRepository(this.progress);

  final ReadingProgress? progress;

  @override
  Stream<List<ReadingProgress>> watchAll() =>
      Stream.value(progress == null ? [] : [progress!]);

  @override
  Stream<ReadingProgress?> watchForBook(String bookId) =>
      Stream.value(progress);

  @override
  Future<ReadingProgress?> getForBook(String bookId) async => progress;

  @override
  Future<void> save(ReadingProgress progress) async {}

  @override
  Future<void> deleteForBook(String bookId) async {}
}

class _BookmarkRepository implements BookmarkRepository {
  const _BookmarkRepository(this.bookmarks);

  final List<LibraryBookmark> bookmarks;

  @override
  Stream<List<LibraryBookmark>> watchBookmarksForBook(String bookId) =>
      Stream.value(
        bookmarks.where((bookmark) => bookmark.bookId == bookId).toList(),
      );

  @override
  Stream<List<LibraryBookmark>> watchAllBookmarks() => Stream.value(bookmarks);

  @override
  Future<LibraryBookmark?> getBookmarkById(String bookmarkId) async =>
      bookmarks.where((bookmark) => bookmark.id == bookmarkId).firstOrNull;

  @override
  Future<LibraryBookmark> createBookmark({
    required String bookId,
    required String locatorJson,
    String? href,
    double? progression,
    String? chapterTitle,
    int? position,
    String? title,
    String? note,
  }) async => throw UnimplementedError();

  @override
  Future<LibraryBookmark> updateBookmarkMetadata({
    required String bookmarkId,
    required BookmarkMetadataUpdate update,
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteBookmark(String bookmarkId) async {}

  @override
  Future<void> deleteBookmarksForBook(String bookId) async {}

  @override
  Future<int> countBookmarksForBook(String bookId) async => bookmarks.length;

  @override
  Future<bool> isBookmarked(BookmarkLocationKey key) async => false;

  @override
  Future<void> removeBookmarksAt(BookmarkLocationKey key) async {}
}

class _AnnotationRepository implements ReaderAnnotationRepository {
  const _AnnotationRepository(this.annotations);

  final List<ReaderAnnotation> annotations;

  @override
  Stream<List<ReaderAnnotation>> watchForBook(String bookId) => Stream.value(
    annotations.where((annotation) => annotation.bookId == bookId).toList(),
  );

  @override
  Future<List<ReaderAnnotation>> listForBook(String bookId) async =>
      annotations.where((annotation) => annotation.bookId == bookId).toList();

  @override
  Future<ReaderAnnotation?> getById(String id) async =>
      annotations.where((annotation) => annotation.id == id).firstOrNull;

  @override
  Future<ReaderAnnotation?> getByLocation({
    required String bookId,
    required String locationKey,
  }) async => annotations
      .where(
        (annotation) =>
            annotation.bookId == bookId &&
            annotation.locationKey == locationKey,
      )
      .firstOrNull;

  @override
  Future<ReaderAnnotation> insert(ReaderAnnotation annotation) async =>
      annotation;

  @override
  Future<ReaderAnnotation> upsert(ReaderAnnotation annotation) async =>
      annotation;

  @override
  Future<ReaderAnnotation> updateNote({
    required String id,
    required String? note,
    required DateTime updatedAt,
  }) async => throw UnimplementedError();

  @override
  Future<ReaderAnnotation> updateStyleAndColor({
    required String id,
    ReaderAnnotationStyle? style,
    ReaderAnnotationColor? color,
    required DateTime updatedAt,
  }) async => throw UnimplementedError();

  @override
  Future<bool> deleteById(String id) async => true;

  @override
  Future<bool> deleteByLocation({
    required String bookId,
    required String locationKey,
  }) async => true;

  @override
  Future<int> deleteAllForBook(String bookId) async => 0;
}
