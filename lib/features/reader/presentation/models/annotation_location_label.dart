import 'package:bibliolife_readium/bibliolife_readium.dart';

enum AnnotationLocationLabelKind { pageLabel, progression }

class AnnotationLocationLabel {
  const AnnotationLocationLabel({required this.kind, required this.text});

  final AnnotationLocationLabelKind kind;
  final String text;

  static AnnotationLocationLabel? fromLocatorJson(
    String locatorJson, {
    String? verifiedPageLabel,
  }) {
    final pageLabel = verifiedPageLabel?.trim();
    if (pageLabel?.isNotEmpty == true) {
      return AnnotationLocationLabel(
        kind: AnnotationLocationLabelKind.pageLabel,
        text: AnnotationLocationStrings.page(pageLabel!),
      );
    }
    final locator = ReadiumLocator.tryParse(locatorJson);
    if (locator == null) return null;
    final progression =
        locator.locations.totalProgression ?? locator.locations.progression;
    if (progression == null) return null;
    return AnnotationLocationLabel(
      kind: AnnotationLocationLabelKind.progression,
      text: AnnotationLocationStrings.percentage(progression),
    );
  }
}

abstract final class AnnotationLocationStrings {
  static String page(String value) => 'Page $value';
  /// Progression is rounded to the nearest whole percentage.
  static String percentage(double value) => '${(value * 100).round()}%';
}
