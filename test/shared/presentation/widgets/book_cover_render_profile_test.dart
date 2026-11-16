import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profiles use stable bounded decode buckets', () {
    expect(BookCoverRenderProfile.searchGrid.cacheWidth, 240);
    expect(BookCoverRenderProfile.searchGrid.cacheHeight, 360);
    expect(BookCoverRenderProfile.details.cacheWidth, 480);
    expect(BookCoverRenderProfile.details.cacheHeight, 720);
    expect(
      BookCoverRenderProfile.searchGrid.cacheWidth,
      lessThan(BookCoverRenderProfile.details.cacheWidth),
    );
  });

  test('Google grid selects thumbnail while details selects medium', () {
    final covers = [
      _location('https://books.google.com/extraLarge?edge=curl'),
      _location('https://books.google.com/large?edge=curl'),
      _location('https://books.google.com/medium?edge=curl'),
      _location('https://books.google.com/small?edge=curl'),
      _location('https://books.google.com/thumbnail?edge=curl'),
      _location('https://books.google.com/smallThumbnail?edge=curl'),
    ];

    expect(
      selectRemoteCoverForProfile(
        preferred: covers.first,
        candidates: covers,
        sourceId: 'builtin-google-books',
        profile: BookCoverRenderProfile.searchGrid,
      )!.uri.path,
      '/thumbnail',
    );
    expect(
      selectRemoteCoverForProfile(
        preferred: covers.first,
        candidates: covers,
        sourceId: 'builtin-google-books',
        profile: BookCoverRenderProfile.details,
      )!.uri.path,
      '/medium',
    );
  });

  test('Open Library keeps default=false and uses profile size', () {
    final cover = _location(
      'https://covers.openlibrary.org/b/id/12-L.jpg?default=false',
    );
    final grid = selectRemoteCoverForProfile(
      preferred: cover,
      candidates: const [],
      sourceId: 'builtin-open-library',
      profile: BookCoverRenderProfile.searchGrid,
    )!;
    final details = selectRemoteCoverForProfile(
      preferred: cover,
      candidates: const [],
      sourceId: 'builtin-open-library',
      profile: BookCoverRenderProfile.details,
    )!;

    expect(
      grid.toString(),
      'https://covers.openlibrary.org/b/id/12-M.jpg?default=false',
    );
    expect(
      details.toString(),
      'https://covers.openlibrary.org/b/id/12-L.jpg?default=false',
    );
  });

  test('duplicate candidates keep one stable selected URI', () {
    final cover = _location('https://catalog.example/cover.jpg');
    final selected = selectRemoteCoverForProfile(
      preferred: cover,
      candidates: [cover, cover],
      sourceId: 'builtin-project-gutenberg',
      profile: BookCoverRenderProfile.searchGrid,
    );

    expect(selected, cover);
  });
}

RemoteCatalogLocation _location(String value) =>
    RemoteCatalogLocation.parse(value);
