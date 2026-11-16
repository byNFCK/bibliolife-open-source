enum LibrarySection { collection, follow, allBooks }

abstract final class LibrarySectionPreferenceCodec {
  static String encode(LibrarySection section) => switch (section) {
    LibrarySection.collection => 'collection',
    LibrarySection.follow => 'follow',
    LibrarySection.allBooks => 'all_books',
  };

  static LibrarySection decode(String? value) => switch (value) {
    'collection' => LibrarySection.collection,
    'follow' => LibrarySection.follow,
    'all_books' => LibrarySection.allBooks,
    // Keep existing users on the semantic successor of the old tab.
    'unsorted' => LibrarySection.allBooks,
    _ => LibrarySection.allBooks,
  };
}
