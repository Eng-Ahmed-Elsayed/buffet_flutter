/// Radii, spacing and touch-target sizes from §2.3.
///
/// A literal in a widget is a bug even when it looks right — it is how a design
/// system drifts. Every number a widget uses comes from here.
abstract final class Dimens {
  // Radii
  static const radiusSm = 10.0;
  static const radius = 14.0;
  static const radiusLg = 18.0;

  // Spacing — a 4px scale, named by role, so "gap between a heading and its
  // section" is one decision made once.
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 24.0;
  static const space6 = 32.0;
  static const space7 = 48.0;
  static const space8 = 64.0;

  /// Minimum interactive target (§2.5). The web standard here is 44px;
  /// Material's 48dp default satisfies it, but anything hand-sized must not
  /// fall below this.
  static const minTarget = 44.0;

  /// Standard height for a primary control — comfortably above [minTarget].
  static const controlHeight = 52.0;

  /// Arabic needs more leading than the Material default (§2.4).
  static const lineHeight = 1.7;
}
