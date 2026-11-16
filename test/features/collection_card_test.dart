import 'dart:convert';
import 'dart:io';

import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/collections/domain/models/collection_summary.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_card.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_cover.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_image.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CollectionSummary summary(
    int bookCount, {
    String name = 'Recent reads',
    String? customCoverPath,
  }) {
    return CollectionSummary(
      collection: LibraryCollection(
        id: 'collection-$bookCount',
        name: name,
        normalizedName: name.toLowerCase(),
        customCoverPath: customCoverPath,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        sortOrder: null,
      ),
      bookCount: bookCount,
      recentBooks: List.generate(
        bookCount.clamp(0, 3),
        (index) => CollectionPreviewBook(
          id: 'book-$index',
          title: 'Book $index',
          coverPath: null,
        ),
      ),
    );
  }

  Future<void> pumpCard(
    WidgetTester tester,
    CollectionSummary value, {
    VoidCallback? onTap,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CollectionCard(summary: value, onTap: onTap ?? () {}),
      ),
    ),
  );

  Future<void> pumpCardWithResolvedCustomCover(
    WidgetTester tester,
    CollectionSummary value,
  ) async {
    await pumpCard(tester, value);
    await tester.pump();
  }

  testWidgets('renders empty collection without fabricated covers', (
    tester,
  ) async {
    await pumpCard(tester, summary(0));

    expect(find.text('0 books'), findsOneWidget);
    expect(find.byType(BookCoverImage), findsNothing);
    expect(find.byIcon(Icons.collections_bookmark_outlined), findsOneWidget);
  });

  testWidgets('shared cover owns ratio, fit, radius, placeholder and overlay', (
    tester,
  ) async {
    final directory = Directory(
      'build/collection-shared-cover-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    final file = File('${directory.path}/cover.png')
      ..writeAsBytesSync(_pngFixture(width: 1, height: 1));
    addTearDown(() => _cleanupCoverFiles(tester, directory, [file]));

    Future<void> pumpCover({File? imageFile}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: CollectionCover(
              imageFile: imageFile,
              placeholder: const ColoredBox(
                key: Key('shared-cover-placeholder'),
                color: Colors.blue,
              ),
              semanticLabel: 'Collection cover',
              imageKey: const Key('shared-cover-image'),
              overlay: const Positioned(
                top: 0,
                right: 0,
                child: SizedBox(key: Key('shared-cover-overlay')),
              ),
            ),
          ),
        ),
      ),
    );

    await pumpCover(imageFile: file);
    await tester.pumpAndSettle();
    final frame = tester.getRect(find.byType(CollectionCover));
    final clip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byType(CollectionCover),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(frame.width / frame.height, closeTo(16 / 9, 0.001));
    expect(clip.borderRadius, CollectionCover.borderRadius);
    expect(
      tester.widget<Image>(find.byKey(const Key('shared-cover-image'))).fit,
      BoxFit.cover,
    );
    expect(find.byKey(const Key('shared-cover-overlay')), findsOneWidget);
    expect(find.byKey(const Key('shared-cover-placeholder')), findsNothing);
    expect(find.bySemanticsLabel('Collection cover'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpCover();
    final emptyFrame = tester.getRect(find.byType(CollectionCover));
    final emptyClip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byType(CollectionCover),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(emptyFrame, frame);
    expect(emptyFrame.width / emptyFrame.height, closeTo(16 / 9, 0.001));
    expect(emptyClip.borderRadius, CollectionCover.borderRadius);
    expect(find.byKey(const Key('shared-cover-placeholder')), findsOneWidget);
    expect(find.byKey(const Key('shared-cover-overlay')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpCover(imageFile: file);
    final image = tester.widget<Image>(
      find.byKey(const Key('shared-cover-image')),
    );
    final fallback = image.errorBuilder!(
      tester.element(find.byKey(const Key('shared-cover-image'))),
      StateError('controlled decode error'),
      StackTrace.current,
    );
    expect(fallback.key, const Key('shared-cover-placeholder'));
    expect(tester.getRect(find.byType(CollectionCover)), frame);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the available cover count up to three', (tester) async {
    await pumpCard(tester, summary(1));
    expect(find.byType(BookCoverImage), findsNWidgets(1));

    await pumpCard(tester, summary(2));
    expect(find.byType(BookCoverImage), findsNWidgets(2));

    await pumpCard(tester, summary(4));
    expect(find.text('4 books'), findsOneWidget);
    expect(find.byType(BookCoverImage), findsNWidgets(3));
  });

  testWidgets('custom cover replaces only the upper preview region', (
    tester,
  ) async {
    final directory = Directory(
      'build/collection-card-test-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    final cover = File('${directory.path}/cover.png')
      ..writeAsBytesSync(_pngFixture(width: 1, height: 1));
    addTearDown(() => _cleanupCoverFiles(tester, directory, [cover]));

    await pumpCardWithResolvedCustomCover(
      tester,
      summary(3, customCoverPath: cover.path),
    );

    expect(
      find.byKey(const Key('collection-card-custom-cover')),
      findsOneWidget,
    );
    final image = tester.widget<Image>(
      find.byKey(const Key('collection-card-custom-cover')),
    );
    expect(image.fit, BoxFit.cover);
    expect(image.alignment, Alignment.center);
    expect(find.byType(BookCoverImage), findsNothing);
    expect(
      find.byKey(const Key('collection-card-information-panel')),
      findsOneWidget,
    );
  });

  testWidgets('missing custom cover falls back to the recent preview stack', (
    tester,
  ) async {
    await pumpCard(
      tester,
      summary(3, customCoverPath: 'build/does-not-exist/collection.png'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(BookCoverImage), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fills the fixed preview area with a landscape custom cover', (
    tester,
  ) async {
    final directory = Directory(
      'build/collection-card-landscape-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    final cover = File('${directory.path}/landscape.png')
      ..writeAsBytesSync(_pngFixture(width: 16, height: 9));
    addTearDown(() => _cleanupCoverFiles(tester, directory, [cover]));

    await pumpCardWithResolvedCustomCover(
      tester,
      summary(3, customCoverPath: cover.path),
    );

    final image = tester.widget<Image>(
      find.byKey(const Key('collection-card-custom-cover')),
    );
    expect(image.fit, BoxFit.cover);
    expect(image.alignment, Alignment.center);
    final cardRect = tester.getRect(
      find.byKey(const Key('collection-card-aspect-ratio')),
    );
    final imageRect = tester.getRect(
      find.byKey(const Key('collection-card-custom-cover')),
    );
    final panelRect = tester.getRect(
      find.byKey(const Key('collection-card-information-panel')),
    );
    expect(imageRect.left, closeTo(cardRect.left, 0.01));
    expect(imageRect.right, closeTo(cardRect.right, 0.01));
    expect(imageRect.top, closeTo(cardRect.top, 0.01));
    expect(imageRect.width / imageRect.height, collectionCoverAspectRatio);
    expect(
      panelRect.height,
      closeTo(cardRect.width / _cardAspectRatio * _panelHeightFraction, 0.5),
    );
    expect(panelRect.top, lessThan(imageRect.bottom));
    expect(find.byType(BookCoverImage), findsNothing);
  });

  testWidgets('keeps fixed geometry for a 4:3 custom cover', (tester) async {
    final directory = Directory(
      'build/collection-card-four-three-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    final cover = File('${directory.path}/four-three.png')
      ..writeAsBytesSync(_pngFixture(width: 4, height: 3));
    addTearDown(() => _cleanupCoverFiles(tester, directory, [cover]));

    await pumpCardWithResolvedCustomCover(
      tester,
      summary(3, customCoverPath: cover.path),
    );

    final cardRect = tester.getRect(
      find.byKey(const Key('collection-card-aspect-ratio')),
    );
    final imageRect = tester.getRect(
      find.byKey(const Key('collection-card-custom-cover')),
    );
    final cardSize = tester.getSize(
      find.byKey(const Key('collection-card-aspect-ratio')),
    );
    final image = tester.widget<Image>(
      find.byKey(const Key('collection-card-custom-cover')),
    );
    expect(image.fit, BoxFit.cover);
    expect(cardSize.aspectRatio, closeTo(_cardAspectRatio, 0.01));
    expect(imageRect.left, closeTo(cardRect.left, 0.01));
    expect(imageRect.right, closeTo(cardRect.right, 0.01));
    expect(imageRect.top, closeTo(cardRect.top, 0.01));
    expect(imageRect.width / imageRect.height, collectionCoverAspectRatio);
    expect(find.byType(BookCoverImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('contains a portrait custom cover without stretching it', (
    tester,
  ) async {
    final directory = Directory(
      'build/collection-card-portrait-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    final cover = File('${directory.path}/portrait.png')
      ..writeAsBytesSync(_pngFixture(width: 2, height: 4));
    addTearDown(() => _cleanupCoverFiles(tester, directory, [cover]));

    await pumpCardWithResolvedCustomCover(
      tester,
      summary(3, customCoverPath: cover.path),
    );

    final image = tester.widget<Image>(
      find.byKey(const Key('collection-card-custom-cover')),
    );
    expect(image.fit, BoxFit.cover);
    expect(image.alignment, Alignment.center);
    final cardSize = tester.getSize(
      find.byKey(const Key('collection-card-aspect-ratio')),
    );
    final panelSize = tester.getSize(
      find.byKey(const Key('collection-card-information-panel')),
    );
    final fallbackCardHeight = cardSize.width / _cardAspectRatio;
    expect(
      panelSize.height,
      closeTo(fallbackCardHeight * _panelHeightFraction, 0.5),
    );
    expect(cardSize.aspectRatio, closeTo(_cardAspectRatio, 0.01));
    expect(find.byType(BookCoverImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing and replacing a custom cover updates the card', (
    tester,
  ) async {
    final directory = Directory(
      'build/collection-card-replace-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    final coverA = File('${directory.path}/cover-a.png')
      ..writeAsBytesSync(_pngFixture(width: 1, height: 1));
    final coverB = File('${directory.path}/cover-b.png')
      ..writeAsBytesSync(_pngFixture(width: 1, height: 1));
    addTearDown(() => _cleanupCoverFiles(tester, directory, [coverA, coverB]));

    await pumpCardWithResolvedCustomCover(
      tester,
      summary(3, customCoverPath: coverA.path),
    );
    expect(_customCoverFile(tester).path, coverA.path);

    await pumpCardWithResolvedCustomCover(
      tester,
      summary(3, customCoverPath: coverB.path),
    );
    expect(_customCoverFile(tester).path, coverB.path);

    await pumpCard(tester, summary(3));
    await tester.pump();
    expect(find.byKey(const Key('collection-card-custom-cover')), findsNothing);
    expect(find.byType(BookCoverImage), findsNWidgets(3));
  });

  testWidgets('keeps a compact landscape card at phone width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: CollectionCard(summary: summary(3), onTap: () {}),
          ),
        ),
      ),
    );

    final card = tester.getSize(
      find.byKey(const Key('collection-card-aspect-ratio')),
    );
    final panel = tester.getRect(
      find.byKey(const Key('collection-card-information-panel')),
    );
    final cardRect = tester.getRect(
      find.byKey(const Key('collection-card-aspect-ratio')),
    );
    expect(card.aspectRatio, inInclusiveRange(1.55, 1.7));
    expect(panel.left, cardRect.left);
    expect(panel.right, cardRect.right);
    expect(panel.bottom, cardRect.bottom);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cover viewport stays 16:9 at common phone widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 900);
      await pumpCard(tester, summary(0));
      final viewport = tester.getSize(
        find.byKey(const Key('collection-card-cover-viewport')),
      );
      final viewportRect = tester.getRect(
        find.byKey(const Key('collection-card-cover-viewport')),
      );
      final cardRect = tester.getRect(
        find.byKey(const Key('collection-card-aspect-ratio')),
      );
      final panelRect = tester.getRect(
        find.byKey(const Key('collection-card-information-panel')),
      );
      final badgeRect = tester.getRect(
        find.byKey(const Key('collection-card-icon-badge')),
      );
      final surface = tester.widget<Material>(
        find.byKey(const Key('collection-card-surface')),
      );
      expect(viewport.width / viewport.height, 16 / 9);
      expect(viewportRect.left, closeTo(cardRect.left, 0.01));
      expect(viewportRect.right, closeTo(cardRect.right, 0.01));
      expect(viewportRect.top, closeTo(cardRect.top, 0.01));
      expect(viewportRect.width, closeTo(cardRect.width, 0.01));
      expect(badgeRect.left, closeTo(panelRect.left + 24, 0.01));
      expect(surface.clipBehavior, Clip.antiAlias);
      expect(surface.borderRadius, CollectionCover.borderRadius);
      expect(
        find.byKey(const Key('collection-card-cover-viewport')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.collections_bookmark_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('shows the reference-style panel icon and navigation chevron', (
    tester,
  ) async {
    await pumpCard(tester, summary(3));

    expect(find.byIcon(Icons.collections_bookmark_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('builds with separated surfaces in light and dark themes', (
    tester,
  ) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: brightness,
            ),
          ),
          home: Scaffold(
            body: CollectionCard(summary: summary(0), onTap: () {}),
          ),
        ),
      );

      expect(
        find.byKey(const Key('collection-card-information-panel')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('uses distinct card surfaces in the BiblioLife dark theme', (
    tester,
  ) async {
    final theme = buildAppTheme(fallbackDarkColorScheme);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: CollectionCard(summary: summary(0), onTap: () {}),
        ),
      ),
    );

    final cardColor = tester
        .widget<Material>(find.byKey(const Key('collection-card-surface')))
        .color;
    final panel = tester.widget<DecoratedBox>(
      find.byKey(const Key('collection-card-information-panel')),
    );
    final panelColor = (panel.decoration as BoxDecoration).color;

    expect(cardColor, isNot(theme.scaffoldBackgroundColor));
    expect(panelColor, isNot(theme.scaffoldBackgroundColor));
    expect(panelColor, isNot(cardColor));
  });

  testWidgets('uses a gradient treatment behind the cover stack', (
    tester,
  ) async {
    await pumpCard(tester, summary(3));

    final background = tester.widget<DecoratedBox>(
      find.byKey(const Key('collection-card-cover-background')),
    );
    expect(
      (background.decoration as BoxDecoration).gradient,
      isA<RadialGradient>(),
    );
  });

  testWidgets('truncates long titles and keeps the card tappable', (
    tester,
  ) async {
    var tapped = false;
    await pumpCard(
      tester,
      summary(1, name: 'A very long collection name that must not overflow'),
      onTap: () => tapped = true,
    );

    expect(
      find.text('A very long collection name that must not overflow'),
      findsOneWidget,
    );
    await tester.tap(find.byType(CollectionCard));
    expect(tapped, isTrue);
  });
}

File _customCoverFile(WidgetTester tester) {
  final provider = tester
      .widget<Image>(find.byKey(const Key('collection-card-custom-cover')))
      .image;
  if (provider is FileImage) {
    return provider.file;
  }
  if (provider is ResizeImage && provider.imageProvider is FileImage) {
    return (provider.imageProvider as FileImage).file;
  }
  throw TestFailure('Expected the custom cover to use a FileImage provider.');
}

Future<void> _cleanupCoverFiles(
  WidgetTester tester,
  Directory directory,
  List<File> files,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.runAsync(() async {
    for (final file in files) {
      await FileImage(file).evict();
    }
    PaintingBinding.instance.imageCache.clearLiveImages();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  try {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  } on FileSystemException {
    // Windows may keep a decoded image file open until the test process exits.
  }
}

List<int> _pngFixture({required int width, required int height}) {
  final raw = <int>[];
  for (var row = 0; row < height; row++) {
    raw.add(0);
    for (var column = 0; column < width; column++) {
      raw.addAll(const [52, 85, 111, 255]);
    }
  }

  return [
    ...const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
    ..._pngChunk('IHDR', [
      ..._uint32(width),
      ..._uint32(height),
      8,
      6,
      0,
      0,
      0,
    ]),
    ..._pngChunk('IDAT', const ZLibEncoder().encodeBytes(raw)),
    ..._pngChunk('IEND', const []),
  ];
}

List<int> _pngChunk(String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  final crc = getCrc32([...typeBytes, ...data]);
  return [..._uint32(data.length), ...typeBytes, ...data, ..._uint32(crc)];
}

List<int> _uint32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

const _cardAspectRatio = 1.62;
const _panelHeightFraction = 0.4;
