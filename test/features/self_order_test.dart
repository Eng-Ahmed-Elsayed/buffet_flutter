import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/features/order/self_order_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaceOrderResponse', () {
    test('reads autoServed and the shortage list off the wire', () {
      final response = PlaceOrderResponse.fromJson(const {
        'orderId': 412,
        'duplicate': false,
        'autoServed': true,
        'shortageNames': 'شاي، حليب',
      });

      expect(response.autoServed, isTrue);
      expect(response.shortageNames, 'شاي، حليب');
    });

    test('a server that predates the fields reads as not auto-served', () {
      // The field was added rather than the status changed precisely so that
      // an older pairing on either side keeps working.
      final response = PlaceOrderResponse.fromJson(const {
        'orderId': 412,
        'duplicate': false,
      });

      expect(response.autoServed, isFalse);
      expect(response.shortageNames, isNull);
    });

    test('a duplicate is never reported as auto-served', () {
      // Serving a replayed order again is exactly what the idempotency key
      // exists to prevent, so the server never sets the flag on one.
      final response = PlaceOrderResponse.fromJson(const {
        'orderId': 412,
        'duplicate': true,
        'autoServed': false,
      });

      expect(response.duplicate, isTrue);
      expect(response.autoServed, isFalse);
    });
  });

  group('SelfOrderOutcome', () {
    test('a clean serve carries no shortage', () {
      const outcome = SelfOrderOutcome(orderId: 412);
      expect(outcome.hasShortages, isFalse);
    });

    test('an empty shortage string is not a shortage', () {
      const outcome = SelfOrderOutcome(orderId: 412, shortageNames: '');
      expect(outcome.hasShortages, isFalse);
    });

    test('named shortages are surfaced', () {
      const outcome = SelfOrderOutcome(orderId: 412, shortageNames: 'شاي');
      expect(outcome.hasShortages, isTrue);
    });
  });

  group('the catalogue still parses', () {
    test('an order response alongside a catalogue payload', () {
      // Guards the model change against a build_runner regeneration that
      // silently dropped a field.
      const catalogue = CatalogueResponse(
        drinks: [],
        sugars: [],
        extras: [],
        locations: [],
        usual: null,
        maxLines: 3,
        maxBuffetDrinks: 1,
      );

      expect(catalogue.maxLines, 3);
    });
  });
}
