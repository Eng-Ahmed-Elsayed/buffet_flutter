import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/features/order/composer_controller.dart';
import 'package:buffet_app/features/order/order_mode.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogueItemDto _item({int id = 1}) => CatalogueItemDto(
  itemId: id,
  nameAr: 'قهوة تركي',
  nameEn: 'Turkish coffee',
  category: 'coffee',
  unit: 'جرام',
  imageUrl: null,
  inStock: true,
  hasOwnStock: false,
  ownServingsLeft: 0,
  variants: const [],
  allowedExtraItemIds: null,
);

void main() {
  group('the composer mode is a property of how the screen was opened', () {
    test('a fresh composer is a self order', () {
      expect(ComposerController().state.mode, OrderMode.self);
    });

    test('setting the mode never mints a new idempotency key', () {
      final controller = ComposerController();
      final key = controller.state.idempotencyKey;

      controller
        ..setMode(OrderMode.guest)
        ..setMode(OrderMode.self)
        ..setMode(OrderMode.guest);

      // The key belongs to the composer SESSION, not to the mode. A key that
      // changed here would turn a retry into a second drink (§7.2).
      expect(controller.state.idempotencyKey, key);
    });

    test('leaving guest mode drops the guest name', () {
      final controller = ComposerController()
        ..setCanOrderForGuests(true)
        ..setMode(OrderMode.guest)
        ..setOnBehalfOfName('ضيف الوزارة');

      expect(controller.state.onBehalfOfName, 'ضيف الوزارة');

      controller.setMode(OrderMode.self);

      // A self order still carrying a guest name would wrongly lift the buffet
      // cap, and the server would reject it.
      expect(controller.state.onBehalfOfName, isNull);
      expect(controller.state.capIsLifted, isFalse);
    });
  });

  group('the mode survives the things that rebuild the state', () {
    test('adding a second drink keeps the mode and the guest', () {
      final controller = ComposerController()
        ..setCanOrderForGuests(true)
        ..setMode(OrderMode.guest)
        ..setOnBehalfOfName('ضيف الوزارة')
        ..selectDrink(_item())
        ..addLine();

      // addLine rebuilds ComposerState field by field. A mode left out of that
      // constructor would drop the user back into a self order — and null the
      // guest name with it — the moment they added a second drink.
      expect(controller.state.mode, OrderMode.guest);
      expect(controller.state.onBehalfOfName, 'ضيف الوزارة');
      expect(controller.state.lines, hasLength(1));
    });

    test('a confirmed order keeps the mode but forgets the guest', () {
      final controller = ComposerController()
        ..setCanOrderForGuests(true)
        ..setMode(OrderMode.guest)
        ..setOnBehalfOfName('ضيف الوزارة')
        ..selectDrink(_item())
        ..resetAfterConfirmedOrder();

      // Still the same screen, opened the same way — but the next guest is a
      // different guest.
      expect(controller.state.mode, OrderMode.guest);
      expect(controller.state.onBehalfOfName, isNull);
    });

    test('a confirmed order does mint a new key', () {
      final controller = ComposerController()..selectDrink(_item());
      final key = controller.state.idempotencyKey;

      controller.resetAfterConfirmedOrder();

      expect(controller.state.idempotencyKey, isNot(key));
    });
  });

  group('a guest order cannot be sent without a guest', () {
    test('a named guest order can be placed', () {
      final controller = ComposerController()
        ..setCanOrderForGuests(true)
        ..setMode(OrderMode.guest)
        ..selectDrink(_item())
        ..setOnBehalfOfName('ضيف الوزارة');

      expect(controller.state.guestNameMissing, isFalse);
      expect(controller.state.canPlaceOrder, isTrue);
    });

    test('an unnamed guest order cannot', () {
      final controller = ComposerController()
        ..setCanOrderForGuests(true)
        ..setMode(OrderMode.guest)
        ..selectDrink(_item());

      expect(controller.state.guestNameMissing, isTrue);
      expect(controller.state.canPlaceOrder, isFalse);
    });

    test('whitespace is not a name', () {
      final controller = ComposerController()
        ..setCanOrderForGuests(true)
        ..setMode(OrderMode.guest)
        ..selectDrink(_item())
        ..setOnBehalfOfName('   ');

      expect(controller.state.guestNameMissing, isTrue);
    });

    test('a self order is never gated on a guest name', () {
      final controller = ComposerController()..selectDrink(_item());

      expect(controller.state.guestNameMissing, isFalse);
      expect(controller.state.canPlaceOrder, isTrue);
    });
  });
}
