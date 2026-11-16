import 'package:bibliolife/features/book_details/application/services/book_file_export_service.dart';
import 'package:flutter/services.dart';

class AndroidBookFileSaver implements BookFileSaver {
  AndroidBookFileSaver({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('bibliolife/book-file-save');

  final MethodChannel _channel;

  @override
  Future<BookFileSaveOutcome> save({
    required String sourcePath,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>('save', {
      'sourcePath': sourcePath,
      'fileName': fileName,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
    });
    return switch (result?['status']) {
      'saved' => BookFileSaveOutcome.saved,
      'cancelled' => BookFileSaveOutcome.cancelled,
      'busy' => BookFileSaveOutcome.busy,
      _ => BookFileSaveOutcome.failed,
    };
  }
}
