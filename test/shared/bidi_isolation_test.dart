import 'package:buffet_app/shared/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

const fsi = '\u2068';
const pdi = '\u2069';

void main() {
  group('bidi isolation — the recurring class of bug', () {
    test('a mixed-script server string is wrapped', () {
      // Observed live: /catalogue composes usual.summary from the item's
      // ENGLISH name and an Arabic parenthetical, identically regardless of
      // Accept-Language. Unisolated, the bidi algorithm reorders the
      // parentheses around the Latin run.
      const summary = 'Coffee (بدون سكر)';
      final isolated = Formatters.isolate(summary);

      expect(isolated.startsWith(fsi), isTrue);
      expect(isolated.endsWith(pdi), isTrue);
      expect(isolated.contains(summary), isTrue);
    });

    test('two values joined by a separator are isolated SEPARATELY', () {
      // Observed live on the queue card: "المالية · meeting room 1". One
      // isolate around the pair would still let the algorithm reorder the
      // halves around the separator — each side needs its own.
      const department = 'المالية';
      const location = 'meeting room 1';
      final line =
          '${Formatters.isolate(department)} · '
          '${Formatters.isolate(location)}';

      expect(line.split(fsi).length - 1, 2, reason: 'two opening isolates');
      expect(line.split(pdi).length - 1, 2, reason: 'two closing isolates');
      // The separator sits OUTSIDE both isolates, where it belongs.
      expect(line.contains('$pdi · $fsi'), isTrue);
    });

    test('isolation is idempotent in effect for an empty string', () {
      // An empty value is common — locationText is optional — and must not
      // produce a stray control-character pair that renders as a blank glyph
      // anywhere.
      final isolated = Formatters.isolate('');
      expect(isolated, '$fsi$pdi');
      expect(isolated.replaceAll(fsi, '').replaceAll(pdi, ''), isEmpty);
    });

    test('a quantity pairs a number with an admin-entered unit', () {
      // The unit keeps whatever language it was typed in, so the pair is
      // reliably mixed-direction.
      final text = Formatters.quantity(160, 'جرام');
      expect(text.startsWith(fsi), isTrue);
      expect(text.endsWith(pdi), isTrue);
    });

    test('a negative quantity nests an inner isolate for the sign', () {
      // The sign gets its own isolate inside the outer one so it cannot
      // migrate past the digits in an RTL run.
      final text = Formatters.quantity(-6, 'جرام');
      expect(text.split(fsi).length - 1, 2);
      expect(text.split(pdi).length - 1, 2);
    });
  });

  group('an optional half is omitted with its separator', () {
    /// Mirrors the queue card's identity line.
    String identityLine(String department, String location) => [
      if (department.trim().isNotEmpty) Formatters.isolate(department),
      if (location.trim().isNotEmpty) Formatters.isolate(location),
    ].join(' · ');

    test('both present gives one separator', () {
      final line = identityLine('المالية', 'مكتبي');
      expect(' · '.allMatches(line).length, 1);
    });

    test('an empty location drops the separator entirely', () {
      // Observed live: order 43 has locationText "" because the field is
      // optional. The card rendered "المالية · " with nothing after it,
      // which reads as a failed load.
      final line = identityLine('المالية', '');
      expect(line.contains('·'), isFalse);
      expect(line.contains('المالية'), isTrue);
    });

    test('a whitespace-only location counts as absent', () {
      expect(identityLine('المالية', '   ').contains('·'), isFalse);
    });

    test('both empty gives an empty line, not a bare separator', () {
      expect(identityLine('', ''), isEmpty);
    });
  });
}
