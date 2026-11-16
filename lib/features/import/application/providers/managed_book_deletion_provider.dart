import 'package:bibliolife/features/import/application/services/managed_book_deletion_service.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/metadata/application/providers/cover_storage_service_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final managedBookDeletionServiceProvider = Provider<ManagedBookDeletionService>(
  (ref) => ManagedBookDeletionService(
    ref.watch(libraryRepositoryProvider),
    ref.watch(coverStorageServiceProvider),
  ),
);
