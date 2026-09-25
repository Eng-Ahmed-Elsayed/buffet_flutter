import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/features/order/composer_controller.dart';
import 'package:buffet_app/features/order/order_mode.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogueItemDto _drink({
  int id = 1,
  bool hasOwnStock = false,
  int ownServingsLeft = 0,
}) => CatalogueItemDto(
  itemId: id,
  nameAr: 'شاي',
  nameEn: 'Tea',
  category: 'Drink',
  unit: 'جرام',
  imageUrl: null,
  inStock: true,
  hasOwnStock: hasOwnStock,
  ownServingsLeft: ownServingsLeft,
  variants: const [],
  allowedExtraItemIds: null,
);

ComposerController _composer({int maxLines = 5, int maxBuffetDrinks = 1}) =>
    ComposerController()
      ..applyLimits(maxLines: maxLines, maxBuffetDrinks: maxBuffetDrinks);

/// The design's quantity stepper. There is no per-line quantity on the wire, so
/// a quantity is identical lines — and every cap has to count it.
void main() {
  group('a quantity is identical lines', () {
    test('the draft is sent as many times as its quantity', () {
      final c = _composer()
        ..selectDrink(
          _drink(hasOwnStock: true, ownServingsLeft: 9),
          fromOwn: true,
        );
      c.setDraftQuantity(3);

      expect(c.state.allLines, hasLength(3));
      expect(c.state.toRequest().lines, hasLength(3));
    });

    test('adding the draft commits every cup, then resets to one', () {
      final c = _composer()
        ..selectDrink(
          _drink(hasOwnStock: true, ownServingsLeft: 9),
          fromOwn: true,
        );
      c
        ..setDraftQuantity(3)
        ..addLine();

      expect(c.state.lines, hasLength(3));
      expect(c.state.drink, isNull);
      expect(c.state.draftQuantity, 1);
    });

    test('a new drink starts at one cup', () {
      final c = _composer()
        ..selectDrink(
          _drink(hasOwnStock: true, ownServingsLeft: 9),
          fromOwn: true,
        );
      c
        ..setDraftQuantity(3)
        ..selectDrink(
          _drink(id: 2, hasOwnStock: true, ownServingsLeft: 9),
          fromOwn: true,
        );

      expect(c.state.draftQuantity, 1);
    });
  });

  group('the maximum comes from structural limits only', () {
    test('a buffet drink under a cap of one offers no stepper', () {
      final c = _composer()..selectDrink(_drink());

      expect(c.state.maxDraftQuantity, 1);
      expect(c.state.offersQuantity, isFalse);
      c.setDraftQuantity(4);
      expect(c.state.draftQuantity, 1);
    });

    test(
      'a drink from the user\'s own jar is limited only by the line cap',
      () {
        final c = _composer(maxLines: 4)
          ..selectDrink(
            _drink(hasOwnStock: true, ownServingsLeft: 9),
            fromOwn: true,
          );

        expect(c.state.maxDraftQuantity, 4);
        expect(c.state.offersQuantity, isTrue);
      },
    );

    test('an own jar that reads empty keeps the stepper — no stock reading', () {
      // It resolves to buffet stock, but hiding a control on a stock reading
      // is the one thing the domain rules forbid. The cap is caught on adding.
      final c = _composer(maxLines: 4)
        ..selectDrink(_drink(hasOwnStock: true), fromOwn: true);

      expect(c.state.offersQuantity, isTrue);
      c.setDraftQuantity(2);
      expect(c.state.draftWouldExceedBuffetCap, isTrue);
    });

    test('a named guest order lifts the buffet allowance to the line cap', () {
      final c = _composer(maxLines: 6)
        ..setCanOrderForGuests(true)
        ..setMode(OrderMode.guest)
        ..setOnBehalfOfName('وفد الوزارة')
        ..selectDrink(_drink());

      expect(c.state.maxDraftQuantity, 6);
    });

    test('lines already added use up the room', () {
      final c = _composer(maxLines: 3)
        ..selectDrink(
          _drink(hasOwnStock: true, ownServingsLeft: 9),
          fromOwn: true,
        )
        ..addLine()
        ..selectDrink(
          _drink(hasOwnStock: true, ownServingsLeft: 9),
          fromOwn: true,
        );

      expect(c.state.maxDraftQuantity, 2);
    });
  });

  group('the caps count the quantity', () {
    test(
      'a quantity past the buffet cap is refused when added, with a reason',
      () {
        final c = _composer(maxLines: 4)
          ..selectDrink(_drink(hasOwnStock: true), fromOwn: true)
          ..setDraftQuantity(2);

        expect(c.state.draftWouldExceedBuffetCap, isTrue);
        c.addLine();
        expect(
          c.state.lines,
          isEmpty,
          reason: 'addLine must not break the cap',
        );
      },
    );

    test('a quantity past the line cap cannot be committed', () {
      final c = _composer(maxLines: 2)
        ..selectDrink(
          _drink(hasOwnStock: true, ownServingsLeft: 9),
          fromOwn: true,
        )
        ..addLine()
        ..selectDrink(
          _drink(hasOwnStock: true, ownServingsLeft: 9),
          fromOwn: true,
        )
        ..setDraftQuantity(5);

      // Clamped to the one line of room left, so adding commits exactly one.
      expect(c.state.draftQuantity, 1);
      c.addLine();
      expect(c.state.lines, hasLength(2));
    });
  });

  group('clearing the draft', () {
    test('drops the drink and its quantity, keeps what was added', () {
      final c = _composer()
        ..selectDrink(
          _drink(hasOwnStock: true, ownServingsLeft: 9),
          fromOwn: true,
        )
        ..addLine()
        ..selectDrink(
          _drink(id: 2, hasOwnStock: true, ownServingsLeft: 9),
          fromOwn: true,
        )
        ..setDraftQuantity(2)
        ..setNotes('بدون ثلج')
        ..clearDraft();

      expect(c.state.drink, isNull);
      expect(c.state.draftQuantity, 1);
      expect(c.state.lines, hasLength(1));
      expect(c.state.notes, 'بدون ثلج');
    });

    test('keeps the idempotency key, so a retry is still the same order', () {
      final c = _composer()..selectDrink(_drink());
      final key = c.state.idempotencyKey;
      c.clearDraft();
      expect(c.state.idempotencyKey, key);
    });
  });
}
