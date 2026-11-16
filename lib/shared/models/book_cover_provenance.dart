/// The persisted source of an installed book cover.
///
/// The order is intentional: a lower-priority source must never replace a
/// valid cover from a higher-priority source.
enum BookCoverProvenance {
  none,
  embedded,
  online,
  manual;

  int get priority => switch (this) {
    BookCoverProvenance.none => 0,
    BookCoverProvenance.embedded => 1,
    BookCoverProvenance.online => 2,
    BookCoverProvenance.manual => 3,
  };

  static BookCoverProvenance parse(String? value) =>
      BookCoverProvenance.values.firstWhere(
        (item) => item.name == value,
        orElse: () => BookCoverProvenance.none,
      );
}
