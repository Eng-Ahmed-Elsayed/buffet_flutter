import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/material_models.dart';
import 'package:buffet_app/features/materials/declare_sheet.dart';
import 'package:buffet_app/features/materials/my_materials_screen.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogueItemDto _item(int id, String nameAr, String category) =>
    CatalogueItemDto(
      itemId: id,
      nameAr: nameAr,
      nameEn: '',
      category: category,
      unit: 'جرام',
      imageUrl: null,
      inStock: true,
      hasOwnStock: false,
      ownServingsLeft: 0,
      variants: const [],
    );

MyMaterialDto _balance(int id, num quantity) => MyMaterialDto(
  itemId: id,
  nameAr: 'x',
  unit: 'جرام',
  quantity: quantity,
  servingsLeft: 1,
  level: 'Ok',
);

/// A catalogue shaped like the live one: seven drinks, one sugar, one extra.
final _catalogue = CatalogueResponse(
  drinks: [
    _item(8, 'قهوة', 'Drink'),
    _item(7, 'قهوة تركية بالهيل', 'Drink'),
    _item(2, 'نسكافيه جولد', 'Drink'),
  ],
  sugars: [_item(1, 'سكر', 'Sugar')],
  extras: [_item(9, 'حليب', 'Extra')],
  locations: const [],
  usual: null,
);

ProviderContainer _container({
  CatalogueResponse? catalogue,
  List<MyMaterialDto> balances = const [],
}) => ProviderContainer(
  overrides: [
    catalogueProvider.overrideWith((ref) async => catalogue ?? _catalogue),
    myMaterialsProvider.overrideWith((ref) async => balances),
  ],
);

void main() {
  group('declarableItemsProvider — the full catalogue, not just what is owned', () {
    test(
      'offers every catalogue item, including ones with no balance',
      () async {
        // The bug this covers: the list used to come from /materials/mine, so a
        // user could only ever top up a material they already held. Bringing in
        // a NEW material was impossible to express.
        final container = _container(balances: [_balance(7, 138)]);
        addTearDown(container.dispose);

        final items = await container.read(declarableItemsProvider.future);

        expect(items.map((i) => i.itemId), [8, 7, 2, 1, 9]);
      },
    );

    test('a user with no balances at all can still declare', () async {
      final container = _container();
      addTearDown(container.dispose);

      final items = await container.read(declarableItemsProvider.future);

      expect(items, hasLength(5));
      expect(items.every((i) => i.balance == null), isTrue);
    });

    test('sugars and extras are declarable, not only drinks', () async {
      // Verified live: POST /materials/declare returned 202 for item 1 (سكر)
      // and item 9 (حليب), neither of which the caller owned.
      final container = _container();
      addTearDown(container.dispose);

      final items = await container.read(declarableItemsProvider.future);

      expect(items.map((i) => i.itemId), containsAll([1, 9]));
    });

    test('an existing balance is attached to its item', () async {
      final container = _container(
        balances: [_balance(7, 138), _balance(2, -6)],
      );
      addTearDown(container.dispose);

      final items = await container.read(declarableItemsProvider.future);
      final byId = {for (final i in items) i.itemId: i};

      expect(byId[7]!.balance!.quantity, 138);
      // A negative balance is a real state, not a defect — it must still be
      // declarable, since declaring is how the user brings it back up.
      expect(byId[2]!.balance!.quantity, -6);
      expect(byId[8]!.balance, isNull);
    });

    test('an empty catalogue yields nothing rather than throwing', () async {
      final container = _container(
        catalogue: const CatalogueResponse(
          drinks: [],
          sugars: [],
          extras: [],
          locations: [],
          usual: null,
        ),
      );
      addTearDown(container.dispose);

      expect(await container.read(declarableItemsProvider.future), isEmpty);
    });
  });
}
