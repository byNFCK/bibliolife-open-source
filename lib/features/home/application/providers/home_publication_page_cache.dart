import 'dart:collection';

import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const homePublicationPageCacheCapacity = 144;

final homePublicationPageCacheProvider = Provider<HomePublicationPageCache>(
  (ref) => HomePublicationPageCache(),
);

class HomePublicationPageCache {
  HomePublicationPageCache({this.capacity = homePublicationPageCacheCapacity});

  final int capacity;
  final LinkedHashMap<String, RemoteCatalogPage> _pages = LinkedHashMap();
  var hits = 0;

  RemoteCatalogPage? read(RemoteCatalogLocation location) {
    final key = location.toString();
    final page = _pages.remove(key);
    if (page == null) return null;
    hits++;
    _pages[key] = page;
    return page;
  }

  void write(RemoteCatalogLocation location, RemoteCatalogPage page) {
    final key = location.toString();
    _pages.remove(key);
    _pages[key] = page;
    while (_pages.length > capacity) {
      _pages.remove(_pages.keys.first);
    }
  }

  int get length => _pages.length;
}
