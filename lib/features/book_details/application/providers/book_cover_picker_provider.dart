import 'package:bibliolife/features/book_details/data/services/book_cover_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bookCoverPickerProvider = Provider<BookCoverPicker>(
  (ref) => const FilePickerBookCoverPicker(),
);
