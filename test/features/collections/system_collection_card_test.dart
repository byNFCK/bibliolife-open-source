import 'package:bibliolife/features/collections/domain/models/collection_summary.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/domain/models/system_collection.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('built-in cards fit 320 dp with large text and RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final entry in systemCollectionNames.entries) {
      final c = LibraryCollection(
        id: entry.key,
        name: entry.value,
        normalizedName: entry.key,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        sortOrder: null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(2),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: CollectionCard(
                  summary: CollectionSummary(
                    collection: c,
                    bookCount: 0,
                    recentBooks: const [],
                  ),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
