import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';

class ReaderCapabilities {
  const ReaderCapabilities({
    required this.supportsTextAppearance,
    required this.supportsTableOfContents,
    required this.supportsBookmarks,
    this.supportsBookmarkNavigation = false,
    this.supportsBookmarkLabels = false,
    required this.supportsHighlights,
    required this.supportsPageSeeking,
    required this.supportsZoom,
    this.supportsNativeContentTap = false,
    this.supportsNativeTextSelection = false,
    this.supportsNativeCopy = false,
    this.supportsAnnotationNotes = false,
    this.supportsDecorationActivation = false,
    this.supportsSearch = false,
    this.supportsSearchResultNavigation = false,
    this.supportsSearchResultHighlighting = false,
  });

  final bool supportsTextAppearance;
  final bool supportsTableOfContents;
  final bool supportsBookmarks;
  final bool supportsBookmarkNavigation;
  final bool supportsBookmarkLabels;
  final bool supportsHighlights;
  final bool supportsPageSeeking;
  final bool supportsZoom;
  final bool supportsNativeContentTap;
  final bool supportsNativeTextSelection;
  final bool supportsNativeCopy;
  final bool supportsAnnotationNotes;
  final bool supportsDecorationActivation;
  final bool supportsSearch;
  final bool supportsSearchResultNavigation;
  final bool supportsSearchResultHighlighting;

  static ReaderCapabilities forKind(ReaderKind kind) => switch (kind) {
    ReaderKind.epub => const ReaderCapabilities(
      supportsTextAppearance: true,
      supportsTableOfContents: true,
      supportsBookmarks: true,
      supportsBookmarkNavigation: true,
      supportsBookmarkLabels: true,
      supportsHighlights: true,
      supportsPageSeeking: true,
      supportsZoom: false,
      supportsNativeContentTap: true,
      supportsNativeTextSelection: true,
      supportsNativeCopy: true,
      supportsAnnotationNotes: true,
      supportsDecorationActivation: true,
      supportsSearch: true,
      supportsSearchResultNavigation: true,
      supportsSearchResultHighlighting: true,
    ),
    ReaderKind.reflowable => const ReaderCapabilities(
      supportsTextAppearance: true,
      supportsTableOfContents: true,
      supportsBookmarks: true,
      supportsBookmarkNavigation: true,
      supportsBookmarkLabels: true,
      supportsHighlights: true,
      supportsPageSeeking: true,
      supportsZoom: false,
      supportsNativeContentTap: true,
      supportsNativeTextSelection: true,
      supportsNativeCopy: true,
      supportsAnnotationNotes: true,
      supportsDecorationActivation: true,
      supportsSearch: true,
      supportsSearchResultNavigation: true,
      supportsSearchResultHighlighting: true,
    ),
    ReaderKind.pdf => const ReaderCapabilities(
      supportsTextAppearance: false,
      supportsTableOfContents: false,
      supportsBookmarks: false,
      supportsHighlights: false,
      supportsPageSeeking: true,
      supportsZoom: true,
    ),
    ReaderKind.comic => const ReaderCapabilities(
      supportsTextAppearance: false,
      supportsTableOfContents: false,
      supportsBookmarks: false,
      supportsHighlights: false,
      supportsPageSeeking: true,
      supportsZoom: true,
    ),
    ReaderKind.unsupported => const ReaderCapabilities(
      supportsTextAppearance: false,
      supportsTableOfContents: false,
      supportsBookmarks: false,
      supportsHighlights: false,
      supportsPageSeeking: false,
      supportsZoom: false,
    ),
  };
}
