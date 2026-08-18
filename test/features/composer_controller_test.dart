import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/features/order/composer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogueItemDto item({
  int id = 1,
  bool hasOwnStock = false,
  int ownServingsLeft = 0,
  bool inStock = true,
}) => CatalogueItemDto(
  itemId: id,
  nameAr: 'قهوة تركي',
  nameEn: 'Turkish coffee',
  category: 'coffee',
  unit: 'جرام',
  imageUrl: null,
  inStock: inStock,
  hasOwnStock: hasOwnStock,
  ownServingsLeft: ownServingsLeft,
  variants: const [],
);

void main() {
  group('sugar stepper — zero is valid and explicit', () {
    test('starts at zero', () {
      final controller = ComposerController();
      expect(controller.state.sugarSpoons, 0);
    });

    test('zero can be set deliberately and is preserved on the wire', () {
      final controller = ComposerController()
        ..selectDrink(item())
        ..setSugarSpoons(3)
        ..setSugarSpoons(0);

      expect(controller.state.sugarSpoons, 0);
      // The server distinguishes "zero spoons" from "unspecified", so zero
      // must actually be sent rather than omitted.
      expect(controller.state.toRequest().lines.single.sugarSpoons, 0);
    });

    test('clamps at the floor rather than going negative', () {
      final controller = ComposerController()..setSugarSpoons(-5);
      expect(controller.state.sugarSpoons, 0);
    });
  });

  group('the "from my materials" toggle', () {
    test('is hidden until a drink the user owns is selected', () {
      final controller = ComposerController();
      // Nothing selected yet.
      expect(controller.state.canUseOwnMaterials, isFalse);

      controller.selectDrink(item(hasOwnStock: false));
      // Selected, but not owned — showing the toggle would be noise for the
      // majority who own nothing.
      expect(controller.state.canUseOwnMaterials, isFalse);

      controller.selectDrink(
        item(id: 2, hasOwnStock: true, ownServingsLeft: 14),
      );
      expect(controller.state.canUseOwnMaterials, isTrue);
    });

    test('resets when a different drink is selected', () {
      final controller = ComposerController()
        ..selectDrink(item(hasOwnStock: true, ownServingsLeft: 5))
        ..setDrinkFromOwn(true);
      expect(controller.state.drinkFromOwn, isTrue);

      // The new drink may not be owned at all, so the previous answer cannot
      // carry over.
      controller.selectDrink(item(id: 2, hasOwnStock: false));
      expect(controller.state.drinkFromOwn, isFalse);
    });
  });

  group('shortages warn but never block', () {
    test('an empty personal jar still allows the order', () {
      final controller = ComposerController()
        ..selectDrink(item(hasOwnStock: true, ownServingsLeft: 0))
        ..setDrinkFromOwn(true);

      expect(controller.state.ownStockIsShort, isTrue);
      // The warning is on; the order button is NOT off. Physical and recorded
      // stock drift, and halting service is worse than a negative number.
      expect(controller.state.canPlaceOrder, isTrue);
    });

    test('a company item out of stock still allows the order', () {
      final controller = ComposerController()
        ..selectDrink(item(inStock: false));
      expect(controller.state.canPlaceOrder, isTrue);
    });

    test('no warning when drawing on company stock', () {
      final controller = ComposerController()
        ..selectDrink(item(hasOwnStock: true, ownServingsLeft: 0));
      // The toggle is off, so the empty jar is irrelevant.
      expect(controller.state.ownStockIsShort, isFalse);
    });
  });

  group('idempotency key', () {
    test('is generated when the composer opens', () {
      final controller = ComposerController();
      expect(controller.state.idempotencyKey, isNotEmpty);
      // UUID v4 shape.
      expect(
        controller.state.idempotencyKey,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('survives edits, so a retry sends the SAME order', () {
      final controller = ComposerController();
      final key = controller.state.idempotencyKey;

      controller
        ..selectDrink(item())
        ..setSugarSpoons(2)
        ..toggleExtra(9)
        ..setNotes('بدون سكر زيادة');

      // A dropped response on office wifi must not become a second coffee.
      expect(controller.state.idempotencyKey, key);
      expect(controller.state.toRequest().idempotencyKey, key);
    });

    test('is replaced only once an order is CONFIRMED', () {
      final controller = ComposerController()..selectDrink(item());
      final key = controller.state.idempotencyKey;

      controller.resetAfterConfirmedOrder();

      expect(controller.state.idempotencyKey, isNot(key));
      // A fresh composer, ready for the next order.
      expect(controller.state.drink, isNull);
      expect(controller.state.sugarSpoons, 0);
    });

    test('two composers never share a key', () {
      expect(
        ComposerController().state.idempotencyKey,
        isNot(ComposerController().state.idempotencyKey),
      );
    });
  });

  group('extras', () {
    test('toggle on and off', () {
      final controller = ComposerController()..toggleExtra(9);
      expect(controller.state.extraItemIds, {9});

      controller.toggleExtra(9);
      expect(controller.state.extraItemIds, isEmpty);
    });

    test('deselecting an extra drops its own-source flag too', () {
      final controller = ComposerController()..toggleExtra(9);
      // Mark it as coming from the user's jar, then remove the extra entirely.
      controller.state = controller.state.copyWith(ownExtraItemIds: {9});
      controller.toggleExtra(9);

      expect(controller.state.extraItemIds, isEmpty);
      // An extra that is not ordered cannot still be sourced from a jar.
      expect(controller.state.ownExtraItemIds, isEmpty);
    });
  });

  group('the usual order', () {
    test('fills the composer including which jar each part came from', () {
      final drink = item(id: 4, hasOwnStock: true, ownServingsLeft: 14);
      final usual = UsualOrderDto.fromJson({
        'summary': 'قهوة تركي وسط · ٢ ملعقة سكر',
        'lines': [
          {
            'drinkItemId': 4,
            'drinkNameAr': 'قهوة تركي',
            'sugarSpoons': 2,
            'variantId': 7,
            'sugarItemId': 3,
            'extraItemIds': [9],
            'lineNote': null,
            'drinkFromOwn': true,
            'sugarFromOwn': false,
            'ownExtraItemIds': [9],
          },
        ],
      });

      final controller = ComposerController()..applyUsual(usual, [drink]);

      expect(controller.state.drink?.itemId, 4);
      expect(controller.state.sugarSpoons, 2);
      expect(controller.state.variantId, 7);
      expect(controller.state.extraItemIds, {9});
      expect(controller.state.drinkFromOwn, isTrue);
      expect(controller.state.sugarFromOwn, isFalse);
      expect(controller.state.ownExtraItemIds, {9});
    });

    test('is a no-op when the drink is no longer in the catalogue', () {
      final usual = UsualOrderDto.fromJson({
        'summary': 'قهوة تركي',
        'lines': [
          {
            'drinkItemId': 99,
            'drinkNameAr': 'قهوة تركي',
            'sugarSpoons': 1,
            'variantId': null,
            'sugarItemId': null,
            'extraItemIds': <int>[],
            'lineNote': null,
            'drinkFromOwn': false,
            'sugarFromOwn': false,
            'ownExtraItemIds': <int>[],
          },
        ],
      });

      final controller = ComposerController()..applyUsual(usual, [item(id: 1)]);
      expect(controller.state.drink, isNull);
    });
  });

  group('location', () {
    test('accepts free text so an unlisted place cannot block an order', () {
      final controller = ComposerController()
        ..selectDrink(item())
        ..setLocation(locationText: 'خلف المخزن');

      final request = controller.state.toRequest();
      expect(request.locationText, 'خلف المخزن');
      expect(request.locationId, isNull);
    });

    test('sends locationId when a managed suggestion is picked', () {
      final controller = ComposerController()
        ..selectDrink(item())
        ..setLocation(locationId: 12);

      final request = controller.state.toRequest();
      expect(request.locationId, 12);
      expect(request.locationText, isNull);
    });
  });
}
