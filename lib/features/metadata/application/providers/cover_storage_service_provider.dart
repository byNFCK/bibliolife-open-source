import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final coverStorageServiceProvider = Provider<CoverStorageService>(
  (ref) => CoverStorageService(),
);
