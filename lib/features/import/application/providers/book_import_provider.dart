import 'package:bibliolife/features/import/application/providers/import_repository_provider.dart';
import 'package:bibliolife/features/import/domain/entities/import_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bookImportProvider =
    AsyncNotifierProvider<BookImportNotifier, ImportResult?>(
      BookImportNotifier.new,
    );

class BookImportNotifier extends AsyncNotifier<ImportResult?> {
  @override
  ImportResult? build() => null;

  Future<void> importFile() async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(importRepositoryProvider).importFile();
      state = AsyncData(result);
    } catch (_) {
      state = const AsyncData(ImportUnknownFailure());
    }
  }
}
