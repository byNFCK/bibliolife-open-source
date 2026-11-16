import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_details_formatters.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_details_view_data.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/expandable_book_details_section.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_section_heading.dart';
import 'package:bibliolife/features/metadata/data/services/isbn_extractor.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';

class BookMoreInformationSection extends StatefulWidget {
  BookMoreInformationSection({required LibraryBook book, super.key})
    : data = const LocalBookDetailsViewDataMapper().map(book);

  const BookMoreInformationSection.fromViewData({
    required this.data,
    super.key,
  });

  final BookDetailsViewData data;

  @override
  State<BookMoreInformationSection> createState() =>
      _BookMoreInformationSectionState();
}

class _BookMoreInformationSectionState
    extends State<BookMoreInformationSection> {
  var _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final language = normalizeBookDetailsText(data.language);
    final publishedDate = normalizeBookDetailsText(data.publicationDate);
    final file = normalizeBookDetailsText(data.file);
    final isbn = IsbnExtractor.canonicalize(data.isbn ?? '') ?? '';
    final genres = _join(data.classification.genres);
    final subgenresOrTags = _join(data.classification.subgenresOrTags);
    final source = normalizeBookDetailsText(data.bibliographicSource);
    final identifiers = _join(
      data.identifiers.where((identifier) {
        final canonical = IsbnExtractor.canonicalize(identifier);
        return canonical == null || canonical != data.isbn;
      }),
    );
    final modified = normalizeBookDetailsText(data.modifiedDate);
    final rights = normalizeBookDetailsText(data.rights);
    final previewRows = <Widget>[
      if (language.isNotEmpty)
        _MetadataRow(label: AppStrings.language, value: language),
      if (publishedDate.isNotEmpty)
        _MetadataRow(label: 'Publication date', value: publishedDate),
      if (file.isNotEmpty) _MetadataRow(label: 'File', value: file),
    ];
    final detailRows = <Widget>[
      if (isbn.isNotEmpty) _MetadataRow(label: AppStrings.isbn, value: isbn),
      if (genres.isNotEmpty) _MetadataRow(label: 'Genre', value: genres),
      if (subgenresOrTags.isNotEmpty)
        _MetadataRow(label: 'Subgenres or tags', value: subgenresOrTags),
      if (source.isNotEmpty) _MetadataRow(label: 'Source', value: source),
      if (identifiers.isNotEmpty)
        _MetadataRow(label: 'Identifiers', value: identifiers),
      if (modified.isNotEmpty) _MetadataRow(label: 'Modified', value: modified),
      if (rights.isNotEmpty) _MetadataRow(label: 'Rights', value: rights),
    ];
    if (previewRows.isEmpty && detailRows.isEmpty) {
      return const SizedBox.shrink();
    }
    return BookDetailsSectionHeading(
      label: 'More information',
      child: ExpandableBookDetailsSection(
        expanded: _expanded,
        canExpand: detailRows.isNotEmpty,
        semanticsLabel: 'Book metadata',
        toggleKey: const Key('more-information-toggle'),
        onToggle: _toggle,
        explicitChildNodes: true,
        expandedChild: detailRows.isEmpty
            ? null
            : Column(
                key: const Key('more-information-content'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  for (var index = 0; index < detailRows.length; index++) ...[
                    detailRows[index],
                    if (index != detailRows.length - 1)
                      const SizedBox(height: 12),
                  ],
                ],
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < previewRows.length; index++) ...[
              previewRows[index],
              if (index != previewRows.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class BookMetadataProvenanceNote extends StatelessWidget {
  BookMetadataProvenanceNote({required LibraryBook book, super.key})
    : data = const LocalBookDetailsViewDataMapper().map(book);

  const BookMetadataProvenanceNote.fromViewData({
    required this.data,
    super.key,
  });

  final BookDetailsViewData data;

  @override
  Widget build(BuildContext context) {
    final source = normalizeBookDetailsText(data.metadataProvenance);
    final download = normalizeBookDetailsText(data.downloadProvenance);
    if (source.isEmpty && download.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: [
        if (source.isNotEmpty) 'Metadata: $source',
        if (download.isNotEmpty) 'Download: $download',
      ].join(', '),
      child: Text(
        [
          if (source.isNotEmpty) 'Metadata: $source',
          if (download.isNotEmpty) 'Download: $download',
        ].join('\n'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _join(Iterable<String> values) => values
    .map(normalizeBookDetailsText)
    .where((value) => value.isNotEmpty)
    .join(', ');

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: value),
            ],
          ),
          style: style,
        ),
      ),
    );
  }
}
