import 'package:buffet_app/shared/search_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Arabic letter forms fold together', () {
    test('teh marbuta and heh match', () {
      expect(matchesSearch('قهوه', ['قهوة تركي']), isTrue);
    });

    test('alef with hamza, madda or none match', () {
      expect(matchesSearch('اسبرسو', ['إسبرسو']), isTrue);
      expect(matchesSearch('أسبرسو', ['اسبرسو']), isTrue);
      expect(matchesSearch('اخر', ['آخر']), isTrue);
    });

    test('alef maqsura and yeh match', () {
      expect(matchesSearch('شاي', ['شاى']), isTrue);
    });

    test('short-vowel marks and tatweel are ignored', () {
      expect(matchesSearch('قهوة', ['قَهْوَة']), isTrue);
      expect(matchesSearch('شاي', ['شـــاي']), isTrue);
    });
  });

  group('Latin and spacing', () {
    test('case does not matter', () {
      expect(matchesSearch('NES', ['Nescafe gold']), isTrue);
    });

    test('extra spaces do not matter', () {
      expect(matchesSearch('  نسكافيه   جولد ', ['نسكافيه جولد']), isTrue);
    });
  });

  group('matching', () {
    test('an empty query matches everything', () {
      expect(matchesSearch('', ['anything']), isTrue);
      expect(matchesSearch('   ', ['anything']), isTrue);
    });

    test('any one field is enough — Arabic or English name', () {
      expect(matchesSearch('tea', ['شاي بالنعناع', 'Mint tea']), isTrue);
    });

    test('a genuine miss is a miss', () {
      expect(matchesSearch('عصير', ['قهوة تركي', 'Turkish coffee']), isFalse);
    });
  });
}
