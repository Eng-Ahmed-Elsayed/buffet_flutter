import 'package:flutter/material.dart';

/// Motion tokens mapped from the CSS custom properties (§2.3).
///
/// Duration expresses distance and consequence. **Exits are always faster than
/// entrances**, because a thing leaving has already been decided and waiting
/// for it is pure cost.
abstract final class Motion {
  /// Colour-only feedback: hover, press-down.
  static const instant = Duration(milliseconds: 90);

  /// Acknowledgement: press, check, chip toggle.
  static const fast = Duration(milliseconds: 140);

  /// Routine state change: panel, badge, row.
  static const base = Duration(milliseconds: 220);

  /// Layout, overlay, route transition.
  static const slow = Duration(milliseconds: 320);

  /// Anything leaving. Deliberately equal to [fast] and never longer.
  static const exit = Duration(milliseconds: 140);

  /// Exponential ease-out: arrives at speed and settles. Reads as physical
  /// without the dated overshoot of a bounce.
  static const easeOut = Cubic(0.16, 1, 0.3, 1);

  /// Gentler, for small frequent moves where [easeOut] is too theatrical.
  static const easeSoft = Cubic(0.32, 0.72, 0, 1);

  static const easeInOut = Cubic(0.65, 0, 0.35, 1);

  /// Collapses a duration to zero when the platform asks for reduced motion.
  ///
  /// The web collapses every duration to 1ms under `prefers-reduced-motion`;
  /// this is the Flutter equivalent. Opacity and colour still carry state —
  /// only spatial movement stops — so call this on the *duration*, and do not
  /// branch away the colour change itself.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
