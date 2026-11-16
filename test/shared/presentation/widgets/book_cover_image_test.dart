import 'dart:io';

import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote cover identity is independent of source provenance', () {
    final uri = Uri(scheme: 'https', host: 'covers.example', path: '/book.jpg');

    expect(
      BookCoverReference.remote(uri, sourceId: 'google'),
      BookCoverReference.remote(uri, sourceId: 'open-library'),
    );
  });

  test('Search-card cover decode bucket remains bounded', () {
    final profile = BookCoverRenderProfile.searchGrid;

    expect(profile.cacheWidth, greaterThan(0));
    expect(profile.cacheHeight, greaterThan(0));
    expect(profile.cacheWidth, lessThanOrEqualTo(512));
    expect(profile.cacheHeight, lessThanOrEqualTo(768));
  });

  test('local cover retains a file-backed reference', () async {
    final directory = await Directory.systemTemp.createTemp('cover-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}cover.jpg')
      ..writeAsBytesSync([0]);

    expect(BookCoverReference.local(file.path), isA<LocalBookCover>());
  });
}
