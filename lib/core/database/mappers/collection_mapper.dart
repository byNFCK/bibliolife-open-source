import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:drift/drift.dart';

extension CollectionMapper on Collection {
  LibraryCollection toLibraryCollection() => LibraryCollection(
    id: id,
    name: name,
    normalizedName: normalizedName,
    description: description,
    customCoverPath: customCoverPath,
    createdAt: createdAt,
    updatedAt: updatedAt,
    sortOrder: sortOrder,
  );
}

extension LibraryCollectionMapper on LibraryCollection {
  CollectionsCompanion toCollectionsCompanion() => CollectionsCompanion.insert(
    id: id,
    name: name,
    normalizedName: normalizedName,
    description: Value(description),
    customCoverPath: Value(customCoverPath),
    createdAt: createdAt,
    updatedAt: updatedAt,
    sortOrder: Value(sortOrder),
  );
}
