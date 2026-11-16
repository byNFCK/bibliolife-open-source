abstract final class AppStrings {
  static const log = 'LOG';
  static const copy = 'COPY';
  static const logsCopied = 'Logs copied';
  static const logsCopyError = 'Could not copy logs.';
  static const noLogsYet = 'No logs yet';
  static const home = 'Home';
  static const library = 'Library';
  static const profile = 'Profile';
  static const readyToRead = 'Ready to read';
  static const readForFree = 'Read for free';
  static const bookUnavailable = 'Unavailable';
  static const openedYesterday = 'Opened yesterday';
  static const openedJustNow = 'Opened just now';
  static const futureBookActions = 'More actions coming soon';
  static String bookPrice(String amount, String currency) =>
      'Price: $amount $currency';
  static String openedHoursAgo(int count) =>
      'Opened $count ${count == 1 ? 'hour' : 'hours'} ago';
  static String openedMinutesAgo(int count) =>
      'Opened $count ${count == 1 ? 'minute' : 'minutes'} ago';
  static String openedDaysAgo(int count) => 'Opened $count days ago';
  static String openedOn(String date) => 'Opened $date';
  static const search = 'Search';
  static const searchBooks = 'Search books';
  static const settings = 'Settings';
  static const bookDisplayLayout = 'Book display layout';
  static const bookDisplayLayoutDescription = 'Choose how books are displayed.';
  static const gridView = 'Grid view';
  static const listView = 'List view';
  static const showGridView = 'Show grid view';
  static const showListView = 'Show list view';
  static const appearance = 'Appearance';
  static const theme = 'Theme';
  static const system = 'System';
  static const light = 'Light';
  static const dark = 'Dark';
  static const storage = 'Storage';
  static const homeOnlineLibraries = 'Home online libraries';
  static const onlineLibraries = 'Online libraries';
  static const onlineCache = 'Online cache';
  static const clearOnlineCache = 'Clear online cache';
  static const cacheCalculatingSize = 'Calculating cache size…';
  static const cacheClearTitle = 'Clear online cache?';
  static const cacheClearBody =
      'Only temporary online covers and metadata will be removed. Downloaded and imported books are kept.';
  static const cacheUpdateError =
      'Could not update the online cache setting. Please try again.';
  static const cacheClearError =
      'Could not clear the online cache. Please try again.';
  static const libraryPreferenceSaveError =
      'Could not save the Library preference.';
  static const settingsSelection = 'Select an option';
  static const homeOnlineLibrariesDescription =
      'Choose which independent discovery tabs appear on Home. Search availability is managed separately.';
  static const homeStandardEbooksDescription =
      'Home discovery; not a text Search provider.';
  static const homeInternetArchiveDescription =
      'Home discovery is independent of acquisition availability.';
  static const homeSearchIndependentDescription =
      'Shown on Home independently from Use in Search.';
  static const homeProviderIndependentDescription =
      'Shown on Home independently from provider availability.';
  static const cacheMinimum = '512 MB';
  static const cacheDefault = '1.25 GB';
  static const cacheMaximum = '2 GB';
  static const clear = 'Clear';
  static const collection = 'Collection';
  static const createCollection = 'Create collection';
  static const editCollection = 'Edit collection';
  static const collectionName = 'Collection name';
  static const uploadCover = 'Upload cover';
  static const changeCover = 'Change cover';
  static const removeCover = 'Remove cover';
  static const addBook = 'Add book';
  static const addedBooks = 'Added books';
  static const done = 'Done';
  static const noBooksAddedYet = 'No books added yet';
  static const save = 'Save';
  static const discardChanges = 'Discard changes?';
  static const discard = 'Discard';
  static const collectionSaveError = 'Could not save collection.';
  static const collectionLoadError = 'Could not load collection.';
  static const collectionDuplicateName =
      'A collection with this name already exists.';
  static const collectionInvalidName = 'Enter a collection name.';
  static const collectionCoverInvalid = 'Choose a valid image cover.';
  static const collectionCoverSaveError = 'Could not save collection cover.';
  static const collectionCover = 'Collection cover';
  static const created = 'Created';
  static const books = 'Books';
  static const addBooks = 'Add books';
  static const delete = 'Delete';
  static const addToCollection = 'Add to collection';
  static const refresh = 'Refresh';
  static const saveBookFile = 'Save book file';
  static const editBook = 'Edit book';
  static const bookTitle = 'Title';
  static const changeBookCover = 'Change cover';
  static const removeBookCover = 'Remove cover';
  static const bookEditSaveError = 'Could not save book details.';
  static const bookEditInvalidTitle = 'Enter a book title.';
  static const restoreOriginal = 'Restore original';
  static const restoreOriginalError =
      'Could not restore original book details.';
  static const bookCoverPickError = 'Could not select a book cover.';
  static const bookFileSaved = 'Book file saved.';
  static const bookFileUnavailable = 'The original book file is unavailable.';
  static const bookFileSaveError = 'Could not save the book file.';
  static const deleteCollection = 'Delete collection';
  static const deleteCollectionTitle = 'Delete collection?';
  static const deleteCollectionBody = 'Books will remain in your library.';
  static const collectionDeleteError = 'Could not delete collection.';
  static const collectionBooksLoadError = 'Could not load books.';
  static const collectionNotFound = 'Collection not found.';
  static const noBooksInCollection = 'No books in this collection.';
  static const follow = 'Follow';
  static const allBooks = 'All books';
  static const noBooksInLibrary = 'No books in your library';
  static const emptyLibraryMessage = 'Imported books will appear here.';
  static const defaultLibraryTab = 'Default tab in Library';
  static const defaultHomeCarousel = 'Default carousel in Home';
  static const homeCarouselPreferenceSaveError =
      'Could not save the Home carousel preference.';
  static const recentlyOpened = 'Recently opened';
  static const favorites = 'Favorites';
  static const seeAll = 'See all';
  static const noRecentlyOpenedBooks = 'No recently opened books';
  static const noFavoriteBooks = 'No favorite books';
  static const onlineLibraryUnavailable =
      'Online recommendations are not configured. Open Online libraries to browse a compatible catalog.';
  static const retry = 'Retry';
  static const back = 'Back';
  static const untitledBook = 'Untitled book';
  static const unknownAuthor = 'Unknown author';
  static const continueReading = 'Read';
  static const moreBookActions = 'More book actions';
  static const noAdditionalBookActions = 'No additional actions';
  static const page = 'Page';
  static const progress = 'Progress';
  static const bookmark = 'Bookmark';
  static const bookmarks = 'Bookmarks';
  static const annotations = 'Annotations';
  static const addToFavorites = 'Add to favorites';
  static const removeFromFavorites = 'Remove from favorites';
  static const author = 'Author';
  static const description = 'Description';
  static const more = 'More';
  static const less = 'Less';
  static const language = 'Language';
  static const publisher = 'Publisher';
  static const isbn = 'ISBN';
  static const applicationMode = 'Application mode';
  static const offline = 'Offline';
  static const online = 'Online';
  static const offlineDescription =
      'Use only books and data stored on this device.';
  static const onlineDescription =
      'Allow online catalogs, metadata requests and book downloads.';
  static const enableOnline = 'Enable Online';
  static const enableOnlineTitle = 'Enable Online mode?';
  static const enableOnlineBody =
      'Online mode may connect to third-party catalogs, load covers and metadata, and download books you select.';
  static const cancel = 'Cancel';
  static const removeLibrarySourceTitle = 'Remove library source?';
  static const removeLibrarySourceBody =
      'This removes the source from BiblioLife. Downloaded books are not affected.';
  static const remove = 'Remove';

  static String homeOnlineLibrariesSummary(int enabled, int total) =>
      '$enabled of $total enabled';
}
