import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/book_details/application/services/book_details_edit_service.dart';
import 'package:bibliolife/features/metadata/application/providers/cover_storage_service_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bookDetailsEditServiceProvider = Provider<BookDetailsEditService>(
  (ref) => BookDetailsEditService(
    booksDao: ref.watch(appDatabaseProvider).booksDao,
    coverStorage: ref.watch(coverStorageServiceProvider),
  ),
);
