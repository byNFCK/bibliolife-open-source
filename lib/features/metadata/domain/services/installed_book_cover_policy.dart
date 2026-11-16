import 'package:bibliolife/shared/models/book_cover_provenance.dart';

/// One authoritative replacement rule for every persisted installed-book
/// cover. Rendering only reads the persisted decision; it does not rank
/// remote and embedded images independently.
class InstalledBookCoverPolicy {
  const InstalledBookCoverPolicy();

  bool mayReplace({
    required BookCoverProvenance current,
    required bool currentFileIsValid,
    required BookCoverProvenance incoming,
  }) {
    if (incoming == BookCoverProvenance.none) return false;
    if (!currentFileIsValid) return true;
    return incoming.priority > current.priority;
  }
}
