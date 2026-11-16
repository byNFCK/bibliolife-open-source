import 'package:bibliolife/features/book_details/application/services/book_file_export_service.dart';
import 'package:bibliolife/features/book_details/data/services/android_book_file_saver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bookFileExportServiceProvider = Provider<BookFileExportService>(
  (ref) => BookFileExportService(AndroidBookFileSaver()),
);
