import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

Future<ui.Rect?> findBookDetailsCoverTrim(ui.Image image) async {
  // Retain the decoded frame while the engine reads its pixels asynchronously.
  final retained = image.clone();
  try {
    final pixels = await retained.toByteData();
    return pixels == null
        ? null
        : detectBookDetailsCoverTrim(pixels, retained.width, retained.height);
  } catch (_) {
    return null;
  } finally {
    retained.dispose();
  }
}

/// Returns the retained source rectangle when a narrow paper gutter is found.
ui.Rect? detectBookDetailsCoverTrim(ByteData pixels, int width, int height) {
  final limit = (width * 0.07).floor();
  if (limit < 2 || height < 16) return null;

  final samples = _CoverEdgeSamples(pixels, width, height);
  final left = samples.gutterWidth(edge: 0, direction: 1, limit: limit);
  final right = samples.gutterWidth(
    edge: width - 1,
    direction: -1,
    limit: limit,
  );
  if (left == 0 && right == 0) return null;
  return ui.Rect.fromLTRB(
    left.toDouble(),
    0,
    (width - right).toDouble(),
    height.toDouble(),
  );
}

class _CoverEdgeSamples {
  _CoverEdgeSamples(this.pixels, this.width, this.height)
    : rows = math.min(height, 64);

  final ByteData pixels;
  final int width;
  final int height;
  final int rows;

  int gutterWidth({
    required int edge,
    required int direction,
    required int limit,
  }) {
    final reference = _pixel(edge, height ~/ 2);
    if (!_isPaper(reference)) return 0;

    var count = 0;
    while (count <= limit && _isUniform(edge + count * direction, reference)) {
      count++;
    }
    // A wide light area or a gradual transition may be part of the artwork.
    final minimum = math.max(2, (width * 0.005).ceil());
    if (count < minimum || count > limit) return 0;
    return _hasArtworkContrast(edge + count * direction, reference) ? count : 0;
  }

  bool _isUniform(int x, int reference) {
    var matches = 0;
    for (var sample = 0; sample < rows; sample++) {
      final pixel = _sample(x, sample);
      if (_isPaper(pixel) && _colorDistance(pixel, reference) <= 14) matches++;
    }
    return matches * 100 >= rows * 96;
  }

  bool _hasArtworkContrast(int x, int reference) {
    var contrasting = 0;
    for (var sample = 0; sample < rows; sample++) {
      final pixel = _sample(x, sample);
      if ((pixel & 0xff) >= 250 && _colorDistance(pixel, reference) >= 40) {
        contrasting++;
      }
    }
    return contrasting * 4 >= rows * 3;
  }

  int _sample(int x, int sample) =>
      _pixel(x, sample * (height - 1) ~/ (rows - 1));

  int _pixel(int x, int y) => pixels.getUint32((y * width + x) * 4);

  static bool _isPaper(int pixel) {
    if ((pixel & 0xff) < 250) return false;
    final red = pixel >>> 24;
    final green = (pixel >>> 16) & 0xff;
    final blue = (pixel >>> 8) & 0xff;
    final low = math.min(red, math.min(green, blue));
    return low >= 218 && math.max(red, math.max(green, blue)) - low <= 24;
  }

  static int _colorDistance(int a, int b) => math.max(
    ((a >>> 24) - (b >>> 24)).abs(),
    math.max(
      (((a >>> 16) & 0xff) - ((b >>> 16) & 0xff)).abs(),
      (((a >>> 8) & 0xff) - ((b >>> 8) & 0xff)).abs(),
    ),
  );
}
