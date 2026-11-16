import 'dart:convert';

/// The persisted subset of Readium's Locator needed by Flutter presentation.
///
/// Readium 3.2.0 defines [position] as a one-based publication index (>= 1).
class ReadiumLocator {
  const ReadiumLocator({required this.locations});

  final ReadiumLocatorLocations locations;

  static ReadiumLocator? tryParse(String locatorJson) {
    try {
      final decoded = jsonDecode(locatorJson);
      if (decoded is! Map<String, dynamic>) return null;
      final rawLocations = decoded['locations'];
      if (rawLocations == null) {
        return const ReadiumLocator(locations: ReadiumLocatorLocations());
      }
      if (rawLocations is! Map<String, dynamic>) return null;
      return ReadiumLocator(
        locations: ReadiumLocatorLocations.fromMap(rawLocations),
      );
    } on FormatException {
      return null;
    }
  }
}

class ReadiumLocatorLocations {
  const ReadiumLocatorLocations({
    this.position,
    this.progression,
    this.totalProgression,
    this.fragments = const [],
  });

  factory ReadiumLocatorLocations.fromMap(Map<String, dynamic> value) {
    final rawPosition = value['position'];
    final position = rawPosition is int && rawPosition >= 1
        ? rawPosition
        : null;
    final fragments = value['fragments'];
    return ReadiumLocatorLocations(
      position: position,
      progression: _validProgression(value['progression']),
      totalProgression: _validProgression(value['totalProgression']),
      fragments: fragments is List
          ? fragments.whereType<String>().toList(growable: false)
          : const [],
    );
  }

  final int? position;
  final double? progression;
  final double? totalProgression;
  final List<String> fragments;

  static double? _validProgression(Object? value) {
    if (value is! num) return null;
    final normalized = value.toDouble();
    return normalized.isFinite && normalized >= 0 && normalized <= 1
        ? normalized
        : null;
  }
}
