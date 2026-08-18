import 'package:flutter/material.dart';

import 'brand_colors.dart';
import 'dimens.dart';

/// Wires the §2 tokens into a Material theme.
///
/// Widgets read colours from `Theme.of(context)` or [BrandColors] — never from
/// a literal. If a value is missing here, add it here rather than reaching for
/// a hex in a widget.
abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.brand,
      primary: BrandColors.brand,
      onPrimary: BrandColors.surface,
      secondary: BrandColors.accent,
      onSecondary: BrandColors.surface,
      surface: BrandColors.surface,
      onSurface: BrandColors.ink,
      error: BrandColors.danger,
      onError: BrandColors.surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Cairo',
      scaffoldBackgroundColor: BrandColors.page,
      textTheme: _textTheme,

      appBarTheme: const AppBarTheme(
        backgroundColor: BrandColors.brandDark,
        foregroundColor: BrandColors.surface,
        elevation: 0,
        centerTitle: false,
      ),

      cardTheme: CardThemeData(
        color: BrandColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radiusLg),
          side: const BorderSide(color: BrandColors.brandLight),
        ),
        margin: EdgeInsets.zero,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BrandColors.brand,
          foregroundColor: BrandColors.surface,
          minimumSize: const Size.fromHeight(Dimens.controlHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Dimens.radius),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: Dimens.lineHeight,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BrandColors.brand,
          minimumSize: const Size.fromHeight(Dimens.controlHeight),
          side: const BorderSide(color: BrandColors.brandLight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Dimens.radius),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: Dimens.lineHeight,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BrandColors.brand,
          minimumSize: const Size(Dimens.minTarget, Dimens.minTarget),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w700,
            height: Dimens.lineHeight,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BrandColors.page,
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: Dimens.space4,
          vertical: Dimens.space3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimens.radius),
          borderSide: const BorderSide(color: BrandColors.brandLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimens.radius),
          borderSide: const BorderSide(color: BrandColors.brandLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimens.radius),
          borderSide: const BorderSide(color: BrandColors.focus, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimens.radius),
          borderSide: const BorderSide(color: BrandColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimens.radius),
          borderSide: const BorderSide(color: BrandColors.danger, width: 1.5),
        ),
        labelStyle: const TextStyle(color: BrandColors.muted),
        hintStyle: const TextStyle(color: BrandColors.muted),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: BrandColors.surface,
        side: const BorderSide(color: BrandColors.brandLight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radiusLg),
        ),
        labelStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13,
          color: BrandColors.ink,
        ),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Dimens.space3,
          vertical: Dimens.space2,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: BrandColors.ink,
        contentTextStyle: const TextStyle(
          fontFamily: 'Cairo',
          color: BrandColors.surface,
          height: Dimens.lineHeight,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radius),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: BrandColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radiusLg),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: BrandColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.vertical(
            top: Radius.circular(Dimens.radiusLg),
          ),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: BrandColors.brandLight,
        thickness: 1,
        space: 1,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: BrandColors.brand,
      ),
    );
  }

  /// Arabic needs more leading than the Material default, and numbers in lists
  /// and tables use tabular figures so columns line up (§2.4).
  static const _textTheme = TextTheme(
    displaySmall: TextStyle(height: Dimens.lineHeight, color: BrandColors.ink),
    headlineMedium: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: Dimens.lineHeight,
      color: BrandColors.ink,
    ),
    headlineSmall: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: Dimens.lineHeight,
      color: BrandColors.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: Dimens.lineHeight,
      color: BrandColors.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: Dimens.lineHeight,
      color: BrandColors.ink,
    ),
    titleSmall: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      height: Dimens.lineHeight,
      color: BrandColors.ink,
    ),
    bodyLarge: TextStyle(
      fontSize: 15,
      height: Dimens.lineHeight,
      color: BrandColors.ink,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: Dimens.lineHeight,
      color: BrandColors.ink,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      height: Dimens.lineHeight,
      color: BrandColors.muted,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: Dimens.lineHeight,
      color: BrandColors.ink,
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      height: Dimens.lineHeight,
      color: BrandColors.muted,
    ),
  );

  /// Tabular figures, for any number rendered in a list, table or stepper.
  static const tabularFigures = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
