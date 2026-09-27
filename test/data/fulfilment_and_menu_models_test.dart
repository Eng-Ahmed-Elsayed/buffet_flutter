import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/models/staff_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fields the backend shipped 2026-09-27 (guide §7.3, §7.8, §7.9). The
/// deployment predates them, so every one must parse when absent too.
void main() {
  Map<String, dynamic> drink([Map<String, dynamic> extra = const {}]) => {
    'itemId': 2,
    'nameAr': 'نسكافيه',
    'nameEn': '',
    'category': 'Drink',
    'unit': 'جرام',
    'imageUrl': null,
    'inStock': true,
    'hasOwnStock': false,
    'ownServingsLeft': 0,
    'variants': <Object>[],
    'allowedExtraItemIds': null,
    ...extra,
  };

  Map<String, dynamic> catalogue([Map<String, dynamic> extra = const {}]) => {
    'drinks': [drink()],
    'sugars': <Object>[],
    'extras': <Object>[],
    'locations': <Object>[],
    'maxLines': 25,
    'maxBuffetDrinks': 1,
    ...extra,
  };

  Map<String, dynamic> order([Map<String, dynamic> extra = const {}]) => {
    'orderId': 70,
    'status': 'Ready',
    'createdAtUtc': '2026-09-27T08:52:00Z',
    'readyAtUtc': '2026-09-27T08:53:24Z',
    'handledAtUtc': null,
    'locationText': 'Desk 3',
    'onBehalfOfName': null,
    'notes': '',
    'lines': <Object>[],
    ...extra,
  };

  group("today's server, without the new fields", () {
    test('a catalogue has no groups and a drink no description', () {
      final parsed = CatalogueResponse.fromJson(catalogue());
      expect(parsed.drinkGroups, isEmpty);
      expect(parsed.drinks.single.drinkGroupId, isNull);
      expect(parsed.drinks.single.localisedDescription('ar'), isNull);
    });

    test('an order has no start time and neutral fulfilment', () {
      final parsed = OrderSummaryDto.fromJson(order());
      expect(parsed.startedAtUtc, isNull);
      expect(parsed.fulfilmentMode, isNull);
    });
  });

  group('the shipped fields', () {
    test('groups, a drink group and descriptions with the Arabic floor', () {
      final parsed = CatalogueResponse.fromJson(
        catalogue({
          'drinks': [
            drink({
              'descriptionAr': 'قهوة سريعة التحضير',
              'descriptionEn': '  ',
              'drinkGroupId': 3,
            }),
          ],
          'drinkGroups': [
            {'drinkGroupId': 3, 'nameAr': 'قهوة', 'nameEn': '', 'sortOrder': 1},
          ],
        }),
      );
      final item = parsed.drinks.single;
      expect(item.drinkGroupId, 3);
      expect(item.localisedDescription('ar'), 'قهوة سريعة التحضير');
      // A blank English description falls back to the Arabic one.
      expect(item.localisedDescription('en'), 'قهوة سريعة التحضير');
      expect(parsed.drinkGroups.single.localisedName('en'), 'قهوة');
    });

    test('an order reads its start time and mode by name', () {
      final parsed = OrderSummaryDto.fromJson(
        order({'startedAtUtc': '2026-09-27T08:52:40Z', 'fulfilment': 'Pickup'}),
      );
      expect(parsed.startedAtUtc, DateTime.utc(2026, 9, 27, 8, 52, 40));
      expect(parsed.fulfilmentMode, Fulfilment.pickup);
      expect(Fulfilment.fromWire('Delivery'), Fulfilment.delivery);
      // Unknown or numeric: neutral, never a guess.
      expect(Fulfilment.fromWire('1'), isNull);
    });

    test('a staff card reads the mode, and the request sends it by name', () {
      final staff = StaffOrderDto.fromJson({
        'orderId': 70,
        'status': 'Pending',
        'createdAtUtc': '2026-09-27T08:52:00Z',
        'readyAtUtc': null,
        'requesterDisplayName': 'سارة',
        'department': 'المالية',
        'locationText': '',
        'onBehalfOfName': null,
        'notes': '',
        'waitingSeconds': 10,
        'lines': <Object>[],
        'fulfilment': 'Delivery',
      });
      expect(staff.fulfilmentMode, Fulfilment.delivery);

      final json = PlaceOrderApiRequest(
        lines: const [],
        fulfilment: Fulfilment.pickup.wire,
      ).toJson();
      expect(json['fulfilment'], 'Pickup');
      expect(
        const PlaceOrderApiRequest(lines: []).toJson(),
        isNot(contains('fulfilment')),
      );
    });
  });
}
