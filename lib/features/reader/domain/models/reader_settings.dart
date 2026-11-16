import 'package:bibliolife/shared/models/book_format.dart';

enum ReaderSettingsProfile { readiumReflowable, pdf, comic }

enum ReaderTheme { system, light, sepia, dark }

enum ReaderFontFamily { original, serif, sansSerif, dyslexic, monospace }

enum ReaderTextAlignment { start, justify }

/// Product-level reading semantics shared by every renderer.
///
/// [continuous] is stored under its established persistence key; it is shown
/// to readers as "Scroll" and means uninterrupted directional reading through
/// the renderer's complete readable sequence.
enum ReaderReadingMode { paginated, continuous }

enum ReaderColumnCount { auto, one, two }

enum ReaderReadingDirection { leftToRight, rightToLeft }

enum ReaderImageFit { page, width }

class ReaderAppearanceCapabilities {
  const ReaderAppearanceCapabilities({this.theme = false});
  final bool theme;
  bool get isEmpty => !theme;

  @override
  bool operator ==(Object other) =>
      other is ReaderAppearanceCapabilities && other.theme == theme;
  @override
  int get hashCode => theme.hashCode;
}

class ReaderTypographyCapabilities {
  const ReaderTypographyCapabilities({
    this.fontFamily = false,
    this.fontSize = false,
    this.fontWeight = false,
  });
  final bool fontFamily;
  final bool fontSize;
  final bool fontWeight;
  bool get isEmpty => !fontFamily && !fontSize && !fontWeight;

  @override
  bool operator ==(Object other) =>
      other is ReaderTypographyCapabilities &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight;
  @override
  int get hashCode => Object.hash(fontFamily, fontSize, fontWeight);
}

class ReaderSpacingCapabilities {
  const ReaderSpacingCapabilities({
    this.lineHeight = false,
    this.textMargins = false,
    this.pageGap = false,
  });
  final bool lineHeight;
  final bool textMargins;
  final bool pageGap;
  bool get isEmpty => !lineHeight && !textMargins && !pageGap;

  @override
  bool operator ==(Object other) =>
      other is ReaderSpacingCapabilities &&
      other.lineHeight == lineHeight &&
      other.textMargins == textMargins &&
      other.pageGap == pageGap;
  @override
  int get hashCode => Object.hash(lineHeight, textMargins, pageGap);
}

class ReaderTextLayoutCapabilities {
  const ReaderTextLayoutCapabilities({
    this.alignment = false,
    this.readingMode = false,
    this.columns = false,
  });
  final bool alignment;
  final bool readingMode;
  final bool columns;
  bool get isEmpty => !alignment && !readingMode && !columns;

  @override
  bool operator ==(Object other) =>
      other is ReaderTextLayoutCapabilities &&
      other.alignment == alignment &&
      other.readingMode == readingMode &&
      other.columns == columns;
  @override
  int get hashCode => Object.hash(alignment, readingMode, columns);
}

class ReaderPageLayoutCapabilities {
  const ReaderPageLayoutCapabilities({
    this.readingMode = false,
    this.readingDirection = false,
    this.singlePage = false,
    this.twoPage = false,
  });
  final bool readingMode;
  final bool readingDirection;
  final bool singlePage;
  final bool twoPage;
  bool get isEmpty =>
      !readingMode && !readingDirection && !singlePage && !twoPage;

  @override
  bool operator ==(Object other) =>
      other is ReaderPageLayoutCapabilities &&
      other.readingMode == readingMode &&
      other.readingDirection == readingDirection &&
      other.singlePage == singlePage &&
      other.twoPage == twoPage;
  @override
  int get hashCode =>
      Object.hash(readingMode, readingDirection, singlePage, twoPage);
}

class ReaderZoomCapabilities {
  const ReaderZoomCapabilities({
    this.fitPage = false,
    this.fitWidth = false,
    this.rememberZoom = false,
    this.resetZoomOnPageChange = false,
  });
  final bool fitPage;
  final bool fitWidth;
  final bool rememberZoom;
  final bool resetZoomOnPageChange;
  bool get isEmpty =>
      !fitPage && !fitWidth && !rememberZoom && !resetZoomOnPageChange;

  @override
  bool operator ==(Object other) =>
      other is ReaderZoomCapabilities &&
      other.fitPage == fitPage &&
      other.fitWidth == fitWidth &&
      other.rememberZoom == rememberZoom &&
      other.resetZoomOnPageChange == resetZoomOnPageChange;
  @override
  int get hashCode =>
      Object.hash(fitPage, fitWidth, rememberZoom, resetZoomOnPageChange);
}

class ReaderCropCapabilities {
  const ReaderCropCapabilities({
    this.cropMargins = false,
    this.cropBorders = false,
  });
  final bool cropMargins;
  final bool cropBorders;
  bool get isEmpty => !cropMargins && !cropBorders;

  @override
  bool operator ==(Object other) =>
      other is ReaderCropCapabilities &&
      other.cropMargins == cropMargins &&
      other.cropBorders == cropBorders;
  @override
  int get hashCode => Object.hash(cropMargins, cropBorders);
}

class ReaderImageCapabilities {
  const ReaderImageCapabilities({this.fitPage = false, this.fitWidth = false});
  final bool fitPage;
  final bool fitWidth;
  bool get isEmpty => !fitPage && !fitWidth;

  @override
  bool operator ==(Object other) =>
      other is ReaderImageCapabilities &&
      other.fitPage == fitPage &&
      other.fitWidth == fitWidth;
  @override
  int get hashCode => Object.hash(fitPage, fitWidth);
}

class ReaderReadingModeCapabilities {
  const ReaderReadingModeCapabilities({
    this.supportsPaginated = false,
    this.supportsContinuousScroll = false,
  });

  final bool supportsPaginated;
  final bool supportsContinuousScroll;

  List<ReaderReadingMode> get supportedModes => [
    if (supportsPaginated) ReaderReadingMode.paginated,
    if (supportsContinuousScroll) ReaderReadingMode.continuous,
  ];

  bool get isEmpty => !supportsPaginated && !supportsContinuousScroll;

  @override
  bool operator ==(Object other) =>
      other is ReaderReadingModeCapabilities &&
      other.supportsPaginated == supportsPaginated &&
      other.supportsContinuousScroll == supportsContinuousScroll;

  @override
  int get hashCode => Object.hash(supportsPaginated, supportsContinuousScroll);
}

class ReaderSourceSpecificCapabilities {
  const ReaderSourceSpecificCapabilities({this.publisherStyles = false});
  final bool publisherStyles;
  bool get isEmpty => !publisherStyles;

  @override
  bool operator ==(Object other) =>
      other is ReaderSourceSpecificCapabilities &&
      other.publisherStyles == publisherStyles;
  @override
  int get hashCode => publisherStyles.hashCode;
}

class ReaderSettingsCapabilities {
  const ReaderSettingsCapabilities({
    required this.profile,
    this.appearance = const ReaderAppearanceCapabilities(),
    this.typography = const ReaderTypographyCapabilities(),
    this.spacing = const ReaderSpacingCapabilities(),
    this.textLayout = const ReaderTextLayoutCapabilities(),
    this.pageLayout = const ReaderPageLayoutCapabilities(),
    this.readingModes = const ReaderReadingModeCapabilities(),
    this.zoom = const ReaderZoomCapabilities(),
    this.crop = const ReaderCropCapabilities(),
    this.image = const ReaderImageCapabilities(),
    this.sourceSpecific = const ReaderSourceSpecificCapabilities(),
  });

  static const readiumOriginal = ReaderSettingsCapabilities(
    profile: ReaderSettingsProfile.readiumReflowable,
    appearance: ReaderAppearanceCapabilities(theme: true),
    typography: ReaderTypographyCapabilities(
      fontFamily: true,
      fontSize: true,
      fontWeight: true,
    ),
    spacing: ReaderSpacingCapabilities(lineHeight: true, textMargins: true),
    textLayout: ReaderTextLayoutCapabilities(
      alignment: true,
      readingMode: true,
      columns: true,
    ),
    readingModes: ReaderReadingModeCapabilities(
      supportsPaginated: true,
      supportsContinuousScroll: true,
    ),
    sourceSpecific: ReaderSourceSpecificCapabilities(publisherStyles: true),
  );

  static const readiumGenerated = ReaderSettingsCapabilities(
    profile: ReaderSettingsProfile.readiumReflowable,
    appearance: ReaderAppearanceCapabilities(theme: true),
    typography: ReaderTypographyCapabilities(
      fontFamily: true,
      fontSize: true,
      fontWeight: true,
    ),
    spacing: ReaderSpacingCapabilities(lineHeight: true, textMargins: true),
    textLayout: ReaderTextLayoutCapabilities(
      alignment: true,
      readingMode: true,
      columns: true,
    ),
    readingModes: ReaderReadingModeCapabilities(
      supportsPaginated: true,
      supportsContinuousScroll: true,
    ),
  );

  static const pdf = ReaderSettingsCapabilities(
    profile: ReaderSettingsProfile.pdf,
    spacing: ReaderSpacingCapabilities(pageGap: true),
    // pdfx is a virtualized vertical document surface. It has no separate
    // discrete-page renderer to expose as a paginated choice.
    readingModes: ReaderReadingModeCapabilities(supportsContinuousScroll: true),
  );

  static const comic = ReaderSettingsCapabilities(
    profile: ReaderSettingsProfile.comic,
    spacing: ReaderSpacingCapabilities(pageGap: true),
    pageLayout: ReaderPageLayoutCapabilities(
      readingMode: true,
      readingDirection: true,
      singlePage: true,
    ),
    readingModes: ReaderReadingModeCapabilities(
      supportsPaginated: true,
      supportsContinuousScroll: true,
    ),
    image: ReaderImageCapabilities(fitPage: true, fitWidth: true),
  );

  final ReaderSettingsProfile profile;
  final ReaderAppearanceCapabilities appearance;
  final ReaderTypographyCapabilities typography;
  final ReaderSpacingCapabilities spacing;
  final ReaderTextLayoutCapabilities textLayout;
  final ReaderPageLayoutCapabilities pageLayout;
  final ReaderReadingModeCapabilities readingModes;
  final ReaderZoomCapabilities zoom;
  final ReaderCropCapabilities crop;
  final ReaderImageCapabilities image;
  final ReaderSourceSpecificCapabilities sourceSpecific;

  bool get isEmpty =>
      appearance.isEmpty &&
      typography.isEmpty &&
      spacing.isEmpty &&
      textLayout.isEmpty &&
      pageLayout.isEmpty &&
      readingModes.isEmpty &&
      zoom.isEmpty &&
      crop.isEmpty &&
      image.isEmpty &&
      sourceSpecific.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ReaderSettingsCapabilities &&
      other.profile == profile &&
      other.appearance == appearance &&
      other.typography == typography &&
      other.spacing == spacing &&
      other.textLayout == textLayout &&
      other.pageLayout == pageLayout &&
      other.readingModes == readingModes &&
      other.zoom == zoom &&
      other.crop == crop &&
      other.image == image &&
      other.sourceSpecific == sourceSpecific;
  @override
  int get hashCode => Object.hash(
    profile,
    appearance,
    typography,
    spacing,
    textLayout,
    pageLayout,
    readingModes,
    zoom,
    crop,
    image,
    sourceSpecific,
  );
}

ReaderSettingsCapabilities readiumSettingsCapabilitiesForSource(
  BookFormat sourceFormat,
) => switch (sourceFormat) {
  BookFormat.epub => ReaderSettingsCapabilities.readiumOriginal,
  BookFormat.fb2 ||
  BookFormat.txt => ReaderSettingsCapabilities.readiumGenerated,
  _ => throw ArgumentError.value(sourceFormat, 'sourceFormat'),
};

class ReaderAppearanceSettings {
  const ReaderAppearanceSettings({this.theme = ReaderTheme.system});
  final ReaderTheme theme;
  ReaderAppearanceSettings copyWith({ReaderTheme? theme}) =>
      ReaderAppearanceSettings(theme: theme ?? this.theme);
  Map<String, Object> toJson() => {'theme': theme.name};
  factory ReaderAppearanceSettings.fromJson(Map<String, Object?> json) =>
      ReaderAppearanceSettings(
        theme: ReaderTheme.values.firstWhere(
          (value) => value.name == json['theme'],
          orElse: () => ReaderTheme.system,
        ),
      );
  @override
  bool operator ==(Object other) =>
      other is ReaderAppearanceSettings && other.theme == theme;
  @override
  int get hashCode => theme.hashCode;
}

class ReaderTypographySettings {
  const ReaderTypographySettings({
    this.fontFamily = ReaderFontFamily.original,
    this.fontSize = 1,
    this.fontWeight = 1,
  });
  final ReaderFontFamily fontFamily;
  final double fontSize;
  final double fontWeight;
  ReaderTypographySettings copyWith({
    ReaderFontFamily? fontFamily,
    double? fontSize,
    double? fontWeight,
  }) => ReaderTypographySettings(
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: _finite(fontSize ?? this.fontSize, 1, .5, 3),
    fontWeight: _finite(fontWeight ?? this.fontWeight, 1, 0, 2.5),
  );
  Map<String, Object> toJson() => {
    'fontFamily': fontFamily.name,
    'fontSize': fontSize,
    'fontWeight': fontWeight,
  };
  factory ReaderTypographySettings.fromJson(Map<String, Object?> json) =>
      ReaderTypographySettings(
        fontFamily: ReaderFontFamily.values.firstWhere(
          (value) => value.name == json['fontFamily'],
          orElse: () => ReaderFontFamily.original,
        ),
        fontSize: _jsonNumber(json['fontSize'], 1, .5, 3),
        fontWeight: _jsonNumber(json['fontWeight'], 1, 0, 2.5),
      );
  @override
  bool operator ==(Object other) =>
      other is ReaderTypographySettings &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight;
  @override
  int get hashCode => Object.hash(fontFamily, fontSize, fontWeight);
}

class ReaderSpacingSettings {
  const ReaderSpacingSettings({
    this.lineHeight = 1.5,
    this.textMargins = 1,
    this.pageGap = 10,
  });
  final double lineHeight;
  final double textMargins;
  final double pageGap;
  ReaderSpacingSettings copyWith({
    double? lineHeight,
    double? textMargins,
    double? pageGap,
  }) => ReaderSpacingSettings(
    lineHeight: _finite(lineHeight ?? this.lineHeight, 1.5, 1, 2.5),
    textMargins: _finite(textMargins ?? this.textMargins, 1, 0, 4),
    pageGap: _finite(pageGap ?? this.pageGap, 10, 0, 40),
  );
  Map<String, Object> toJson() => {
    'lineHeight': lineHeight,
    'textMargins': textMargins,
    'pageGap': pageGap,
  };
  factory ReaderSpacingSettings.fromJson(Map<String, Object?> json) =>
      ReaderSpacingSettings(
        lineHeight: _jsonNumber(json['lineHeight'], 1.5, 1, 2.5),
        textMargins: _jsonNumber(json['textMargins'], 1, 0, 4),
        pageGap: _jsonNumber(json['pageGap'], 10, 0, 40),
      );
  @override
  bool operator ==(Object other) =>
      other is ReaderSpacingSettings &&
      other.lineHeight == lineHeight &&
      other.textMargins == textMargins &&
      other.pageGap == pageGap;
  @override
  int get hashCode => Object.hash(lineHeight, textMargins, pageGap);
}

class ReaderTextLayoutSettings {
  const ReaderTextLayoutSettings({
    this.alignment = ReaderTextAlignment.start,
    this.readingMode = ReaderReadingMode.paginated,
    this.columns = ReaderColumnCount.auto,
  });
  final ReaderTextAlignment alignment;
  final ReaderReadingMode readingMode;
  final ReaderColumnCount columns;
  ReaderTextLayoutSettings copyWith({
    ReaderTextAlignment? alignment,
    ReaderReadingMode? readingMode,
    ReaderColumnCount? columns,
  }) => ReaderTextLayoutSettings(
    alignment: alignment ?? this.alignment,
    readingMode: readingMode ?? this.readingMode,
    columns: columns ?? this.columns,
  );
  Map<String, Object> toJson() => {
    'alignment': alignment.name,
    'readingMode': readingMode.name,
    'columns': columns.name,
  };
  factory ReaderTextLayoutSettings.fromJson(Map<String, Object?> json) =>
      ReaderTextLayoutSettings(
        alignment: ReaderTextAlignment.values.firstWhere(
          (value) => value.name == json['alignment'],
          orElse: () => ReaderTextAlignment.start,
        ),
        readingMode: ReaderReadingMode.values.firstWhere(
          (value) => value.name == json['readingMode'],
          orElse: () => ReaderReadingMode.paginated,
        ),
        columns: ReaderColumnCount.values.firstWhere(
          (value) => value.name == json['columns'],
          orElse: () => ReaderColumnCount.auto,
        ),
      );
  @override
  bool operator ==(Object other) =>
      other is ReaderTextLayoutSettings &&
      other.alignment == alignment &&
      other.readingMode == readingMode &&
      other.columns == columns;
  @override
  int get hashCode => Object.hash(alignment, readingMode, columns);
}

class ReaderPageSettings {
  const ReaderPageSettings({
    this.readingMode = ReaderReadingMode.paginated,
    this.readingDirection = ReaderReadingDirection.leftToRight,
    this.imageFit = ReaderImageFit.page,
  });
  final ReaderReadingMode readingMode;
  final ReaderReadingDirection readingDirection;
  final ReaderImageFit imageFit;
  ReaderPageSettings copyWith({
    ReaderReadingMode? readingMode,
    ReaderReadingDirection? readingDirection,
    ReaderImageFit? imageFit,
  }) => ReaderPageSettings(
    readingMode: readingMode ?? this.readingMode,
    readingDirection: readingDirection ?? this.readingDirection,
    imageFit: imageFit ?? this.imageFit,
  );
  Map<String, Object> toJson() => {
    'readingMode': readingMode.name,
    'readingDirection': readingDirection.name,
    'imageFit': imageFit.name,
  };
  factory ReaderPageSettings.fromJson(Map<String, Object?> json) =>
      ReaderPageSettings(
        readingMode: ReaderReadingMode.values.firstWhere(
          (value) => value.name == json['readingMode'],
          orElse: () => ReaderReadingMode.paginated,
        ),
        readingDirection: ReaderReadingDirection.values.firstWhere(
          (value) => value.name == json['readingDirection'],
          orElse: () => ReaderReadingDirection.leftToRight,
        ),
        imageFit: ReaderImageFit.values.firstWhere(
          (value) => value.name == json['imageFit'],
          orElse: () => ReaderImageFit.page,
        ),
      );
  @override
  bool operator ==(Object other) =>
      other is ReaderPageSettings &&
      other.readingMode == readingMode &&
      other.readingDirection == readingDirection &&
      other.imageFit == imageFit;
  @override
  int get hashCode => Object.hash(readingMode, readingDirection, imageFit);
}

class ReaderSourceSpecificSettings {
  const ReaderSourceSpecificSettings({this.publisherStyles = true});
  final bool publisherStyles;
  ReaderSourceSpecificSettings copyWith({bool? publisherStyles}) =>
      ReaderSourceSpecificSettings(
        publisherStyles: publisherStyles ?? this.publisherStyles,
      );
  Map<String, Object> toJson() => {'publisherStyles': publisherStyles};
  factory ReaderSourceSpecificSettings.fromJson(Map<String, Object?> json) =>
      ReaderSourceSpecificSettings(
        publisherStyles: json['publisherStyles'] as bool? ?? true,
      );
  @override
  bool operator ==(Object other) =>
      other is ReaderSourceSpecificSettings &&
      other.publisherStyles == publisherStyles;
  @override
  int get hashCode => publisherStyles.hashCode;
}

class ReaderSettingsState {
  const ReaderSettingsState({
    required this.profile,
    this.appearance,
    this.typography,
    this.spacing,
    this.textLayout,
    this.page,
    this.sourceSpecific,
  });

  static const readiumDefaults = ReaderSettingsState(
    profile: ReaderSettingsProfile.readiumReflowable,
    appearance: ReaderAppearanceSettings(),
    typography: ReaderTypographySettings(),
    spacing: ReaderSpacingSettings(),
    textLayout: ReaderTextLayoutSettings(),
    sourceSpecific: ReaderSourceSpecificSettings(),
  );
  static const pdfDefaults = ReaderSettingsState(
    profile: ReaderSettingsProfile.pdf,
    spacing: ReaderSpacingSettings(),
  );
  static const comicDefaults = ReaderSettingsState(
    profile: ReaderSettingsProfile.comic,
    spacing: ReaderSpacingSettings(),
    page: ReaderPageSettings(),
  );

  final ReaderSettingsProfile profile;
  final ReaderAppearanceSettings? appearance;
  final ReaderTypographySettings? typography;
  final ReaderSpacingSettings? spacing;
  final ReaderTextLayoutSettings? textLayout;
  final ReaderPageSettings? page;
  final ReaderSourceSpecificSettings? sourceSpecific;

  ReaderSettingsState copyWith({
    ReaderAppearanceSettings? appearance,
    ReaderTypographySettings? typography,
    ReaderSpacingSettings? spacing,
    ReaderTextLayoutSettings? textLayout,
    ReaderPageSettings? page,
    ReaderSourceSpecificSettings? sourceSpecific,
  }) => ReaderSettingsState(
    profile: profile,
    appearance: appearance ?? this.appearance,
    typography: typography ?? this.typography,
    spacing: spacing ?? this.spacing,
    textLayout: textLayout ?? this.textLayout,
    page: page ?? this.page,
    sourceSpecific: sourceSpecific ?? this.sourceSpecific,
  );

  Map<String, Object?> toJson() => {
    'profile': profile.name,
    if (appearance != null) 'appearance': appearance!.toJson(),
    if (typography != null) 'typography': typography!.toJson(),
    if (spacing != null) 'spacing': spacing!.toJson(),
    if (textLayout != null) 'textLayout': textLayout!.toJson(),
    if (page != null) 'page': page!.toJson(),
    if (sourceSpecific != null) 'sourceSpecific': sourceSpecific!.toJson(),
  };

  factory ReaderSettingsState.fromJson(Map<String, Object?> json) {
    final profile = ReaderSettingsProfile.values.firstWhere(
      (value) => value.name == json['profile'],
      orElse: () => throw const FormatException('invalid_settings_profile'),
    );
    Map<String, Object?>? group(String key) {
      final value = json[key];
      return value is Map ? value.cast<String, Object?>() : null;
    }

    final appearance = group('appearance');
    final typography = group('typography');
    final spacing = group('spacing');
    final textLayout = group('textLayout');
    final page = group('page');
    final sourceSpecific = group('sourceSpecific');
    return ReaderSettingsState(
      profile: profile,
      appearance: appearance == null
          ? null
          : ReaderAppearanceSettings.fromJson(appearance),
      typography: typography == null
          ? null
          : ReaderTypographySettings.fromJson(typography),
      spacing: spacing == null ? null : ReaderSpacingSettings.fromJson(spacing),
      textLayout: textLayout == null
          ? null
          : ReaderTextLayoutSettings.fromJson(textLayout),
      page: page == null ? null : ReaderPageSettings.fromJson(page),
      sourceSpecific: sourceSpecific == null
          ? null
          : ReaderSourceSpecificSettings.fromJson(sourceSpecific),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderSettingsState &&
      other.profile == profile &&
      other.appearance == appearance &&
      other.typography == typography &&
      other.spacing == spacing &&
      other.textLayout == textLayout &&
      other.page == page &&
      other.sourceSpecific == sourceSpecific;
  @override
  int get hashCode => Object.hash(
    profile,
    appearance,
    typography,
    spacing,
    textLayout,
    page,
    sourceSpecific,
  );
}

double _finite(double value, double fallback, double low, double high) =>
    value.isFinite ? value.clamp(low, high).toDouble() : fallback;
double _jsonNumber(Object? value, double fallback, double low, double high) =>
    value is num ? _finite(value.toDouble(), fallback, low, high) : fallback;
