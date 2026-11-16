import 'package:bibliolife/features/import/data/repositories/local_import_repository.dart';
import 'package:bibliolife/features/import/data/services/book_importer.dart';
import 'package:bibliolife/features/import/data/services/import_file_picker.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/import/domain/repositories/import_repository.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/metadata/application/providers/book_metadata_repository_provider.dart';
import 'package:bibliolife/features/metadata/application/providers/cover_storage_service_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';

final bookImporterProvider = Provider<BookImporter>((ref) {
  return BookImporter(
    filePicker: FilePickerImportFilePicker(),
    libraryRepository: ref.watch(libraryRepositoryProvider),
    metadataRepository: ref.watch(bookMetadataRepositoryProvider),
    coverStorageService: ref.watch(coverStorageServiceProvider),
    remoteCache: ref.watch(remoteCacheServiceProvider),
    tocExtractor: MethodChannelReadiumTocExtractor(),
  );
});

final importRepositoryProvider = Provider<ImportRepository>(
  (ref) => LocalImportRepository(ref.watch(bookImporterProvider)),
);
