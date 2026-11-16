import 'package:bibliolife/features/book_details/presentation/models/book_details_view_data.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_metadata_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Details keeps metadata and download provenance separate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookMetadataProvenanceNote.fromViewData(
            data: BookDetailsViewData(
              title: 'Book',
              authors: const ['Author'],
              metadataProvenance: 'Open Library',
              downloadProvenance: 'Internet Archive',
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Metadata: Open Library\nDownload: Internet Archive'),
      findsOneWidget,
    );
  });
}
