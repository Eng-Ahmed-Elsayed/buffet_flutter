import 'package:intl/intl.dart';

/// Formatting helpers for the two traps that bite across every screen:
/// bidi-unsafe quantity strings, and raw UTC timestamps.
abstract final class Formatters {
  /// Unicode First Strong Isolate (U+2068) — opens an isolate whose direction
  /// is taken from the first strong character inside it.
  ///
  /// Written as an escape rather than the literal character: these are
  /// invisible in an editor, and a bare one would silently reorder this source
  /// file for anyone reading it.
  static const _fsi = '\u{2068}';

  /// Pop Directional Isolate (U+2069) — closes the innermost isolate.
  static const _pdi = '\u{2069}';

  /// Wraps a quantity-and-unit string in a directional isolate.
  ///
  /// **Unit names are admin-entered data and keep the language they were typed
  /// in**, so "جرام" regularly appears in an English screen and vice versa.
  /// Left alone, the bidi algorithm reorders the surrounding run and a value
  /// like `988 جرام (1988 جرام)` renders visually scrambled.
  ///
  /// Call this on anything that pairs a number with an admin-entered unit,
  /// then render the result as a single `Text`.
  static String quantity(num value, String unit) =>
      '$_fsi${_signedNumber(value)} $unit$_pdi';

  /// Isolates an arbitrary string whose direction may differ from the page —
  /// an admin-entered item name, an owner's display name, a Latin wordmark.
  static String isolate(String value) => '$_fsi$value$_pdi';

  /// The minus sign, as U+2212 rather than an ASCII hyphen.
  static const _minus = '\u{2212}';

  /// A number with its sign kept on the correct side.
  ///
  /// A balance can legitimately be **negative** — serving past an empty jar is
  /// allowed and leaves an overdraw for an admin to reconcile. Two things go
  /// wrong if that minus is left as a plain ASCII hyphen:
  ///
  /// 1. Inside a run made RTL by an Arabic unit ("جرام"), a hyphen is a
  ///    neutral character, so the bidi algorithm places it **after** the
  ///    digits: `-6 جرام` renders as `6-`, which reads as six rather than
  ///    minus six. Observed on device.
  /// 2. U+2212 is the correct character for a minus sign in any case; an
  ///    ASCII hyphen is a hyphen.
  ///
  /// Isolating the signed number separately keeps the sign bound to its digits
  /// whatever the unit does to the surrounding direction.
  static String _signedNumber(num value) {
    final text = _number(value);
    if (!text.startsWith('-')) return text;
    return '$_fsi$_minus${text.substring(1)}$_pdi';
  }

  /// Trims a trailing `.0` so whole numbers do not read as decimals, while
  /// keeping real fractions intact.
  static String _number(num value) {
    if (value is int) return value.toString();
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  /// Converts a UTC timestamp from the API to a local time-of-day string.
  ///
  /// **Every timestamp in the API is UTC** (`createdAtUtc`, `readyAtUtc`,
  /// `expiresUtc`) and the server reports in Arab Standard Time. Never render a
  /// raw UTC value — parse as UTC and convert.
  static String timeOfDay(DateTime utc, String locale) =>
      DateFormat.jm(locale).format(utc.toLocal());

  /// A date and time, for anything older than today.
  static String dateTime(DateTime utc, String locale) =>
      DateFormat.yMMMd(locale).add_jm().format(utc.toLocal());

  /// Whole minutes from a `waitingSeconds` value, for the ageing indicator.
  /// Rounds down: an order is "2 min" old until it is genuinely three.
  static int minutesFromSeconds(int seconds) => seconds ~/ 60;
}
