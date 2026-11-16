import 'package:bibliolife/features/catalog_sources/application/remote_book_download_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_temporary_epub_importer.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_temporary_epub_import.dart';
import 'package:bibliolife/features/import/application/providers/import_repository_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final remoteTemporaryEpubImporterProvider =
    Provider<RemoteTemporaryEpubImporter>(
      (ref) => ProductionRemoteTemporaryEpubImporter(
        ref.watch(bookImporterProvider),
        ref.watch(libraryRepositoryProvider),
        ref.watch(remoteDownloadTemporaryDirectoryProvider),
      ),
    );
