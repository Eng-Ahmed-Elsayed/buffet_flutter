import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/features/order/composer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogueItemDto drink({
  int id = 1,
  bool hasOwnStock = false,
  int ownServingsLeft = 0,
  List<int>? allowedExtraItemIds,
  List<VariantDto> variants = const [],
}) => CatalogueItemDto(
  itemId: id,
  nameAr: 'قهوة تركي',
  nameEn: 'Turkish coffee',
  category: 'Drink',
  unit: 'جرام',
  imageUrl: null,
  inStock: true,
  hasOwnStock: hasOwnStock,
  ownServingsLeft: ownServingsLeft,
  variants: variants,
  allowedExtraItemIds: allowedExtraItemIds,
);

/// A preparation, optionally with a recipe.
VariantDto variant({
  required int id,
  bool isDefault = false,
  List<int> pours = const [],
}) => VariantDto(
  variantId: id,
  nameAr: 'فرنساوي',
  nameEn: 'French',
  isDefault: isDefault,
  ingredientItemIds: pours,
);

/// A drink the user genuinely owns, with servings left.
///
/// Stacking several buffet drinks is refused by design, so any test that just
/// needs *n* lines builds them from the user's own jar.
CatalogueItemDto owned(int id) =>
    drink(id: id, hasOwnStock: true, ownServingsLeft: 10);

/// Adds [count] own-jar drinks to [controller].
void addOwned(ComposerController controller, int count) {
  for (var i = 0; i < count; i++) {
    controller
      ..selectDrink(owned(i))
      ..setDrinkFromOwn(true)
      ..addLine();
  }
}

void main() {
  group('§8 — double portions are annotated, never filtered', () {
    // Milk (9) is poured by French (71) and not by Dark (72).
    CatalogueItemDto coffee() => drink(
      variants: [
        variant(id: 71, isDefault: true, pours: const [9]),
        variant(id: 72),
      ],
    );

    test('an extra the preparation already pours is flagged', () {
      final controller = ComposerController()..selectDrink(coffee());

      // The default variant is French, which pours milk.
      expect(controller.state.extraDoublesUp(9), isTrue);
      expect(controller.state.extraDoublesUp(10), isFalse);
    });

    test('THE MARK MOVES when the preparation changes', () {
      final controller = ComposerController()..selectDrink(coffee());
      expect(controller.state.extraDoublesUp(9), isTrue);

      // Dark pours nothing, so the same chip stops being a double portion.
      controller.selectVariant(72);
      expect(controller.state.extraDoublesUp(9), isFalse);

      controller.selectVariant(71);
      expect(controller.state.extraDoublesUp(9), isTrue);
    });

    test('the hint tracks what is actually ticked', () {
      final controller = ComposerController()..selectDrink(coffee());
      // Flagged, but not chosen — nothing doubles yet.
      expect(controller.state.doubledExtraItemIds, isEmpty);

      controller.toggleExtra(9);
      expect(controller.state.doubledExtraItemIds, {9});

      // An extra the recipe does not pour never counts.
      controller.toggleExtra(10);
      expect(controller.state.doubledExtraItemIds, {9});
    });

    test('the extra is still ORDERABLE — annotate, never filter', () {
      final controller = ComposerController()
        ..selectDrink(coffee())
        ..toggleExtra(9);

      // An ingredient cannot be declined, which is what separates it from
      // allowedExtraItemIds. The doubling is a real thing to order.
      expect(controller.state.extraItemIds, {9});
      expect(controller.state.toRequest().lines.single.extraItemIds, [9]);
      expect(controller.state.canPlaceOrder, isTrue);
    });

    test('a preparation with no recipe flags nothing', () {
      // Empty, not null — there is no "unrestricted" case to distinguish.
      final controller = ComposerController()
        ..selectDrink(drink(variants: [variant(id: 72, isDefault: true)]));

      expect(controller.state.selectedVariant?.ingredientItemIds, isEmpty);
      expect(controller.state.extraDoublesUp(9), isFalse);
    });

    test('a drink made one way flags nothing', () {
      final controller = ComposerController()..selectDrink(drink());
      expect(controller.state.selectedVariant, isNull);
      expect(controller.state.extraDoublesUp(9), isFalse);
    });
  });

  group('multiple lines', () {
    test('the ordinary one-drink order sends exactly one line', () {
      final controller = ComposerController()..selectDrink(drink());

      // No "add" needed: a drink left in the draft is part of the order.
      expect(controller.state.toRequest().lines, hasLength(1));
    });

    test('adding a drink moves the draft into the line list', () {
      final controller = ComposerController()
        ..selectDrink(drink())
        ..addLine();

      expect(controller.state.lines, hasLength(1));
      // The controls are cleared for the next drink.
      expect(controller.state.drink, isNull);
      expect(controller.state.toRequest().lines, hasLength(1));
    });

    test('the draft is submitted alongside the added lines', () {
      final controller = ComposerController()
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2));

      // Two: one added, one still in the draft. Dropping the draft on submit
      // would silently discard a drink the user chose.
      expect(controller.state.toRequest().lines, hasLength(2));
    });

    test('order-level fields survive adding a line', () {
      final controller = ComposerController()
        ..setNotes('بدون سكر')
        ..setLocation(locationText: 'خلف المخزن')
        ..selectDrink(drink())
        ..addLine();

      final request = controller.state.toRequest();
      expect(request.notes, 'بدون سكر');
      expect(request.locationText, 'خلف المخزن');
    });

    test('adding with no drink selected is a no-op', () {
      final controller = ComposerController()..addLine();
      expect(controller.state.lines, isEmpty);
    });

    test('a line can be removed', () {
      final controller = ComposerController();
      addOwned(controller, 2);
      expect(controller.state.lines, hasLength(2));

      controller.removeLine(0);
      expect(controller.state.lines, hasLength(1));
      expect(controller.state.lines.single.drink.itemId, 1);
    });

    test('removing an out-of-range index is ignored, not a crash', () {
      final controller = ComposerController()
        ..selectDrink(drink())
        ..addLine()
        ..removeLine(7)
        ..removeLine(-1);

      expect(controller.state.lines, hasLength(1));
    });

    test('the idempotency key survives building a multi-drink order', () {
      final controller = ComposerController();
      final key = controller.state.idempotencyKey;

      controller
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2))
        ..addLine();

      // A dropped response must not become a second round of coffees.
      expect(controller.state.toRequest().idempotencyKey, key);
    });
  });

  group('the line cap', () {
    test('stops at the server-published maxLines', () {
      final controller = ComposerController()
        ..applyLimits(maxLines: 3, maxBuffetDrinks: 1);
      addOwned(controller, 3);

      expect(controller.state.lines, hasLength(3));
      expect(controller.state.canAddAnotherLine, isFalse);

      // Past the cap the server rejects the order outright, so there is
      // nothing to gain by letting the user compose one more.
      controller
        ..selectDrink(owned(9))
        ..addLine();
      expect(controller.state.lines, hasLength(3));
    });

    test('a full order refuses a NEW draft rather than dropping it later', () {
      final controller = ComposerController()
        ..applyLimits(maxLines: 2, maxBuffetDrinks: 1);
      addOwned(controller, 2);

      // Refused at selection. Accepting it and quietly dropping it at submit
      // would leave a tile looking selected but missing from the order — a
      // short order the user cannot explain.
      controller.selectDrink(drink(id: 9));
      expect(controller.state.drink, isNull);
      expect(controller.state.toRequest().lines, hasLength(2));
    });

    test('a draft already open can still be swapped at the cap', () {
      final controller = ComposerController()
        ..applyLimits(maxLines: 2, maxBuffetDrinks: 1)
        ..selectDrink(owned(1))
        ..setDrinkFromOwn(true)
        ..addLine()
        ..selectDrink(drink(id: 2));

      // The order is full (one added + one draft), but replacing the draft
      // does not change the count, so it must stay allowed.
      controller.selectDrink(drink(id: 3));
      expect(controller.state.drink?.itemId, 3);
      expect(controller.state.toRequest().lines, hasLength(2));
    });

    test('a lower cap never removes lines already composed', () {
      final controller = ComposerController();
      addOwned(controller, 5);

      // A refetched catalogue — a mid-order language switch is enough — must
      // not silently delete drinks the user can see on screen. The server owns
      // the rule and will say so.
      controller.applyLimits(maxLines: 3, maxBuffetDrinks: 1);

      expect(controller.state.lines, hasLength(5));
      expect(controller.state.toRequest().lines, hasLength(5));
    });

    test('defaults to the limit the server enforces anyway', () {
      // A catalogue from a server predating the field must not leave the
      // client unbounded.
      expect(ComposerController().state.maxLines, 25);
      expect(ComposerController().state.maxBuffetDrinks, 1);
    });
  });

  group('the buffet cap', () {
    test('one buffet drink is fine', () {
      final controller = ComposerController()..selectDrink(drink());
      expect(controller.state.buffetDrinkCount, 1);
      expect(controller.state.exceedsBuffetCap, isFalse);
    });

    test('a second buffet drink exceeds it', () {
      final controller = ComposerController()
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2));

      expect(controller.state.buffetDrinkCount, 2);
      expect(controller.state.exceedsBuffetCap, isTrue);
    });

    test('a drink from the user own jar does not count against it', () {
      final controller = ComposerController()
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2, hasOwnStock: true, ownServingsLeft: 5))
        ..setDrinkFromOwn(true);

      expect(controller.state.buffetDrinkCount, 1);
      expect(controller.state.exceedsBuffetCap, isFalse);
    });

    test('an EMPTY own jar still counts as buffet stock', () {
      // The server counts the source each line RESOLVES to, not the one
      // requested: claiming a jar you do not hold falls back to company stock.
      // A client counting the flag alone would let the user compose an order
      // the server rejects.
      final controller = ComposerController()
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2, hasOwnStock: true, ownServingsLeft: 0))
        ..setDrinkFromOwn(true);

      expect(controller.state.buffetDrinkCount, 2);
      expect(controller.state.exceedsBuffetCap, isTrue);
    });

    test('a second BUFFET drink cannot be added at all', () {
      final controller = ComposerController()
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2));

      expect(controller.state.draftWouldExceedBuffetCap, isTrue);

      // Refused, so the violation cannot grow. The user fixes it by switching
      // this drink to their own jar — the choice the rule exists to force.
      controller.addLine();
      expect(controller.state.lines, hasLength(1));
    });

    test('the same drink from the own jar CAN be added', () {
      final controller = ComposerController()
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2, hasOwnStock: true, ownServingsLeft: 3))
        ..setDrinkFromOwn(true);

      expect(controller.state.draftWouldExceedBuffetCap, isFalse);
      controller.addLine();
      expect(controller.state.lines, hasLength(2));
    });

    test(
      'an empty own jar is still refused — resolved source, not requested',
      () {
        final controller = ComposerController()
          ..selectDrink(drink())
          ..addLine()
          ..selectDrink(drink(id: 2, hasOwnStock: true, ownServingsLeft: 0))
          ..setDrinkFromOwn(true);

        // It falls back to buffet stock server-side, so it counts.
        expect(controller.state.draftWouldExceedBuffetCap, isTrue);
      },
    );

    test('exceeding it never blocks placing the order', () {
      final controller = ComposerController()
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2));

      expect(controller.state.exceedsBuffetCap, isTrue);
      // The banner explains it; the button stays live. The user fixes it by
      // switching a drink to their own jar or removing it.
      expect(controller.state.canPlaceOrder, isTrue);
    });

    test('naming a guest lifts the cap — WITH the privilege', () {
      final controller = ComposerController()
        ..setCanOrderForGuests(true)
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2))
        ..addLine()
        ..selectDrink(drink(id: 3));

      expect(controller.state.exceedsBuffetCap, isTrue);

      controller.setOnBehalfOfName('ضيف الإدارة');
      expect(controller.state.exceedsBuffetCap, isFalse);
      expect(controller.state.toRequest().onBehalfOfName, 'ضيف الإدارة');
    });

    test('a guest name WITHOUT the privilege does not lift the cap', () {
      // Both halves are required, matching the server. The name alone comes
      // from a field the client controls.
      final controller = ComposerController()
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2))
        ..setOnBehalfOfName('ضيف الإدارة');

      expect(controller.state.exceedsBuffetCap, isTrue);
    });

    test('the privilege alone does not lift the cap', () {
      // Otherwise a privileged employee could quietly take ten cups for
      // themselves on an ordinary order.
      final controller = ComposerController()
        ..setCanOrderForGuests(true)
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2));

      expect(controller.state.exceedsBuffetCap, isTrue);
    });

    test('losing the privilege drops any guest name with it', () {
      final controller = ComposerController()
        ..setCanOrderForGuests(true)
        ..setOnBehalfOfName('ضيف الإدارة')
        ..setCanOrderForGuests(false);

      // A name the server would now reject must not linger — and until then it
      // would wrongly lift the cap.
      expect(controller.state.toRequest().onBehalfOfName, isNull);
    });

    test('a blank guest name does not lift the cap', () {
      final controller = ComposerController()
        ..setCanOrderForGuests(true)
        ..selectDrink(drink())
        ..addLine()
        ..selectDrink(drink(id: 2))
        ..setOnBehalfOfName('   ');

      expect(controller.state.toRequest().onBehalfOfName, isNull);
      expect(controller.state.exceedsBuffetCap, isTrue);
    });
  });

  group('allowed extras', () {
    test('a null list means the drink permits every extra', () {
      final d = drink();
      expect(d.permitsExtra(9), isTrue);
      expect(d.permitsAnyExtra, isTrue);
    });

    test(
      'an empty list means no extras at all — never conflated with null',
      () {
        final d = drink(allowedExtraItemIds: const []);
        expect(d.permitsExtra(9), isFalse);
        expect(d.permitsAnyExtra, isFalse);
      },
    );

    test('only the listed extras are permitted', () {
      final d = drink(allowedExtraItemIds: const [9, 11]);
      expect(d.permitsExtra(9), isTrue);
      expect(d.permitsExtra(12), isFalse);
    });

    test('switching drinks drops an extra the new drink disallows', () {
      final controller = ComposerController()
        ..selectDrink(drink(allowedExtraItemIds: const [9, 11]))
        ..toggleExtra(9)
        ..toggleExtra(11);
      expect(controller.state.extraItemIds, {9, 11});

      // Carrying the selection over would be dropped server-side while the
      // order still succeeded — a drink that arrives wrong.
      controller.selectDrink(drink(id: 2, allowedExtraItemIds: const [11]));
      expect(controller.state.extraItemIds, {11});
    });

    test('the own-source flag goes with a dropped extra', () {
      final controller = ComposerController()
        ..selectDrink(drink(allowedExtraItemIds: const [9]))
        ..toggleExtra(9);
      controller.state = controller.state.copyWith(ownExtraItemIds: {9});

      controller.selectDrink(drink(id: 2, allowedExtraItemIds: const []));
      expect(controller.state.extraItemIds, isEmpty);
      expect(controller.state.ownExtraItemIds, isEmpty);
    });

    test(
      'a replayed favourite is filtered by what the drink still permits',
      () {
        // An admin may have narrowed the drink's extras since it was saved.
        final saved = FavouriteDto.fromJson({
          'favouriteId': 3,
          'name': 'قهوتي',
          'createdAtUtc': '2026-08-24T09:12:00Z',
          'lastUsedAtUtc': null,
          'lines': [
            {
              'drinkItemId': 4,
              'drinkNameAr': 'قهوة تركي',
              'sugarSpoons': 2,
              'variantId': null,
              'sugarItemId': null,
              'extraItemIds': [9, 12],
              'lineNote': null,
              'drinkFromOwn': false,
              'sugarFromOwn': false,
              'ownExtraItemIds': <int>[],
            },
          ],
        });

        final controller = ComposerController()
          ..applyFavourite(saved, [
            drink(id: 4, allowedExtraItemIds: const [9]),
          ]);

        expect(controller.state.extraItemIds, {9});
      },
    );

    test('a favourite fills the draft without discarding added lines', () {
      final saved = FavouriteDto.fromJson({
        'favouriteId': 3,
        'name': 'قهوتي',
        'createdAtUtc': '2026-08-24T09:12:00Z',
        'lastUsedAtUtc': null,
        'lines': [
          {
            'drinkItemId': 4,
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

      final controller = ComposerController()
        ..selectDrink(drink(id: 1))
        ..addLine()
        ..applyFavourite(saved, [drink(id: 4)]);

      // Replaying on top of a part-built order adds to it.
      expect(controller.state.lines, hasLength(1));
      expect(controller.state.drink?.itemId, 4);
    });

    test('the save toggle survives adding a second drink', () {
      // addLine() rebuilds ComposerState field by field, so anything left out
      // is silently reset the moment the user adds another drink.
      final controller = ComposerController()
        ..setSaveAsFavourite(true)
        ..setFavouriteName('قهوة الصبح')
        ..selectDrink(drink(id: 1))
        ..addLine();

      expect(controller.state.saveAsFavourite, isTrue);
      expect(controller.state.favouriteName, 'قهوة الصبح');
    });
  });
}
