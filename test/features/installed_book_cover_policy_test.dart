import 'package:bibliolife/features/metadata/domain/services/installed_book_cover_policy.dart';
import 'package:bibliolife/shared/models/book_cover_provenance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = InstalledBookCoverPolicy();

  test('online cover is never replaced by embedded cover', () {
    expect(
      policy.mayReplace(
        current: BookCoverProvenance.online,
        currentFileIsValid: true,
        incoming: BookCoverProvenance.embedded,
      ),
      isFalse,
    );
  });

  test('embedded cover replaces a placeholder', () {
    expect(
      policy.mayReplace(
        current: BookCoverProvenance.none,
        currentFileIsValid: false,
        incoming: BookCoverProvenance.embedded,
      ),
      isTrue,
    );
  });

  test('online cover can replace an embedded cover', () {
    expect(
      policy.mayReplace(
        current: BookCoverProvenance.embedded,
        currentFileIsValid: true,
        incoming: BookCoverProvenance.online,
      ),
      isTrue,
    );
  });

  test('manual cover is never replaced by online or embedded sources', () {
    for (final incoming in [
      BookCoverProvenance.online,
      BookCoverProvenance.embedded,
    ]) {
      expect(
        policy.mayReplace(
          current: BookCoverProvenance.manual,
          currentFileIsValid: true,
          incoming: incoming,
        ),
        isFalse,
      );
    }
  });

  test('an invalid local cover may recover from the next valid source', () {
    expect(
      policy.mayReplace(
        current: BookCoverProvenance.online,
        currentFileIsValid: false,
        incoming: BookCoverProvenance.embedded,
      ),
      isTrue,
    );
  });
}
