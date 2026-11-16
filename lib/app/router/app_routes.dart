abstract final class AppRoutes {
  static const homePath = '/';
  static const libraryPath = '/library';
  static const searchPath = '/search';
  static const settingsPath = '/settings';
  static const profilePath = '/profile';
  static const readerPath = '/reader/:bookId';
  static const bookDetailsPath = '/books/:bookId';
  static const bookAnnotationsPath = '/books/:bookId/annotations';
  static const collectionsPath = '/collections';
  static const createCollectionPath = '/collections/create';
  static const collectionDetailsPath = '/collections/:collectionId';
  static const editCollectionPath = '/collections/:collectionId/edit';
  static const onlineLibrariesPath = '/online-libraries';
  static const addOnlineLibraryPath = '/online-libraries/add';
  static const editOnlineLibraryPath = '/online-libraries/:sourceId/edit';
  static const browseOnlineLibraryPath = '/online-libraries/:sourceId/browse';
  static const searchOnlineLibraryPath = '/online-libraries/:sourceId/search';
  static const publicationOnlineLibraryPath =
      '/online-libraries/:sourceId/publication';
  static const downloadsPath = '/downloads';
  static const logsPath = '/logs';

  static const homeName = 'home';
  static const libraryName = 'library';
  static const searchName = 'search';
  static const settingsName = 'settings';
  static const profileName = 'profile';
  static const readerName = 'reader';
  static const bookDetailsName = 'bookDetails';
  static const bookAnnotationsName = 'bookAnnotations';
  static const collectionsName = 'collections';
  static const createCollectionName = 'createCollection';
  static const collectionDetailsName = 'collectionDetails';
  static const editCollectionName = 'editCollection';
  static const onlineLibrariesName = 'onlineLibraries';
  static const addOnlineLibraryName = 'addOnlineLibrary';
  static const editOnlineLibraryName = 'editOnlineLibrary';
  static const browseOnlineLibraryName = 'browseOnlineLibrary';
  static const searchOnlineLibraryName = 'searchOnlineLibrary';
  static const publicationOnlineLibraryName = 'publicationOnlineLibrary';
  static const downloadsName = 'downloads';
  static const logsName = 'logs';
}
