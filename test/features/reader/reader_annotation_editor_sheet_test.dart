import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_annotation_editor_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explicit existing editor retains its complete form', (
    tester,
  ) async {
    await _pumpEditor(tester);

    expect(find.text('Selected passage'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('Style'), findsOneWidget);
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<ReaderAnnotationStyle>),
      findsOneWidget,
    );
    expect(
      find.byType(DropdownButtonFormField<ReaderAnnotationColor>),
      findsOneWidget,
    );
  });

  testWidgets('shared editor saves note and style through its callback', (
    tester,
  ) async {
    ReaderAnnotationStyle? savedStyle;
    ReaderAnnotationColor? savedColor;
    String? savedNote;
    await _pumpEditor(
      tester,
      onSave: (note, style, color) async {
        savedNote = note;
        savedStyle = style;
        savedColor = color;
      },
    );

    await tester.enterText(find.byType(TextField), 'new note');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedNote, 'new note');
    expect(savedStyle, ReaderAnnotationStyle.highlight);
    expect(savedColor, ReaderAnnotationColor.yellow);
  });

  testWidgets('shared editor deletes through its callback', (tester) async {
    var deleted = false;
    await _pumpEditor(
      tester,
      onDelete: () async {
        deleted = true;
      },
    );

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  Future<void> Function(
    String? note,
    ReaderAnnotationStyle style,
    ReaderAnnotationColor color,
  )?
  onSave,
  Future<void> Function()? onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => ReaderAnnotationEditorSheet(
                  annotation: _annotation(),
                  onSave: onSave ?? ((_, _, _) async {}),
                  onDelete: onDelete ?? (() async {}),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

ReaderAnnotation _annotation() {
  final now = DateTime(2026);
  return ReaderAnnotation(
    id: 'annotation-1',
    bookId: 'book-1',
    locatorJson: '{"href":"chapter.xhtml"}',
    locationKey: 'chapter.xhtml',
    selectedText: 'Selected passage',
    note: 'old note',
    href: 'chapter.xhtml',
    createdAt: now,
    updatedAt: now,
  );
}
