import 'package:flutter/material.dart';

@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    required this.pagePadding,
    required this.sectionSpacing,
    required this.carouselGap,
    required this.bookCardWidth,
    required this.bookCardAspectRatio,
    required this.coverAspectRatio,
    required this.cardRadius,
    required this.bookCardOutlineWidth,
    required this.bookCardBottomBarHeight,
    required this.bookCardBottomBarHorizontalPadding,
    required this.bookCardFavoriteIconSize,
    required this.bookCardGridGap,
    required this.navigationRadius,
    required this.buttonRadius,
    required this.navigationHeight,
  });

  factory AppThemeTokens.standard() => const AppThemeTokens(
    pagePadding: 20,
    sectionSpacing: 32,
    carouselGap: 12,
    bookCardWidth: 164,
    bookCardAspectRatio: 0.65,
    coverAspectRatio: 2 / 3,
    cardRadius: 24,
    bookCardOutlineWidth: 1,
    bookCardBottomBarHeight: 40,
    bookCardBottomBarHorizontalPadding: 12,
    bookCardFavoriteIconSize: 20,
    bookCardGridGap: 16,
    navigationRadius: 24,
    buttonRadius: 999,
    navigationHeight: 64,
  );

  final double pagePadding;
  final double sectionSpacing;
  final double carouselGap;
  final double bookCardWidth;
  final double bookCardAspectRatio;
  final double coverAspectRatio;
  final double cardRadius;
  final double bookCardOutlineWidth;
  final double bookCardBottomBarHeight;
  final double bookCardBottomBarHorizontalPadding;
  final double bookCardFavoriteIconSize;
  final double bookCardGridGap;
  final double navigationRadius;
  final double buttonRadius;
  final double navigationHeight;

  @override
  AppThemeTokens copyWith({
    double? pagePadding,
    double? sectionSpacing,
    double? carouselGap,
    double? bookCardWidth,
    double? bookCardAspectRatio,
    double? coverAspectRatio,
    double? cardRadius,
    double? bookCardOutlineWidth,
    double? bookCardBottomBarHeight,
    double? bookCardBottomBarHorizontalPadding,
    double? bookCardFavoriteIconSize,
    double? bookCardGridGap,
    double? navigationRadius,
    double? buttonRadius,
    double? navigationHeight,
  }) => AppThemeTokens(
    pagePadding: pagePadding ?? this.pagePadding,
    sectionSpacing: sectionSpacing ?? this.sectionSpacing,
    carouselGap: carouselGap ?? this.carouselGap,
    bookCardWidth: bookCardWidth ?? this.bookCardWidth,
    bookCardAspectRatio: bookCardAspectRatio ?? this.bookCardAspectRatio,
    coverAspectRatio: coverAspectRatio ?? this.coverAspectRatio,
    cardRadius: cardRadius ?? this.cardRadius,
    bookCardOutlineWidth: bookCardOutlineWidth ?? this.bookCardOutlineWidth,
    bookCardBottomBarHeight:
        bookCardBottomBarHeight ?? this.bookCardBottomBarHeight,
    bookCardBottomBarHorizontalPadding:
        bookCardBottomBarHorizontalPadding ??
        this.bookCardBottomBarHorizontalPadding,
    bookCardFavoriteIconSize:
        bookCardFavoriteIconSize ?? this.bookCardFavoriteIconSize,
    bookCardGridGap: bookCardGridGap ?? this.bookCardGridGap,
    navigationRadius: navigationRadius ?? this.navigationRadius,
    buttonRadius: buttonRadius ?? this.buttonRadius,
    navigationHeight: navigationHeight ?? this.navigationHeight,
  );

  @override
  AppThemeTokens lerp(covariant AppThemeTokens? other, double t) {
    if (other == null) return this;
    return AppThemeTokens(
      pagePadding: lerpDouble(pagePadding, other.pagePadding, t),
      sectionSpacing: lerpDouble(sectionSpacing, other.sectionSpacing, t),
      carouselGap: lerpDouble(carouselGap, other.carouselGap, t),
      bookCardWidth: lerpDouble(bookCardWidth, other.bookCardWidth, t),
      bookCardAspectRatio: lerpDouble(
        bookCardAspectRatio,
        other.bookCardAspectRatio,
        t,
      ),
      coverAspectRatio: lerpDouble(coverAspectRatio, other.coverAspectRatio, t),
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t),
      bookCardOutlineWidth: lerpDouble(
        bookCardOutlineWidth,
        other.bookCardOutlineWidth,
        t,
      ),
      bookCardBottomBarHeight: lerpDouble(
        bookCardBottomBarHeight,
        other.bookCardBottomBarHeight,
        t,
      ),
      bookCardBottomBarHorizontalPadding: lerpDouble(
        bookCardBottomBarHorizontalPadding,
        other.bookCardBottomBarHorizontalPadding,
        t,
      ),
      bookCardFavoriteIconSize: lerpDouble(
        bookCardFavoriteIconSize,
        other.bookCardFavoriteIconSize,
        t,
      ),
      bookCardGridGap: lerpDouble(bookCardGridGap, other.bookCardGridGap, t),
      navigationRadius: lerpDouble(navigationRadius, other.navigationRadius, t),
      buttonRadius: lerpDouble(buttonRadius, other.buttonRadius, t),
      navigationHeight: lerpDouble(navigationHeight, other.navigationHeight, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

extension AppThemeTokensContext on BuildContext {
  AppThemeTokens get appTokens =>
      Theme.of(this).extension<AppThemeTokens>() ?? AppThemeTokens.standard();
}
