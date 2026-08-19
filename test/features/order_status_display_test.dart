import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The catalogue as the live server returns it: قهوة carries three variants,
/// most other drinks carry none and no English name.
const _catalogue = CatalogueResponse(
  drinks: [
    CatalogueItemDto(
      itemId: 8,
      nameAr: 'قهوة',
      nameEn: 'Coffee',
      category: 'Drink',
      unit: 'جرام',
      imageUrl: null,
      inStock: true,
      hasOwnStock: false,
      ownServingsLeft: 0,
      variants: [
        VariantDto(
          variantId: 1,
          nameAr: 'غامق',
          nameEn: 'Dark',
          isDefault: true,
        ),
        VariantDto(
          variantId: 2,
          nameAr: 'فاتح',
          nameEn: 'Light',
          isDefault: false,
        ),
      ],
    ),
  ],
  sugars: [],
  extras: [],
  locations: [],
  usual: null,
);

/// Mirrors the resolution the status card performs.
String? variantName(
  CatalogueResponse? catalogue,
  OrderLineDto line,
  String languageCode,
) {
  final variantId = line.variantId;
  if (variantId == null || catalogue == null) return null;
  for (final item in catalogue.drinks) {
    if (item.itemId != line.drinkItemId) continue;
    for (final variant in item.variants) {
      if (variant.variantId == variantId) {
        return variant.localisedName(languageCode);
      }
    }
  }
  return null;
}

OrderLineDto line({int? variantId, int drinkItemId = 8}) =>
    OrderLineDto.fromJson({
      'drinkItemId': drinkItemId,
      'drinkNameAr': 'قهوة',
      'sugarSpoons': 0,
      'variantId': variantId,
      'sugarItemId': null,
      'extraItemIds': <dynamic>[],
      'lineNote': '',
      'drinkFromOwn': false,
      'sugarFromOwn': false,
      'ownExtraItemIds': <dynamic>[],
    });

void main() {
  group('variant name on the status screen', () {
    test('names the variant the user actually chose', () {
      // Verified live: ordering قهوة with فاتح sends variantId 2, and the
      // order response carries only that id — so the name has to come from
      // the catalogue or the user never sees what they ordered confirmed.
      expect(variantName(_catalogue, line(variantId: 2), 'ar'), 'فاتح');
      expect(variantName(_catalogue, line(variantId: 2), 'en'), 'Light');
    });

    test('a drink with no variant shows no chip', () {
      expect(variantName(_catalogue, line(), 'ar'), isNull);
    });

    test('resolves to null while the catalogue is still loading', () {
      // A bare id must never be rendered — the chip is omitted instead.
      expect(variantName(null, line(variantId: 2), 'ar'), isNull);
    });

    test('an unknown variant id does not throw', () {
      // The item may have changed since the order was placed.
      expect(variantName(_catalogue, line(variantId: 99), 'ar'), isNull);
    });

    test('a variant id on the wrong drink does not cross-match', () {
      expect(
        variantName(_catalogue, line(variantId: 2, drinkItemId: 6), 'ar'),
        isNull,
      );
    });
  });

  group('empty locationText', () {
    test('an order can legitimately carry no location', () {
      // Observed live: order 43 came back with locationText "". The managed
      // list is a suggestion and an order stands without one, so this is a
      // normal state, not a failure — the screen must say so rather than
      // rendering a bare pin icon with nothing beside it.
      final order = OrderSummaryDto.fromJson({
        'orderId': 43,
        'status': 'Pending',
        'createdAtUtc': '2026-08-19T09:53:58.4122331Z',
        'readyAtUtc': null,
        'handledAtUtc': null,
        'locationText': '',
        'onBehalfOfName': null,
        'notes': '',
        'lines': <dynamic>[],
      });

      expect(order.locationText, isEmpty);
      expect(order.locationText.trim().isEmpty, isTrue);
    });
  });
}
