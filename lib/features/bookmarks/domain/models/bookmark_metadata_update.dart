sealed class FieldUpdate<T> {
  const FieldUpdate();
}

class Unchanged<T> extends FieldUpdate<T> {
  const Unchanged();
}

class Changed<T> extends FieldUpdate<T> {
  const Changed(this.value);
  final T value;
}

/// Explicitly distinguishes keeping a nullable value from clearing it.
class BookmarkMetadataUpdate {
  const BookmarkMetadataUpdate({
    this.title = const Unchanged<String?>(),
    this.note = const Unchanged<String?>(),
  });

  final FieldUpdate<String?> title;
  final FieldUpdate<String?> note;
}
