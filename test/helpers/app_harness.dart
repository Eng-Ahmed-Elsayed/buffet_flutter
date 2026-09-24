import 'dart:io';

import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Shared scaffolding for widget tests, so a screen under test looks and
/// measures the way it ships.
///
/// It exists because the 320dp responsive suite used to pump every screen
/// with Flutter's default theme and the test binding's placeholder font. It
/// measured layouts nobody would ever see: no Cairo, no Inter, no 1.7 Arabic
/// leading, none of the app's button heights. A theme change could overflow a
/// real screen while the suite stayed green.

bool _fontsLoaded = false;

/// Loads the fonts the app bundles (Cairo, Inter) and the Material icon font.
///
/// Call it from `setUpAll`. It is idempotent within a test file.
///
/// Without it every glyph is a placeholder box, which both makes captures
/// unreadable and changes every text measurement the layout tests rely on.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;

  Future<void> load(String family, String path) async {
    final loader = FontLoader(family)
      ..addFont(File(path).readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }

  await load('Cairo', 'assets/fonts/Cairo.ttf');
  await load('Inter', 'assets/fonts/Inter.ttf');

  // The Material icon font ships inside the SDK rather than this repo, so its
  // path is resolved from the running toolchain instead of hardcoded: the test
  // binary is `…/bin/cache/artifacts/engine/<platform>/flutter_tester.exe`,
  // which puts the font two directories up. A missing one is skipped rather
  // than failing the run — icons are fixed-size, so layouts still measure
  // correctly without their glyphs.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final icons = File(
    '${artifacts.path}/material_fonts/materialicons-regular.otf',
  );
  if (icons.existsSync()) {
    await load('MaterialIcons', icons.path);
  }
}

/// A `MaterialApp` configured as the app configures it: the real theme for
/// [locale], the localisation delegates, Arabic and English supported.
///
/// [textScale] pins the text scale factor, for tests that check a layout at
/// 1.5x and 2x.
Widget testApp({
  required Widget home,
  Locale locale = const Locale('ar'),
  double? textScale,
}) => MaterialApp(
  theme: AppTheme.forLocale(locale),
  debugShowCheckedModeBanner: false,
  locale: locale,
  supportedLocales: const [Locale('ar'), Locale('en')],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: textScale == null
      ? null
      : (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
  home: home,
);
