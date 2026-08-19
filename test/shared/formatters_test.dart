import 'package:buffet_app/shared/formatters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  // Mirrors main(): DateFormat throws without it. Loading it here is what
  // proves the app's own call in main() is genuinely required.
  setUpAll(initializeDateFormatting);

  // U+2068 FIRST STRONG ISOLATE / U+2069 POP DIRECTIONAL ISOLATE.
  const fsi = '\u{2068}';
  const pdi = '\u{2069}';

  group('quantity strings are bidi-isolated', () {
    test('wraps an Arabic unit so the surrounding run cannot reorder', () {
      // Unit names are admin-entered and keep the language they were typed in,
      // so "جرام" regularly lands in an English screen and vice versa. Left
      // alone the bidi algorithm scrambles the visual order.
      final result = Formatters.quantity(988, 'جرام');
      expect(result.startsWith(fsi), isTrue);
      expect(result.endsWith(pdi), isTrue);
      expect(result, '${fsi}988 جرام$pdi');
    });

    test('wraps a Latin unit the same way', () {
      expect(Formatters.quantity(500, 'grams'), '${fsi}500 grams$pdi');
    });

    test('renders a whole double without a trailing .0', () {
      // 500.0 grams should read "500 grams", not "500.0 grams".
      expect(Formatters.quantity(500.0, 'جرام'), '${fsi}500 جرام$pdi');
    });

    test('keeps a real fraction intact', () {
      expect(Formatters.quantity(1.5, 'كجم'), '${fsi}1.5 كجم$pdi');
    });

    test('isolate() wraps an arbitrary owner name', () {
      expect(Formatters.isolate('Ahmed Hassan'), '${fsi}Ahmed Hassan$pdi');
    });
  });

  group('UTC timestamps are converted for display', () {
    test('toLocal is applied rather than rendering the raw UTC value', () {
      final utc = DateTime.utc(2026, 8, 18, 9, 42);
      final formatted = Formatters.timeOfDay(utc, 'en');

      // The exact string depends on the test machine's zone, so assert the
      // property that matters: it reflects local time, not the UTC clock,
      // unless the machine genuinely runs at UTC.
      final local = utc.toLocal();
      final expectedHour = local.hour % 12 == 0 ? 12 : local.hour % 12;
      expect(formatted, contains('$expectedHour'));
    });

    test('a UTC instant keeps its isUtc flag before conversion', () {
      final utc = DateTime.parse('2026-08-18T09:42:00Z');
      expect(utc.isUtc, isTrue);
    });
  });

  group('ageing indicator', () {
    test('rounds down, so an order is 2 min old until it is genuinely 3', () {
      expect(Formatters.minutesFromSeconds(0), 0);
      expect(Formatters.minutesFromSeconds(59), 0);
      expect(Formatters.minutesFromSeconds(60), 1);
      expect(Formatters.minutesFromSeconds(179), 2);
      expect(Formatters.minutesFromSeconds(180), 3);
    });
  });

  group('a negative quantity keeps its sign on the correct side', () {
    test('uses U+2212 MINUS SIGN, not an ASCII hyphen', () {
      // Observed on device: with an ASCII hyphen, "-6 جرام" rendered as
      // "6-" — the bidi algorithm treats the hyphen as neutral and moves it
      // to the far end of an RTL run. Read as six, not minus six.
      final text = Formatters.quantity(-6, 'جرام');
      expect(text.contains('\u2212'), isTrue);
      expect(text.contains('-'), isFalse);
    });

    test('the sign is isolated with its digits', () {
      // The isolate binds sign to number so it cannot migrate regardless of
      // what the unit does to the surrounding direction.
      final text = Formatters.quantity(-6, 'جرام');
      final signIndex = text.indexOf('\u2212');
      final digitIndex = text.indexOf('6');
      expect(signIndex, lessThan(digitIndex));
    });

    test('a positive quantity is untouched', () {
      final text = Formatters.quantity(160, 'جرام');
      expect(text.contains('\u2212'), isFalse);
      expect(text.contains('160'), isTrue);
    });

    test('a negative decimal keeps its fraction', () {
      expect(Formatters.quantity(-6.5, 'جرام'), contains('6.5'));
    });

    test('zero carries no sign', () {
      expect(Formatters.quantity(0, 'جرام').contains('\u2212'), isFalse);
    });
  });
}
