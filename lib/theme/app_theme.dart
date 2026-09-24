import 'package:flutter/material.dart';

import 'brand_colors.dart';
import 'dimens.dart';

/// Wires the tokens into a Material theme, one per script.
///
/// Widgets read colours from `Theme.of(context)` or [BrandColors] — never from
/// a literal. If a value is missing here, add it here rather than reaching for
/// a hex in a widget.
abstract final class AppTheme {
  /// The theme for [locale]. Arabic and English share every colour and size;
  /// they differ in typeface and leading, which is the whole reason there are
  /// two.
  ///
  /// - **Arabic** is set in Cairo at `height` 1.7 (§2.4), with no letter
  ///   spacing — spacing breaks the joins between Arabic letters.
  /// - **English** is set in Inter, the design's Latin face, at the design's
  ///   tighter leading (heading 28/36 at 600). Cairo is its fallback, because
  ///   admin-entered item names are often Arabic even on an English screen.
  static ThemeData forLocale(Locale locale) {
    final arabic = locale.languageCode == 'ar';
    final family = arabic ? _arabicFamily : _latinFamily;
    final fallback = arabic ? null : const [_arabicFamily];
    final text = _textTheme(arabic: arabic);

    TextStyle font(TextStyle style) =>
        style.copyWith(fontFamily: family, fontFamilyFallback: fallback);

    final scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.brand,
      primary: BrandColors.brand,
      onPrimary: BrandColors.surface,
      // Not violet. Material paints some selected states from `secondary`, and
      // violet is reserved for "from my own jar" (rule 3).
      secondary: BrandColors.brandSecondary,
      onSecondary: BrandColors.surface,
      surface: BrandColors.surface,
      onSurface: BrandColors.ink,
      onSurfaceVariant: BrandColors.muted,
      outline: BrandColors.outline,
      outlineVariant: BrandColors.brandLight,
      error: BrandColors.danger,
      onError: BrandColors.surface,
      brightness: Brightness.light,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Dimens.radius),
      borderSide: const BorderSide(color: BrandColors.brand),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: family,
      fontFamilyFallback: fallback,
      scaffoldBackgroundColor: BrandColors.page,
      textTheme: text,

      // The design's top bar is white with a hairline under it, not the navy
      // bar the web uses. Icons take the primary blue; the title takes ink.
      appBarTheme: AppBarTheme(
        backgroundColor: BrandColors.surface,
        foregroundColor: BrandColors.brand,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: Dimens.topBarHeight,
        titleTextStyle: font(text.titleLarge!),
        shape: const Border(bottom: BorderSide(color: BrandColors.brandLight)),
      ),

      cardTheme: CardThemeData(
        color: BrandColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radius),
          side: const BorderSide(color: BrandColors.brandLight),
        ),
        margin: EdgeInsets.zero,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BrandColors.brand,
          foregroundColor: BrandColors.surface,
          minimumSize: const Size.fromHeight(Dimens.controlHeight),
          shape: const StadiumBorder(),
          textStyle: font(text.titleMedium!),
        ),
      ),

      // White-filled with a primary border: the design's secondary button
      // ("Login" under "Next" on onboarding).
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BrandColors.brand,
          backgroundColor: BrandColors.surface,
          minimumSize: const Size.fromHeight(Dimens.controlHeight),
          side: const BorderSide(color: BrandColors.brand),
          shape: const StadiumBorder(),
          textStyle: font(text.titleMedium!),
        ),
      ),

      // Links ("Change", "Forgot?") are the second blue, which holds AA on
      // both the page and white.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BrandColors.brandSecondary,
          minimumSize: const Size(Dimens.minTarget, Dimens.minTarget),
          textStyle: font(text.labelLarge!),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BrandColors.surface,
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: Dimens.space4,
          vertical: Dimens.space4,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(
            color: BrandColors.focus,
            width: Dimens.borderSelected,
          ),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: BrandColors.danger),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(
            color: BrandColors.danger,
            width: Dimens.borderSelected,
          ),
        ),
        prefixIconColor: BrandColors.iconBlue,
        suffixIconColor: BrandColors.muted,
        labelStyle: const TextStyle(color: BrandColors.muted),
        hintStyle: const TextStyle(color: BrandColors.muted),
      ),

      // Pills. Unselected: white with the [BrandColors.outline] edge, which
      // holds 3:1 where the design's paler edge did not. Selected: the bright
      // blue fill with white text. The own-jar extra chip overrides both with
      // violet, and must stay the only chip that does.
      chipTheme: ChipThemeData(
        backgroundColor: BrandColors.surface,
        selectedColor: BrandColors.brandBright,
        checkmarkColor: BrandColors.surface,
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const BorderSide(color: BrandColors.brandBright)
              : const BorderSide(color: BrandColors.outline),
        ),
        shape: const StadiumBorder(),
        labelStyle: font(text.bodyMedium!).copyWith(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? BrandColors.surface
                : BrandColors.ink,
          ),
        ),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Dimens.space3,
          vertical: Dimens.space2,
        ),
      ),

      // The design's bottom bar: white, icons and labels only, no pill behind
      // the active item. Active is the primary blue; inactive the bright blue,
      // which holds AA on the white bar.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: BrandColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: Dimens.navBarHeight,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? BrandColors.brand
                : BrandColors.brandBright,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => font(text.labelMedium!).copyWith(
            color: states.contains(WidgetState.selected)
                ? BrandColors.brand
                : BrandColors.brandBright,
          ),
        ),
      ),

      // Process / Done on the tracking screen. The design's inactive label
      // (`#8CBCF9`, 1.71:1) could not be read, so it takes [BrandColors.muted].
      tabBarTheme: TabBarThemeData(
        labelColor: BrandColors.brand,
        unselectedLabelColor: BrandColors.muted,
        indicatorColor: BrandColors.iconBlue,
        dividerColor: BrandColors.brandLight,
        labelStyle: font(text.titleMedium!),
        unselectedLabelStyle: font(text.titleMedium!),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: BrandColors.ink,
        contentTextStyle: font(text.bodyMedium!)
            .copyWith(color: BrandColors.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radius),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: BrandColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radiusLg),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: BrandColors.surface,
        surfaceTintColor: Colors.transparent,
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

  static const _arabicFamily = 'Cairo';
  static const _latinFamily = 'Inter';

  /// One type scale for both scripts; only the leading (and, for Latin
  /// labels, the tracking) differs. Sizes follow the design — heading 28 at
  /// 600, section and card titles 16 at 600, body 16 and 14.
  ///
  /// Each style's height is the Latin value, replaced by [Dimens.lineHeight]
  /// for Arabic, which needs the extra room for its marks (§2.4).
  static TextTheme _textTheme({required bool arabic}) {
    TextStyle style(
      double size,
      double latinHeight, {
      FontWeight weight = FontWeight.w400,
      Color color = BrandColors.ink,
      double latinTracking = 0,
    }) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: arabic ? Dimens.lineHeight : latinHeight,
      letterSpacing: arabic ? 0 : latinTracking,
      color: color,
    );

    return TextTheme(
      displaySmall: style(32, 1.25, weight: FontWeight.w600),
      // "Welcome Back", a drink's name: Figma's 28/36 at 600.
      headlineMedium: style(28, 36 / 28, weight: FontWeight.w600),
      // The greeting: "Good Morning, Salma".
      headlineSmall: style(20, 28 / 20, weight: FontWeight.w600),
      titleLarge: style(18, 24 / 18, weight: FontWeight.w600),
      // Section headings and card titles.
      titleMedium: style(16, 24 / 16, weight: FontWeight.w600),
      titleSmall: style(15, 22 / 15, weight: FontWeight.w600),
      bodyLarge: style(16, 24 / 16),
      bodyMedium: style(14, 20 / 14),
      bodySmall: style(13, 18 / 13, color: BrandColors.muted),
      labelLarge: style(14, 20 / 14, weight: FontWeight.w600),
      // The design's small-caps field labels ("EMAIL ADDRESS", "CHOOSE
      // SIZE") and the nav labels. Tracked in Latin only.
      labelMedium: style(
        12,
        16 / 12,
        weight: FontWeight.w600,
        latinTracking: 0.5,
      ),
      labelSmall: style(12, 16 / 12, color: BrandColors.muted),
    );
  }

  /// Tabular figures, for any number rendered in a list, table or stepper.
  static const tabularFigures = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
