import 'package:flutter/material.dart';

/// The palette, taken from the Figma design (`design/figma/`) and fixed for
/// contrast where the design fell short — see `docs/figma-redesign.md`.
///
/// The blues are sampled from the 2x exports; the semantic colours (danger,
/// warning, ok) and the violet [accent] are kept from the web's `site.css`,
/// because the design has none of its own. Never recolour the logo to match a
/// theme; the theme already matches the logo.
///
/// The contrast ratios in the comments are measurements, not decoration. A
/// palette edit is exactly the moment they silently stop holding, so re-measure
/// rather than deleting them. "Page" means [page]; "white" means [surface].
abstract final class BrandColors {
  /// The design's primary blue: filled buttons, input and outline-button
  /// borders, headings, the active nav item. 8.21:1 with white text, 7.16:1
  /// on the page.
  static const brand = Color(0xFF1C4B9F);

  /// The design's second blue: card titles, links, the tracking timeline.
  /// Text on both grounds — 6.11:1 on white, 5.33:1 on the page.
  static const brandSecondary = Color(0xFF285EBE);

  /// The selected chip's fill and the inactive nav labels on the white bar.
  /// 4.65:1 with white text and on white — but only 4.06:1 on the page, so it
  /// never carries text there.
  static const brandBright = Color(0xFF3871D7);

  /// Icons, the active tab indicator, the inactive page dot. **Non-text only**:
  /// 4.45:1 on white passes for text, but 3.88:1 on the page does not, and an
  /// icon colour that is text on one ground and not the other is a trap.
  static const iconBlue = Color(0xFF2A71F0);

  /// The hairline: card borders, dividers, the top bar's bottom edge.
  /// **Decorative only** — 1.35:1 on white, 1.18:1 on the page. Nothing a user
  /// must find to operate may depend on it; that is what [outline] is for.
  static const brandLight = Color(0xFFD0DFF2);

  /// The outline of an interactive control that is not primary — an unselected
  /// chip, a stepper. Figma's `#B4CDEC` measured 1.42:1 on the page, below the
  /// 3:1 non-text minimum; darkened in the same hue to 3.04:1 on the page and
  /// 3.48:1 on white.
  static const outline = Color(0xFF6B8AC1);

  /// The violet end of the logo gradient. A *fill*: 7.32:1 with white text,
  /// 6.38:1 on the page.
  ///
  /// Violet means "from my own jar" — everywhere, without exception. Do not
  /// reuse it for a generic selection state, or "from my materials" stops being
  /// readable at a glance. The design uses no violet in its UI, so nothing
  /// collides.
  static const accent = Color(0xFF6D22D8);

  /// The focus ring on an input, drawn 2dp over the 1dp [brand] border.
  /// Blue rather than the violet it used to be, so violet stays "my own jar".
  /// 4.45:1 on white, the ground inputs sit on.
  static const focus = iconBlue;

  /// Headings and body text. 13.48:1 on white, 11.75:1 on the page.
  static const ink = Color(0xFF1C2F4B);

  /// Secondary text, hints and placeholders. 5.67:1 on white, 4.94:1 on the
  /// page. It replaces the design's greys (`#ACACAC`, `#BEBEBE`, `#919191`),
  /// which measured 1.86–2.43:1 and could not be read.
  static const muted = Color(0xFF5C6780);

  static const surface = Color(0xFFFFFFFF);

  /// The design's pale-blue page. White cards read as white on it.
  static const page = Color(0xFFE7F0FF);

  /// 6.57:1 on white, 5.73:1 on the page.
  static const danger = Color(0xFFB42318);

  /// 5.43:1 on white, 4.73:1 on the page.
  static const warning = Color(0xFFB54708);

  /// Deliberately green, not brand-blue: "healthy stock" loses its meaning
  /// if the level colours are all one hue. It also replaces the design's
  /// `#00B67A`, which carried white text at 2.63:1. 5.19:1 on white, 4.52:1
  /// on the page.
  static const ok = Color(0xFF0E7C5A);

  /// Tint of [accent] for the "from my own jar" surfaces. Non-text: it exists
  /// to carry violet text and borders (6.54:1), never to carry white.
  static const accentSurface = Color(0xFFF5F0FE);

  /// Tint of [warning] for shortage banners. Non-text, as above (5.07:1).
  static const warningSurface = Color(0xFFFEF6EE);

  /// Tint of [ok] for the ready/handover surfaces. Non-text, as above (4.59:1).
  static const okSurface = Color(0xFFE7F4EF);
}
