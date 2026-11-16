import 'package:bibliolife/features/collections/data/services/collection_cover_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final collectionCoverPickerProvider = Provider<CollectionCoverPicker>(
  (ref) => const FilePickerCollectionCoverPicker(),
);
