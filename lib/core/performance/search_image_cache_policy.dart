import 'package:flutter/widgets.dart';

/// Applies one bounded decoded-image budget for the app lifetime. Remote files
/// remain on disk; this only controls Flutter's decoded in-memory images.
class SearchImageCachePolicy with WidgetsBindingObserver {
  SearchImageCachePolicy._();

  static final instance = SearchImageCachePolicy._();
  static const _normalBytes = 96 * 1024 * 1024;
  static const _pressureBytes = 64 * 1024 * 1024;

  var _configured = false;

  void configure() {
    if (_configured) return;
    _configured = true;
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = 220;
    cache.maximumSizeBytes = _normalBytes;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didHaveMemoryPressure() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = _pressureBytes;
    cache.clearLiveImages();
    cache.clear();
  }
}
