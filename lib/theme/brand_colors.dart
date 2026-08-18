import 'package:flutter/material.dart';

/// The palette, ported verbatim from the backend's `site.css`.
///
/// The colours are *sampled from the logo gradient* — `brand` and `accent` are
/// the two ends of the circuit mark's navy-to-violet stroke. Never recolour the
/// logo to match a theme; the theme already matches the logo.
///
/// The contrast ratios in the comments are measurements, not decoration. A
/// palette edit is exactly the moment they silently stop holding, so re-measure
/// rather than deleting them.
abstract final class BrandColors {
  /// Logo gradient, deep-blue mid-stroke. 10.98:1 with white text.
  static const brand = Color(0xFF123A7A);

  /// The wordmark navy. 16.13:1 with white text.
  static const brandDark = Color(0xFF0B1E4B);

  /// Tinted from brand, not picked — keeps chips in one hue family.
  static const brandLight = Color(0xFFE9EFF9);

  /// The violet end of the gradient. A *fill*: 7.32:1 with white text.
  ///
  /// Violet means "from my own jar" — everywhere, without exception. Do not
  /// reuse it for a generic selection state, or "from my materials" stops being
  /// readable at a glance.
  static const accent = Color(0xFF6D22D8);

  /// Lightened until it clears 3:1 on the navy bar. Non-text UI only —
  /// at 2.72:1 it must never carry white text.
  static const accentBright = Color(0xFFA78BFA);

  static const focus = Color(0xFF5417B0);
  static const ink = Color(0xFF141B2E);

  /// Holds AA on both white (5.67:1) and the page background (5.24:1).
  static const muted = Color(0xFF5C6780);

  static const surface = Color(0xFFFFFFFF);

  /// Neutral cooled toward the brand hue so cards read as white on it.
  static const page = Color(0xFFF4F6FA);

  static const danger = Color(0xFFB42318);
  static const warning = Color(0xFFB54708);

  /// Deliberately green, not brand-blue: "healthy stock" loses its meaning
  /// if the level colours are all one hue. 5.19:1 on white.
  static const ok = Color(0xFF0E7C5A);

  /// Tint of [accent] for the "from my own jar" surfaces. Non-text: it exists
  /// to carry violet text and borders, never to carry white.
  static const accentSurface = Color(0xFFF5F0FE);

  /// Tint of [warning] for shortage banners. Non-text, as above.
  static const warningSurface = Color(0xFFFEF6EE);

  /// Tint of [ok] for the ready/handover surfaces. Non-text, as above.
  static const okSurface = Color(0xFFE7F4EF);
}
