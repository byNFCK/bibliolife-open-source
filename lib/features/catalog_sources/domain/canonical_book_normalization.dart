String canonicalText(String? value) => (value ?? '')
    .toLowerCase()
    .trim()
    .replaceAll(RegExp(r'[\u2018\u2019\u201A\u201B\u2032\u00B4]'), "'")
    .replaceAll(RegExp(r'[\u201C\u201D\u201E\u201F\u2033]'), '"')
    .replaceAll(RegExp(r'[\u2010-\u2015]'), '-')
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r"[^\p{L}\p{N}]+", unicode: true), '');

String canonicalAuthor(String? value) => canonicalText(value);

String? canonicalLanguage(String? value) {
  final normalized = value?.trim().toLowerCase().replaceAll('_', '-');
  if (normalized == null || normalized.isEmpty) return null;
  return RegExp(r'^[a-z]{2,3}(-[a-z0-9]{2,8})?$').hasMatch(normalized)
      ? normalized
      : null;
}

String? canonicalIsbn(String value) {
  final isbn = value.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
  if (isbn.length == 13 && RegExp(r'^\d{13}$').hasMatch(isbn)) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(isbn[i]) * (i.isEven ? 1 : 3);
    }
    return (10 - sum % 10) % 10 == int.parse(isbn[12]) ? isbn : null;
  }
  if (isbn.length == 10 && RegExp(r'^\d{9}[\dX]$').hasMatch(isbn)) {
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      sum += (isbn[i] == 'X' ? 10 : int.parse(isbn[i])) * (10 - i);
    }
    return sum % 11 == 0 ? isbn : null;
  }
  return null;
}

String? isbn13FromIsbn10(String isbn10) {
  final value = canonicalIsbn(isbn10);
  if (value == null || value.length != 10) return null;
  final base = '978${value.substring(0, 9)}';
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(base[i]) * (i.isEven ? 1 : 3);
  }
  return '$base${(10 - sum % 10) % 10}';
}
