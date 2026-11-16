class LibraryCollection {
  const LibraryCollection({
    required this.id,
    required this.name,
    required this.normalizedName,
    this.description,
    this.customCoverPath,
    required this.createdAt,
    required this.updatedAt,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String normalizedName;
  final String? description;
  final String? customCoverPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? sortOrder;

  LibraryCollection copyWith({
    String? id,
    String? name,
    String? normalizedName,
    String? description,
    String? customCoverPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? sortOrder,
  }) => LibraryCollection(
    id: id ?? this.id,
    name: name ?? this.name,
    normalizedName: normalizedName ?? this.normalizedName,
    description: description ?? this.description,
    customCoverPath: customCoverPath ?? this.customCoverPath,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  @override
  bool operator ==(Object other) =>
      other is LibraryCollection &&
      other.id == id &&
      other.name == name &&
      other.normalizedName == normalizedName &&
      other.description == description &&
      other.customCoverPath == customCoverPath &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    normalizedName,
    description,
    customCoverPath,
    createdAt,
    updatedAt,
    sortOrder,
  );

  @override
  String toString() => 'LibraryCollection(id: $id, name: $name)';
}

class CollectionName {
  const CollectionName._(this.displayName, this.normalizedName);

  final String displayName;
  final String normalizedName;

  static CollectionName? tryParse(String rawName) {
    final displayName = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (displayName.isEmpty) return null;
    return CollectionName._(displayName, displayName.toLowerCase());
  }
}
