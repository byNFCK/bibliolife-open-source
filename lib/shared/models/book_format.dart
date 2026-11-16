enum BookFormat {
  epub,
  pdf,
  fb2,
  cbz,
  cbr,
  txt,
  unknown;

  static const supportedExtensions = <String>[
    'epub',
    'pdf',
    'fb2',
    'cbz',
    'txt',
  ];

  factory BookFormat.fromExtension(String extension) {
    final normalized = extension.trim().toLowerCase().replaceFirst(
      RegExp(r'^\\.+'),
      '',
    );

    return switch (normalized) {
      'epub' => BookFormat.epub,
      'pdf' => BookFormat.pdf,
      'fb2' => BookFormat.fb2,
      'cbz' => BookFormat.cbz,
      'cbr' => BookFormat.cbr,
      'txt' => BookFormat.txt,
      _ => BookFormat.unknown,
    };
  }

  factory BookFormat.fromFileName(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot <= 0 || lastDot == fileName.length - 1) {
      return BookFormat.unknown;
    }
    return BookFormat.fromExtension(fileName.substring(lastDot + 1));
  }

  String get normalizedExtension => switch (this) {
    BookFormat.epub => 'epub',
    BookFormat.pdf => 'pdf',
    BookFormat.fb2 => 'fb2',
    BookFormat.cbz => 'cbz',
    BookFormat.cbr => 'cbr',
    BookFormat.txt => 'txt',
    BookFormat.unknown => '',
  };
}
