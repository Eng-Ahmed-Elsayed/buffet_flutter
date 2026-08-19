import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogueItemDto item({required String nameAr, required String nameEn}) =>
    CatalogueItemDto(
      itemId: 1,
      nameAr: nameAr,
      nameEn: nameEn,
      category: 'Drink',
      unit: 'جرام',
      imageUrl: null,
      inStock: true,
      hasOwnStock: false,
      ownServingsLeft: 0,
      variants: const [],
    );

void main() {
  group('localisedName — the app is bilingual, not Arabic-only', () {
    test('English locale gets the English name when there is one', () {
      // Observed live: قهوة carries nameEn "Coffee".
      final coffee = item(nameAr: 'قهوة', nameEn: 'Coffee');
      expect(coffee.localisedName('en'), 'Coffee');
    });

    test('Arabic locale always gets the Arabic name', () {
      final coffee = item(nameAr: 'قهوة', nameEn: 'Coffee');
      expect(coffee.localisedName('ar'), 'قهوة');
    });

    test('English falls back to Arabic when nameEn is empty', () {
      // This is the common case, not an edge case: كركديه, نعناع, ينسون and
      // قهوة تركية بالهيل all return "" for nameEn on the live server. An
      // English user must see the Arabic name, never an empty tile.
      final karkade = item(nameAr: 'كركديه', nameEn: '');
      expect(karkade.localisedName('en'), 'كركديه');
    });

    test('whitespace-only nameEn counts as absent', () {
      final item_ = item(nameAr: 'نعناع', nameEn: '   ');
      expect(item_.localisedName('en'), 'نعناع');
    });

    test('an unknown locale falls back to Arabic, the primary language', () {
      final coffee = item(nameAr: 'قهوة', nameEn: 'Coffee');
      // Only ar and en are supported; anything else takes the English branch
      // only when a real English name exists.
      expect(coffee.localisedName('fr'), 'Coffee');
      expect(item(nameAr: 'ينسون', nameEn: '').localisedName('fr'), 'ينسون');
    });
  });

  group('VariantDto.localisedName', () {
    test('variants localise on the same rule', () {
      // Observed live: قهوة has variants غامق/Dark, فاتح/Light, فرنساوي/French.
      const dark = VariantDto(
        variantId: 1,
        nameAr: 'غامق',
        nameEn: 'Dark',
        isDefault: true,
      );
      expect(dark.localisedName('en'), 'Dark');
      expect(dark.localisedName('ar'), 'غامق');
    });

    test('a variant with no English name falls back to Arabic', () {
      const plain = VariantDto(
        variantId: 2,
        nameAr: 'سادة',
        nameEn: '',
        isDefault: false,
      );
      expect(plain.localisedName('en'), 'سادة');
    });
  });
}
