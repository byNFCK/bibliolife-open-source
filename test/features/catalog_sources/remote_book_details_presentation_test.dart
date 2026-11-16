import 'dart:io';
import 'dart:ui' as ui;

import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_details_view_data.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_cover.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_layout.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_primary_action.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_status_bar.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final viewport in [
    const Size(200, 500),
    const Size(320, 300),
    const Size(320, 700),
  ]) {
    testWidgets('missing cover scales proportionally inside $viewport', (
      tester,
    ) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(
        _page(
          const BookDetailsCover.remote(
            title: 'Missing',
            cover: BookCoverReference.missing(),
          ),
          ColorScheme.fromSeed(seedColor: Colors.teal),
          largeText: true,
        ),
      );
      await tester.pumpAndSettle();
      final slot = tester.getRect(
        find.byKey(const Key('book-details-cover-slot')),
      );
      final hero = tester.getRect(
        find.byKey(const Key('book-details-cover-hero')),
      );
      expect(slot.size.aspectRatio, closeTo(2 / 3, 0.001));
      expect(slot.width, lessThanOrEqualTo(220));
      expect(slot.height, lessThanOrEqualTo(330));
      expect(slot.left, greaterThanOrEqualTo(20));
      expect(slot.right, lessThanOrEqualTo(viewport.width - 20));
      expect(hero.bottom, lessThanOrEqualTo(viewport.height - 16));
      expect(
        find.byKey(const Key('book-details-cover-placeholder')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final brightness in Brightness.values) {
    for (final imageSize in [
      const Size(200, 300),
      const Size(240, 240),
      const Size(360, 180),
      const Size(160, 640),
    ]) {
      testWidgets(
        'remote hero $imageSize uses fixed bounds and cached pixels in $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(320, 700);
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPadding);
          final directory = Directory.systemTemp.createTempSync(
            'remote-details-',
          );
          addTearDown(() => directory.deleteSync(recursive: true));
          final file = File('${directory.path}/cover.png');
          await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            Canvas(recorder).drawColor(Colors.orange, BlendMode.src);
            final picture = recorder.endRecording();
            final image = await picture.toImage(
              imageSize.width.toInt(),
              imageSize.height.toInt(),
            );
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await file.writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
            picture.dispose();
          });
          final cache = _CachedCover(file);
          final scheme = ColorScheme.fromSeed(
            seedColor: Colors.purple,
            brightness: brightness,
          );
          final cover = BookDetailsCover.remote(
            title: 'Remote title',
            cover: BookCoverReference.remote(
              Uri.parse('https://covers.example/book.png'),
            ),
            remoteCache: cache,
          );
          await tester.pumpWidget(_page(cover, scheme));
          for (
            var i = 0;
            i < 30 && find.byType(ImageFiltered).evaluate().isEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();
          final blur = find.byType(ImageFiltered);
          final slot = find.byKey(const Key('book-details-cover-slot'));
          expect(blur, findsOneWidget);
          expect(find.ancestor(of: slot, matching: blur), findsNothing);
          final foreground = tester.widget<RawImage>(
            find.descendant(of: slot, matching: find.byType(RawImage)),
          );
          final background = tester.widget<RawImage>(
            find.descendant(of: blur, matching: find.byType(RawImage)),
          );
          expect(foreground.image, same(background.image));
          expect(tester.getSize(slot), const Size(220, 330));
          expect(
            tester
                .getSize(find.byKey(const Key('book-details-cover-hero')))
                .height,
            426,
          );
          expect(
            tester.getTopLeft(find.byKey(const Key('book-details-title'))).dy,
            432,
          );
          final fitted = tester.widget<FittedBox>(
            find.descendant(of: slot, matching: find.byType(FittedBox)),
          );
          expect(fitted.fit, BoxFit.contain);
          expect(
            tester
                .getSize(
                  find.descendant(of: slot, matching: find.byType(RawImage)),
                )
                .aspectRatio,
            closeTo(imageSize.aspectRatio, 0.01),
          );
          expect(tester.getSize(blur).width, 320);
          expect(
            tester
                .getRect(slot)
                .overlaps(
                  tester.getRect(find.byKey(const Key('book-details-back'))),
                ),
            isFalse,
          );
          expect(
            find.byKey(const Key('book-details-cover-fade')),
            findsOneWidget,
          );
          final bars = tester
              .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
                find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
              )
              .value;
          expect(
            bars.statusBarIconBrightness,
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          );
          final button = tester.widget<FilledButton>(
            find.byKey(const Key('download')),
          );
          expect(
            button.style!.backgroundColor!.resolve({}),
            scheme.primaryContainer,
          );
          expect(
            button.style!.foregroundColor!.resolve({}),
            scheme.onPrimaryContainer,
          );
          await tester.pumpWidget(_page(cover, scheme));
          await tester.pump();
          expect(cache.calls, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'remote content fits 320 dp at scale 2 with long metadata in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        );
        const cover = BookDetailsCover.remote(
          title: 'Title',
          cover: BookCoverReference.missing(),
        );
        await tester.pumpWidget(_page(cover, scheme, largeText: true));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('book-author')), findsNothing);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('book-details-title')))
              .maxLines,
          isNull,
        );
        await tester.ensureVisible(find.byKey(const Key('download')));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('download'))).height,
          greaterThanOrEqualTo(56),
        );
        await tester.ensureVisible(find.byKey(const Key('description-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('description-toggle')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const Key('book-description-text')))
              .maxLines,
          isNull,
        );
        expect(find.textContaining('Progress:'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(_page(cover, scheme, noDescription: true));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('book-description-text')), findsNothing);
      },
    );
  }
}

Widget _page(
  BookDetailsCover cover,
  ColorScheme scheme, {
  bool largeText = false,
  bool noDescription = false,
}) => MaterialApp(
  theme: ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
  ),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
      child: Scaffold(
        body: SafeArea(
          top: false,
          left: false,
          right: false,
          child: BookDetailsStatusBar(
            child: BookDetailsLayout(
              data: BookDetailsViewData(
                title: largeText
                    ? List.filled(10, 'A long original title').join(' ')
                    : 'Remote title',
                authors: largeText ? [] : ['Original Author'],
                description: noDescription
                    ? null
                    : List.filled(
                        25,
                        'A remote description available before download.',
                      ).join(' '),
                language: 'en',
                publicationDate: '2026',
                file: 'EPUB',
              ),
              cover: cover,
              onBack: () {},
              primaryAction: FilledButton(
                key: const Key('download'),
                onPressed: () {},
                style: bookDetailsPrimaryActionStyle(context),
                child: const Text('Download'),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

class _CachedCover extends RemoteCacheService {
  _CachedCover(this.file);
  final File file;
  int calls = 0;
  @override
  Future<File?> cover(
    Uri uri, {
    OnlineSearchPerformanceSession? performanceSession,
  }) async {
    calls++;
    return file;
  }
}
